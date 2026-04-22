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

@Test func scanFindsMakefileStartTarget() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("devbar-test-\(UUID().uuidString)")
    let projectDir = root.appendingPathComponent("stack")
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    let makefile = """
    .PHONY: start stop start-service
    start:
    \tdocker compose up
    stop:
    \tdocker compose down
    start-service:
    \t@echo nope
    """
    try makefile.write(to: projectDir.appendingPathComponent("Makefile"),
                       atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    let scanner = ProjectScanner()
    let projects = scanner.scan(rootFolder: root.path)

    #expect(projects.count == 1)
    #expect(projects[0].name == "stack")
    #expect(projects[0].startCommand == "make start")
}

@Test func scanMarksMakefileWithoutRunTargetAsUnsupported() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("devbar-test-\(UUID().uuidString)")
    let projectDir = root.appendingPathComponent("lib")
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    let makefile = """
    build:
    \tcc main.c
    test:
    \t./test
    """
    try makefile.write(to: projectDir.appendingPathComponent("Makefile"),
                       atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    let scanner = ProjectScanner()
    let projects = scanner.scan(rootFolder: root.path)

    #expect(projects.count == 1)
    #expect(projects[0].startCommand == nil)
    #expect(projects[0].isSupported == false)
}

@Test func scanPrefersMakeDevOverStart() {
    let makefile = """
    .PHONY: dev start
    dev:
    \tnpm run dev
    start:
    \tnode server.js
    """
    #expect(ProjectScanner.extractMakeTarget(from: makefile) == "dev")
}

@Test func scanReadmePicksUpStartCommand() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("devbar-test-\(UUID().uuidString)")
    let projectDir = root.appendingPathComponent("tool")
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    let readme = """
    # tool

    ## Quick start
    ```bash
    pnpm dev
    ```
    """
    try readme.write(to: projectDir.appendingPathComponent("README.md"),
                     atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    let scanner = ProjectScanner()
    let projects = scanner.scan(rootFolder: root.path)

    #expect(projects.count == 1)
    #expect(projects[0].startCommand == "pnpm dev")
}

@Test func extractComposePortsHandlesQuotedAndUnquoted() {
    let compose = """
    services:
      web:
        image: nginx
        ports:
          - "8080:80"
          - 9090:9090
      db:
        image: postgres
        ports:
          - "5432"
    volumes:
      - data:/var/lib
    """
    let ports = ProjectScanner.extractComposePorts(compose)
    #expect(ports == [8080, 9090, 5432])
}

@Test func extractComposePortsIgnoresNonPortLists() {
    let compose = """
    services:
      app:
        command:
          - serve
          - --port
          - "3000"
        ports:
          - "3000:3000"
    """
    // Only "3000:3000" from the ports: block; the command list should not leak in
    let ports = ProjectScanner.extractComposePorts(compose)
    #expect(ports == [3000])
}

@Test func extractPortFromViteConfigReadsServerPort() {
    let cfg = """
    import { defineConfig } from "vite";
    export default defineConfig({
      server: { port: 5173, strictPort: true }
    });
    """
    #expect(ProjectScanner.extractPortFromViteConfig(cfg) == 5173)
}

@Test func scanFindsVitePortInSubPackage() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("devbar-test-\(UUID().uuidString)")
    let outer = root.appendingPathComponent("monorepo")
    let inner = outer.appendingPathComponent("apps").appendingPathComponent("frontend")
    try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)

    // Outer package.json delegates to inner workspace package, no --port flag.
    let outerJson = #"{"name":"monorepo","scripts":{"dev":"pnpm --filter @x/frontend dev"}}"#
    try outerJson.write(to: outer.appendingPathComponent("package.json"),
                        atomically: true, encoding: .utf8)
    let vite = """
    export default { server: { port: 4444, strictPort: true } };
    """
    try vite.write(to: inner.appendingPathComponent("vite.config.ts"),
                   atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: root) }

    let scanner = ProjectScanner()
    let projects = scanner.scan(rootFolder: root.path)

    #expect(projects.count == 1)
    #expect(projects[0].expectedPort == 4444)
}

@Test func scanReadmeIgnoresProseMentions() {
    let readme = "Call `make startup` to do stuff, or `makestart` somewhere"
    #expect(ProjectScanner.extractCommandFromReadme(readme) == nil)
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
