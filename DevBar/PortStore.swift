import SwiftUI
import os

// MARK: - PortStore

@MainActor
@Observable
final class PortStore {
    static let shared = PortStore()

    var entries: [ActivePort] = []
    var lastError: ScanError?
    var isScanning: Bool = false
    var lastDiagnostics: ScanDiagnostics?

    var projects: [DiscoveredProject] = []
    var projectStates: [String: ProjectState] = [:]  // keyed by project path
    var processManager = ProcessManager()
    /// True while the project-folder filesystem scan is running.
    var isScanningProjects: Bool = false

    /// Last port we observed each project binding to, keyed by project path.
    /// Used (together with `DiscoveredProject.expectedPort`) to surface
    /// conflicts for stopped projects whose port is currently held by
    /// something else.
    var knownPorts: [String: UInt16] = [:]

    /// URLs extracted from each project's pm2 logs whose port matches a
    /// currently-listening port. Rebuilt on each refresh; used to open
    /// the project with its actual scheme/host (e.g. https://tenant1.cds-dev.com:8000)
    /// rather than a hardcoded localhost.
    var logDetectedURLs: [String: URL] = [:]

    @ObservationIgnored
    @AppStorage("refreshInterval") private var storedInterval: Double = RefreshInterval.defaultInterval.rawValue

    var refreshInterval: RefreshInterval {
        get { RefreshInterval(rawValue: storedInterval) ?? .defaultInterval }
        set {
            storedInterval = newValue.rawValue
            restartTimer()
            Log.store.info("Refresh interval changed to \(newValue.rawValue)s")
        }
    }

    @ObservationIgnored private let scanner: PortScanning
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var recentlyKilled: [UInt16: Date] = [:]
    @ObservationIgnored private var sleepObserver: Any?
    @ObservationIgnored private var wakeObserver: Any?
    @ObservationIgnored private var projectScanner = ProjectScanner()
    /// Project paths that have clicked Start but haven't confirmed a port yet.
    /// Observable so views can react to simultaneous-start races.
    private var pendingStartPaths: Set<String> = []
    @ObservationIgnored private let knownPortsDefaultsKey = "knownPorts"

    init(scanner: PortScanning = LivePortScanner()) {
        self.scanner = scanner
        knownPorts = Self.loadKnownPorts(key: knownPortsDefaultsKey)
        setupLifecycleObservers()
        Log.lifecycle.info("PortStore initialized")
    }

