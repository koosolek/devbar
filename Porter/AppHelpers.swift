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
        let tempInstallURL = destinationURL
            .deletingLastPathComponent()
            .appending(path: "Port Menu.install-\(UUID().uuidString).app")
        var backedUpExistingInstall = false

        defer {
            try? fileManager.removeItem(at: tempInstallURL)
        }

        if fileManager.fileExists(atPath: destinationURL.path()) {
            let replaceAlert = NSAlert()
            replaceAlert.messageText = "Replace Existing Application?"
            replaceAlert.informativeText = "A copy of Port Menu already exists in Applications. Replace it with this version?"
            replaceAlert.addButton(withTitle: "Replace")
            replaceAlert.addButton(withTitle: "Cancel")
            replaceAlert.alertStyle = .warning

            guard replaceAlert.runModal() == .alertFirstButtonReturn else { return }

            try fileManager.moveItem(at: destinationURL, to: backupURL)
            backedUpExistingInstall = true
        }

        try fileManager.copyItem(at: sourceURL, to: tempInstallURL)
        try fileManager.moveItem(at: tempInstallURL, to: destinationURL)

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
        showApplicationsInstallError(error)
    }
}

@MainActor
private func showApplicationsInstallError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Couldn’t Install Port Menu"
    alert.informativeText = "Port Menu could not be copied to the Applications folder.\n\n\(error.localizedDescription)"
    alert.addButton(withTitle: "OK")
    alert.alertStyle = .warning
    alert.runModal()
}
