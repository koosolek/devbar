# DevBar — Dev Server Manager for macOS

**Date:** 2026-04-16
**Status:** Approved
**Base:** Fork of [Port Menu](https://github.com/wieandteduard/port-menu) (MIT license)
**Stack:** Swift / SwiftUI, macOS 14+
**Dependency:** pm2 (Node.js process manager)

## Problem

Managing multiple local dev servers means keeping terminal windows open, losing track of what's running, and manually remembering URLs. Existing menu bar tools either only monitor ports (Port Menu, LocalPorts) or still open terminal windows (Noodles).

## Solution

A macOS menu bar app that discovers projects in a configured folder, starts/stops them via pm2 (fully backgrounded — no terminal windows), and shows running servers with clickable URLs.

## Architecture

Three components layered on top of Port Menu's existing codebase:

### ProjectScanner

- Scans a user-configured root folder (e.g. `~/Code`) up to 3 levels deep
- Looks for project markers: `package.json` with a `dev` or `start` script in the `scripts` field
- Projects without a detectable start command are not shown
- Produces a list of `DiscoveredProject` structs: name, path, inferred start command
- Rescan on app launch and via manual trigger in the UI
- Project name derived from the directory name
- Relative path shown as subtitle (e.g. `Personal/blog`)

### ProcessManager

- Wraps pm2 CLI calls via Swift's `Process` API
- Start: `pm2 start "<command>" --name "devbar-<project>" --cwd <path>`
- Stop: `pm2 stop "devbar-<project>"`
- Status: `pm2 jlist` (JSON output) to check which managed processes are running
- All processes namespaced with `devbar-` prefix to avoid collisions with user's other pm2 usage
- On app launch, reconciles pm2 state with discovered projects

### PortStore (extended from Port Menu)

- Keeps Port Menu's existing `lsof`-based port scanning and polling
- Extended to cross-reference detected ports with known projects from ProjectScanner
- After a project is started, polls for its port to appear (up to ~10 seconds)
- Ports that don't match any known project shown as "unmanaged" (Port Menu's current behavior)

## Project States

Each discovered project is in one of three states:

- **Stopped** — known project, pm2 process not running, no port detected
- **Running** — pm2 process active, port detected, URL available
- **Error** — pm2 process started but crashed or port not detected after timeout

## Features

### Start / Stop

- Starting a project calls `pm2 start` with the inferred command
- Stopping calls `pm2 stop`
- No terminal window opened in either case
- Port conflicts handled by the project's own framework (many auto-increment); if the process crashes, shown as Error state

### View Logs

- Opens a new terminal window with `pm2 logs devbar-<project>`
- This is the only action that opens a terminal — intentionally on-demand

### Open URL

- Opens `localhost:<port>` in the default browser
- Only available for running projects with a detected port

### Open in Editor

- Opens the project directory in the configured editor
- Available for both running and stopped projects
- Editor launched via CLI command (e.g. `code <path>`, `cursor <path>`, `zed <path>`)

### Kill (unmanaged processes)

- Retained from Port Menu for processes detected on ports but not managed by the app
- Sends SIGTERM to the process

## Settings

Two user-configurable options, persisted via `@AppStorage` or a plist:

- **Root folder** — path to scan for projects (e.g. `~/Code`)
- **Default editor** — which editor to open projects in, selectable from common options (VS Code, Cursor, Zed, Xcode, etc.) with a custom command fallback

## Menu Bar UI

### Layout

```
┌─────────────────────────────────────────┐
│ DevBar                   Settings  Quit │
├─────────────────────────────────────────┤
│ frontend                    [↗] [✎] [■] │
│ localhost:3000 · 2h 15m                 │
│                                         │
│ api                         [↗] [✎] [■] │
│ localhost:8080 · 2h 15m                 │
│                                         │
│ dashboard                   [↗] [✎] [■] │
│ localhost:5173 · 45m                    │
│─────────────────────────────────────────│
│ blog                            [✎] [▶] │
│ Personal/blog                           │
│                                         │
│ portfolio                       [✎] [▶] │
│ Personal/portfolio                      │
└─────────────────────────────────────────┘
```

### Design Principles

- Monochrome throughout, follows system light/dark theme
- No color-coded status indicators — section separation (hr divider) distinguishes running from available
- Monochrome SVG icons for actions: external link (URL), pencil (editor), square (stop), play (start)
- No row hover highlights — hovers only on action buttons
- Settings and Quit as text buttons in the top-right header
- Running projects show: name, localhost URL, uptime
- Available (stopped) projects show: name, relative path from root folder
- Available projects displayed at reduced opacity for visual hierarchy

### Menu Bar Icon

- Reuse or adapt Port Menu's existing menu bar icon
- Show count of running servers next to the icon

## pm2 Dependency

- App checks for pm2 on launch (`which pm2`)
- If not found, shows an onboarding screen with install instructions (`npm install -g pm2`)
- App does not attempt to install pm2 itself

## What We're Keeping from Port Menu

- Menu bar app shell and lifecycle (SwiftUI `MenuBarExtra`)
- Port scanning via `lsof` (`PortScanning.swift`)
- Port polling and sleep/wake awareness (`PortStore.swift`)
- Process termination for unmanaged processes
- Git-based project name resolution (as fallback)
- Sparkle auto-update framework (remove — not needed for a personal tool)
- `ActivePort` model and `ScanDiagnostics`

## What We're Adding

- `ProjectScanner` — folder scanning and project discovery
- `ProcessManager` — pm2 CLI integration
- `SettingsView` — root folder and editor configuration
- Extended `Views.swift` — two-section layout, start/stop buttons, open-in-editor action
- Extended `Models.swift` — `DiscoveredProject` struct, project state enum
- Onboarding flow for pm2 installation

## What We're Removing / Replacing

- Port Menu's onboarding flow (replaced with our own)
- Refresh interval settings (keep a sensible default, no user-facing control needed)
- Any Port Menu branding (rename to DevBar or chosen name)

## Out of Scope (for now)

- Support for non-Node project types (can be added later by teaching ProjectScanner new markers)
- Custom per-project config files (`.devserver` etc.)
- Multiple root folders
- Port conflict resolution
- Auto-start projects on app launch