    private static func loadKnownPorts(key: String) -> [String: UInt16] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: UInt16].self, from: data)
        else { return [:] }
        return raw
    }

    private func persistKnownPorts() {
        if let data = try? JSONEncoder().encode(knownPorts) {
            UserDefaults.standard.set(data, forKey: knownPortsDefaultsKey)
        }
    }

    private func rememberPort(_ port: UInt16, for projectPath: String) {
        guard port > 0, knownPorts[projectPath] != port else { return }
        knownPorts[projectPath] = port
        persistKnownPorts()
    }

    /// User-driven port link: ties a currently-listening port to this project.
    /// Needed for Docker-launched services where `lsof` can't attribute the
    /// port back to our pm2 process through the process tree.
    func setKnownPort(_ port: UInt16, for project: DiscoveredProject) {
        knownPorts[project.path] = port
        persistKnownPorts()
        if case .running(_, let startedAt) = projectStates[project.path] {
            projectStates[project.path] = .running(port: port, startedAt: startedAt)
        }
    }

    func clearKnownPort(for project: DiscoveredProject) {
        guard knownPorts[project.path] != nil else { return }
        knownPorts.removeValue(forKey: project.path)
        persistKnownPorts()
        if case .running(_, let startedAt) = projectStates[project.path] {
            projectStates[project.path] = .running(port: 0, startedAt: startedAt)
        }
    }

    // MARK: - Polling

    func ensurePolling() {
        guard timer == nil else { return }
        Log.lifecycle.info("Starting polling (interval: \(self.refreshInterval.rawValue)s)")
        refresh()
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        let interval = refreshInterval.rawValue
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func restartTimer() {
        guard timer != nil else { return }
        startTimer()
    }

    // MARK: - Refresh

    func refresh() {
        guard !isScanning else {
            if Log.isVerbose { Log.store.debug("Refresh skipped — already scanning") }
            return
        }

        scanTask?.cancel()
        scanTask = Task { [scanner] in
            isScanning = true
            defer { isScanning = false }

            let result = await scanner.scan()

            guard !Task.isCancelled else { return }

            switch result {
            case .success(let ports, let diag):
                lastError = nil
                lastDiagnostics = diag
                pruneRecentlyKilled()
                let filtered = ports.filter { !recentlyKilled.keys.contains($0.port) }
                applyUpdate(filtered)
                if !projects.isEmpty {
                    await reconcileStates()
                }

            case .failure(let error, _):
                lastError = error
                Log.store.error("Scan error: \(error.localizedDescription)")
            }
        }
    }

    /// Smoothly updates entries, preserving existing items during transition.
    private func applyUpdate(_ newEntries: [ActivePort]) {
        let oldIDs = Set(entries.map(\.port))
        let newIDs = Set(newEntries.map(\.port))

        if oldIDs == newIDs && entries.count == newEntries.count {
            var needsUpdate = false
            for (old, new) in zip(entries, newEntries) {
                if old != new { needsUpdate = true; break }
            }
            if !needsUpdate { return }
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            entries = newEntries
        }
    }

    // MARK: - Actions

    func killProcess(pid: Int32, port: UInt16) {
        kill(pid, SIGTERM)
        recentlyKilled[port] = Date()
        Log.store.info("Killed PID \(pid) on port \(port)")
    }

    func killAllProcesses() {
        let currentEntries = entries
        guard !currentEntries.isEmpty else { return }

        for entry in currentEntries {
            kill(entry.pid, SIGTERM)
            recentlyKilled[entry.port] = Date()
        }

        Log.store.info("Killed \(currentEntries.count) processes")
        withAnimation(.easeInOut(duration: 0.25)) {
            entries = []
        }
    }

    func removeEntry(port: UInt16) {
        withAnimation(.easeInOut(duration: 0.3)) {
            entries.removeAll { $0.port == port }
        }
    }

    static func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    // MARK: - Recently Killed Cleanup

    private func pruneRecentlyKilled() {
        let cutoff = Date().addingTimeInterval(-8)
        recentlyKilled = recentlyKilled.filter { $0.value > cutoff }
    }

    // MARK: - Sleep / Wake

    private func setupLifecycleObservers() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSleep()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWake()
            }
        }
    }

    private func handleSleep() {
        Log.lifecycle.info("System going to sleep — pausing polling")
        timer?.invalidate()
        timer = nil
        scanTask?.cancel()
    }

    private func handleWake() {
        Log.lifecycle.info("System woke — resuming polling")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.ensurePolling()
        }
    }

    // MARK: - Project Management

    func scanProjects(rootFolder: String) {
        Log.store.info("scanProjects called (rootFolder='\(rootFolder)')")
        guard !rootFolder.isEmpty else {
            projects = []
            return
        }
        // Filesystem scan is fast; keep it synchronous so the UI shows
        // projects on the first paint. The slow part is the port scan,
        // which already runs asynchronously.
        let found = projectScanner.scan(rootFolder: rootFolder)
        Log.store.info("scanProjects: found \(found.count) project(s)")
        projects = found
        Task { await reconcileStates() }
    }

    func startProject(_ project: DiscoveredProject, autoAssignPort: Bool = true) async {
        // Defensive: the UI should hide the Start action for unsupported
        // projects, but guard here too.
        guard project.startCommand != nil else { return }

        let startTime = Date()
        projectStates[project.path] = .running(port: 0, startedAt: startTime)
        pendingStartPaths.insert(project.path)

        var env: [String: String] = [:]
        if autoAssignPort {
            let occupied = Set(entries.map(\.port))
            if let allocated = PortAllocator.allocate(occupied: occupied) {
                env["PORT"] = String(allocated)
            }
        }

        do {
            try await processManager.start(project: project, extraEnv: env)
            // Poll for a port to appear (up to 10s). If none shows up we leave
            // the project in its current running-without-port state and let the
            // regular refresh/reconcile cycle take over — pm2 status will
            // eventually flip it to errored/stopped if the process bails.
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                refresh()
                try? await Task.sleep(for: .milliseconds(200))
                if let match = findPortForProject(project) {
                    projectStates[project.path] = .running(port: match.port, startedAt: startTime)
                    if match.isStrong {
                        rememberPort(match.port, for: project.path)
                    }
                    pendingStartPaths.remove(project.path)
                    return
                }
            }
            pendingStartPaths.remove(project.path)
        } catch {
            pendingStartPaths.remove(project.path)
            projectStates[project.path] = .error(message: error.localizedDescription)
        }
    }

    func stopProject(_ project: DiscoveredProject) async {
        do {
            try await processManager.stop(project: project)
            projectStates[project.path] = .stopped
        } catch {
            projectStates[project.path] = .error(message: error.localizedDescription)
        }
    }

    /// Fully remove the project from pm2 and transition back to Available.
    /// Used for errored/stuck rows where a plain `stop` would leave a pm2 entry behind.
    func deleteProject(_ project: DiscoveredProject) async {
        pendingStartPaths.remove(project.path)
        try? await processManager.delete(project: project)
        projectStates[project.path] = .stopped
    }

    /// Stop whatever is listening on this project's probable port, then start it.
    /// Used when the user explicitly confirms "kill the occupant and run this".
    func replaceAndStart(_ project: DiscoveredProject, autoAssignPort: Bool) async {
        guard let port = portConflict(for: project) else {
            await startProject(project, autoAssignPort: autoAssignPort)
            return
        }

        // Prefer stopping a managed DevBar project (running or mid-start) so
        // pm2's view and ours stay consistent. Fall back to SIGTERM on the
        // raw PID for external listeners.
        let managedRunning = projects.first { candidate in
            if case .running(let p, _) = projectStates[candidate.path], p == port { return true }
            return false
        }
        let managedPending = projects.first { candidate in
            candidate.path != project.path
                && pendingStartPaths.contains(candidate.path)
                && probablePort(for: candidate) == port
        }

        if let managedRunning {
            await stopProject(managedRunning)
        } else if let managedPending {
            await deleteProject(managedPending)
        } else if let entry = entries.first(where: { $0.port == port }) {
            killProcess(pid: entry.pid, port: entry.port)
        }

        // Small grace period for the kernel to release the port.
        try? await Task.sleep(for: .milliseconds(500))
        await startProject(project, autoAssignPort: autoAssignPort)
    }

    func reconcileStates() async {
        let pm2Statuses = await processManager.status()
        let pm2ByName = Dictionary(pm2Statuses.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })

        // Refresh log-detected URLs for projects pm2 considers online so
        // findPortForProject can use them on the same pass.
        let listeningPorts = Set(entries.map(\.port))
        for project in projects {
            let info = pm2ByName[project.pm2Name]
            guard info?.status == "online", !listeningPorts.isEmpty else {
                logDetectedURLs.removeValue(forKey: project.path)
                continue
            }
            if let url = LogURLDetector.detectURL(forPm2Name: project.pm2Name, listeningPorts: listeningPorts) {
                logDetectedURLs[project.path] = url
            }
        }

        for project in projects {
            if pendingStartPaths.contains(project.path) { continue }

            if let info = pm2ByName[project.pm2Name] {
                if info.status == "online" {
                    if let match = findPortForProject(project) {
                        projectStates[project.path] = .running(port: match.port, startedAt: Date())
                        if match.isStrong {
                            rememberPort(match.port, for: project.path)
                        }
                    } else {
                        projectStates[project.path] = .running(port: 0, startedAt: Date())
                    }
                } else if info.status == "errored" {
                    projectStates[project.path] = .error(message: "Process crashed")
                } else {
                    projectStates[project.path] = .stopped
                }
            } else {
                if projectStates[project.path] == nil {
                    projectStates[project.path] = .stopped
                }
            }
        }
    }

    /// Returns the port this project would likely try to bind, derived from
    /// (1) the last-known port if we've seen it run, or (2) `--port N` in
    /// the project's dev/start script.
    func probablePort(for project: DiscoveredProject) -> UInt16? {
        knownPorts[project.path] ?? project.expectedPort
    }

    /// If the project's probable port is currently being used by a process
    /// OTHER than this same project, return that port. Otherwise nil.
    /// Covers: live listeners (lsof), other DevBar projects already running
    /// on the port, and other DevBar projects mid-start that will try to
    /// claim the same port.
    func portConflict(for project: DiscoveredProject) -> UInt16? {
        guard let port = probablePort(for: project) else { return nil }

        // If the matching state is this project's own running/starting instance,
        // it's not a conflict.
        if case .running(let ownPort, _) = projectStates[project.path],
           ownPort == port || ownPort == 0 && pendingStartPaths.contains(project.path) {
            return nil
        }

        // 1. Something is already listening on the port.
        if entries.contains(where: { $0.port == port }) {
            return port
        }

        // 2. Another project is in the middle of starting and will try to
        //    bind this same port.
        let racing = projects.contains { other in
            other.path != project.path
                && pendingStartPaths.contains(other.path)
                && probablePort(for: other) == port
        }
        if racing { return port }

        return nil
    }

    struct PortMatch {
        let port: UInt16
        /// True for signals where the port clearly represents the project's
        /// primary URL (user-linked, log URL, or cwd/git-root by-name match).
        /// False for weak heuristic matches like "one of the compose ports
        /// happens to be listening" — those should not be persisted as
        /// `knownPort` because they're often sidecars (Redis, etc.), not
        /// the user-facing URL.
        let isStrong: Bool
    }

    private func findPortForProject(_ project: DiscoveredProject) -> PortMatch? {
        // 1. Explicit user link wins.
        if let linked = knownPorts[project.path],
           entries.contains(where: { $0.port == linked }) {
            return PortMatch(port: linked, isStrong: true)
        }
        // 2. URL scraped from this project's pm2 logs — precise and authoritative.
        if let detected = logDetectedURLs[project.path],
           let port = detected.port.map(UInt16.init),
           entries.contains(where: { $0.port == port }) {
            return PortMatch(port: port, isStrong: true)
        }
        // 3. lsof attributes the listener to this project by name/git root.
        let dirName = project.name.lowercased()
        if let port = entries.first(where: { $0.projectName.lowercased() == dirName })?.port {
            return PortMatch(port: port, isStrong: true)
        }
        // 4. Weak: *any* compose-declared port happens to be up. Lets us
        // show the project as running but we don't remember this — a
        // sidecar like Redis on 6380 is a poor stand-in for the real URL.
        if !project.composePorts.isEmpty {
            let declared = Set(project.composePorts)
            if let entry = entries.first(where: { declared.contains($0.port) }) {
                return PortMatch(port: entry.port, isStrong: false)
            }
        }
        return nil
    }

    /// Full URL to open for this project — prefers a URL scraped from the
    /// project's own logs (so custom hostnames + https Just Work), falling
    /// back to http://localhost:port when we only have a port.
    func openURL(for project: DiscoveredProject) -> URL? {
        if let detected = logDetectedURLs[project.path] { return detected }
        if case .running(let port, _) = projectStates[project.path], port > 0 {
            return URL(string: "http://localhost:\(port)")
        }
        return nil
    }

    // MARK: - Diagnostics

    var diagnosticsSnapshot: String {
        """
        === DevBar Diagnostics ===
        Ports found: \(entries.count)
        Is scanning: \(isScanning)
        Last error: \(lastError?.localizedDescription ?? "none")
        Refresh interval: \(refreshInterval.rawValue)s
        Last scan: \(lastDiagnostics?.summary ?? "none")
        Recently killed: \(recentlyKilled.keys.sorted().map(String.init).joined(separator: ", "))
        Entries: \(entries.map { ":\($0.port) (\($0.projectName))" }.joined(separator: ", "))
        ============================
        """
    }
}
