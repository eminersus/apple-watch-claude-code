# Claude on your wrist — send prompts to live Claude Code sessions from an Apple Watch

Dictate or type a prompt on your Apple Watch and have it typed straight into a
**real, running Claude Code terminal session** on your computer. You pick which
session to target when several are open. Because the prompt goes into your
interactive `claude` session (not a headless API call), it uses your **Claude
subscription**, not pay-per-token API billing.

```
┌──────────────┐   HTTPS over    ┌──────────────────────┐   tmux send-keys   ┌──────────────────┐
│ Apple Watch  │   Tailscale     │  Bridge (server.py)  │  ───────────────►  │  claude (live)   │
│  ClaudeWatch │ ──────────────► │  on your computer    │                    │  in a tmux session│
│   app        │  Bearer token   │  GET /sessions       │  ◄── lists ──────  │  …and others      │
└──────────────┘                 │  POST /prompt        │                    └──────────────────┘
                                  └──────────────────────┘
```

## What's here

| Path | What |
|---|---|
| `bridge/server.py` | Zero-dependency Python bridge. Lists tmux sessions and injects prompts. |
| `bridge/config.example.json` | Copy to `config.json`, set your token. |
| `bridge/test_bridge.py` | End-to-end tests (health, auth, session listing, real injection). |
| `watch-app/ClaudeWatch/` | Native watchOS SwiftUI app (source). |
| `watch-app/project.yml` | XcodeGen spec to generate the Xcode project deterministically. |
| `docs/SETUP.md` | **Start here** — full end-to-end setup, copy-paste. |
| `watch-app/README.md` | How to build & install the watch app in Xcode. |

## How it works (the short version)

1. You run each Claude Code session **inside its own tmux session**
   (`tmux new -s trading`, then `claude`). tmux gives the bridge a stable handle
   to type into.
2. The **bridge** runs on your computer. `GET /sessions` enumerates tmux panes
   (flagging the ones running Claude); `POST /prompt` runs `tmux send-keys` to
   type your prompt into the chosen pane and press Return.
3. **Tailscale** connects your watch to your computer privately from anywhere,
   with a valid HTTPS certificate (via `tailscale serve`) so the watch app needs
   no insecure-network exceptions.
4. The **watch app** lists your sessions, you pick one, dictate a prompt
   (English or Turkish via the globe key) and tap **Send**. It appears in your
   session as if you typed it.

## Quick start

```bash
# 1. Bridge
cd bridge
cp config.example.json config.json
python3 -c "import secrets;print(secrets.token_urlsafe(24))"   # paste into config.json "token"
./run.sh

# 2. Run a Claude Code session it can see (in another terminal)
tmux new -s work
claude            # inside the tmux session

# 3. Expose it to your watch (see docs/SETUP.md for Tailscale)
tailscale serve --bg 8787

# 4. Build the watch app -> watch-app/README.md
```

Then open the **Claude** app on your watch, enter your Tailscale URL + token in
Settings, pick the **work** session, dictate, and send.

Full, careful walk-through with every command: **[docs/SETUP.md](docs/SETUP.md)**.

## Run the tests

```bash
cd bridge && python3 test_bridge.py
```

Covers health, auth rejection, session listing + Claude detection, real tmux
injection, and error handling. (Requires `tmux` on PATH.)

## Security notes

- Every request requires `Authorization: Bearer <token>` (constant-time compared).
- With Tailscale, the bridge is only reachable inside your private tailnet; it is
  **not** exposed to the public internet. The token is defense-in-depth.
- The bridge only ever does two things: list tmux panes, and type text into the
  one you choose. Your prompt is delivered with `send-keys -l` (literal), so it
  can't be interpreted as tmux key chords.
- Whatever Claude then does with that prompt is governed by your normal Claude
  Code permissions in that session — the watch doesn't change them.
