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
                onSettings: { showSettings.toggle() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )

            Divider()
                .padding(.vertical, 4)
                .padding(.horizontal, 12)

            if !settings.hasRootFolder {
                noFolderView
            } else if store.projects.isEmpty {
                emptyStateView
            } else {
                projectsList
            }
        }
        .padding(12)
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
                        onRetry: { Task { await store.startProject(project) } }
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
                    onOpenEditor: { settings.openInEditor(path: project.path) },
                    onStart: { Task { await store.startProject(project) } }
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
        let unmanaged = store.entries.filter { !managedPorts.contains($0.port) }
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

    private func openURL(port: UInt16) {
        if let url = URL(string: "http://localhost:\(port)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Header

struct DevBarHeaderView: View {
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack {
            Text("DevBar")
                .font(.system(size: 13, weight: .semibold))
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
                if port > 0 {
                    Text("localhost:\(port) · \(formatUptime(since: startedAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                } else {
                    Text("Starting...")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                }
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
}

// MARK: - Available Project Row

struct AvailableProjectRow: View {
    let project: DiscoveredProject
    let onOpenEditor: () -> Void
    let onStart: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                Text(project.relativePath)
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
            }
            Spacer()
            HStack(spacing: 4) {
                ActionButton(systemImage: "pencil", tooltip: "Open in Editor", action: onOpenEditor)
                ActionButton(systemImage: "play.fill", tooltip: "Start", action: onStart)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .opacity(0.55)
    }
}

// MARK: - Error Project Row

struct ErrorProjectRow: View {
    let project: DiscoveredProject
    let message: String
    let onOpenEditor: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
            }
            Spacer()
            HStack(spacing: 4) {
                ActionButton(systemImage: "pencil", tooltip: "Open in Editor", action: onOpenEditor)
                ActionButton(systemImage: "arrow.clockwise", tooltip: "Retry", action: onRetry)
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
                    .foregroundStyle(.quaternary)
            }
            Spacer()
            HStack(spacing: 4) {
                ActionButton(systemImage: "arrow.up.forward.square", tooltip: "Open URL", action: onOpenURL)
                ActionButton(systemImage: "xmark", tooltip: "Kill", action: onKill)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .opacity(0.55)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let systemImage: String
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .contentShape(Rectangle())
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
