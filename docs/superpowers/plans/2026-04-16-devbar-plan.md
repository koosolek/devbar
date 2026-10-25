# DevBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fork Port Menu and extend it into DevBar — a macOS menu bar app that discovers projects, starts/stops them via pm2, and shows running servers with clickable URLs.

**Architecture:** Three new components (ProjectScanner, ProcessManager, SettingsStore) layered on Port Menu's existing port scanning and menu bar infrastructure. Port Menu's PortStore is extended to cross-reference detected ports with discovered projects. UI rewritten to show two sections (running/available) with start/stop/open actions.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14+ (Sonoma), pm2 (external dependency), Xcode 15+

**Spec:** `docs/superpowers/specs/2026-04-16-devbar-design.md`

---

## File Structure

### New files to create

| File | Responsibility |
|------|---------------|
| `DevBar/ProjectScanner.swift` | Scans root folder for projects with `package.json`, produces `DiscoveredProject` list |
| `DevBar/ProcessManager.swift` | Wraps pm2 CLI calls (start, stop, status, logs) via Swift `Process` |
| `DevBar/SettingsStore.swift` | Persists root folder path and editor choice via `@AppStorage` |
| `DevBar/SettingsView.swift` | Settings window UI — folder picker, editor dropdown |
| `DevBarTests/ProjectScannerTests.swift` | Tests for folder scanning and package.json parsing |
| `DevBarTests/ProcessManagerTests.swift` | Tests for pm2 command construction |

### Existing files to modify

| File | Changes |
|------|---------|
| `Porter/Models.swift` → `DevBar/Models.swift` | Add `DiscoveredProject`, `ProjectState`, `EditorOption` types |
| `Porter/PortStore.swift` → `DevBar/PortStore.swift` | Add project cross-referencing, integrate ProcessManager |
| `Porter/PorterApp.swift` → `DevBar/DevBarApp.swift` | Remove Sparkle, wire up SettingsStore, rename |
| `Porter/Views.swift` → `DevBar/Views.swift` | Complete rewrite: two-section layout, new actions, settings/quit header |
| `Porter/Onboarding.swift` → `DevBar/Onboarding.swift` | Replace with pm2 check and install instructions |
| `Porter/AppHelpers.swift` → `DevBar/AppHelpers.swift` | Keep move-to-Applications, remove Sparkle refs |
| `Porter/PortScanning.swift` → `DevBar/PortScanning.swift` | Minimal changes — keep as-is, just rename module refs |
| `Porter.xcodeproj` → `DevBar.xcodeproj` | Rename target, bundle ID, remove Sparkle package dependency |

---

### Task 1: Fork, Clone, and Rename Project

**Files:**
- Modify: `Porter.xcodeproj` (rename to DevBar)
- Modify: All `.swift` files (rename folder references)
- Delete: Sparkle dependency

- [ ] **Step 1: Fork and clone the repo**

```bash
cd /Users/mronk/Code/Personal
gh repo fork wieandteduard/port-menu --clone --fork-name devbar
cd devbar
```

- [ ] **Step 2: Rename the Porter directory to DevBar**

```bash
mv Porter DevBar
mv PorterTests DevBarTests
mv PorterUITests DevBarUITests
```

- [ ] **Step 3: Update the Xcode project**

Open `Porter.xcodeproj/project.pbxproj` and perform these find-and-replace operations:
- Replace all `Porter` references with `DevBar` in the project file
- Update `PRODUCT_BUNDLE_IDENTIFIER` to `com.devbar.app`
- Update `PRODUCT_NAME` to `DevBar`
- Remove the Sparkle package dependency entry from the project file

This is a text-based operation on the `.pbxproj` file. The key replacements:
- `Porter.app` → `DevBar.app`
- `Porter` (target name) → `DevBar`
- `PorterTests` → `DevBarTests`
- `PorterUITests` → `DevBarUITests`
- Remove the `XCRemoteSwiftPackageReference "Sparkle"` block and its `XCSwiftPackageProductDependency`

- [ ] **Step 4: Remove Sparkle imports and references from Swift files**

In `DevBar/DevBarApp.swift` (was `PorterApp.swift`):
- Remove `import Sparkle`
- Remove the `UpdaterDelegate` class
- Remove `SPUStandardUpdaterController` property
- Remove the update check menu command

