import SwiftUI

@main
struct DevBarApp: App {
    @State private var store = PortStore.shared
    @State private var settings = SettingsStore()

    init() {
        moveToApplicationsIfNeeded()
        LaunchAtLogin.ensureRegisteredByDefault()
    }

    var body: some Scene {
        MenuBarExtra {
            DevBarMainView()
                .environment(store)
                .environment(settings)
        } label: {
            let runningCount = store.projects.filter { project in
                if case .running = store.projectStates[project.path] { return true }
                return false
            }.count
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                if runningCount > 0 {
                    Text("\(runningCount)")
                }
            }
            .onAppear {
                store.ensurePolling()
                if settings.hasRootFolder {
                    store.scanProjects(rootFolder: settings.rootFolder)
                }
            }
        }
        .menuBarExtraStyle(.window)

        // Log viewer window — one per project, addressed by pm2 name.
        WindowGroup(id: "logs", for: LogWindowTarget.self) { $target in
            if let target {
                LogsView(pm2Name: target.pm2Name, projectName: target.projectName)
                    .navigationTitle("Logs · \(target.projectName)")
            }
        }
        .defaultSize(width: 760, height: 460)
    }
}

/// Small value type so we can pass both pm2 name and display name to a
/// WindowGroup(for:) scene.
struct LogWindowTarget: Hashable, Codable {
    let pm2Name: String
    let projectName: String
}
