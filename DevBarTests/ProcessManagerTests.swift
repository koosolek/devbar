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
    let path = ProcessManager.findPm2Path()
    if let path {
        #expect(path.hasSuffix("pm2"))
    }
}
