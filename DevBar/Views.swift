import ServiceManagement
import SwiftUI

// MARK: - Main View

struct DevBarMainView: View {
    @Environment(PortStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openWindow) private var openWindow
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showSettings = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView(isPm2Available: store.processManager.isPm2Available)
            } else if showSettings {
                SettingsView(settings: settings, onDone: {
                    showSettings = false
                    if settings.hasRootFolder {
                        store.scanProjects(rootFolder: settings.rootFolder)
                    }
                })
            } else {
                projectListView
            }
        }
        .frame(width: 340)
        .onAppear {
            store.ensurePolling()
            if settings.hasRootFolder {
                store.scanProjects(rootFolder: settings.rootFolder)
            }
        }
        .onChange(of: settings.rootFolder) { _, newValue in
            // Triggered when the user picks a folder via first-run or
            // Settings, so the list populates without needing a reopen.
            if !newValue.isEmpty {
                store.scanProjects(rootFolder: newValue)
            }
        }
    }

    @ViewBuilder
    private var projectListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            DevBarHeaderView(
                isScanning: isAnyScanActive,
                onSettings: { showSettings.toggle() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )

            Divider()
                .padding(.vertical, 4)

            if !settings.hasRootFolder {
                noFolderView
            } else if store.projects.isEmpty &&
                        (!settings.showUnmanagedPorts || store.entries.isEmpty) {
                if isAnyScanActive { scanningStateView } else { emptyStateView }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        projectsList
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: maxListHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }

    /// Cap the project list at ~60% of the visible screen so Docker (or
    /// anything else spawning dozens of listeners) can't blow the menu up.
    private var maxListHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return max(300, screenHeight * 0.6)
    }

    @ViewBuilder
    private var projectsList: some View {
        let editorIcon = AppIcons.icon(forAnyBundleIdentifier: settings.selectedEditor.bundleIdentifierCandidates)
        let browserIcon: NSImage? = {
            if let bundleId = settings.selectedBrowser.bundleIdentifier {
                return AppIcons.icon(forBundleIdentifier: bundleId)
            }
            return AppIcons.defaultBrowserIcon()
        }()

        // Classify listening entries up front so Available can skip
        // anything already running externally.
        let managedPorts = Set(store.projects.compactMap { project -> UInt16? in
            if case .running(let port, _) = store.projectStates[project.path], port > 0 {
                return port
            }
            return nil
        })
        let managedProjectNames = Set(store.projects.compactMap { project -> String? in
            if store.stoppingPaths.contains(project.path) {
                return project.name.lowercased()
            }
            switch store.projectStates[project.path] {
            case .running, .error: return project.name.lowercased()
            default: return nil
            }
        })
        let stoppingProjectPaths = store.stoppingPaths
        let rootFolder = settings.rootFolder
        let leftover = store.entries.filter { entry in
            !managedPorts.contains(entry.port)
                && !managedProjectNames.contains(entry.projectName.lowercased())
        }
        let external = leftover.filter { entry in
            guard !rootFolder.isEmpty, let root = entry.gitRootPath else { return false }
            // Skip paths we're in the middle of stopping — the port is
            // still listening briefly, but the row stays in Running.
            if stoppingProjectPaths.contains(root) { return false }
            return root == rootFolder || root.hasPrefix(rootFolder + "/")
        }
        let externallyRunningPaths = Set(external.compactMap(\.gitRootPath))
        let dockerRunning = DockerStatus.isRunning()

        let running = store.projects.filter { project in
            if case .running = store.projectStates[project.path] { return true }
            return false
        }
        let errored = store.projects.filter { project in
            if case .error = store.projectStates[project.path] { return true }
            return false
        }
        let available = store.projects.filter { project in
            let state = store.projectStates[project.path]
            guard state == nil || state == .stopped else { return false }
            // Hide from Available if already running externally
            // (detected via matching git root path).
            return !externallyRunningPaths.contains(project.path)
        }

        if !running.isEmpty {
            ForEach(running) { project in
                if case .running(let port, let startedAt) = store.projectStates[project.path] {
                    RunningProjectRow(
                        project: project,
                        port: port,
                        startedAt: startedAt,
                        isStopping: store.stoppingPaths.contains(project.path),
                        editorIcon: editorIcon,
                        browserIcon: browserIcon,
                        linkablePorts: linkablePorts(excluding: port),
                        onOpenURL: { openURL(for: project, fallbackPort: port) },
                        onOpenEditor: { settings.openInEditor(path: project.path) },
                        onOpenLogs: { openLogsWindow(for: project) },
                        onStop: { Task { await store.stopProject(project) } },
                        onLinkPort: { store.setKnownPort($0, for: project) },
                        onUnlinkPort: { store.clearKnownPort(for: project) }
                    )
                }
            }
        }

        // External servers — running from terminal, live alongside managed
        // Running rows. The "external" label + missing logs button are the
        // only things distinguishing them visually.
        if !external.isEmpty {
            ForEach(external) { entry in
                ExternalProjectRow(
                    entry: entry,
                    editorIcon: editorIcon,
                    browserIcon: browserIcon,
                    onOpenURL: { openURL(port: entry.port) },
                    onOpenEditor: { entry.gitRootPath.map { settings.openInEditor(path: $0) } },
                    onKill: { store.killProcess(pid: entry.pid, port: entry.port) }
                )
            }
        }

        if !errored.isEmpty {
            ForEach(errored) { project in
                if case .error(let message) = store.projectStates[project.path] {
                    ErrorProjectRow(
                        project: project,
                        message: message,
                        editorIcon: editorIcon,
                        onOpenEditor: { settings.openInEditor(path: project.path) },
                        onOpenLogs: { openLogsWindow(for: project) },
                        onRetry: { Task { await store.startProject(project, autoAssignPort: settings.autoAssignPorts) } },
                        onStop: { Task { await store.deleteProject(project) } }
                    )
                }
            }
        }

        if !available.isEmpty {
            if !running.isEmpty || !external.isEmpty || !errored.isEmpty {
                Divider()
                    .padding(.vertical, 4)
            }

            ForEach(available) { project in
                let conflict = store.portConflict(for: project)
                let conflictEntry = conflict.flatMap { p in
                    store.entries.first(where: { $0.port == p })
                }
                let conflictOwner = conflictEntry?.projectName
                let conflictIsDocker = conflictOwner?.lowercased() == "docker"
                AvailableProjectRow(
                    project: project,
                    conflictPort: conflict,
                    conflictOwner: conflictOwner,
                    conflictIsDockerOwned: conflictIsDocker,
                    dockerMissing: project.requiresDocker && !dockerRunning,
                    editorIcon: editorIcon,
                    onOpenEditor: { settings.openInEditor(path: project.path) },
                    onStart: { Task { await store.startProject(project, autoAssignPort: settings.autoAssignPorts) } },
                    onReplace: { Task { await store.replaceAndStart(project, autoAssignPort: settings.autoAssignPorts) } }
                )
            }
        }

        let unmanaged = settings.showUnmanagedPorts
            ? leftover.filter { entry in !external.contains(entry) }
            : []

        if !unmanaged.isEmpty {
            Divider()
                .padding(.vertical, 4)

            ForEach(unmanaged) { entry in
                UnmanagedPortRow(
                    entry: entry,
                    browserIcon: browserIcon,
                    onOpenURL: { openURL(port: entry.port) },
                    onKill: { store.killProcess(pid: entry.pid, port: entry.port) }
                )
            }
        }
    }

    private var noFolderView: some View {
        VStack(spacing: 8) {
            Text("No projects folder set")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Choose Folder") { settings.pickRootFolder() }
                .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var emptyStateView: some View {
        Text("No projects found")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    private var scanningStateView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Scanning for servers…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    /// Combined scan activity — port scan (first load empty) or project scan.
    private var isAnyScanActive: Bool {
        store.isScanningProjects || (store.isScanning && store.entries.isEmpty)
    }

    private func openURL(port: UInt16) {
        if let url = URL(string: "http://localhost:\(port)") {
            settings.openInBrowser(url)
        }
    }

    private func openURL(for project: DiscoveredProject, fallbackPort: UInt16) {
        if let url = store.openURL(for: project) {
            settings.openInBrowser(url)
        } else {
            openURL(port: fallbackPort)
        }
    }

    /// Ports currently listening that the user could link to a project,
    /// excluding the project's own currently-matched port so the menu doesn't
    /// offer something that's already set.
    private func linkablePorts(excluding current: UInt16) -> [ActivePort] {
        store.entries.filter { $0.port != current || current == 0 }
            .sorted { $0.port < $1.port }
    }

    private func openLogsWindow(for project: DiscoveredProject) {
        let target = LogWindowTarget(
            pm2Name: project.pm2Name,
            projectName: project.name
        )
        // LSUIElement apps (menu bar only, no Dock icon) need to activate
        // before a window will surface. Without this the WindowGroup
        // instance is created but stays hidden behind other apps.
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "logs", value: target)
    }
}

// MARK: - Header

struct DevBarHeaderView: View {
    let isScanning: Bool
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("DevBar")
                .font(.system(size: 13, weight: .semibold))
            if isScanning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
            }
            Spacer()
            Button("Settings") { onSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Button("Quit") { onQuit() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

// MARK: - Running Project Row

struct RunningProjectRow: View {
    let project: DiscoveredProject
    let port: UInt16
    let startedAt: Date
    let isStopping: Bool
    let editorIcon: NSImage?
    let browserIcon: NSImage?
    let linkablePorts: [ActivePort]
    let onOpenURL: () -> Void
    let onOpenEditor: () -> Void
    let onOpenLogs: () -> Void
    let onStop: () -> Void
    let onLinkPort: (UInt16) -> Void
    let onUnlinkPort: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                detailText
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 4) {
                if port > 0 {
                    ActionButton(appIcon: browserIcon, fallbackSystem: "arrow.up.forward.square", tooltip: "Open URL", action: onOpenURL)
                }
                ActionButton(appIcon: editorIcon, fallbackSystem: "pencil", tooltip: "Open in Editor", action: onOpenEditor)
                ActionButton(systemImage: "text.alignleft", tooltip: "View Logs", action: onOpenLogs)
                portMenuButton
                if isStopping {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 26, height: 26)
                        .help("Stopping…")
                } else {
                    ActionButton(systemImage: "stop.fill", tooltip: "Stop", action: onStop)
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 56)
    }

    @ViewBuilder
    private var portMenuButton: some View {
        Menu {
            if !linkablePorts.isEmpty {
                Menu("Link port") {
                    ForEach(linkablePorts) { entry in
                        Button(":\(entry.port) · \(entry.projectName)") {
                            onLinkPort(entry.port)
                        }
                    }
                }
            }
            if port > 0 {
                Button("Unlink port") { onUnlinkPort() }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Port options")
    }

    /// pm2 takes up to ~10s after `start` before anything shows as bound.
    /// After that, if pm2 still says online but we've found no port, the
    /// process is likely running but routing through Docker/a proxy where
    /// lsof can't tie the listener back to our process — say so instead of
    /// pretending it's still "starting".
    private var detailText: Text {
        let parent = (project.relativePath as NSString).deletingLastPathComponent
        let folder = Text("\(Image(systemName: "folder"))")
        let pathText: Text = parent.isEmpty ? folder : folder + Text(" \(parent)")
        if port > 0 {
            return Text("localhost:\(port) · \(formatUptime(since: startedAt)) · ") + pathText
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < 15 {
            return Text("Starting… · ") + pathText
        }
        return Text("Running · port unknown · link via ⋯ menu · ") + pathText
    }
}

// MARK: - Available Project Row

struct AvailableProjectRow: View {
    let project: DiscoveredProject
    let conflictPort: UInt16?
    let conflictOwner: String?
    let conflictIsDockerOwned: Bool
    let dockerMissing: Bool
    let editorIcon: NSImage?
    let onOpenEditor: () -> Void
    let onStart: () -> Void
    let onReplace: () -> Void

    @State private var confirming = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                if !confirming {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(project.isSupported ? .primary : .secondary)
                        if !project.isSupported {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .help("No dev command detected in package.json or Makefile. Open the project to configure it.")
                        }
                        if project.isComplexOrchestration {
                            Text("Run in terminal")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.primary.opacity(0.07))
                                )
                                .help("Complex multi-service stack — DevBar may not manage this reliably. Running directly in a terminal is usually more predictable.")
                        }
                    }
                }
                subtitleText
                    .font(.system(size: confirming ? 10 : 11))
                    .foregroundStyle(confirming ? .primary : .secondary)
                    .lineLimit(confirming ? 3 : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(subtitleHelp)
            }
            Spacer()
            if confirming {
                ConfirmRunButtons(
                    onCancel: { confirming = false },
                    onConfirm: {
                        confirming = false
                        if conflictPort != nil {
                            onReplace()
                        } else {
                            onStart()
                        }
                    }
                )
            } else {
                HStack(spacing: 4) {
                    ActionButton(appIcon: editorIcon, fallbackSystem: "pencil", tooltip: "Open in Editor", action: onOpenEditor)
                    if project.isSupported {
                        ActionButton(systemImage: "play.fill", tooltip: "Run") {
                            if needsConfirm {
                                confirming = true
                            } else {
                                onStart()
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 56)
        .onChange(of: conflictPort) { _, newValue in
            if newValue == nil { confirming = false }
        }
    }

    /// Combined confirm message — lists every reason we're asking before
    /// starting, so the "Run anyway" button has context no matter what
    /// combination of issues applies.
    private var confirmMessage: String {
        var parts: [String] = []
        if project.isComplexOrchestration {
            parts.append("Multi-service stack — usually better run from a terminal.")
        }
        if let port = conflictPort {
            if conflictIsDockerOwned {
                parts.append("Port \(port) held by Docker — running this will stop Docker Desktop.")
            } else {
                let owner = conflictOwner ?? "another process"
                parts.append("Port \(port) used by \(owner) — running this will stop \(owner).")
            }
        }
        return parts.joined(separator: " ")
    }

    /// Whether clicking Start should first ask the user to confirm.
    /// Triggered by port conflicts and by projects flagged as complex
    /// orchestration stacks (where DevBar is unlikely to manage well).
    private var needsConfirm: Bool {
        conflictPort != nil || project.isComplexOrchestration
    }

    /// Hover text for the subtitle — only set when there's useful context
    /// beyond what's already visible (mainly the port-conflict warning).
    private var subtitleHelp: String {
        if confirming { return "" }
        if let port = conflictPort {
            let owner = conflictOwner ?? "another process"
            if conflictIsDockerOwned {
                return "Port \(port) is held by Docker (com.docker.backend). Running this project will stop the Docker backend, which shuts down Docker Desktop and makes all running containers unreachable."
            }
            return "Port \(port) is in use by \(owner). Running this project will stop \(owner) first."
        }
        return ""
    }

    private var parentPathText: Text {
        let parent = (project.relativePath as NSString).deletingLastPathComponent
        let folder = Text("\(Image(systemName: "folder"))")
        if parent.isEmpty { return folder }
        return folder + Text(" \(parent)")
    }

    private var subtitleText: Text {
        if confirming {
            return Text(confirmMessage)
        }
        if let port = conflictPort {
            let owner = conflictOwner.map { " (\($0))" } ?? ""
            return Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(port)\(owner) · ") + parentPathText
        }
        if !project.isSupported {
            return Text("No dev command found · ") + parentPathText
        }
        if dockerMissing {
            return Text("\(Image(systemName: "exclamationmark.triangle.fill")) Docker not running · ") + parentPathText
        }
        return parentPathText
    }
}

private struct ConfirmRunButtons: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

            Button(action: onConfirm) {
                Text("Run")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Error Project Row

struct ErrorProjectRow: View {
    let project: DiscoveredProject
    let message: String
    let editorIcon: NSImage?
    let onOpenEditor: () -> Void
    let onOpenLogs: () -> Void
    let onRetry: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                subtitleText
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 4) {
                ActionButton(appIcon: editorIcon, fallbackSystem: "pencil", tooltip: "Open in Editor", action: onOpenEditor)
                ActionButton(systemImage: "text.alignleft", tooltip: "View Logs", action: onOpenLogs)
                ActionButton(systemImage: "arrow.clockwise", tooltip: "Retry", action: onRetry)
                ActionButton(systemImage: "stop.fill", tooltip: "Stop", action: onStop)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 56)
    }

    private var subtitleText: Text {
        let parent = (project.relativePath as NSString).deletingLastPathComponent
        let folder = Text("\(Image(systemName: "folder"))")
        let pathText: Text = parent.isEmpty ? folder : folder + Text(" \(parent)")
        return Text("\(message) · ") + pathText
    }
}

// MARK: - Unmanaged Port Row

// MARK: - External Project Row

struct ExternalProjectRow: View {
    let entry: ActivePort
    let editorIcon: NSImage?
    let browserIcon: NSImage?
    let onOpenURL: () -> Void
    let onOpenEditor: () -> Void
    let onKill: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.projectName)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 4) {
                ActionButton(appIcon: browserIcon, fallbackSystem: "arrow.up.forward.square", tooltip: "Open URL", action: onOpenURL)
                if entry.gitRootPath != nil {
                    ActionButton(appIcon: editorIcon, fallbackSystem: "pencil", tooltip: "Open in Editor", action: onOpenEditor)
                }
                ActionButton(systemImage: "stop.fill", tooltip: "Stop", action: onKill)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 56)
    }

    private var subtitle: String {
        let portBit = "localhost:\(entry.port)"
        if !entry.branch.isEmpty {
            return "\(portBit) · \(entry.branch) · external"
        }
        return "\(portBit) · external"
    }
}

