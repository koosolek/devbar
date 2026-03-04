# Port Menu — Launch Checklist

## Code & App
- [ ] Test onboarding on a clean machine (reset with `defaults delete eduard.Porter`)
- [ ] Test kill animation end-to-end
- [ ] Test with 0, 1, and 3+ servers running
- [ ] Check app works after macOS restart (auto-launch not set up yet)
- [ ] Add "Launch at Login" toggle to the dropdown (optional but nice)

## Distribution
- [ ] Sign up for Apple Developer Program ($99/year) at developer.apple.com
- [ ] Create a "Developer ID Application" certificate in Xcode
- [ ] Archive & export the app with Developer ID signing
- [ ] Notarize the app with `xcrun notarytool`
- [ ] Staple the notarization ticket: `xcrun stapler staple Port\ Menu.app`
- [ ] Zip the .app and create a GitHub Release (tag: v1.0.0)
- [ ] Upload the zip as a release asset on GitHub

## GitHub Repo
- [ ] Make the repo public on GitHub
- [ ] Add MIT license (Settings → Add file → LICENSE)
- [ ] Write a README with screenshot, install instructions, and feature list
- [ ] Add `.gitignore` entries for `default.profraw`, `DerivedData`, etc.
- [ ] Add repo topics: macos, swift, swiftui, menu-bar, developer-tools

## Landing Page
- [ ] Create new repo `port-menu-site` (separate from the app repo)
- [ ] Build landing page in Next.js / deployed on Vercel
- [ ] Buy a domain (portmenu.app, portmenu.dev, or useportmenu.com)
- [ ] Link landing page → GitHub Release download
- [ ] Add the tweet video / screen recording as hero asset

## Marketing
- [ ] Tweet the GitHub release link + landing page
- [ ] Post on Hacker News "Show HN"
- [ ] Post on Reddit r/macapps
- [ ] Consider ProductHunt launch
