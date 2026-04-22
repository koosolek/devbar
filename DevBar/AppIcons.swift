import AppKit

/// Fetches an installed app's icon by bundle identifier, cached for the
/// process lifetime. Used to show real editor/browser icons in the list
/// instead of generic SF Symbols. Returns nil if the app isn't installed
/// — callers should fall back to a symbol.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage?] = [:]

    static func icon(forBundleIdentifier bundleId: String) -> NSImage? {
        if let cached = cache[bundleId] { return cached }
        let image = loadIcon(forBundleIdentifier: bundleId)
        cache[bundleId] = image
        return image
    }

    /// Load the raw icon from the app bundle's CFBundleIconFile resource.
    /// We avoid `NSWorkspace.icon(forFile:)` for bundles because it wraps
    /// legacy (pre–Big Sur) app icons in a generic "application" squircle
    /// template — that's what makes VS Code render with extra padding while
    /// modern template-compliant icons like Safari don't. Reading the .icns
    /// directly gives us the artwork as authored.
    private static func loadIcon(forBundleIdentifier bundleId: String) -> NSImage? {
        let ws = NSWorkspace.shared
        guard let appURL = ws.urlForApplication(withBundleIdentifier: bundleId),
              let bundle = Bundle(url: appURL)
        else { return nil }

        let iconName = (bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String)

        if let iconName {
            let base = iconName.hasSuffix(".icns") ? String(iconName.dropLast(5)) : iconName
            if let url = bundle.urlForImageResource(base),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        // Fall back only if we really can't read the resource.
        return ws.icon(forFile: appURL.path)
    }

    /// Try each candidate in order, returning the first icon that resolves.
    /// Apps with unstable/versioned bundle IDs (Cursor, VS Code Insiders, etc.)
    /// can provide multiple candidates.
    static func icon(forAnyBundleIdentifier candidates: [String]) -> NSImage? {
        for bundleId in candidates {
            if let image = icon(forBundleIdentifier: bundleId) {
                return image
            }
        }
        return nil
    }

    /// Returns the bundle identifier of the system default browser (the app
    /// macOS hands `http://` URLs to). `nil` if none is resolved.
    static func defaultBrowserBundleIdentifier() -> String? {
        guard let url = URL(string: "http://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
              let bundle = Bundle(url: appURL)
        else { return nil }
        return bundle.bundleIdentifier
    }

    static func defaultBrowserIcon() -> NSImage? {
        defaultBrowserBundleIdentifier().flatMap { icon(forBundleIdentifier: $0) }
    }

    /// Icon of whatever app macOS hands `.command` files to (Terminal by
    /// default, but iTerm2/Warp if the user has overridden). That's the app
    /// our log scripts actually open.
    static func terminalIcon() -> NSImage? {
        let probe = URL(fileURLWithPath: "/tmp/devbar-terminal-probe.command")
        if let url = NSWorkspace.shared.urlForApplication(toOpen: probe),
           let bundle = Bundle(url: url),
           let bundleId = bundle.bundleIdentifier,
           let icon = icon(forBundleIdentifier: bundleId) {
            return icon
        }
        return icon(forBundleIdentifier: "com.apple.Terminal")
    }
}