struct UnmanagedPortRow: View {
    let entry: ActivePort
    let browserIcon: NSImage?
    let onOpenURL: () -> Void
    let onKill: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.projectName)
                    .font(.system(size: 13, weight: .medium))
                Text("localhost:\(entry.port)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                ActionButton(appIcon: browserIcon, fallbackSystem: "arrow.up.forward.square", tooltip: "Open URL", action: onOpenURL)
                ActionButton(systemImage: "xmark", tooltip: "Kill", action: onKill)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 56)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    enum Icon {
        case system(String)
        case app(NSImage, fallbackSystem: String)
    }

    let icon: Icon
    let tooltip: String
    let action: () -> Void

    init(systemImage: String, tooltip: String, action: @escaping () -> Void) {
        self.icon = .system(systemImage)
        self.tooltip = tooltip
        self.action = action
    }

    init(appIcon: NSImage?, fallbackSystem: String, tooltip: String, action: @escaping () -> Void) {
        if let appIcon {
            self.icon = .app(appIcon, fallbackSystem: fallbackSystem)
        } else {
            self.icon = .system(fallbackSystem)
        }
        self.tooltip = tooltip
        self.action = action
    }

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            iconView
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(tooltip)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 12))
        case .app(let image, _):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .saturation(0)
                .frame(width: 18, height: 18)
        }
    }
}

// MARK: - Helpers

func formatUptime(since date: Date) -> String {
    let elapsed = Int(Date().timeIntervalSince(date))
    if elapsed < 60 { return "<1m" }
    let minutes = elapsed / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    if hours < 24 {
        return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
    }
    let days = hours / 24
    return "\(days)d \(hours % 24)h"
}
