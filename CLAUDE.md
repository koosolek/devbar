# DevBar

## What this is

A macOS menu bar app for managing local dev servers. Forked from [Port Menu](https://github.com/wieandteduard/port-menu), which only monitors ports. DevBar adds the ability to discover projects, start/stop them via pm2, and open URLs and editors — all without terminal windows.

## Why it exists

The problem: running dev servers means keeping terminal windows open, losing track of what's running, and manually remembering URLs. Existing tools either only monitor ports (Port Menu, LocalPorts) or still open terminal windows (Noodles). DevBar combines project discovery + backgrounded process management + a clean menu bar UI.

## Architecture

Three components layered on top of Port Menu's existing port scanner:

- **ProjectScanner** (`ProjectScanner.swift`) — scans a configured root folder up to 3 levels deep for `package.json` files with `dev` or `start` scripts
- **ProcessManager** (`ProcessManager.swift`) — wraps pm2 CLI via Swift's `Process` API. All managed processes are namespaced with `devbar-` prefix
- **PortStore** (`PortStore.swift`, extended) — Port Menu's existing `lsof`-based port scanner, extended to cross-reference detected ports with discovered projects and manage project states

Settings are persisted via `@AppStorage` in `SettingsStore.swift`.

## Tech stack

- Swift / SwiftUI, macOS 14+ (Sonoma)
- Xcode 15+
- pm2 (external dependency, installed via `npm install -g pm2`)

## Build and test

```bash
xcodebuild -scheme DevBar -configuration Debug build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
xcodebuild test -scheme DevBar -destination "platform=macOS" CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

## Design decisions

- **pm2 over raw background processes** — pm2 handles daemonization, crash recovery, and log management. We shell out to the pm2 CLI rather than reimplementing process management
- **Port Menu fork over building from scratch** — Port Menu already had working menu bar infrastructure, `lsof`-based port scanning, git project detection, and sleep/wake awareness. Saved significant effort
- **Sparkle removed** — auto-update framework from Port Menu, not needed for a personal tool
- **Node-first, extensible** — only detects `package.json` projects for now. Other project types (Cargo.toml, docker-compose.yml) can be added by teaching ProjectScanner new markers
- **No per-project config files** — the app infers start commands from package.json. If it can't figure out the command, the project is skipped. Keeps things simple
- **Monochrome UI** — follows system light/dark theme, no color-coded status indicators. Running vs available is communicated through section separation

## Known issues

- **Port conflicts when running multiple projects that share the same port** — e.g. prototypes built from the same starter template all default to port 5173 with `strictPort: true`. Fix: have DevBar auto-assign unique ports and pass them as a `PORT` env variable via pm2. Requires the starter's `vite.config.ts` to read `process.env.PORT` instead of hardcoding. See `pd-perforce-prototype-starter` repo's `apps/frontend/vite.config.ts`.

## Key files

| File | Purpose |
|------|---------|
| `DevBarApp.swift` | App entry point, menu bar setup |
| `Models.swift` | `ActivePort` (from Port Menu), `DiscoveredProject`, `ProjectState`, `EditorOption` |
| `ProjectScanner.swift` | Folder scanning and package.json parsing |
| `ProcessManager.swift` | pm2 CLI wrapper (start, stop, status, logs) |
| `PortStore.swift` | Port polling + project state management |
| `SettingsStore.swift` | Root folder and editor preference persistence |
| `PortScanning.swift` | Port Menu's lsof-based port detection (mostly unchanged) |
| `Views.swift` | All SwiftUI views — main list, row types, action buttons |
| `SettingsView.swift` | Settings panel UI |
| `Onboarding.swift` | First-run pm2 check |
