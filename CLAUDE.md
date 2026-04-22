# DevBar

## What this is

A macOS menu bar app for managing local dev servers. Forked from [Port Menu](https://github.com/wieandteduard/port-menu), which only monitors ports. DevBar adds the ability to discover projects, start/stop them via pm2, and open URLs and editors — all without terminal windows.

## Why it exists

The problem: running dev servers means keeping terminal windows open, losing track of what's running, and manually remembering URLs. Existing tools either only monitor ports (Port Menu, LocalPorts) or still open terminal windows (Noodles). DevBar combines project discovery + backgrounded process management + a clean menu bar UI.

## Architecture

Core components layered on top of Port Menu's existing port scanner:

- **ProjectScanner** (`ProjectScanner.swift`) — scans a configured root folder up to 3 levels deep. Detection order per directory: `package.json` (dev/start script) → `Makefile` (dev/start/run/up target) → `README` (scans for `make start`, `pnpm dev`, `npm run dev`, etc.). Extracts `expectedPort` from `--port N` flags in scripts; falls back to parsing `vite.config.*` for `server.port`. Parses adjacent `docker-compose*.yml` for all declared host ports (stored as `composePorts`). Flags `requiresDocker` when a compose file is present.
- **ProcessManager** (`ProcessManager.swift`) — wraps pm2 CLI via Swift's `Process` API. pm2 names are `devbar-<slug>-<4-char-path-hash>` so two projects that share a folder name don't collide. Uses `--max-restarts 3 --min-uptime 30000` so crash-loops actually stop.
- **PortStore** (`PortStore.swift`) — state machine keyed by pm2 status + an lsof port matcher. `findPortForProject` ranks candidates (user-linked > log-URL > lsof name-match > any compose port). Only "strong" matches get persisted as `knownPort`; weak compose-port matches transition state but are not remembered. Also exposes `replaceAndStart`, `setKnownPort`/`clearKnownPort`, and `logDetectedURLs` for URL-aware Open URL.
- **LogURLDetector** (`LogURLDetector.swift`) — reads the tail of each project's `~/.pm2/logs/<name>-out.log`, regex-extracts `http(s)://…` URLs whose port is currently listening, and hands them to PortStore. How cds-setup's `https://tenant1.cds-dev.com:8000/` gets auto-attributed.
- **PortAllocator** (`PortAllocator.swift`) — picks first free port in 4100–4199 for the `PORT` env var injected into pm2-launched processes. Toggle: `autoAssignPorts` in Settings.
- **DockerStatus** (`DockerStatus.swift`) — coarse "is the Docker daemon socket present?" check across the common paths (Docker Desktop, OrbStack, colima, `/var/run/docker.sock`). Drives the pre-start warning on compose-based projects.
- **AppIcons** (`AppIcons.swift`) — resolves installed apps' icons for editor/browser/terminal action buttons. Reads raw `.icns` via `Bundle.urlForImageResource` rather than `NSWorkspace.icon(forFile:)`, which wraps legacy (pre–Big Sur) icons in a generic squircle template (VS Code looked "framed" before this).

Settings are persisted via `@AppStorage` in `SettingsStore.swift`. Launch-at-login is registered via `SMAppService.mainApp` (`LaunchAtLogin.swift`) only when DevBar is running from `/Applications/`. The in-app **log viewer** (`LogsView.swift`) is a separate `WindowGroup` scene; opening it requires `NSApplication.shared.activate(...)` because the app is LSUIElement.

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
- **pm2 invocation uses `npm -- run dev` pattern** — `pm2 start npm --name X --cwd /path --max-restarts 3 -- run dev`. Direct `pm2 start "npm run dev"` is unreliable because pm2 splits the string. The `--max-restarts 3` cap stops crash-looping servers (e.g. one that needs Docker when Docker isn't running) from spinning forever.
- **Pre-delete before start** — `pm2 delete <name>` runs before every `pm2 start` so duplicate entries and stale errored states never accumulate.
- **Port Menu fork over building from scratch** — Port Menu already had working menu bar infrastructure, `lsof`-based port scanning, git project detection, and sleep/wake awareness. Saved significant effort
- **Sparkle removed** — auto-update framework from Port Menu, not needed for a personal tool
- **Node-first, extensible** — only detects `package.json` projects for now. Other project types (Cargo.toml, docker-compose.yml) can be added by teaching ProjectScanner new markers
- **No per-project config files** — the app infers start commands from package.json/Makefile/README. Projects where we find a marker but no recognizable run command show up with a "?" and no Start button instead of vanishing — makes detection transparent.
- **Monochrome UI** — follows system light/dark theme. Action buttons use real editor/browser app icons for recognition; everything else is SF Symbols.

## Gotchas / non-obvious behavior

- **TCC prompts from `findGitRoot`** — walking up from a random process's cwd (Docker, Xcode workers) hits `/Applications/X.app/...` or `~/Library/Containers/...`, which triggers macOS "access data from other apps" prompts on every `fileExists` call. `LivePortScanner.isProtectedSystemPath` short-circuits those paths in both `findGitRoot` and `ProjectScanner.scanDirectory`. Any new filesystem walk must route through it.
- **ScrollView with `.frame(maxHeight:)` collapses to 0** — ScrollView has no intrinsic minimum height, so pairing `maxHeight` with `.fixedSize(horizontal: false, vertical: true)` is required in `projectListView` to make the list use natural content height up to the 60%-of-screen cap.
- **pm2 env is captured at CLI invocation** — `ProcessManager.run(extraEnv:)` merges into the Swift `Process` env *before* `pm2 start`, and pm2 captures that env at start time. `pm2 restart` does NOT repick up env, which is why we always `delete → start`.
- **Synchronous project scan is fine** — tried making it async via `Task.detached`; broke the list update path.
- **AppleScript for logs is dead end** — controlling Terminal requires the "Automation" TCC permission, which silently errors with `-1743` if the user ever denied it. We use a SwiftUI in-app log viewer (`LogsView`) instead, tailing `~/.pm2/logs/<name>-{out,error}.log` with polling.
- **LSUIElement window activation** — opening `LogsView` via `openWindow(id:value:)` from the menu-bar popover doesn't surface the window unless `NSApplication.shared.activate(ignoringOtherApps: true)` is called first. Same applies to any future window scene we add.
- **Right-click `.contextMenu` is unreliable inside `MenuBarExtra(.window)`** — popovers sometimes eat secondary clicks. Use an explicit ellipsis button (`Menu` with `.menuIndicator(.hidden)`) for discoverable port Link/Unlink actions.
- **Weak vs strong port matches** — compose-declared ports are a big unordered list (Redis, DB, sidecars, the actual UI). Matching any of them attributes the project's state to running, but must NOT write back to `knownPort` or a sidecar becomes the "main" port forever. `PortStore.PortMatch.isStrong` encodes this.
- **App icons via raw .icns** — `NSWorkspace.icon(forFile: appURL.path)` applies a legacy-template squircle to pre-Big-Sur icons (VS Code looked padded). `AppIcons` reads the app bundle's `CFBundleIconFile` resource directly to get the authored artwork.

## Known issues

- **Hardcoded-port collisions** — DevBar auto-assigns `PORT` for projects that read `process.env.PORT`. Configs that hardcode the port (e.g. Vite `strictPort: true` with a fixed number, no env read) still collide; we surface them via the conflict warning + "Replace" flow but can't override the source port. The proper fix is in the project's own config.

## Key files

| File | Purpose |
|------|---------|
| `DevBarApp.swift` | App entry point, menu bar setup, log-viewer `WindowGroup`, first-launch side effects (move-to-Applications, launch-at-login) |
| `Models.swift` | `ActivePort` (incl. `gitRootPath`), `DiscoveredProject` (incl. `expectedPort`, `composePorts`, `requiresDocker`, optional `startCommand`), `ProjectState`, `EditorOption`, `BrowserOption` |
| `ProjectScanner.swift` | Package.json / Makefile / README detection, `--port` extraction, `vite.config.*` scan, docker-compose port + file detection |
| `ProcessManager.swift` | pm2 CLI wrapper — start (with `--max-restarts 3 --min-uptime 30000`) / stop / delete / status, env passthrough |
| `PortStore.swift` | Port polling + project state + strong/weak port matching, known-port cache, conflict detection, replace-and-start, log URL attribution |
| `PortScanning.swift` | lsof-based port detection, git-root discovery, TCC-safe protected-path guard |
| `PortAllocator.swift` | Picks free port in 4100–4199 for `PORT` env |
| `LogURLDetector.swift` | Scrapes URLs from pm2 log tails and cross-references with listening ports |
| `DockerStatus.swift` | Coarse "is Docker reachable?" check via socket file presence |
| `AppIcons.swift` | Editor/browser/terminal icon lookup — reads raw `.icns` instead of using NSWorkspace's legacy-template wrapper |
| `LaunchAtLogin.swift` | `SMAppService.mainApp` wrapper, first-run auto-register |
| `SettingsStore.swift` | Root folder / editor / browser / autoAssignPorts / showUnmanagedPorts persistence, `openInBrowser` (uses preferred browser) |
| `Views.swift` | All SwiftUI views — header, Running (managed) / External / Errored / Available / Unmanaged rows, port Link/Unlink menu, confirm-replace prompt, scanning + Docker warnings |
| `SettingsView.swift` | Settings panel UI — folder picker, editor & browser radios, launch-at-login / auto-port / unmanaged-ports toggles |
| `LogsView.swift` | In-app log viewer — polls `~/.pm2/logs/<name>-{out,error}.log` |
| `Onboarding.swift` | First-run pm2 check |
