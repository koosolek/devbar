import SwiftUI
import Network

// ──────────────────────────────────────────────
// Config – add/remove ports here
// ──────────────────────────────────────────────

let portMap: [(port: UInt16, name: String)] = [
    (3000,  "Next.js"),
    (5173,  "Vite"),
    (8080,  "Node API"),
    (9229,  "Node Debug"),
    (19000, "Expo"),
]

// ──────────────────────────────────────────────
// App entry point
// ──────────────────────────────────────────────

@main
struct PorterApp: App {
    var body: some Scene {
        MenuBarExtra("Porter", systemImage: "network") {
            PortListView()
        }
        .menuBarExtraStyle(.window)
    }
}

// ──────────────────────────────────────────────
// Model
// ──────────────────────────────────────────────

struct PortEntry: Identifiable {
    let id: UInt16
    let name: String
    var isUp = false

    var label: String { "localhost:\(id)" }
    var url: URL { URL(string: "http://localhost:\(id)")! }
}

// ──────────────────────────────────────────────
// ViewModel – polling + lightweight TCP probe
// ──────────────────────────────────────────────

final class PortStore: ObservableObject {
    @Published var entries: [PortEntry]
    @Published var showDown = true

    private var timer: Timer?
    private static let queue = DispatchQueue(label: "porter.probe", attributes: .concurrent)

    init() {
        entries = portMap.map { PortEntry(id: $0.port, name: $0.name) }
    }

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        for i in entries.indices {
            let port = entries[i].id
            Self.probe(port: port) { [weak self] up in
                DispatchQueue.main.async {
                    guard let self, i < self.entries.count else { return }
                    self.entries[i].isUp = up
                }
            }
        }
    }

    /// Pure TCP connect to loopback with 200ms timeout. No HTTP, no shell.
    private static func probe(port: UInt16, completion: @escaping (Bool) -> Void) {
        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        var done = false
        let lock = NSLock()

        func finish(_ value: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            completion(value)
        }

        conn.stateUpdateHandler = { (state: NWConnection.State) in
            switch state {
            case .ready:
                finish(true)
                conn.cancel()
            case .failed:
                finish(false)
                conn.cancel()
            case .cancelled:
                finish(false)
            default:
                break
            }
        }

        conn.start(queue: queue)

        queue.asyncAfter(deadline: .now() + .milliseconds(200)) {
            finish(false)
            conn.cancel()
        }
    }
}

// ──────────────────────────────────────────────
// Views
// ──────────────────────────────────────────────

struct PortListView: View {
    @StateObject private var store = PortStore()

    private var visible: [PortEntry] {
        store.showDown ? store.entries : store.entries.filter(\.isUp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if visible.isEmpty {
                Text("No ports to show")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(visible) { entry in
                    PortRow(entry: entry)
                }
            }

            Divider()
            footer
        }
        .frame(width: 300)
        .onAppear { store.startPolling() }
        .onDisappear { store.stopPolling() }
    }

    private var header: some View {
        HStack {
            Text("Porter").font(.headline)
            Spacer()
            Button(action: store.refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Toggle("Show inactive", isOn: $store.showDown)
                .toggleStyle(.checkbox)
                .controlSize(.small)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct PortRow: View {
    let entry: PortEntry

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(entry.isUp ? Color.green : Color.red.opacity(0.5))
                .frame(width: 8, height: 8)

            Text(entry.label)
                .font(.system(.body, design: .monospaced))

            Spacer()

            Text(entry.name)
                .foregroundStyle(.secondary)
                .font(.callout)

            Text(entry.isUp ? "up" : "down")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(entry.isUp ? Color.green.opacity(0.15) : Color.red.opacity(0.1))
                .foregroundStyle(entry.isUp ? .green : .red)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if entry.isUp {
                Button { NSWorkspace.shared.open(entry.url) } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open in browser")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}
