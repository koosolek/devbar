import ServiceManagement
import SwiftUI

// MARK: - Main View

struct DevBarMainView: View {
    @Environment(PortStore.self) private var store
    @Environment(SettingsStore.self) private var settings
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
            } else if store.projects.isEmpty && store.entries.isEmpty {
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
            return state == nil || state == .stopped
        }

        if !running.isEmpty {
            ForEach(running) { project in
                if case .running(let port, let startedAt) = store.projectStates[project.path] {
                    RunningProjectRow(
                        project: project,
                        port: port,
                        startedAt: startedAt,
                        onOpenURL: { openURL(port: port) },
                        onOpenEditor: { settings.openInEditor(path: project.path) },
                        onStop: { Task { await store.stopProject(project) } }
                    )
                }
            }
        }

        if !errored.isEmpty {
            ForEach(errored) { project in
                if case .error(let message) = store.projectStates[project.path] {
                    ErrorProjectRow(
                        project: project,
                        message: message,
                        onOpenEditor: { settings.openInEditor(path: project.path) },
                        onRetry: { Task { await store.startProject(project, autoAssignPort: settings.autoAssignPorts) } },
                        onStop: { Task { await store.deleteProject(project) } }
                    )
                }
            }
        }

        if !available.isEmpty {
            if !running.isEmpty || !errored.isEmpty {
                Divider()
                    .padding(.vertical, 4)
            }

            ForEach(available) { project in
                AvailableProjectRow(
                    project: project,
                    conflictPort: store.portConflict(for: project),
                    onOpenEditor: { settings.openInEditor(path: project.path) },
                    onStart: { Task { await store.startProject(project, autoAssignPort: settings.autoAssignPorts) } },
                    onReplace: { Task { await store.replaceAndStart(project, autoAssignPort: settings.autoAssignPorts) } }
                )
            }
        }

        // Unmanaged ports — detected by lsof but not matching any known project
        let managedPorts = Set(store.projects.compactMap { project -> UInt16? in
            if case .running(let port, _) = store.projectStates[project.path], port > 0 {
                return port
            }
            return nil
        })
        // In a monorepo, sub-services share the project's git root, so lsof
        // reports them all under the same projectName. Suppress those so we
        // don't show ghost "cds" / "app" rows alongside the managed project.
        let managedProjectNames = Set(store.projects.compactMap { project -> String? in
            switch store.projectStates[project.path] {
            case .running, .error: return project.name.lowercased()
            default: return nil
            }
        })
        let unmanaged = store.entries.filter { entry in
            !managedPorts.contains(entry.port)
                && !managedProjectNames.contains(entry.projectName.lowercased())
        }
        if !unmanaged.isEmpty {
            Divider()
                .padding(.vertical, 4)

            ForEach(unmanaged) { entry in
                UnmanagedPortRow(
                    entry: entry,
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
            Button("Choose Folder") { showSettings = true }
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
            NSWorkspace.shared.open(url)
        }
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
    let onOpenURL: () -> Void
    let onOpenEditor: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                Text(detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 4) {
                if port > 0 {
                    ActionButton(systemImage: "arrow.up.forward.square", tooltip: "Open URL", action: onOpenURL)
                }
                ActionButton(systemImage: "pencil", tooltip: "Open in Editor", action: onOpenEditor)
                ActionButton(systemImage: "stop.fill", tooltip: "Stop", action: onStop)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
    }

    private var detailText: String {
        if port > 0 {
            return "localhost:\(port) · \(formatUptime(since: startedAt)) · \(project.relativePath)"
        }
        return "Starting... · \(project.relativePath)"
    }
}

// MARK: - Available Project Row

struct AvailableProjectRow: View {
    let project: DiscoveredProject
    let conflictPort: UInt16?
    let onOpenEditor: () -> Void
    let onStart: () -> Void
    let onReplace: () -> Void

    @State private var confirming = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .medium))
                    if conflictPort != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if confirming, let port = conflictPort {
                ConfirmReplaceButtons(
                    port: port,
                    onCancel: { confirming = false },
                    onConfirm: {
                        confirming = false
                        onReplace()
                    }
                )
            } else {
                HStack(spacing: 4) {
                    ActionButton(systemImage: "pencil", tooltip: "Open in Editor", action: onOpenEditor)
                    ActionButton(systemImage: "play.fill", tooltip: "Start") {
                        if conflictPort != nil {
                            confirming = true
                        } else {
                            onStart()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .onChange(of: conflictPort) { _, newValue in
            if newValue == nil { confirming = false }
        }
    }

    private var subtitle: String {
        if confirming, let port = conflictPort {
            return "Kill process on :\(port) and start?"
        }
        if let port = conflictPort {
            return "Port \(port) busy · \(project.relativePath)"
        }
        return project.relativePath
    }
}

private struct ConfirmReplaceButtons: View {
    let port: UInt16
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
                Text("Replace")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .help("Stop the process on :\(port) and start this project")
        }
    }
}

// MARK: - Error Project Row

struct ErrorProjectRow: View {
    let project: DiscoveredProject
    let message: String
    let onOpenEditor: () -> Void
    let onRetry: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                Text("\(message) · \(project.relativePath)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 4) {
                ActionButton(systemImage: "pencil", tooltip: "Open in Editor", action: onOpenEditor)
                ActionButton(systemImage: "arrow.clockwise", tooltip: "Retry", action: onRetry)
                ActionButton(systemImage: "stop.fill", tooltip: "Stop", action: onStop)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
    }
}

// MARK: - Unmanaged Port Row

struct UnmanagedPortRow: View {
    let entry: ActivePort
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
                ActionButton(systemImage: "arrow.up.forward.square", tooltip: "Open URL", action: onOpenURL)
                ActionButton(systemImage: "xmark", tooltip: "Kill", action: onKill)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let systemImage: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
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
