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
        if scripts["dev"] != nil {
            startCommand = "npm run dev"
        } else if scripts["start"] != nil {
            startCommand = "npm start"
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
            startCommand: startCommand
        )
    }
}
