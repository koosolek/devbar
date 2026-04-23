# DevBar

A macOS menu bar app that manages your local dev servers. Discover projects, start and stop them without terminal windows, and open URLs with one click.

Forked from [Port Menu](https://github.com/wieandteduard/port-menu).

## What it does

DevBar sits in your menu bar and gives you control over your dev servers:

- **Project discovery** -- scans a root folder (e.g. `~/Code`) up to 3 levels deep. Detects `package.json` (dev/start scripts), `Makefile` (dev/start/run/up targets), and falls back to scanning README for common dev commands.
- **Start / stop** -- launches servers via pm2 in the background, no terminal windows
- **Running servers** -- shows project name, localhost URL, uptime, relative path; action buttons use real editor + browser icons
- **Open URL** -- auto-detects the server's actual URL from pm2 logs (so a server at `https://my.dev.domain:8000/` opens there, not `localhost:8000`). Browser is configurable in Settings.
- **Open in editor** -- VS Code, Cursor, Zed, Xcode, or a custom command
- **In-app log viewer** -- tails `pm2` output in a dedicated window; no Terminal or Automation permissions required
- **Port conflict handling** -- warns when a project's known port is busy and offers an inline "Replace" action that stops the occupant before starting. Knows about `--port` flags, Vite configs (monorepo-aware), and docker-compose port mappings.
- **Manual port linking** -- right-click / ellipsis menu lets you link a listening port to a project (useful for Docker-launched services where the daemon obscures the process)
- **External servers** -- projects started outside DevBar (from a terminal) in your root folder appear alongside DevBar-managed ones with an "external" label
- **Auto-assign ports** -- injects `PORT=<free port>` into pm2 so projects that read the env var avoid collisions (toggle in Settings)
- **Docker awareness** -- projects with a `docker-compose` file warn pre-start when the Docker daemon isn't running
- **Unmanaged ports** -- optional section (toggle in Settings) lists everything else listening on your machine — Docker, Homebrew services, etc. — with a Kill button
- **Launch at login** -- registers itself as a login item on first run (toggle in Settings)

## Requirements

- macOS 14 (Sonoma) or later
- [pm2](https://pm2.keymetrics.io/) -- install with `npm install -g pm2`

## Install

### From a release (recommended)

1. Grab `DevBar-<version>.zip` from the [latest release](https://github.com/koosolek/devbar/releases/latest).
2. Unzip and drag `DevBar.app` into `/Applications`.
3. **First launch: right-click → Open**. DevBar is ad-hoc signed, so Gatekeeper asks once; click "Open" to allow.
4. Install pm2 if you haven't yet: `npm install -g pm2`.

### Build from source

Requires Xcode 15+.

```bash
git clone https://github.com/koosolek/devbar.git
cd devbar
scripts/package-release.sh              # → dist/DevBar.app + dist/DevBar-dev.zip
cp -R dist/DevBar.app /Applications/
```

Or just a plain debug build:

```bash
xcodebuild -scheme DevBar -configuration Debug build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

Debug build lands in `~/Library/Developer/Xcode/DerivedData/DevBar-*/Build/Products/Debug/DevBar.app`.

## Testing

```bash
xcodebuild test -scheme DevBar -destination "platform=macOS" CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

## License

MIT
