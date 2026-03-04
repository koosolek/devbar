# Porter — Product Context

## One-liner
A tiny macOS menu bar app that shows which dev servers are running and where.

## What it does
Porter lives in your menu bar and automatically detects local development servers running on your machine. It shows them in a clean dropdown — one glance to see what's running, which project it belongs to, and on which port.

No config, no setup. It just works.

## The problem
When working across multiple projects, you lose track of which dev servers are running. You end up checking terminal tabs, guessing ports, or accidentally starting a second server on the same project. Porter gives you a single place to see everything.

## Key features
- **Auto-detection** — discovers running dev servers automatically via TCP port scanning (no config needed)
- **Project context** — shows the Git repo name, current branch, port number, and uptime for each server
- **Quick actions** — open in browser or kill a server directly from the dropdown
- **Copy URL** — right-click to copy localhost URL to clipboard
- **Native macOS design** — built with SwiftUI, feels like a system utility
- **Menu bar badge** — shows the count of active servers with a green status dot
- **Lightweight** — polls every 3 seconds, minimal resource usage

## How it works under the hood
- Uses `lsof` to find processes listening on TCP ports (1024+)
- Filters to only show projects that have a Git repo (ignores system services)
- Resolves the working directory, Git root, and branch name for each process
- Tracks process start time for uptime display

## Tech stack
- Swift / SwiftUI
- macOS 13+ (Ventura)
- MenuBarExtra API
- No external dependencies

## Design principles
- Minimal and native — looks and feels like it belongs on macOS
- No jargon — approachable for anyone, not just senior devs
- No config — works out of the box
- Non-intrusive — sits quietly in the menu bar until you need it

## UI details
- Dropdown width: 340pt
- Each server shows: green status dot, project name, Git branch, port number (e.g. `:3000`), uptime
- Kill and Open buttons appear on hover with subtle scale animation
- Kill action: row slides out to the right with blur + fade, then list collapses smoothly
- Empty state: "No projects running — Start a dev server to see it here"
- Menu bar: green dot + count when servers active, grey square + 0 when idle

## Target audience
- Developers who run multiple local dev servers across different projects
- Primarily frontend/fullstack devs working with tools like Next.js, Vite, Remix, Django, Rails, etc.
- macOS users

## Links
- GitHub: https://github.com/wieandteduard/Porter
- Tweet: https://x.com/eduardwieandt (Feb 27, 2026 — 26K+ views, 500+ likes, 360+ bookmarks)

## Assets available
- Screen recording of the app in action (from the tweet)
- Screenshot at: `assets/CleanShot_2026-02-28_at_15.48.32_2x-0d80fbbe-91ef-481f-a582-2075275adea2.png`

## Tone & voice
- Lowercase, casual, developer-friendly
- Not salesy — it's a small utility, not a SaaS product
- Let the product speak for itself
