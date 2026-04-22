import AppKit
import SwiftUI

@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored @AppStorage("rootFolder") private var _rootFolder: String = ""
    @ObservationIgnored @AppStorage("editorCommand") private var _editorCommand: String = "code"
    @ObservationIgnored @AppStorage("autoAssignPorts") private var _autoAssignPorts: Bool = true
    @ObservationIgnored @AppStorage("showUnmanagedPorts") private var _showUnmanagedPorts: Bool = false
    /// Bundle identifier of the preferred browser; empty string = macOS default.
    @ObservationIgnored @AppStorage("browserBundleId") private var _browserBundleId: String = ""

    var rootFolder: String {
        get {
            access(keyPath: \.rootFolder)
            return _rootFolder
        }
        set {
            withMutation(keyPath: \.rootFolder) {
                _rootFolder = newValue
            }
        }
    }

    var editorCommand: String {
        get {
            access(keyPath: \.editorCommand)
            return _editorCommand
        }
        set {
            withMutation(keyPath: \.editorCommand) {
                _editorCommand = newValue
            }
        }
    }

    var autoAssignPorts: Bool {
        get {
            access(keyPath: \.autoAssignPorts)
            return _autoAssignPorts
        }
        set {
            withMutation(keyPath: \.autoAssignPorts) {
                _autoAssignPorts = newValue
            }
        }
    }

    var showUnmanagedPorts: Bool {
        get {
            access(keyPath: \.showUnmanagedPorts)
            return _showUnmanagedPorts
        }
        set {
            withMutation(keyPath: \.showUnmanagedPorts) {
                _showUnmanagedPorts = newValue
            }
        }
    }

    var selectedBrowser: BrowserOption {
        get {
            access(keyPath: \.selectedBrowser)
            if _browserBundleId.isEmpty { return .system }
            return BrowserOption.selectable.first { $0.bundleIdentifier == _browserBundleId } ?? .system
        }
        set {
            withMutation(keyPath: \.selectedBrowser) {
                _browserBundleId = newValue.bundleIdentifier ?? ""
            }
        }
    }

    var hasRootFolder: Bool {
        !rootFolder.isEmpty && FileManager.default.fileExists(atPath: rootFolder)
    }

    var selectedEditor: EditorOption {
        get {
            switch editorCommand {
            case "code": return .vscode
            case "cursor": return .cursor
            case "zed": return .zed
            case "xed": return .xcode
            default: return .custom(editorCommand)
            }
        }
        set {
            editorCommand = newValue.command
        }
    }

    func openInEditor(path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editorCommand, path]
        // GUI apps launched from /Applications don't inherit the user's
        // shell PATH, so `code`/`cursor`/etc. CLIs in /opt/homebrew/bin
        // or /usr/local/bin wouldn't resolve. Augment the PATH explicitly.
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + currentPath.split(separator: ":").map(String.init))
            .joined(separator: ":")
        process.environment = env
        do {
            try process.run()
        } catch {
            Log.lifecycle.error("openInEditor(\(self.editorCommand)) failed: \(error.localizedDescription)")
        }
    }

    /// Open a URL in the user's preferred browser (or system default).
    /// Silently falls back to system default if the preferred browser
    /// isn't installed.
    func openInBrowser(_ url: URL) {
        let ws = NSWorkspace.shared
        if let bundleId = selectedBrowser.bundleIdentifier,
           let appURL = ws.urlForApplication(withBundleIdentifier: bundleId) {
            ws.open([url], withApplicationAt: appURL,
                    configuration: NSWorkspace.OpenConfiguration(),
                    completionHandler: nil)
        } else {
            ws.open(url)
        }
    }
}
