# DevBar

## What this is

A macOS menu bar app for managing local dev servers. Forked from [Port Menu](https://github.com/wieandteduard/port-menu), which only monitors ports. DevBar adds the ability to discover projects, start/stop them via pm2, and open URLs and editors — all without terminal windows.

## Why it exists

The problem: running dev servers means keeping terminal windows open, losing track of what's running, and manually remembering URLs. Existing tools either only monitor ports (Port Menu, LocalPorts) or still open terminal windows (Noodles). DevBar combines project discovery + backgrounded process management + a clean menu bar UI.

## Architecture

Four components layered on top of Port Menu's existing port scanner:

- **ProjectScanner** (`ProjectScanner.swift`) — scans a configured root folder up to 3 levels deep for `package.json` files with `dev` or `start` scripts. Extracts `expectedPort` from `--port N` flags in the script body.
- **ProcessManager** (`ProcessManager.swift`) — wraps pm2 CLI via Swift's `Process` API. All managed processes are namespaced `devbar-<slug>-<4-char-path-hash>` so two projects that share a folder name (e.g. two monorepos both called `cds`) don't collide in pm2.
- **PortStore** (`PortStore.swift`) — Port Menu's `lsof`-based scanner extended to (1) reconcile pm2 process state on every refresh, (2) track last-known-port per project (persisted in UserDefaults), (3) surface port conflicts including races against projects mid-start.
- **PortAllocator** (`PortAllocator.swift`) — picks first free port in 4100–4199 for the `PORT` env var injected into pm2-launched processes. Toggle: `autoAssignPorts` in Settings.

Settings are persisted via `@AppStorage` in `SettingsStore.swift`. Launch-at-login is registered via `SMAppService.mainApp` (`LaunchAtLogin.swift`) only when DevBar is running from `/Applications/`.

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
- **No per-project config files** — the app infers start commands from package.json. If it can't figure out the command, the project is skipped. Keeps things simple
- **Monochrome UI** — follows system light/dark theme, no color-coded status indicators. Running vs available is communicated through section separation

## Gotchas / non-obvious behavior

- **TCC prompts from `findGitRoot`** — walking up from a random process's cwd (e.g. Docker, Xcode workers) hits `/Applications/X.app/...` or `~/Library/Containers/...`, which triggers macOS "access data from other apps" prompts on every `fileExists` call. `LivePortScanner.isProtectedSystemPath` short-circuits those paths in both `findGitRoot` and `ProjectScanner.scanDirectory`. If you add new filesystem walks, route them through this check.
- **ScrollView with `.frame(maxHeight:)` collapses to 0** — ScrollView has no intrinsic minimum height, so pairing `maxHeight` with `.fixedSize(horizontal: false, vertical: true)` is required in `projectListView` to make the list use natural content height up to the 60%-of-screen cap.
- **pm2 daemon inherits env at CLI invocation** — `ProcessManager.run(extraEnv:)` merges into the Swift `Process` env *before* `pm2 start`, so `PORT=4100` propagates to the child. Env set after pm2 is running (e.g. via `pm2 restart`) does NOT propagate, which is why we always `delete → start` and never `restart`.
- **Synchronous project scan is fine** — tried making it async via `Task.detached`; broke the list update path. The filesystem scan is small enough to run on main.

## Known issues

- **Hardcoded-port collisions** — DevBar auto-assigns `PORT` for projects that read `process.env.PORT`. Configs that hardcode the port (e.g. Vite `strictPort: true` with a fixed number, no env read) still collide; we surface them via the conflict warning + "Replace" flow but can't override the source port. The proper fix is in the project's own config.

## Key files

| File | Purpose |
|------|---------|
| `DevBarApp.swift` | App entry point, menu bar setup, first-launch side effects (move-to-Applications, launch-at-login register) |
| `Models.swift` | `ActivePort` (from Port Menu), `DiscoveredProject` (incl. `expectedPort` + path-hashed `pm2Name`), `ProjectState`, `EditorOption` |
| `ProjectScanner.swift` | Folder scanning, package.json parsing, `--port N` extraction |
| `ProcessManager.swift` | pm2 CLI wrapper — start/stop/delete/status/logs, env passthrough |
| `PortStore.swift` | Port polling + project state + known-port cache + conflict detection + replace-and-start |
| `PortScanning.swift` | lsof-based port detection, git-root discovery, TCC-safe protected-path guard |
| `PortAllocator.swift` | Picks free port in 4100–4199 for `PORT` env |
| `LaunchAtLogin.swift` | `SMAppService.mainApp` wrapper, first-run auto-register |
| `SettingsStore.swift` | Root folder, editor, `autoAssignPorts` persistence |
| `Views.swift` | All SwiftUI views — header, project rows (running/error/available/unmanaged), confirm-replace prompt, scanning indicators |
| `SettingsView.swift` | Settings panel UI incl. launch-at-login and auto-assign-ports toggles |
| `Onboarding.swift` | First-run pm2 check |
