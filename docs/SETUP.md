# Setup — end to end

Follow this once. ~20 minutes, most of it the one-time Xcode build. Every command
is copy-pasteable. Order: **bridge → tmux sessions → Tailscale → watch app → languages**.

> Assumes macOS. The bridge is plain `python3` (built into macOS) with no
> `pip install`. The watch app needs Xcode (free) and a Mac.

---

## 1. Run the bridge

```bash
cd bridge
cp config.example.json config.json

# generate a strong token and look at it
python3 -c "import secrets; print(secrets.token_urlsafe(24))"
```

Open `config.json` and paste that value into `"token"`. Leave the rest as-is:

```json
{
  "host": "0.0.0.0",
  "port": 8787,
  "token": "the-token-you-just-generated",
  "default_target": "",
  "submit": true
}
```

Start it:

```bash
./run.sh
# Claude Watch Bridge listening on http://0.0.0.0:8787
```

Sanity check from the same Mac (new terminal):

```bash
curl -s localhost:8787/health
# {"ok": true, "service": "claude-watch-bridge", "default_target": ""}
```

Leave it running. (To keep it running after you close the terminal, see
[§6 Run the bridge automatically](#6-optional-run-the-bridge-automatically).)

---

## 2. Run your Claude Code sessions inside tmux

The bridge types into terminal sessions managed by **tmux**. Run each Claude Code
session in its own named tmux session so the watch can list and target it:

```bash
brew install tmux                # if you don't have it

tmux new -s trading             # start a session named "trading"
claude                          # run Claude Code inside it
#  ... Ctrl-b then d  to detach (leaves it running) ...

tmux new -s research            # a second session
claude
```

Now `GET /sessions` will show both. You can have as many as you like; the watch
picks which one each prompt goes to. The bridge flags sessions that are running
Claude Code (it inspects each pane's process tree) and sorts them to the top.

Verify:

```bash
curl -s -H "Authorization: Bearer YOUR_TOKEN" localhost:8787/sessions | python3 -m json.tool
```

You should see your `trading` and `research` sessions with `"claude_like": true`.

> **Tip:** to reattach to a session on your Mac and watch the prompts land:
> `tmux attach -t trading`.

---

## 3. Connect your watch to your Mac with Tailscale

[Tailscale](https://tailscale.com) puts your Mac and your iPhone/Watch on the
same private encrypted network, reachable from anywhere — no ports opened to the
public internet.

1. Install Tailscale on your **Mac** (App Store or `brew install --cask tailscale`)
   and sign in.
2. Install **Tailscale** on your **iPhone** from the App Store and sign in with
   the **same account**. (The Watch reaches the tailnet through your paired
   iPhone, or on its own when on Wi-Fi/cellular.)
3. On the Mac, give the bridge a real HTTPS endpoint on your Tailscale name:

   ```bash
   tailscale serve --bg 8787
   tailscale serve status
   ```

   This prints a URL like:

   ```
   https://your-mac.your-tailnet.ts.net/  ->  http://127.0.0.1:8787
   ```

   That `https://your-mac.your-tailnet.ts.net` is what you'll type into the watch
   app. It has a **valid certificate**, so the watch app needs no insecure-network
   exceptions.

   Find your Mac's name anytime with: `tailscale status` (first column).

Test the HTTPS endpoint from the Mac:

```bash
curl -s https://your-mac.your-tailnet.ts.net/health
# {"ok": true, ...}
```

> **Plain-LAN alternative (home only):** skip Tailscale and use
> `http://<mac-LAN-ip>:8787`. The app already allows plain-http loads
> (`NSAllowsArbitraryLoads` is set in `watch-app/ClaudeWatch/Info.plist`), so no
> edit is needed. Tailscale is strongly recommended — it works away from home and
> keeps real TLS.

---

## 4. Build & install the watch app

See **[watch-app/README.md](../watch-app/README.md)** for the full Xcode steps
(two paths: XcodeGen one-liner, or manual New-Project). Summary:

```bash
brew install xcodegen
cd watch-app
xcodegen generate
open ClaudeWatch.xcodeproj
```

In Xcode: select the **ClaudeWatch** target → **Signing & Capabilities** → pick
your **Team** (a free Apple ID works) → choose your watch as the run destination
→ press **Run (⌘R)**. The **Claude** app installs on your watch.

---

## 5. Configure the app + enable EN/TR dictation

### a) First launch
The app opens **Settings** automatically. Enter:
- **URL:** `https://your-mac.your-tailnet.ts.net`
- **Bearer token:** the token from `config.json`

Tap **Done**. (Typing a long token on the watch is painful — see the
[token trick](#typing-the-token-once) below.)

### b) Pick a session
On the main screen tap the **Session** row → the app lists your live sessions →
tap **trading** (or whichever). The ⟳ button refreshes the list.

### c) Send a prompt
Tap the prompt field. The watchOS input panel appears with **Dictation (voice)**,
**Scribble**, and **keyboard** — both voice and typing are supported out of the
box. Speak or type your prompt, then tap **Send**. It lands in your chosen Claude
Code session and (by default) presses Return.

### d) English + Turkish dictation
watchOS dictation uses your **enabled keyboard languages**, and you switch
between them in the input panel with the **globe (🌐) key**. To get both:

**On iPhone (easiest):** Watch app → **General → Keyboards** (or **Language &
Region**) → add both **English** and **Türkçe**.

**On the Watch directly:** Settings → **General → Keyboards** → add **Türkçe**
(English is usually already there).

Also make sure Dictation is on: Watch app → **General → Dictation → On**, and
that your watch is configured for the languages you want.

Now, when the input panel is open, tap the **🌐 globe key** to switch the input
language; dictation transcribes in whichever language is selected. So you can
dictate in English, switch with the globe key, and dictate the next prompt in
Turkish.

> Apple does not expose an API to force a specific dictation language *per app* on
> watchOS — it always follows the system's enabled keyboards/Siri language. The
> globe-key switch is the supported way, and it works well once both languages
> are enabled.

---

## 6. (Optional) Run the bridge automatically

Keep the bridge alive across reboots/logouts with a LaunchAgent.

```bash
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.claudewatch.bridge.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.claudewatch.bridge</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>$(pwd)/server.py</string>
  </array>
  <key>WorkingDirectory</key><string>$(pwd)</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/claudewatch-bridge.log</string>
  <key>StandardErrorPath</key><string>/tmp/claudewatch-bridge.log</string>
</dict></plist>
PLIST

launchctl load ~/Library/LaunchAgents/com.claudewatch.bridge.plist
```

> Run this from inside `bridge/` so `$(pwd)` resolves correctly.
> Logs: `tail -f /tmp/claudewatch-bridge.log`. Unload with
> `launchctl unload ~/Library/LaunchAgents/com.claudewatch.bridge.plist`.

Do the same persistence for Tailscale serve if you want it permanent:
`tailscale serve --bg 8787` already persists across reboots once set.

---

## Typing the token once

Rather than thumb a 32-char token into the watch:

1. In the iOS **Shortcuts** app make a one-step shortcut: **Set value of [your URL
   + token]**… — simplest is to just **paste the token into the watch field via
   Handoff**: type it in **Notes** on your Mac, the note syncs to the watch's
   Notes, long-press to copy, then paste into the app's token field.
2. Or run the app first in the **watchOS Simulator** on your Mac (Xcode), paste
   the token there with your Mac keyboard to confirm everything works, then enter
   it once on the real watch.

The token is stored in the app's settings and persists — you only do this once.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Watch app: "Set the bridge URL and token" | Fill both in Settings. |
| "Server 401 unauthorized" | Token in app ≠ token in `config.json`. |
| Sessions list empty | No tmux sessions running. `tmux new -s work` then `claude`. |
| "target '…' not found" | The session was closed. Re-pick from the Sessions list (⟳). |
| Transport error / can't connect | `curl https://your-mac…ts.net/health` from the Mac. Check `tailscale status` on Mac **and** iPhone; both signed into the same tailnet. |
| Works on Wi-Fi, not on cellular | Make sure Tailscale is connected on the iPhone; the Watch routes through it. |
| Dictation always English | Add **Türkçe** keyboard (see §5d); switch with the 🌐 key in the input panel. |
| Prompt typed but not sent | "Press Enter to submit" is off in Settings, or the session was mid-edit. |