In `DevBar/Views.swift`:
- Remove `import Sparkle`
- Remove `CheckForUpdatesView`
- Remove any update-related UI elements from `PortHeaderView`

In `DevBar/AppHelpers.swift`:
- Remove any Sparkle references if present

- [ ] **Step 5: Verify project builds**

```bash
cd /Users/mronk/Code/Personal/devbar
xcodebuild -scheme DevBar -configuration Debug build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Fork Port Menu and rename to DevBar, remove Sparkle"
```

---

### Task 2: Add New Model Types

**Files:**
- Modify: `DevBar/Models.swift`
- Create: `DevBarTests/ModelTests.swift`

- [ ] **Step 1: Write tests for new model types**

Create `DevBarTests/ModelTests.swift`:

```swift
import Testing
@testable import DevBar

@Test func discoveredProjectInit() {
    let project = DiscoveredProject(
        name: "frontend",
        path: "/Users/me/Code/Personal/frontend",
        relativePath: "Personal/frontend",
        startCommand: "npm run dev"
    )
    #expect(project.name == "frontend")
    #expect(project.relativePath == "Personal/frontend")
    #expect(project.pm2Name == "devbar-frontend")
}

@Test func discoveredProjectPm2NameSanitization() {
    let project = DiscoveredProject(
        name: "my cool app",
        path: "/Users/me/Code/my cool app",
        relativePath: "my cool app",
        startCommand: "npm run dev"
    )
    #expect(project.pm2Name == "devbar-my-cool-app")
}

@Test func projectStateEquality() {
    #expect(ProjectState.stopped != ProjectState.running(port: 3000, startedAt: Date()))
}

@Test func editorOptionCommand() {
    #expect(EditorOption.vscode.command == "code")
    #expect(EditorOption.cursor.command == "cursor")
    #expect(EditorOption.zed.command == "zed")
    #expect(EditorOption.custom("subl").command == "subl")
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme DevBar -destination 'platform=macOS' 2>&1 | grep -E "(Test|error|FAILED)"
```

Expected: Compilation errors — types don't exist yet.

- [ ] **Step 3: Add model types to Models.swift**

Append to `DevBar/Models.swift`:

```swift
// MARK: - DevBar Models

struct DiscoveredProject: Identifiable, Equatable, Hashable, Sendable {
    let name: String
    let path: String
    let relativePath: String
    let startCommand: String

    var id: String { path }

    var pm2Name: String {
        "devbar-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
    }
}

enum ProjectState: Equatable, Sendable {
    case stopped
    case running(port: UInt16, startedAt: Date)
    case error(message: String)
}

enum EditorOption: Equatable, Hashable, Sendable, Codable {
    case vscode
    case cursor
    case zed
    case xcode
    case custom(String)

    var command: String {
        switch self {
        case .vscode: return "code"
        case .cursor: return "cursor"
        case .zed: return "zed"
        case .xcode: return "xed"
        case .custom(let cmd): return cmd
        }
    }

    var displayName: String {
        switch self {
        case .vscode: return "VS Code"
        case .cursor: return "Cursor"
        case .zed: return "Zed"
        case .xcode: return "Xcode"
        case .custom(let cmd): return cmd
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme DevBar -destination 'platform=macOS' 2>&1 | grep -E "(Test|PASSED|FAILED)"
```

Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add DevBar/Models.swift DevBarTests/ModelTests.swift
git commit -m "Add DiscoveredProject, ProjectState, and EditorOption models"
```

---

### Task 3: Implement ProjectScanner

**Files:**
- Create: `DevBar/ProjectScanner.swift`
- Create: `DevBarTests/ProjectScannerTests.swift`

- [ ] **Step 1: Write tests for ProjectScanner**

Create `DevBarTests/ProjectScannerTests.swift`. Tests use a temporary directory with fake project structures:

```swift
import Testing
import Foundation
@testable import DevBar

@Test func scanFindsProjectWithDevScript() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("devbar-test-\(UUID().uuidString)")
    let projectDir = root
        .appendingPathComponent("Personal")
        .appendingPathComponent("myapp")
    try FileManager.default.createDirectory(
        at: projectDir, withIntermediateDirectories: true
    )
    let packageJson = """
    {
        "name": "myapp",
        "scripts": {
            "dev": "vite",
            "build": "vite build"
        }
    }
    """
    try packageJson.write(
        to: projectDir.appendingPathComponent("package.json"),
        atomically: true, encoding: .utf8
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let scanner = ProjectScanner()
    let projects = scanner.scan(rootFolder: root.path)

    #expect(projects.count == 1)
    #expect(projects[0].name == "myapp")
    #expect(projects[0].startCommand == "npm run dev")
    #expect(projects[0].relativePath == "Personal/myapp")
}

