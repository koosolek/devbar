import Testing
import Foundation
@testable import DevBar

@Test func startCommandConstructionRunScript() {
    let project = DiscoveredProject(
        name: "frontend",
        path: "/Users/me/Code/frontend",
        relativePath: "Personal/frontend",
        startCommand: "npm run dev"
    )
    let args = ProcessManager.startArguments(for: project)
    #expect(args == [
        "start", "npm",
        "--name", project.pm2Name,
        "--cwd", "/Users/me/Code/frontend",
        "--max-restarts", "3",
        "--", "run", "dev"
    ])
}

@Test func startCommandConstructionNpmStart() {
    let project = DiscoveredProject(
        name: "api",
        path: "/Users/me/Code/api",
        relativePath: "api",
        startCommand: "npm start"
    )
    let args = ProcessManager.startArguments(for: project)
    #expect(args == [
        "start", "npm",
        "--name", project.pm2Name,
        "--cwd", "/Users/me/Code/api",
        "--max-restarts", "3",
        "--", "start"
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
    #expect(args == ["stop", project.pm2Name])
}

@Test func deleteCommandConstruction() {
    let project = DiscoveredProject(
        name: "frontend",
        path: "/Users/me/Code/frontend",
        relativePath: "Personal/frontend",
        startCommand: "npm run dev"
    )
    let args = ProcessManager.deleteArguments(for: project)
    #expect(args == ["delete", project.pm2Name])
}

@Test func pm2PathResolution() {
    let path = ProcessManager.findPm2Path()
    if let path {
        #expect(path.hasSuffix("pm2"))
    }
}
