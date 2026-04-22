import Foundation

/// Scans pm2 log files for URLs the project has printed to stdout/stderr
/// and cross-references them with currently-listening ports. If a URL in
/// the logs has a port that's actually listening, we treat that as the
/// project's canonical dev URL. Works for Docker-launched services where
/// we can't tie the listener back to our pm2 process any other way.
enum LogURLDetector {
    /// Max bytes to read from the tail of each log file. Large compose
    /// projects can produce multi-MB logs, and we only need recent output.
    private static let tailBytes = 128 * 1024

    /// Returns a URL the project is serving on, or nil if no log-derived
    /// URL matches any currently listening port.
    static func detectURL(forPm2Name pm2Name: String, listeningPorts: Set<UInt16>) -> URL? {
        guard !listeningPorts.isEmpty else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".pm2/logs/\(pm2Name)-out.log"),
            home.appending(path: ".pm2/logs/\(pm2Name)-error.log")
        ]
        for url in candidates {
            guard let text = readTail(of: url, bytes: tailBytes) else { continue }
            if let matched = matchURL(in: text, against: listeningPorts) {
                return matched
            }
        }
        return nil
    }

    /// Finds http(s)://host(:port)?/path URLs whose port is in the listening
    /// set. Returns the last match — later log output tends to reflect the
    /// current steady state rather than startup transient messages.
    static func matchURL(in text: String, against listeningPorts: Set<UInt16>) -> URL? {
        let pattern = #"https?://[A-Za-z0-9.\-]+(?::[0-9]+)?(?:/[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%\-]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var latest: URL?
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let r = Range(match.range, in: text),
                  var url = URL(string: String(text[r])),
                  let host = url.host
            else { return }
            if isDocsHost(host) { return }
            // Strip trailing punctuation that regex picked up from prose.
            let stripped = String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)\"'`"))
            if let clean = URL(string: stripped) { url = clean }

            // Scheme implies default port when one isn't in the URL.
            let port = url.port.map(UInt16.init) ?? defaultPort(for: url.scheme)
            if let port, listeningPorts.contains(port) {
                latest = url
            }
        }
        return latest
    }

    private static func defaultPort(for scheme: String?) -> UInt16? {
        switch scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    private static func isDocsHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        let blocked = ["docs.", "github.com", "gitlab.com", "bitbucket.org",
                       "example.com", "docker.com", "kubernetes.io",
                       "k8s.io", "nodejs.org", "python.org", "kind.sigs.k8s.io"]
        return blocked.contains { lower.contains($0) }
    }

    private static func readTail(of url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = UInt64(max(0, Int64(size) - Int64(bytes)))
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
