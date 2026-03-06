import AppKit
import os

@MainActor
func moveToApplicationsIfNeeded() {
    let bundlePath = Bundle.main.bundlePath

    var sourcePath = bundlePath
    if bundlePath.contains("AppTranslocation") {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path()
        let appName = URL(filePath: bundlePath).lastPathComponent
        let candidates = ["\(home)/Downloads/\(appName)", "\(home)/Desktop/\(appName)"]
        if let real = candidates.first(where: { fm.fileExists(atPath: $0) }) {
            sourcePath = real
        }
    }

    guard !sourcePath.hasPrefix("/Applications/"),
          !sourcePath.contains("DerivedData"),
          !sourcePath.hasPrefix("/tmp/"),
          !sourcePath.contains("AppTranslocation") else { return }

    let fileManager = FileManager.default
    let sourceURL = URL(filePath: sourcePath)
    let destinationURL = URL(filePath: "/Applications/Port Menu.app")

    guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else { return }

    let alert = NSAlert()
    alert.messageText = "Move to Applications Folder?"
    alert.informativeText = "Port Menu works best when run from the Applications folder."
    alert.addButton(withTitle: "Move to Applications")
    alert.addButton(withTitle: "Don't Move")
    alert.alertStyle = .informational

    guard alert.runModal() == .alertFirstButtonReturn else { return }

    do {
        let backupURL = destinationURL
            .deletingLastPathComponent()
            .appending(path: "Port Menu.backup-\(UUID().uuidString).app")
        var backedUpExistingInstall = false

        if fileManager.fileExists(atPath: destinationURL.path()) {
            try fileManager.moveItem(at: destinationURL, to: backupURL)
            backedUpExistingInstall = true
        }

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            if backedUpExistingInstall && !fileManager.fileExists(atPath: destinationURL.path()) {
                try? fileManager.moveItem(at: backupURL, to: destinationURL)
            }
            throw error
        }

        if backedUpExistingInstall {
            try? fileManager.removeItem(at: backupURL)
        }

        let task = Process()
        task.executableURL = URL(filePath: "/usr/bin/open")
        task.arguments = [destinationURL.path()]
        try task.run()
        NSApp.terminate(nil)
    } catch {
        Log.lifecycle.error("Failed to move app to Applications: \(error.localizedDescription)")
    }
}
