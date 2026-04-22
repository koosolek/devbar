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
    }
}
