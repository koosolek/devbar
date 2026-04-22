import AppKit
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

    nonisolated static func startArguments(for project: DiscoveredProject) -> [String] {
        guard let command = project.startCommand else { return [] }
        let parts = command
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        let interpreter = parts.first ?? "npm"
        let scriptArgs = Array(parts.dropFirst())

        // --max-restarts 3 limits crash loops. pm2's CLI doesn't expose
        // --min-uptime (only available via ecosystem.config.js), so we
        // can't tune what counts as a "stable" restart from here — retry
        // loops for services that limp for a few seconds before crashing
        // are best handled by the user cancelling.
        var args = ["start", interpreter,
                    "--name", project.pm2Name,
                    "--cwd", project.path,
                    "--max-restarts", "3"]
        if !scriptArgs.isEmpty {
            args.append("--")
            args.append(contentsOf: scriptArgs)
        }
        return args
    }

    nonisolated static func stopArguments(for project: DiscoveredProject) -> [String] {
        ["stop", project.pm2Name]
    }

    nonisolated static func deleteArguments(for project: DiscoveredProject) -> [String] {
        ["delete", project.pm2Name]
    }

    nonisolated static func findPm2Path() -> String? {
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
        let result = Self.runSync(command: "/usr/bin/which", arguments: ["pm2"])
        let trimmed = result?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return nil
    }

    // MARK: - Actions

    func start(project: DiscoveredProject, extraEnv: [String: String] = [:]) async throws {
        guard let pm2Path else { throw ProcessManagerError.pm2NotFound }
        // Clean up any stale entry for this name so we never end up with duplicates
        // or inherit a stuck "errored" state from a previous run.
        try? await run(command: pm2Path, arguments: Self.deleteArguments(for: project))
        let args = Self.startArguments(for: project)
        try await run(command: pm2Path, arguments: args, extraEnv: extraEnv)
    }

    func stop(project: DiscoveredProject) async throws {
        guard let pm2Path else { throw ProcessManagerError.pm2NotFound }
        let args = Self.stopArguments(for: project)
        try await run(command: pm2Path, arguments: args)
    }

    func delete(project: DiscoveredProject) async throws {
        guard let pm2Path else { throw ProcessManagerError.pm2NotFound }
        let args = Self.deleteArguments(for: project)
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
        guard let pm2Path else {
            Log.lifecycle.error("openLogs: pm2 not found")
            return
        }
        // macOS opens .command files in Terminal by default, so writing a
        // tmp shell script and opening it gives us Terminal output without
        // needing AppleScript (which requires Automation permission and
        // errors with -1743 otherwise).
        let tmpDir = FileManager.default.temporaryDirectory
        let scriptURL = tmpDir.appendingPathComponent("devbar-logs-\(project.pm2Name).command")
        let script = """
        #!/bin/bash
        clear
        echo "Logs: \(project.pm2Name) (Ctrl+C to exit)"
        echo
        exec "\(pm2Path)" logs "\(project.pm2Name)"
        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )
            NSWorkspace.shared.open(scriptURL)
        } catch {
            Log.lifecycle.error("openLogs failed to prepare script: \(error.localizedDescription)")
        }
    }

    // MARK: - pm2 jlist parsing

    nonisolated static func parseJlist(_ json: String) -> [Pm2ProcessInfo] {
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

    private func run(command: String, arguments: [String], extraEnv: [String: String] = [:]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            var env = Self.shellEnvironment()
            for (k, v) in extraEnv { env[k] = v }
            process.environment = env
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

    nonisolated static func runSync(command: String, arguments: [String]) -> String? {
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

    nonisolated private static func shellEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
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
            return "pm2 not found. Install with: npm install -g pm2"
        case .commandFailed(let command, let exitCode):
            return "Command failed (\(exitCode)): \(command)"
        }
    }
}