@Test func scanFindsStartScriptWhenNoDevScript() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("devbar-test-\(UUID().uuidString)")
    let projectDir = root.appendingPathComponent("myapp")
    try FileManager.default.createDirectory(
        at: projectDir, withIntermediateDirectories: true
    )
    let packageJson = """
    {
        "name": "myapp",
        "scripts": {
            "start": "node server.js",
            "build": "tsc"
        }
    }
    """
    try packageJson.write(
        to: projectDir.appendingPathComponent("package.json"),
        atomically: true, encoding: .utf8
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let scanner = ProjectScanner()
    let projects = scanner.scan(rootFolder: root.path)

    #expect(projects.count == 1)
    #expect(projects[0].startCommand == "npm start")
}

@Test func scanSkipsProjectsWithoutDevOrStartScript() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("devbar-test-\(UUID().uuidString)")
    let projectDir = root.appendingPathComponent("lib")
    try FileManager.default.createDirectory(
        at: projectDir, withIntermediateDirectories: true
    )
    let packageJson = """
    { "name": "lib", "scripts": { "build": "tsc" } }
    """
    try packageJson.write(
        to: projectDir.appendingPathComponent("package.json"),
        atomically: true, encoding: .utf8
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let scanner = ProjectScanner()
    let projects = scanner.scan(rootFolder: root.path)

    #expect(projects.isEmpty)
}

@Test func scanRespectsThreeLevelDepthLimit() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("devbar-test-\(UUID().uuidString)")
    // Level 1/2/3 — should be found
    let deep = root
        .appendingPathComponent("a").appendingPathComponent("b")
        .appendingPathComponent("c")
    // Level 1/2/3/4 — too deep, should be skipped
    let tooDeep = deep.appendingPathComponent("d")

    for dir in [deep, tooDeep] {
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let json = """
        { "name": "\(dir.lastPathComponent)", "scripts": { "dev": "vite" } }
        """
        try json.write(
            to: dir.appendingPathComponent("package.json"),
            atomically: true, encoding: .utf8
        )
    }
    defer { try? FileManager.default.removeItem(at: root) }

    let scanner = ProjectScanner()
    let projects = scanner.scan(rootFolder: root.path)

    #expect(projects.count == 1)
    #expect(projects[0].name == "c")
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme DevBar -destination 'platform=macOS' 2>&1 | grep -E "(error|FAILED)"
```

Expected: Compilation error — `ProjectScanner` doesn't exist.

- [ ] **Step 3: Implement ProjectScanner**

Create `DevBar/ProjectScanner.swift`:

```swift
import Foundation

struct ProjectScanner: Sendable {
    private static let maxDepth = 3

    func scan(rootFolder: String) -> [DiscoveredProject] {
        let rootURL = URL(fileURLWithPath: rootFolder)
        var projects: [DiscoveredProject] = []
        scanDirectory(rootURL, rootURL: rootURL, depth: 0, results: &projects)
        return projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scanDirectory(
        _ url: URL,
        rootURL: URL,
        depth: Int,
        results: inout [DiscoveredProject]
    ) {
        guard depth <= Self.maxDepth else { return }

        let packageJsonURL = url.appendingPathComponent("package.json")
        if let project = parsePackageJson(at: packageJsonURL, projectURL: url, rootURL: rootURL) {
            results.append(project)
            return // Don't scan deeper once we find a project
        }

        // Not a project — scan subdirectories
        guard depth < Self.maxDepth else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for child in contents {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                scanDirectory(child, rootURL: rootURL, depth: depth + 1, results: &results)
            }
        }
    }

