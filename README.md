# Port Menu

**localhost, organized.**

A tiny macOS menu bar app that tracks your dev servers across projects.

No config. No setup. It just works.

---

## What it does

Port Menu sits in your menu bar and automatically detects local development servers running on your machine. One click to see what's running, which project it belongs to, and on which port.

- **Auto-detection** — scans for running dev servers every few seconds
- **Project context** — shows Git repo name, current branch, port, and uptime
- **Kill or open** — stop a server or open it in your browser directly from the menu
- **Copy URL** — right-click to copy the localhost URL

## Download

**[Download for macOS →](https://portmenu.dev)**

Requires macOS 14 (Sonoma) or later.

1. Download and unzip
2. Open `Port Menu.app` — it will offer to move itself to your Applications folder
3. Click the icon in your menu bar to get started

## Build from source

```bash
git clone https://github.com/wieandteduard/port-menu.git
cd Porter
open Porter.xcodeproj
```

Requires Xcode 15+.

## Release a signed build

Port Menu supports a reproducible direct-download release flow for macOS outside the App Store.

Requirements:

- `Developer ID Application` certificate installed in your login keychain
- Xcode command line tools with `xcodebuild`, `codesign`, and `xcrun`
- a notary keychain profile created once with:

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "you@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password"
```

Then build, sign, notarize, and staple a release archive with:

```bash
TEAM_ID="YOUR_TEAM_ID" \
DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
./scripts/release-macos.sh
```

Optional environment variables:

- `SCHEME` defaults to `Porter`
- `PROJECT` defaults to `Porter.xcodeproj`
- `APP_NAME` defaults to `Port Menu`
- `NOTARY_PROFILE` defaults to `AC_PASSWORD`
- `OUTPUT_DIR` defaults to `dist`

The script produces:

- a signed `.app`
- a notarized `.zip`
- a stapled app bundle ready for distribution

## Testing

```bash
xcodebuild test -project "Porter.xcodeproj" -scheme "Porter" -destination "platform=macOS"
```

## License

MIT
