import SwiftUI

@main
struct DevBarApp: App {
    @State private var store = PortStore.shared
    @State private var settings = SettingsStore()

    init() {
        moveToApplicationsIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            DevBarMainView()
                .environment(store)
                .environment(settings)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: store.entries.isEmpty
                      ? "square.fill"
                      : "circle.fill")
                    .font(.system(size: 5.5))
                    .foregroundStyle(statusColor)
                Text(store.entries.count, format: .number)
                    .fontDesign(.monospaced)
            }
            .onAppear { store.ensurePolling() }
        }
        .menuBarExtraStyle(.window)
    }

    private var statusColor: Color {
        if store.lastError != nil && store.entries.isEmpty {
            return .orange
        }
        return store.entries.isEmpty ? .gray : .green
    }
}
