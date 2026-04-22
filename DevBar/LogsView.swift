import SwiftUI

/// In-app log viewer for a pm2-managed project. Polls the pm2 log files
/// and renders them monospaced. Replaces the old Terminal-based flow,
/// which had two problems: (1) closing the Terminal window showed a
/// misleading "process will be terminated" prompt even though only the
/// `pm2 logs` client was affected, not the managed server, and (2) we
/// couldn't suppress that prompt without requiring Automation permission.
struct LogsView: View {
    let pm2Name: String
    let projectName: String

    @State private var content: String = ""
    @State private var hasLoaded = false
    @State private var pollTimer: Timer?
    @State private var autoScrollTick = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logBody
        }
        .frame(minWidth: 500, minHeight: 300)
        .onAppear {
            refresh()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                refresh()
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(projectName)
                .font(.system(size: 13, weight: .semibold))
            Text("·")
                .foregroundStyle(.tertiary)
            Text(pm2Name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear view") { content = "" }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Button("Reveal in Finder") { revealLogDir() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                if content.isEmpty {
                    Text(hasLoaded ? "No logs yet." : "Loading…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    Text(content)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("logContent")
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .onChange(of: autoScrollTick) { _, _ in
                withAnimation(.linear(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var outLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".pm2/logs/\(pm2Name)-out.log")
    }

    private var errLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".pm2/logs/\(pm2Name)-error.log")
    }

    private func refresh() {
        let out = (try? String(contentsOf: outLogURL, encoding: .utf8)) ?? ""
        let err = (try? String(contentsOf: errLogURL, encoding: .utf8)) ?? ""
        let combined = err.isEmpty ? out : out + "\n--- stderr ---\n" + err

        // Keep only the last ~800 lines so the view doesn't balloon.
        let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed: String
        if lines.count > 800 {
            trimmed = lines.suffix(800).joined(separator: "\n")
        } else {
            trimmed = combined
        }

        hasLoaded = true
        guard trimmed != content else { return }
        content = trimmed
        autoScrollTick &+= 1
    }

    private func revealLogDir() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".pm2/logs")
        NSWorkspace.shared.activateFileViewerSelecting([outLogURL])
        _ = dir  // silence unused warning if future code changes
    }
}