    private func parsePackageJson(
        at url: URL,
        projectURL: URL,
        rootURL: URL
    ) -> DiscoveredProject? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: String] else {
            return nil
        }

        let startCommand: String
        if scripts["dev"] != nil {
            startCommand = "npm run dev"
        } else if scripts["start"] != nil {
            startCommand = "npm start"
        } else {
            return nil
        }

        let name = projectURL.lastPathComponent
        let relativePath = projectURL.path
            .replacingOccurrences(of: rootURL.path + "/", with: "")

        return DiscoveredProject(
            name: name,
            path: projectURL.path,
            relativePath: relativePath,
            startCommand: startCommand
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme DevBar -destination 'platform=macOS' 2>&1 | grep -E "(Test|PASSED|FAILED)"
```

Expected: All 4 ProjectScanner tests pass.

- [ ] **Step 5: Commit**

```bash
git add DevBar/ProjectScanner.swift DevBarTests/ProjectScannerTests.swift
git commit -m "Add ProjectScanner with folder scanning and package.json detection"
```

---

### Task 4: Implement ProcessManager

**Files:**
- Create: `DevBar/ProcessManager.swift`
- Create: `DevBarTests/ProcessManagerTests.swift`

- [ ] **Step 1: Write tests for command construction**

Create `DevBarTests/ProcessManagerTests.swift`:

```swift
import Testing
import Foundation
@testable import DevBar

@Test func startCommandConstruction() {
    let project = DiscoveredProject(
        name: "frontend",
        path: "/Users/me/Code/frontend",
        relativePath: "Personal/frontend",
        startCommand: "npm run dev"
    )
    let args = ProcessManager.startArguments(for: project)
    #expect(args == [
        "start", "npm run dev",
        "--name", "devbar-frontend",
        "--cwd", "/Users/me/Code/frontend"
    ])
}

@Test func stopCommandConstruction() {
    let project = DiscoveredProject(
        name: "frontend",
        path: "/Users/me/Code/frontend",
        relativePath: "Personal/frontend",
        startCommand: "npm run dev"
    )
    let args = ProcessManager.stopArguments(for: project)
    #expect(args == ["stop", "devbar-frontend"])
}

