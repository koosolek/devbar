import Foundation

/// Lightweight check for whether the Docker daemon is reachable.
/// Avoids shelling out to `docker info` — we only need a coarse signal
/// for UI warnings, and the presence of the daemon socket is a reliable
/// stand-in on macOS installations (Docker Desktop, OrbStack, colima).
enum DockerStatus {
    /// Returns true if any known Docker socket path exists as a socket
    /// file. False otherwise. Cheap enough to call per-render.
    static func isRunning() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            home + "/.docker/run/docker.sock",   // Docker Desktop (modern)
            home + "/.orbstack/run/docker.sock", // OrbStack
            home + "/.colima/default/docker.sock", // colima default
            "/var/run/docker.sock"               // generic
        ]
        let fm = FileManager.default
        for path in candidates {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
                return true
            }
        }
        return false
    }
}
