import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    private static let hasRegisteredDefaultKey = "hasRegisteredLaunchAtLoginDefault"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var isSupportedInCurrentLocation: Bool {
        // SMAppService refuses to register apps running from translocated or temp locations.
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/")
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            Log.lifecycle.error("Launch-at-login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Register once on first eligible launch so the app is in login items by default.
    /// Runs only when the app lives in /Applications — otherwise the registration
    /// would point at a path that won't survive a rebuild or move.
    static func ensureRegisteredByDefault() {
        guard isSupportedInCurrentLocation else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: hasRegisteredDefaultKey) else { return }
        if setEnabled(true) {
            defaults.set(true, forKey: hasRegisteredDefaultKey)
        }
    }
}
