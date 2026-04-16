import SwiftUI

@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored @AppStorage("rootFolder") private var _rootFolder: String = ""
    @ObservationIgnored @AppStorage("editorCommand") private var _editorCommand: String = "code"

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
        try? process.run()
    }
}
