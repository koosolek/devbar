import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    var onDone: (() -> Void)?

    @State private var customEditorCommand: String = ""
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled

    private let builtInEditors: [EditorOption] = [
        .vscode, .cursor, .zed, .xcode
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            Divider()
                .padding(.vertical, 4)

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
            .padding(.horizontal, 4)
            .padding(.vertical, 7)

            Divider()
                .padding(.vertical, 4)

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
            .padding(.horizontal, 4)
            .padding(.vertical, 7)

            Divider()
                .padding(.vertical, 4)

            // Browser
            VStack(alignment: .leading, spacing: 6) {
                Text("Browser")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(BrowserOption.selectable, id: \.self) { option in
                        BrowserRow(
                            browser: option,
                            isSelected: settings.selectedBrowser == option
                        ) {
                            settings.selectedBrowser = option
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 7)

            Divider()
                .padding(.vertical, 4)

            // General
            VStack(alignment: .leading, spacing: 6) {
                Text("General")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at login")
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!LaunchAtLogin.isSupportedInCurrentLocation)
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLogin.setEnabled(newValue)
                    // Re-read actual state in case the system refused the change.
                    launchAtLogin = LaunchAtLogin.isEnabled
                }

                if !LaunchAtLogin.isSupportedInCurrentLocation {
                    Text("Move DevBar to Applications to enable.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Toggle(isOn: $settings.autoAssignPorts) {
                    Text("Auto-assign ports")
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Text("Sets PORT=4100… so projects that respect it don't collide. Configs with hardcoded ports (e.g. Vite `strictPort: true`) still need a code change.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: $settings.showUnmanagedPorts) {
                    Text("Show unmanaged ports")
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Text("Lists every other process listening on a port — Homebrew services, Docker, and anything you started in a terminal. Useful for killing stray servers; off by default to reduce noise.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 7)

            if let onDone {
                Divider()
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                Button("Done") { onDone() }
                    .font(.system(size: 11))
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
            }
        }
        .padding(12)
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

private struct BrowserRow: View {
    let browser: BrowserOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : .tertiary)
                Text(browser.displayName)
                    .font(.system(size: 12))
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}
