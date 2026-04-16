import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var onDone: (() -> Void)?

    @State private var customEditorCommand: String = ""

    private let builtInEditors: [EditorOption] = [
        .vscode, .cursor, .zed, .xcode
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let onDone {
                    Button("Done") { onDone() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            // Root folder
            VStack(alignment: .leading, spacing: 6) {
                Text("Projects folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack {
                    Text(settings.rootFolder.isEmpty ? "Not set" : abbreviatePath(settings.rootFolder))
                        .font(.system(size: 12))
                        .foregroundStyle(settings.rootFolder.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Choose...") {
                        selectFolder()
                    }
                    .font(.system(size: 11))
                }
            }

            Divider()

            // Editor
            VStack(alignment: .leading, spacing: 6) {
                Text("Editor")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(builtInEditors, id: \.self) { editor in
                        EditorRow(
                            editor: editor,
                            isSelected: settings.selectedEditor == editor
                        ) {
                            settings.selectedEditor = editor
                        }
                    }

                    // Custom editor
                    HStack(spacing: 6) {
                        Image(systemName: settings.selectedEditor.isCustom ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(settings.selectedEditor.isCustom ? .primary : .tertiary)

                        TextField("Custom command...", text: $customEditorCommand)
                            .font(.system(size: 12))
                            .textFieldStyle(.plain)
                            .onSubmit {
                                if !customEditorCommand.isEmpty {
                                    settings.selectedEditor = .custom(customEditorCommand)
                                }
                            }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            if case .custom(let cmd) = settings.selectedEditor {
                customEditorCommand = cmd
            }
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose your projects root folder"
        if panel.runModal() == .OK, let url = panel.url {
            settings.rootFolder = url.path
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}

private struct EditorRow: View {
    let editor: EditorOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : .tertiary)
                Text(editor.displayName)
                    .font(.system(size: 12))
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

extension EditorOption {
    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}
