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
            // MenuBarExtra's status-button renders SwiftUI views
            // unreliably when the label contains more than one Image
            // (HStack, Text+Image interpolation, overlays all failed).
            // Pre-rendering both SF Symbols into a single NSImage via
            // Core Graphics is the approach apps like Stats use — the
            // status button then just displays one image.
            Image(nsImage: menuBarImage(count: runningCount))
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

/// SF Symbol name for the running-count badge. `N.circle.fill` exists for
/// every integer from 0 through 50; anything above becomes an ellipsis
/// badge as an easter egg / overflow indicator.
private func badgeSymbolName(for count: Int) -> String {
    count >= 0 && count <= 50 ? "\(count).circle.fill" : "ellipsis.circle.fill"
}

/// Build the menu-bar image: drive icon (template-style, crisp, adapts
/// to menu-bar theme) + a manually-drawn red circle with a white digit
/// as the badge, placed top-right. Only drawn when count > 0.
///
/// The badge is hand-drawn rather than sourced from `N.circle.fill`
/// because that SF Symbol is single-layer — its digit is a transparent
/// cutout, so tinting the symbol red makes the digit disappear entirely.
private func menuBarImage(count: Int) -> NSImage {
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

        // Red circle + white digit, drawn by hand for full control over
        // both layers. Skipped entirely when nothing is running.
        if count > 0 {
            let diameter: CGFloat = 12
            let circleRect = NSRect(
                x: canvas.width - diameter,
                y: canvas.height - diameter,
                width: diameter,
                height: diameter
            )
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: circleRect).fill()

            let text = count > 9 ? "∞" : "\(count)"
            let digitAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let digit = NSAttributedString(string: text, attributes: digitAttrs)
            let digitSize = digit.size()
            // +1 on Y because the glyph baseline metrics leave it
            // sitting slightly low within the circle.
            let digitOrigin = NSPoint(
                x: circleRect.midX - digitSize.width / 2,
                y: circleRect.midY - digitSize.height / 2 + 1
            )
            digit.draw(at: digitOrigin)
        }
        return true
    }
    return image
}
