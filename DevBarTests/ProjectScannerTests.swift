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
    let deep = root
        .appendingPathComponent("a").appendingPathComponent("b")
        .appendingPathComponent("c")
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
