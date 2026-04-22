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

        // Priority: package.json → Makefile → README. First hit wins; we
        // don't descend further once we've claimed this directory as a
        // project, so a monorepo root shadowing its packages is by design.
        if let project = parsePackageJson(at: url.appendingPathComponent("package.json"),
                                          projectURL: url, rootURL: rootURL) {
            results.append(project)
            return
        }
        if let project = parseMakefile(at: url.appendingPathComponent("Makefile"),
                                       projectURL: url, rootURL: rootURL) {
            results.append(project)
            return
        }
        if let project = parseReadme(in: url, projectURL: url, rootURL: rootURL) {
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
              let scripts = json["scripts"] as? [String: String]
        else { return nil }

        // If a package.json doesn't declare a dev/start script, it's almost
        // always a library (build + test only). Surfacing those as
        // "unsupported" would bury the list in noise, so we stay strict
        // here — Makefile detection below is where we tolerate ambiguity.
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

        let scriptPort = Self.extractPort(from: scriptBody)
        let expectedPort = scriptPort ?? Self.findViteConfigPort(in: projectURL)

        return makeProject(
            at: projectURL,
            rootURL: rootURL,
            startCommand: startCommand,
            expectedPort: expectedPort
        )
    }

    /// Best-effort: look for `--port 5173` or `--port=5173` in a script body.
    static func extractPort(from script: String) -> UInt16? {
        guard let range = script.range(
            of: #"--port[=\s]+(\d+)"#,
            options: .regularExpression
        ) else { return nil }
        let digits = script[range].drop(while: { !$0.isNumber })
        return UInt16(digits)
    }

    /// Walks into the project looking for a Vite config and reads `port:` from
    /// it. Needed for monorepos where the outer package.json just delegates
    /// to a workspace package (`pnpm --filter foo dev`), so there's no
    /// `--port` flag to parse at the root.
    static func findViteConfigPort(in directory: URL, maxDepth: Int = 3) -> UInt16? {
        guard maxDepth >= 0 else { return nil }
        let names = [
            "vite.config.ts", "vite.config.js",
            "vite.config.mts", "vite.config.mjs", "vite.config.cjs"
        ]
        for name in names {
            let url = directory.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8),
               let port = extractPortFromViteConfig(text) {
                return port
            }
        }
        guard maxDepth > 0,
              let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return nil }
        for child in children {
            // Avoid the node_modules black hole — it contains thousands of
            // tiny vite configs belonging to dependencies.
            if child.lastPathComponent == "node_modules" { continue }
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            if let port = findViteConfigPort(in: child, maxDepth: maxDepth - 1) {
                return port
            }
        }
        return nil
    }

    static func extractPortFromViteConfig(_ content: String) -> UInt16? {
        guard let range = content.range(
            of: #"port\s*:\s*(\d+)"#,
            options: .regularExpression
        ) else { return nil }
        let digits = content[range].drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
        return UInt16(digits)
    }

    // MARK: - Makefile parsing

    private func parseMakefile(
        at url: URL,
        projectURL: URL,
        rootURL: URL
    ) -> DiscoveredProject? {
        guard let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8)
        else { return nil }
        let command = Self.extractMakeTarget(from: contents).map { "make \($0)" }
        return makeProject(
            at: projectURL,
            rootURL: rootURL,
            startCommand: command
        )
    }

    /// Finds `dev:` / `start:` / `run:` / `up:` declarations at line start.
    /// Matches only a full-word target name so `start:` matches but
    /// `start-service:` or `.PHONY: start dev` do not.
    static func extractMakeTarget(from makefile: String) -> String? {
        let candidates = ["dev", "start", "run", "up"]
        for target in candidates {
            let pattern = "(?m)^\(target)[ \\t]*:"
            if makefile.range(of: pattern, options: .regularExpression) != nil {
                return target
            }
        }
        return nil
    }

    // MARK: - README parsing

    /// Fallback when neither package.json nor Makefile hints at a dev
    /// command. Scans README(.md/.MD/.txt) for a known command pattern.
    private func parseReadme(
        in directory: URL,
        projectURL: URL,
        rootURL: URL
    ) -> DiscoveredProject? {
        let candidateNames = ["README.md", "Readme.md", "readme.md", "README", "README.txt"]
        for name in candidateNames {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let contents = String(data: data, encoding: .utf8),
                  let command = Self.extractCommandFromReadme(contents)
            else { continue }
            return makeProject(
                at: projectURL,
                rootURL: rootURL,
                startCommand: command
            )
        }
        return nil
    }

    /// Pattern-based: check the README text for any command in our
    /// priority list. First hit wins. Intentionally narrow — we only match
    /// invocations that look like recognised dev commands, so prose
    /// mentions of "start the server" don't trigger a false positive.
    static func extractCommandFromReadme(_ content: String) -> String? {
        let candidates = [
            "make dev", "make start", "make up", "make run",
            "pnpm dev", "pnpm start",
            "npm run dev", "npm start",
            "yarn dev", "yarn start",
            "bun dev", "bun start"
        ]
        for candidate in candidates {
            let escaped = NSRegularExpression.escapedPattern(for: candidate)
            let pattern = "(?<![A-Za-z0-9_])\(escaped)(?![A-Za-z0-9_])"
            if content.range(of: pattern, options: .regularExpression) != nil {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func makeProject(
        at projectURL: URL,
        rootURL: URL,
        startCommand: String?,
        expectedPort: UInt16? = nil
    ) -> DiscoveredProject {
        let name = projectURL.lastPathComponent
        let resolvedProject = projectURL.resolvingSymlinksInPath()
        let relativePath = resolvedProject.path
            .replacingOccurrences(of: rootURL.path + "/", with: "")
        let hasCompose = Self.hasComposeFile(in: projectURL)
        return DiscoveredProject(
            name: name,
            path: resolvedProject.path,
            relativePath: relativePath,
            startCommand: startCommand,
            expectedPort: expectedPort,
            composePorts: Self.composePortsIn(projectURL),
            requiresDocker: hasCompose
        )
    }

    static func hasComposeFile(in directory: URL) -> Bool {
        for name in composeFileNames {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return true }
        }
        return false
    }

    // MARK: - docker-compose parsing

    private static let composeFileNames = [
        "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"
    ]

    /// Return host ports declared across all services in an adjacent
    /// docker-compose file. Returns `[]` if no compose file exists.
    static func composePortsIn(_ directory: URL) -> [UInt16] {
        for name in composeFileNames {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let contents = String(data: data, encoding: .utf8) else { continue }
            return extractComposePorts(contents)
        }
        return []
    }

    /// Naive YAML walker: tracks the indent of the nearest `ports:` block
    /// and collects host ports from `- "HOST:CONTAINER"` / `- HOST` lines
    /// while we're inside it. Good enough for real compose files without
    /// pulling in a YAML dependency.
    static func extractComposePorts(_ compose: String) -> [UInt16] {
        var ports: [UInt16] = []
        var seen: Set<UInt16> = []
        var portsIndent: Int? = nil

        for rawLine in compose.components(separatedBy: .newlines) {
            let indent = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if let block = portsIndent {
                // Leaving the ports: block once we dedent back to or past its indent.
                if indent <= block {
                    portsIndent = nil
                } else if trimmed.hasPrefix("-") {
                    let item = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                    let unquoted = item.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    let hostPart = unquoted.split(separator: ":", maxSplits: 1).first.map(String.init) ?? unquoted
                    if let port = UInt16(hostPart), seen.insert(port).inserted {
                        ports.append(port)
                    }
                    continue
                }
            }
            if trimmed == "ports:" || trimmed.hasPrefix("ports:") && trimmed.hasSuffix(":") {
                portsIndent = indent
            }
        }
        return ports
    }
}
