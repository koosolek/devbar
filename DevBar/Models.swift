import Foundation

// MARK: - Port Model

struct ActivePort: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let port: UInt16
    let pid: Int32
    let projectName: String
    let branch: String
    let startTime: Date?

    var url: URL {
        URL(string: "http://localhost:\(port)")!
    }

    init(port: UInt16, pid: Int32, projectName: String, branch: String, startTime: Date?) {
        self.id = "\(port)-\(pid)"
        self.port = port
        self.pid = pid
        self.projectName = projectName
        self.branch = branch
        self.startTime = startTime
    }
}

// MARK: - Scan Result

enum ScanResult: Sendable {
    case success([ActivePort], ScanDiagnostics)
    case failure(ScanError, [ActivePort])
}

struct ScanDiagnostics: Sendable {
    let duration: TimeInterval
    let portsFound: Int
    let dataSource: String
    let timestamp: Date

    var summary: String {
        let ms = (duration * 1000).formatted(.number.precision(.fractionLength(1)))
        let time = timestamp.formatted(date: .omitted, time: .standard)
        return "Scan: \(ms)ms | \(portsFound) ports | source: \(dataSource) | \(time)"
    }
}

enum ScanError: Error, Sendable, LocalizedError {
    case lsofFailed(String)
    case lsofTimeout

    var errorDescription: String? {
        switch self {
        case .lsofFailed(let msg): return "Port scan failed: \(msg)"
        case .lsofTimeout: return "Port scan timed out"
        }
    }
}

// MARK: - Refresh Interval

enum RefreshInterval: Double, CaseIterable, Sendable {
    case fast = 2
    case normal = 5
    case relaxed = 10
    case slow = 30

    static let defaultInterval: RefreshInterval = .normal
}

// MARK: - DevBar Models

struct DiscoveredProject: Identifiable, Equatable, Hashable, Sendable {
    let name: String
    let path: String
    let relativePath: String
    let startCommand: String
    /// Port detected from an explicit `--port NNNN` flag in the dev/start
    /// script. `nil` means we couldn't infer it from package.json; callers
    /// may still know the port from a prior run.
    let expectedPort: UInt16?

    init(name: String, path: String, relativePath: String, startCommand: String, expectedPort: UInt16? = nil) {
        self.name = name
        self.path = path
        self.relativePath = relativePath
        self.startCommand = startCommand
        self.expectedPort = expectedPort
    }

    var id: String { path }

    var pm2Name: String {
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        return "devbar-\(slug)-\(Self.stableSuffix(for: path))"
    }

    /// Short, deterministic hex suffix derived from the project path.
    /// Ensures two projects that share the same name (e.g. nested
    /// monorepos both called "cds") still get distinct pm2 process names.
    static func stableSuffix(for path: String) -> String {
        var h: UInt64 = 5381
        for byte in path.utf8 {
            h = (h &* 33) &+ UInt64(byte)
        }
        return String(format: "%04x", UInt16(truncatingIfNeeded: h))
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