@Test func pm2PathResolution() {
    // pm2 should be findable if installed
    let path = ProcessManager.findPm2Path()
    // This test passes whether pm2 is installed or not —
    // it just verifies the function returns a string or nil
    if let path {
        #expect(path.hasSuffix("pm2"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme DevBar -destination 'platform=macOS' 2>&1 | grep -E "(error|FAILED)"
```

Expected: Compilation error — `ProcessManager` doesn't exist.

- [ ] **Step 3: Implement ProcessManager**

Create `DevBar/ProcessManager.swift`:

```swift
import Foundation

struct Pm2ProcessInfo: Sendable {
    let name: String
    let status: String // "online", "stopped", "errored"
    let pid: Int32?
}

@MainActor
final class ProcessManager {
    private var pm2Path: String?

    init() {
        pm2Path = Self.findPm2Path()
    }

    var isPm2Available: Bool { pm2Path != nil }

    // MARK: - Command construction (static, testable)

    static func startArguments(for project: DiscoveredProject) -> [String] {
        ["start", project.startCommand,
         "--name", project.pm2Name,
         "--cwd", project.path]
    }

    static func stopArguments(for project: DiscoveredProject) -> [String] {
        ["stop", project.pm2Name]
    }

    static func findPm2Path() -> String? {
        let commonPaths = [
            "/opt/homebrew/bin/pm2",
            "/usr/local/bin/pm2",
            "/usr/bin/pm2"
        ]
        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Fallback: use `which`
        let result = Self.runSync(command: "/usr/bin/which", arguments: ["pm2"])
        let trimmed = result?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return nil
    }

    // MARK: - Actions

    func start(project: DiscoveredProject) async throws {
        guard let pm2Path else { throw ProcessManagerError.pm2NotFound }
        let args = Self.startArguments(for: project)
        try await run(command: pm2Path, arguments: args)
    }

    func stop(project: DiscoveredProject) async throws {
        guard let pm2Path else { throw ProcessManagerError.pm2NotFound }
        let args = Self.stopArguments(for: project)
        try await run(command: pm2Path, arguments: args)
    }

    func status() async -> [Pm2ProcessInfo] {
        guard let pm2Path else { return [] }
        guard let output = try? await runCapture(command: pm2Path, arguments: ["jlist"]) else {
            return []
        }
        return Self.parseJlist(output)
    }

    func openLogs(project: DiscoveredProject) {
        guard let pm2Path else { return }
        let script = """
        tell application "Terminal"
            do script "\(pm2Path) logs \(project.pm2Name)"
            activate
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    // MARK: - pm2 jlist parsing

    static func parseJlist(_ json: String) -> [Pm2ProcessInfo] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { entry in
            guard let name = entry["name"] as? String,
                  name.hasPrefix("devbar-") else { return nil }
            let pm2Env = entry["pm2_env"] as? [String: Any]
            let status = pm2Env?["status"] as? String ?? "unknown"
            let pid = entry["pid"] as? Int32
            return Pm2ProcessInfo(name: name, status: status, pid: pid)
        }
    }

    // MARK: - Shell execution

    private func run(command: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.environment = Self.shellEnvironment()
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ProcessManagerError.commandFailed(
                        command: "\(command) \(arguments.joined(separator: " "))",
                        exitCode: proc.terminationStatus
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func runCapture(command: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = pipe
            process.environment = Self.shellEnvironment()
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func runSync(command: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func shellEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Ensure common bin paths are in PATH for Node/npm/pm2
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let allPaths = (extraPaths + currentPath.split(separator: ":").map(String.init))
        env["PATH"] = allPaths.joined(separator: ":")
        return env
    }
}

enum ProcessManagerError: LocalizedError {
    case pm2NotFound
    case commandFailed(command: String, exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .pm2NotFound:
            return "pm2 not found. Install with: brew install pm2"
        case .commandFailed(let command, let exitCode):
            return "Command failed (\(exitCode)): \(command)"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme DevBar -destination 'platform=macOS' 2>&1 | grep -E "(Test|PASSED|FAILED)"
```

Expected: All 3 ProcessManager tests pass.

- [ ] **Step 5: Commit**

```bash
git add DevBar/ProcessManager.swift DevBarTests/ProcessManagerTests.swift
git commit -m "Add ProcessManager with pm2 CLI integration"
```

---

### Task 5: Implement SettingsStore

**Files:**
- Create: `DevBar/SettingsStore.swift`

- [ ] **Step 1: Create SettingsStore**

Create `DevBar/SettingsStore.swift`:

```swift
import SwiftUI

@MainActor
@Observable
final class SettingsStore {
    @AppStorage("rootFolder") var rootFolder: String = ""
    @AppStorage("editorCommand") var editorCommand: String = "code"

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
```

- [ ] **Step 2: Verify it compiles**

```bash
xcodebuild -scheme DevBar -configuration Debug build 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add DevBar/SettingsStore.swift
git commit -m "Add SettingsStore for root folder and editor preferences"
```

---

### Task 6: Implement SettingsView

**Files:**
- Create: `DevBar/SettingsView.swift`

- [ ] **Step 1: Create SettingsView**

Create `DevBar/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore

    @State private var customEditorCommand: String = ""
    @State private var isSelectingFolder = false

    private let builtInEditors: [EditorOption] = [
        .vscode, .cursor, .zed, .xcode
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))

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

// Helper extension for EditorOption
extension EditorOption {
    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
xcodebuild -scheme DevBar -configuration Debug build 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add DevBar/SettingsView.swift
git commit -m "Add SettingsView with folder picker and editor selection"
```

---

### Task 7: Replace Onboarding with pm2 Check

**Files:**
- Modify: `DevBar/Onboarding.swift`

- [ ] **Step 1: Replace the entire Onboarding.swift content**

Replace the contents of `DevBar/Onboarding.swift` with a simpler pm2 check view:

```swift
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    let isPm2Available: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                Text("DevBar")
                    .font(.system(size: 28, weight: .semibold))
                    .padding(.bottom, 8)

                Text("Manage your dev servers\nfrom the menu bar.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)

            Spacer()

            if !isPm2Available {
                VStack(alignment: .leading, spacing: 8) {
                    Text("pm2 required")
                        .font(.system(size: 12, weight: .medium))

                    Text("Install pm2 to manage dev servers in the background:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        CopyableCommand("brew install pm2")
                        Text("or")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        CopyableCommand("npm i -g pm2")
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            }

            HStack {
                Button(isPm2Available ? "Get Started" : "I've Installed pm2") {
                    hasCompletedOnboarding = true
                }
                .buttonStyle(OnboardingButtonStyle())
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(width: 340, height: 240)
    }
}

private struct CopyableCommand: View {
    let command: String

    init(_ command: String) {
        self.command = command
    }

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        } label: {
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help("Click to copy")
    }
}

struct OnboardingButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.7 : 1))
            )
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
xcodebuild -scheme DevBar -configuration Debug build 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add DevBar/Onboarding.swift
git commit -m "Replace onboarding with pm2 availability check"
```

---

### Task 8: Extend PortStore with Project Integration

**Files:**
- Modify: `DevBar/PortStore.swift`

- [ ] **Step 1: Add project-aware properties and methods to PortStore**

Add the following to the `PortStore` class. These integrate with ProjectScanner and ProcessManager to provide a unified view of projects and ports:

```swift
// Add these properties alongside existing ones in PortStore:
var projects: [DiscoveredProject] = []
var projectStates: [String: ProjectState] = [:]  // keyed by project path
var processManager = ProcessManager()

private var projectScanner = ProjectScanner()
private var pendingStartPaths: Set<String> = []

// Add these methods to PortStore:

func scanProjects(rootFolder: String) {
    guard !rootFolder.isEmpty else {
        projects = []
        return
    }
    projects = projectScanner.scan(rootFolder: rootFolder)
    Task { await reconcileStates() }
}

func startProject(_ project: DiscoveredProject) async {
    projectStates[project.path] = .running(port: 0, startedAt: Date())
    pendingStartPaths.insert(project.path)
    do {
        try await processManager.start(project: project)
        // Port detection will happen via the existing poll cycle.
        // Wait up to 10 seconds for port to appear.
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            if let port = findPortForProject(project) {
                projectStates[project.path] = .running(port: port, startedAt: Date())
                pendingStartPaths.remove(project.path)
                return
            }
        }
        // Timeout — port never appeared
        pendingStartPaths.remove(project.path)
        projectStates[project.path] = .error(message: "Server started but no port detected")
    } catch {
        pendingStartPaths.remove(project.path)
        projectStates[project.path] = .error(message: error.localizedDescription)
    }
}

func stopProject(_ project: DiscoveredProject) async {
    do {
        try await processManager.stop(project: project)
        projectStates[project.path] = .stopped
    } catch {
        projectStates[project.path] = .error(message: error.localizedDescription)
    }
}

func reconcileStates() async {
    let pm2Statuses = await processManager.status()
    let pm2ByName = Dictionary(pm2Statuses.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })

    for project in projects {
        if pendingStartPaths.contains(project.path) { continue }

        if let info = pm2ByName[project.pm2Name] {
            if info.status == "online" {
                if let port = findPortForProject(project) {
                    projectStates[project.path] = .running(port: port, startedAt: Date())
                } else {
                    projectStates[project.path] = .running(port: 0, startedAt: Date())
                }
            } else if info.status == "errored" {
                projectStates[project.path] = .error(message: "Process crashed")
            } else {
                projectStates[project.path] = .stopped
            }
        } else {
            if projectStates[project.path] == nil {
                projectStates[project.path] = .stopped
            }
        }
    }
}

private func findPortForProject(_ project: DiscoveredProject) -> UInt16? {
    // Match by checking if any active port's working directory
    // is within the project path
    entries.first { entry in
        entry.projectPath?.hasPrefix(project.path) == true
    }?.port
}
```

Note: The `findPortForProject` method depends on `ActivePort` having a `projectPath` property. If Port Menu's `ActivePort` uses a different property name for the working directory (e.g., `workingDirectory` or derives it from `projectName`), match accordingly. Check the existing `ActivePort` struct and use the correct property that holds the process's working directory.

- [ ] **Step 2: Verify it compiles**

```bash
xcodebuild -scheme DevBar -configuration Debug build 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED` (may need to adjust property names based on actual ActivePort definition)

- [ ] **Step 3: Commit**

```bash
git add DevBar/PortStore.swift
git commit -m "Extend PortStore with project scanning and pm2 integration"
```

---

### Task 9: Rewrite Views

**Files:**
- Modify: `DevBar/Views.swift`

This is the largest task. Replace Port Menu's views with DevBar's two-section layout.

- [ ] **Step 1: Rewrite the header**

Replace `PortHeaderView` with:

```swift
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
```

- [ ] **Step 2: Create the project row views**

Add running project row and available project row:

```swift
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
                Text("localhost:\(port) · \(formatUptime(since: startedAt))")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
            }
            Spacer()
            HStack(spacing: 4) {
                ActionButton(systemImage: "arrow.up.forward.square", tooltip: "Open URL", action: onOpenURL)
                ActionButton(systemImage: "pencil", tooltip: "Open in Editor", action: onOpenEditor)
                ActionButton(systemImage: "stop.fill", tooltip: "Stop", action: onStop)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
    }
}

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

struct UnmanagedPortRow: View {
    let entry: ActivePort
    let onOpenURL: () -> Void
    let onKill: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.projectName ?? "Unknown")
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
```

- [ ] **Step 3: Rewrite the main content view**

Replace `PortMainContentView` and `PortListView` with:

```swift
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
                SettingsView(settings: settings)
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
```

- [ ] **Step 4: Remove unused Port Menu views**

Delete from `Views.swift`:
- `CheckForUpdatesView`
- `PortListView`
- `PortMainContentView`
- `PortHeaderView`
- `PortEntryListView`
- `PortRow`
- `PortEmptyStateView`
- `PortScanningStateView`
- `PortErrorStateView`
- `HoverButton`
- `FloatingTooltipPanel`
- `HeaderControlButton`
- `HeaderButtonStyle`
- `RowButtonStyle`

Keep `formatUptime` if it already exists (or use the new one above).

- [ ] **Step 5: Verify it compiles**

```bash
xcodebuild -scheme DevBar -configuration Debug build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add DevBar/Views.swift
git commit -m "Rewrite views with two-section project list layout"
```

---

### Task 10: Update App Entry Point

**Files:**
- Modify: `DevBar/DevBarApp.swift` (was `PorterApp.swift`)

- [ ] **Step 1: Rewrite the app entry point**

Replace the contents of `DevBarApp.swift`:

```swift
import SwiftUI

@main
struct DevBarApp: App {
    @State private var store = PortStore()
    @State private var settings = SettingsStore()

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
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 2: Remove AppHelpers move-to-applications call if it references the old name**

In `DevBar/AppHelpers.swift`, update any references from "Port Menu" to "DevBar" in user-facing strings. The `moveToApplicationsIfNeeded()` function can stay as-is functionally.

- [ ] **Step 3: Verify it compiles and launches**

```bash
xcodebuild -scheme DevBar -configuration Debug build 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`

Then test manually:
```bash
open /Users/mronk/Code/Personal/devbar/build/Build/Products/Debug/DevBar.app
```

Verify:
- Menu bar icon appears
- Onboarding shows (pm2 check)
- After onboarding, settings prompt appears
- After setting root folder, projects are discovered

- [ ] **Step 4: Commit**

```bash
git add DevBar/DevBarApp.swift DevBar/AppHelpers.swift
git commit -m "Wire up app entry point with SettingsStore and new main view"
```

---

### Task 11: Manual Integration Testing

No new files — this task verifies the full workflow end-to-end.

- [ ] **Step 1: Build and launch the app**

```bash
cd /Users/mronk/Code/Personal/devbar
xcodebuild -scheme DevBar -configuration Debug build
open build/Build/Products/Debug/DevBar.app
```

- [ ] **Step 2: Complete onboarding**

Verify:
- If pm2 is installed: "Get Started" button appears
- If pm2 is not installed: install instructions shown with copyable commands
- After clicking through, main view appears

- [ ] **Step 3: Configure settings**

- Click Settings in the header
- Set root folder to `~/Code`
- Set editor to your preferred editor
- Go back — projects should appear in the "available" section

- [ ] **Step 4: Test start/stop cycle**

- Click play on an available project
- Verify it moves to the running section with a detected port
- Click the URL button — browser opens to `localhost:<port>`
- Click the editor button — project opens in configured editor
- Click stop — project moves back to available section
- Verify `pm2 list` in terminal shows/hides the `devbar-*` process

- [ ] **Step 5: Test view logs**

If a View Logs action is accessible (via right-click or context menu):
- Click View Logs on a running project
- Verify Terminal opens with `pm2 logs devbar-<project>`

- [ ] **Step 6: Test error state**

- Manually corrupt a project's start command in pm2: `pm2 start "nonexistent-command" --name devbar-test`
- Verify the project shows in error state with a message
- Clean up: `pm2 delete devbar-test`

- [ ] **Step 7: Commit any fixes**

```bash
git add -A
git commit -m "Fix integration issues found during testing"
```

(Only if fixes were needed.)
