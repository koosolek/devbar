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
    @ObservationIgnored private var pendingStartPaths: Set<String> = []

    init(scanner: PortScanning = LivePortScanner()) {
        self.scanner = scanner
        setupLifecycleObservers()
        Log.lifecycle.info("PortStore initialized")
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
        guard !rootFolder.isEmpty else {
            projects = []
            return
        }
        projects = projectScanner.scan(rootFolder: rootFolder)
        Task { await reconcileStates() }
    }

    func startProject(_ project: DiscoveredProject) async {
        projectStates[project.path] = .running(port: 0, startedAt: Date())
        pendingStartPaths.insert(project.path)
        do {
            try await processManager.start(project: project)
            // Poll for port to appear (up to 10 seconds)
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                refresh()  // trigger a port scan
                try? await Task.sleep(for: .milliseconds(200))
                if let port = findPortForProject(project) {
                    projectStates[project.path] = .running(port: port, startedAt: Date())
                    pendingStartPaths.remove(project.path)
                    return
                }
            }
            pendingStartPaths.remove(project.path)
            projectStates[project.path] = .error(message: "Server started but no port detected")
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

    func reconcileStates() async {
        let pm2Statuses = await processManager.status()
        let pm2ByName = Dictionary(pm2Statuses.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })

        for project in projects {
            if pendingStartPaths.contains(project.path) { continue }

            if let info = pm2ByName[project.pm2Name] {
                if info.status == "online" {
                    if let port = findPortForProject(project) {
                        projectStates[project.path] = .running(port: port, startedAt: Date())
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

    private func findPortForProject(_ project: DiscoveredProject) -> UInt16? {
        let dirName = project.name.lowercased()
        return entries.first { entry in
            entry.projectName.lowercased() == dirName
        }?.port
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
