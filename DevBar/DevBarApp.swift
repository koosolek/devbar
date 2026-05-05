import AppKit
import SwiftUI

@main
struct DevBarApp: App {
    @State private var store = PortStore.shared
    @State private var settings = SettingsStore()

    init() {
        moveToApplicationsIfNeeded()
        LaunchAtLogin.ensureRegisteredByDefault()
    }

    var body: some Scene {
        MenuBarExtra {
            DevBarMainView()
                .environment(store)
                .environment(settings)
        } label: {
            let runningCount = store.projects.filter { project in
                if case .running = store.projectStates[project.path] { return true }
                return false
            }.count
            let errorCount = store.projects.filter { project in
                if case .error = store.projectStates[project.path] { return true }
                return false
            }.count
            // MenuBarExtra's status-button renders SwiftUI views
            // unreliably when the label contains more than one Image
            // (HStack, Text+Image interpolation, overlays all failed).
            // Pre-rendering both SF Symbols into a single NSImage via
            // Core Graphics is the approach apps like Stats use — the
            // status button then just displays one image.
            Image(nsImage: menuBarImage(runningCount: runningCount, errorCount: errorCount))
            .onAppear {
                store.ensurePolling()
                if settings.hasRootFolder {
                    store.scanProjects(rootFolder: settings.rootFolder)
                }
            }
        }
        .menuBarExtraStyle(.window)

        // Log viewer window — one per project, addressed by pm2 name.
        WindowGroup(id: "logs", for: LogWindowTarget.self) { $target in
            if let target {
                LogsView(pm2Name: target.pm2Name, projectName: target.projectName)
                    .navigationTitle("Logs · \(target.projectName)")
            }
        }
        .defaultSize(width: 760, height: 460)
    }
}

/// Small value type so we can pass both pm2 name and display name to a
/// WindowGroup(for:) scene.
struct LogWindowTarget: Hashable, Codable {
    let pm2Name: String
    let projectName: String
}

/// Slightly desaturated blue used for the running-count badge. Reads as
/// neutral status next to the more attention-grabbing red error badge.
private let countBadgeFill = NSColor(srgbRed: 0.36, green: 0.58, blue: 0.85, alpha: 1.0)

/// Build the menu-bar image: drive icon (template-style, crisp, adapts
/// to menu-bar theme) + a manually-drawn badge.
///
/// Errors override the running count — one signal at a time: red `!` when
/// any project is in `.error`, otherwise muted blue digit when something is
/// running, otherwise no badge.
///
/// The badge is hand-drawn rather than sourced from an SF Symbol because
/// `N.circle.fill` is single-layer — its digit is a transparent cutout, so
/// tinting the whole symbol makes the digit/`!` disappear entirely.
private func menuBarImage(runningCount: Int, errorCount: Int) -> NSImage {
    let canvas = NSSize(width: 26, height: 18)
    let image = NSImage(size: canvas, flipped: false) { _ in
        // Drive icon, centered. `pointSize: 14` matches the stock
        // menu-bar icon metric (bumping higher makes the drive look
        // oversized + slightly soft). Origin rounded so the glyph lands
        // on whole-pixel boundaries — sub-pixel origins are the usual
        // cause of a "blurry" SF Symbol in a custom NSImage canvas.
        let driveConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let drive = NSImage(systemSymbolName: "externaldrive.fill",
                               accessibilityDescription: nil)?
            .withSymbolConfiguration(driveConfig) {
            let origin = NSPoint(
                x: floor((canvas.width - drive.size.width) / 2),
                y: floor((canvas.height - drive.size.height) / 2)
            )
            drive.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            let driveRect = NSRect(origin: origin, size: drive.size)
            NSColor.textColor.setFill()
            driveRect.fill(using: .sourceAtop)
        }

        let badge: (text: String, fill: NSColor)? = {
            if errorCount > 0 {
                return ("!", .systemRed)
            }
            if runningCount > 0 {
                return (runningCount > 9 ? "∞" : "\(runningCount)", countBadgeFill)
            }
            return nil
        }()

        if let badge {
            let diameter: CGFloat = 12
            let circleRect = NSRect(
                x: canvas.width - diameter,
                y: canvas.height - diameter,
                width: diameter,
                height: diameter
            )
            badge.fill.setFill()
            NSBezierPath(ovalIn: circleRect).fill()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let glyph = NSAttributedString(string: badge.text, attributes: attrs)
            let glyphSize = glyph.size()
            // +1 on Y because the glyph baseline metrics leave it
            // sitting slightly low within the circle.
            let glyphOrigin = NSPoint(
                x: circleRect.midX - glyphSize.width / 2,
                y: circleRect.midY - glyphSize.height / 2 + 1
            )
            glyph.draw(at: glyphOrigin)
        }
        return true
    }
    return image
}
