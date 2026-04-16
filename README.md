# DevBar

A macOS menu bar app that manages your local dev servers. Discover projects, start and stop them without terminal windows, and open URLs with one click.

Forked from [Port Menu](https://github.com/wieandteduard/port-menu).

## What it does

DevBar sits in your menu bar and gives you control over your dev servers:

- **Project discovery** -- scans a root folder (e.g. `~/Code`) up to 3 levels deep for Node.js projects with a `dev` or `start` script
- **Start / stop** -- launches servers via pm2 in the background, no terminal windows needed
- **Running servers** -- shows project name, localhost URL, and uptime
- **Open URL** -- click to open a running server in your browser
- **Open in editor** -- open any project in VS Code, Cursor, Zed, or a custom editor
- **View logs** -- check pm2 output on demand
- **Unmanaged ports** -- also detects servers started outside the app and lets you kill them

## Requirements

- macOS 14 (Sonoma) or later
- [pm2](https://pm2.keymetrics.io/) -- install with `npm install -g pm2`
- Xcode 15+ (to build from source)

## Build from source

```bash
git clone https://github.com/koosolek/devbar.git
cd devbar
xcodebuild -scheme DevBar -configuration Debug build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

The built app will be in `~/Library/Developer/Xcode/DerivedData/DevBar-*/Build/Products/Debug/DevBar.app`.

## Testing

```bash
xcodebuild test -scheme DevBar -destination "platform=macOS" CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

## License

MIT
