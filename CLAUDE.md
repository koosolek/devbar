# DevBar

## What this is

A macOS menu bar app for managing local dev servers. Forked from [Port Menu](https://github.com/wieandteduard/port-menu), which only monitors ports. DevBar adds the ability to discover projects, start/stop them via pm2, and open URLs and editors — all without terminal windows.

## Why it exists

The problem: running dev servers means keeping terminal windows open, losing track of what's running, and manually remembering URLs. Existing tools either only monitor ports (Port Menu, LocalPorts) or still open terminal windows (Noodles). DevBar combines project discovery + backgrounded process management + a clean menu bar UI.

## Architecture

Core components layered on top of Port Menu's existing port scanner:

- **ProjectScanner** (`ProjectScanner.swift`) — scans a configured root folder up to 3 levels deep. Detection order per directory: `package.json` (dev/start script) → `Makefile` (dev/start/run/up target) → `README` (scans for `make start`, `pnpm dev`, `npm run dev`, etc.). Extracts `expectedPort` from `--port N` flags in scripts; falls back to parsing `vite.config.*` for `server.port`. Parses adjacent `docker-compose*.yml` for all declared host ports (stored as `composePorts`). Flags `requiresDocker` when a compose file is present.
- **ProcessManager** (`ProcessManager.swift`) — wraps pm2 CLI via Swift's `Process` API. pm2 names are `devbar-<slug>-<4-char-path-hash>` so two projects that share a folder name don't collide. Uses `--max-restarts 3` to cap crash loops.
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

## Build, test, release

```bash
# Dev loop
xcodebuild -scheme DevBar -configuration Debug build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
xcodebuild test -scheme DevBar -destination "platform=macOS" CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

# Package an unsigned .app + zip locally for sharing
scripts/package-release.sh 0.1.0        # → dist/DevBar.app, dist/DevBar-0.1.0.zip, dist/…sha256
```

Tag-driven releases: `.github/workflows/release.yml` runs on `v*` tag pushes, builds Release configuration on a macOS runner, zips `DevBar.app`, and attaches it to an auto-generated GitHub Release. No signing/notarization — distribution is ad-hoc, so first-run requires right-click → Open.

### Release process

When shipping user-visible changes, cut a release so the downloadable binary stays in sync with `main`:

```bash
scripts/cut-release.sh          # patch bump (0.1.0 → 0.1.1) — default for bug fixes
scripts/cut-release.sh minor    # minor bump (0.1.0 → 0.2.0) — for new features
scripts/cut-release.sh major    # major bump (0.X.Y → 1.0.0) — for breaking changes
scripts/cut-release.sh 1.2.3    # explicit version
```

The script requires a clean tree on `main`. It bumps `MARKETING_VERSION` across every target in `DevBar.xcodeproj`, commits as `Release vX.Y.Z`, tags, and pushes — which fires the GitHub Action that builds the `.zip` and publishes the Release. GitHub auto-generates notes from the commit log since the last tag; writing good commit messages between releases pays off here.

Rule of thumb: patch for fixes, minor for any new capability or UX change worth mentioning, major saved for 1.0 once the feature set stabilises.

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
- **MenuBarExtra label renders only single Image reliably** — HStack of two Images, `.overlay` with offset, and `Text`-with-Image interpolation all silently collapsed to one visible glyph (or nothing) in the status-item button. The working pattern is one `Image(nsImage:)` with a `NSImage(size:flipped:drawingHandler:)` that composites the drive icon + red circled-number badge via Core Graphics. The drawing handler also re-runs on appearance change, so `NSColor.textColor` adapts to dark/light menu bars.
- **Menu-bar digit is hand-drawn** — `N.circle.fill` SF Symbol is a single-layer shape: its digit is a transparent cutout, so tinting the symbol red makes the digit vanish. The badge is drawn manually (filled `NSBezierPath` circle + `NSAttributedString` digit) to get two colors.
- **NSOpenPanel from LSUIElement apps** — `runModal()` opens unfocused unless you call `NSApplication.shared.activate(ignoringOtherApps: true)` first. Same rule as `openWindow(id:)`; `SettingsStore.pickRootFolder` centralises this.
- **Project rows are fixed-height (56 pt)** — `.frame(height: 56)` on each row prevents the confirm-run prompt (3 lines at 10 pt) from making rows jump size.

## Known issues

- **Hardcoded-port collisions** — DevBar auto-assigns `PORT` for projects that read `process.env.PORT`. Configs that hardcode the port (e.g. Vite `strictPort: true` with a fixed number, no env read) still collide; we surface them via the conflict warning + "Run anyway" flow but can't override the source port. The proper fix is in the project's own config.

## Key files

| File | Purpose |
|------|---------|
| `DevBarApp.swift` | App entry point, menu bar setup (icon + red badge composed via NSImage drawing handler), log-viewer `WindowGroup`, first-launch side effects (move-to-Applications, launch-at-login) |
| `Models.swift` | `ActivePort` (incl. `gitRootPath`), `DiscoveredProject` (incl. `expectedPort`, `composePorts`, `requiresDocker`, optional `startCommand`), `ProjectState`, `EditorOption`, `BrowserOption` |
| `ProjectScanner.swift` | Package.json / Makefile / README detection, `--port` extraction, `vite.config.*` scan, docker-compose port + file detection |
| `ProcessManager.swift` | pm2 CLI wrapper — start (with `--max-restarts 3`) / stop / delete / status, env passthrough |
| `PortStore.swift` | Port polling + project state + strong/weak port matching, known-port cache, conflict detection, replace-and-start, log URL attribution |
| `PortScanning.swift` | lsof-based port detection, git-root discovery, TCC-safe protected-path guard |
| `PortAllocator.swift` | Picks free port in 4100–4199 for `PORT` env |
| `LogURLDetector.swift` | Scrapes URLs from pm2 log tails and cross-references with listening ports |
| `DockerStatus.swift` | Coarse "is Docker reachable?" check via socket file presence |
| `AppIcons.swift` | Editor/browser/terminal icon lookup — reads raw `.icns` instead of using NSWorkspace's legacy-template wrapper |
| `LaunchAtLogin.swift` | `SMAppService.mainApp` wrapper, first-run auto-register |
| `SettingsStore.swift` | Root folder / editor / browser / autoAssignPorts / showUnmanagedPorts persistence, `openInBrowser`, `openInEditor`, `pickRootFolder` (native folder picker with LSUIElement activation) |
| `Views.swift` | All SwiftUI views — header, Running (managed) / External / Errored / Available / Unmanaged rows (fixed 56 pt height), port Link/Unlink menu, unified "Run anyway" confirm prompt, scanning + Docker warnings |
| `SettingsView.swift` | Settings panel UI — folder picker, editor & browser radios, launch-at-login / auto-port / unmanaged-ports toggles |
| `LogsView.swift` | In-app log viewer — polls `~/.pm2/logs/<name>-{out,error}.log` |
| `Onboarding.swift` | First-run pm2 check |
| `.github/workflows/release.yml` | Tag-driven CI build that packages a `.app.zip` and publishes it as a GitHub Release |
| `scripts/package-release.sh` | Local equivalent of the release workflow for ad-hoc packaging |
| `scripts/cut-release.sh` | Bump `MARKETING_VERSION`, commit, tag, and push — triggers the release workflow |
