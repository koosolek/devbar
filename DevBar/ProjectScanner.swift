import Foundation

struct ProjectScanner: Sendable {
    private static let maxDepth = 3

    func scan(rootFolder: String) -> [DiscoveredProject] {
        let rootURL = URL(fileURLWithPath: rootFolder).resolvingSymlinksInPath()
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
        // Never descend into system or other-app directories — they're not
        // dev projects and reading inside them triggers macOS TCC prompts.
        if LivePortScanner.isProtectedSystemPath(url.path()) { return }

        let packageJsonURL = url.appendingPathComponent("package.json")
        if let project = parsePackageJson(at: packageJsonURL, projectURL: url, rootURL: rootURL) {
            results.append(project)
            return
        }

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
        let scriptBody: String
        if let dev = scripts["dev"] {
            startCommand = "npm run dev"
            scriptBody = dev
        } else if let start = scripts["start"] {
            startCommand = "npm start"
            scriptBody = start
        } else {
            return nil
        }

        let name = projectURL.lastPathComponent
        let resolvedProject = projectURL.resolvingSymlinksInPath()
        let relativePath = resolvedProject.path
            .replacingOccurrences(of: rootURL.path + "/", with: "")

        return DiscoveredProject(
            name: name,
            path: resolvedProject.path,
            relativePath: relativePath,
            startCommand: startCommand,
            expectedPort: Self.extractPort(from: scriptBody)
        )
    }

    /// Best-effort: look for `--port 5173` or `--port=5173` in a script body.
    /// Config-file inference (vite.config.ts etc.) is intentionally skipped —
    /// it's fragile across tooling versions. Combined with the last-known-port
    /// cache this covers enough ground to catch common collisions.
    static func extractPort(from script: String) -> UInt16? {
        guard let range = script.range(
            of: #"--port[=\s]+(\d+)"#,
            options: .regularExpression
        ) else { return nil }
        let digits = script[range].drop(while: { !$0.isNumber })
        return UInt16(digits)
    }
}
