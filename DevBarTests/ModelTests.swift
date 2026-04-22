import Testing
import Foundation
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
    #expect(project.pm2Name.hasPrefix("devbar-frontend-"))
    #expect(project.pm2Name.count == "devbar-frontend-".count + 4)
}

@Test func discoveredProjectPm2NameSanitization() {
    let project = DiscoveredProject(
        name: "my cool app",
        path: "/Users/me/Code/my cool app",
        relativePath: "my cool app",
        startCommand: "npm run dev"
    )
    #expect(project.pm2Name.hasPrefix("devbar-my-cool-app-"))
}

@Test func pm2NameIsStableForSamePath() {
    let a = DiscoveredProject(name: "cds", path: "/A/cds",
                              relativePath: "A/cds", startCommand: "npm run dev")
    let b = DiscoveredProject(name: "cds", path: "/A/cds",
                              relativePath: "A/cds", startCommand: "npm run dev")
    #expect(a.pm2Name == b.pm2Name)
}

@Test func pm2NameDiffersForSameNameDifferentPath() {
    let a = DiscoveredProject(name: "cds", path: "/Users/me/Code/Perforce/cds",
                              relativePath: "Perforce/cds", startCommand: "npm run dev")
    let b = DiscoveredProject(name: "cds", path: "/Users/me/Code/Perforce/cds-setup/cds",
                              relativePath: "Perforce/cds-setup/cds", startCommand: "npm run dev")
    #expect(a.pm2Name != b.pm2Name)
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
