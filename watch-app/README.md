# ClaudeWatch — building & installing the watch app

A small native **watchOS** SwiftUI app that lists your live Claude Code sessions,
lets you pick one, and sends a dictated/typed prompt to it via the bridge.

Source files (everything the app needs is here):

| File | Role |
|---|---|
| `ClaudeWatch/ClaudeWatchApp.swift` | App entry point. |
| `ClaudeWatch/ContentView.swift` | Main screen: session row, prompt field, Send, presets. |
| `ClaudeWatch/SessionsView.swift` | Lists `/sessions` and lets you pick the target. |
| `ClaudeWatch/SettingsView.swift` | Bridge URL, token, submit toggle. |
| `ClaudeWatch/BridgeClient.swift` | Networking (`GET /sessions`, `POST /prompt`). |
| `ClaudeWatch/Settings.swift` | AppStorage keys. |
| `ClaudeWatch/Assets.xcassets` | App icon + accent color slots. |
| `ClaudeWatch/Info.plist` | watchOS app plist (allows plain-http to the bridge for the LAN/Tailscale fallback). |
| `project.yml` | XcodeGen spec to generate the `.xcodeproj`. |

Requirements: a **Mac with Xcode 16+** (free from the App Store) and an **Apple
ID** for signing (a free personal team works for installing on your own watch).

---

## Path A — XcodeGen (recommended, deterministic)

```bash
brew install xcodegen
cd watch-app
xcodegen generate          # creates ClaudeWatch.xcodeproj from project.yml
open ClaudeWatch.xcodeproj
```

Then in Xcode:

1. Select the **ClaudeWatch** project → **ClaudeWatch** target →
   **Signing & Capabilities**.
2. Check **Automatically manage signing** and choose your **Team**.
   - If it complains the bundle id is taken, change
     **PRODUCT_BUNDLE_IDENTIFIER** (e.g. `com.yourname.claudewatch.watchkitapp`)
     in `project.yml` and re-run `xcodegen generate`.
3. Pick your **Apple Watch** (or a **watchOS Simulator**) as the run destination
   in the toolbar.
4. Press **Run (⌘R)**. The **Claude** app installs and launches on the watch.

To install on a physical watch you may need to: pair the watch, trust your
developer certificate on the watch (**Settings → General → VPN & Device
Management** on the *paired iPhone* the first time), and have the watch unlocked.

---

## Path B — manual, no extra tools

If you'd rather not install XcodeGen:

1. **Xcode → File → New → Project… → watchOS → App.**
   - Product Name: `ClaudeWatch`
   - Interface: **SwiftUI**, Language: **Swift**
   - Uncheck tests/notifications/complications — none are needed.
2. In the new project, **delete** the template `ContentView.swift` and the
   `…App.swift` Xcode generated (Move to Trash).
3. **Drag** all the `.swift` files from `watch-app/ClaudeWatch/` into
   the project's app group (check *Copy items if needed* and add to the
   ClaudeWatch target):
   - `ClaudeWatchApp.swift`, `ContentView.swift`, `SessionsView.swift`,
     `SettingsView.swift`, `BridgeClient.swift`, `Settings.swift`
4. Replace the generated `Assets.xcassets` with the one here (optional — the
   generated one works too; the app just uses the system accent if missing).
5. Set the **deployment target** to watchOS 10.0 or later
   (target → General → Minimum Deployments).
6. **Signing & Capabilities** → choose your Team, then **Run (⌘R)**.

> The app only uses SwiftUI + Foundation — no third-party packages, no
> capabilities/entitlements beyond outbound networking (which needs none on
> watchOS for a normal HTTPS request).

---

## Using it

1. On first launch, **Settings** opens. Enter the bridge **URL**
   (`https://your-mac.your-tailnet.ts.net`) and **token** (from the bridge's
   `config.json`). For watchOS Simulator testing on the same Mac, use
   `http://localhost:8787` instead; the simulator shares the Mac's network
   stack and this project allows local HTTP for that test path. Tap **Done**.
2. Tap the **Session** row → pick the Claude Code session to target.
3. Tap the prompt field → **dictate** (voice) or **type** → tap **Send**.
4. Use **Quick prompts** for one-tap `continue` / `run the tests` / `yes` etc.
   (edit the `presets` array in `ContentView.swift` to customize).

**English + Turkish dictation:** enable both keyboards on the watch and switch
with the **🌐 globe key** in the input panel — see
[docs/SETUP.md §5d](../docs/SETUP.md#d-english--turkish-dictation).

---

## Customizing

- **Quick prompts:** edit `presets` in `ContentView.swift`.
- **Accent color:** edit `Assets.xcassets/AccentColor.colorset/Contents.json`.
- **Display name:** `CFBundleDisplayName` in `project.yml` (or target → General).
- **Don't auto-submit by default:** turn off "Press Enter to submit" in Settings,
  or set `"submit": false` in the bridge `config.json`.
