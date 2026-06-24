#!/usr/bin/env python3
"""
Claude Watch Bridge
===================

A tiny, zero-dependency HTTP server that lets an Apple Watch send prompts to
*real, running Claude Code terminal sessions* on this computer.

It does NOT call the API or run `claude -p` headlessly — it types your prompt
straight into a live, interactive Claude Code session, exactly as if you typed
it at the keyboard. That means everything runs inside your normal Claude Code
session and uses your Claude subscription, not pay-per-token API billing.

The mechanism is tmux: you run each Claude Code session inside its own tmux
session, and this bridge uses `tmux send-keys` to deliver keystrokes to the one
you pick. The watch can list every running session and choose which to target.

Endpoints (all under `Authorization: Bearer <token>`):
  GET  /health             -> liveness + config summary
  GET  /sessions           -> list running terminal sessions (Claude ones flagged)
  POST /prompt             -> type a prompt into a chosen session

Stdlib only — runs on the system python3 on macOS with no `pip install`.

Run:    python3 server.py
Config: copy config.example.json -> config.json and edit, or use env vars.
"""

from __future__ import annotations

import hmac
import json
import logging
import os
import shutil
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #

DEFAULTS = {
    "host": "0.0.0.0",          # bind all interfaces so Tailscale/LAN can reach it
    "port": 8787,
    "token": "",                # REQUIRED. Shared secret the watch sends.
    "default_target": "",       # optional fallback tmux target if the watch sends none
    "submit": True,             # press Enter after typing the prompt
}

CONFIG_PATH = Path(os.environ.get("WATCH_BRIDGE_CONFIG", Path(__file__).with_name("config.json")))


def load_config() -> dict:
    cfg = dict(DEFAULTS)
    if CONFIG_PATH.exists():
        try:
            cfg.update(json.loads(CONFIG_PATH.read_text()))
        except Exception as exc:  # noqa: BLE001
            sys.exit(f"FATAL: could not parse {CONFIG_PATH}: {exc}")
    env_map = {
        "WATCH_BRIDGE_TOKEN": ("token", str),
        "WATCH_BRIDGE_PORT": ("port", int),
        "WATCH_BRIDGE_HOST": ("host", str),
        "WATCH_BRIDGE_TARGET": ("default_target", str),
    }
    for env, (key, caster) in env_map.items():
        if os.environ.get(env):
            cfg[key] = caster(os.environ[env])

    if not cfg["token"]:
        sys.exit(
            "FATAL: no token set. Put a strong random token in config.json "
            '("token": "...") or set WATCH_BRIDGE_TOKEN. '
            "Generate one with:  python3 -c \"import secrets;print(secrets.token_urlsafe(24))\""
        )
    return cfg


CFG = load_config()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-5s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("watch-bridge")


# --------------------------------------------------------------------------- #
# tmux helpers
# --------------------------------------------------------------------------- #

def _require_tmux():
    if not shutil.which("tmux"):
        raise RuntimeError("tmux is not installed / not on PATH")


def _process_tree():
    """Return (children: ppid->[pid], cmd: pid->command-string) for all processes."""
    out = subprocess.run(["ps", "-axo", "pid=,ppid=,command="],
                         capture_output=True, text=True)
    children: dict[str, list[str]] = {}
    cmd: dict[str, str] = {}
    for line in out.stdout.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) < 3:
            continue
        pid, ppid, command = parts
        children.setdefault(ppid, []).append(pid)
        cmd[pid] = command
    return children, cmd


def _descendant_commands(pid: str, children, cmd) -> list[str]:
    """All command strings in the process subtree rooted at `pid` (excl. itself)."""
    found, stack, seen = [], [pid], set()
    while stack:
        p = stack.pop()
        for child in children.get(p, []):
            if child in seen:
                continue
            seen.add(child)
            found.append(cmd.get(child, ""))
            stack.append(child)
    return found


def list_sessions() -> list[dict]:
    """Enumerate tmux panes, flagging the ones that look like Claude Code."""
    _require_tmux()
    fmt = "\t".join([
        "#{session_name}", "#{window_index}", "#{window_name}",
        "#{pane_index}", "#{pane_pid}", "#{pane_current_command}",
        "#{pane_current_path}", "#{pane_active}", "#{pane_title}",
    ])
    res = subprocess.run(["tmux", "list-panes", "-a", "-F", fmt],
                         capture_output=True, text=True)
    if res.returncode != 0:
        # No server running yet -> just an empty list, not an error.
        if "no server running" in (res.stderr or "").lower():
            return []
        raise RuntimeError(res.stderr.strip() or "tmux list-panes failed")

    children, cmd = _process_tree()
    sessions = []
    for line in res.stdout.splitlines():
        f = line.split("\t")
        if len(f) < 9:
            continue
        sess, win_idx, win_name, pane_idx, pane_pid, command, path, active, title = f[:9]
        target = f"{sess}:{win_idx}.{pane_idx}"

        hay = " ".join([win_name, command, title]).lower()
        descendants = _descendant_commands(pane_pid, children, cmd)
        claude_like = ("claude" in hay) or any("claude" in d.lower() for d in descendants)

        sessions.append({
            "target": target,
            "session": sess,
            "window": win_idx,
            "window_name": win_name,
            "pane": pane_idx,
            "command": command,
            "path": path,
            "active": active == "1",
            "claude_like": claude_like,
        })
    # Claude-looking sessions first, then by name for a stable order.
    sessions.sort(key=lambda s: (not s["claude_like"], s["session"], s["window"], s["pane"]))
    return sessions


def tmux_inject(prompt: str, target: str, submit: bool) -> dict:
    """Type `prompt` into the live Claude Code session at `target`."""
    _require_tmux()
    if not target:
        raise RuntimeError("no target session given (and no default_target configured)")

    # Confirm the exact pane exists so we fail loudly instead of silently.
    valid = {s["target"] for s in list_sessions()}
    base_ok = subprocess.run(
        ["tmux", "has-session", "-t", target.split(":")[0]],
        capture_output=True, text=True,
    ).returncode == 0
    if target not in valid and not base_ok:
        raise RuntimeError(
            f"target '{target}' not found. Open /sessions to see live sessions. "
            f"Start one with:  tmux new -s mywork   then run  claude  inside it."
        )

    subprocess.run(["tmux", "send-keys", "-t", target, "-l", prompt], check=True)
    if submit:
        time.sleep(0.15)  # let the TUI register the paste before Enter
        subprocess.run(["tmux", "send-keys", "-t", target, "Enter"], check=True)

    log.info("inject -> %s  (%d chars, submit=%s)", target, len(prompt), submit)
    return {"ok": True, "target": target, "submitted": bool(submit), "chars": len(prompt)}


# --------------------------------------------------------------------------- #
# HTTP
# --------------------------------------------------------------------------- #

def _bearer_ok(header_value: str | None) -> bool:
    if not header_value or not header_value.startswith("Bearer "):
        return False
    return hmac.compare_digest(header_value[len("Bearer "):].strip(), CFG["token"])


class Handler(BaseHTTPRequestHandler):
    server_version = "ClaudeWatchBridge/2.0"

    def log_message(self, fmt, *args):  # noqa: N802
        log.debug("%s - %s", self.address_string(), fmt % args)

    def _send_json(self, code: int, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth(self) -> bool:
        if _bearer_ok(self.headers.get("Authorization")):
            return True
        log.warning("rejected request from %s (bad/missing token)", self.address_string())
        self._send_json(401, {"ok": False, "error": "unauthorized"})
        return False

    def do_GET(self):  # noqa: N802
        path = urlparse(self.path).path
        if path in ("/health", "/"):
            self._send_json(200, {"ok": True, "service": "claude-watch-bridge",
                                  "default_target": CFG["default_target"]})
            return
        if path == "/sessions":
            if not self._auth():
                return
            try:
                sessions = list_sessions()
            except Exception as exc:  # noqa: BLE001
                self._send_json(500, {"ok": False, "error": str(exc)})
                return
            self._send_json(200, {"ok": True, "sessions": sessions})
            return
        self._send_json(404, {"ok": False, "error": "not found"})

    def do_POST(self):  # noqa: N802
        if urlparse(self.path).path != "/prompt":
            self._send_json(404, {"ok": False, "error": "not found"})
            return
        if not self._auth():
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > 64_000:
            self._send_json(400, {"ok": False, "error": "empty or oversized body"})
            return
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except Exception:  # noqa: BLE001
            self._send_json(400, {"ok": False, "error": "invalid JSON"})
            return

        prompt = (data.get("prompt") or "").strip()
        if not prompt:
            self._send_json(400, {"ok": False, "error": "missing 'prompt'"})
            return

        target = data.get("target") or CFG["default_target"]
        submit = data.get("submit", CFG["submit"])
        try:
            result = tmux_inject(prompt, target, submit)
        except Exception as exc:  # noqa: BLE001
            log.error("inject failed: %s", exc)
            self._send_json(500, {"ok": False, "error": str(exc)})
            return
        self._send_json(200, result)


def main():
    httpd = ThreadingHTTPServer((CFG["host"], int(CFG["port"])), Handler)
    log.info("Claude Watch Bridge listening on http://%s:%s", CFG["host"], CFG["port"])
    log.info("GET /sessions   POST /prompt   (Authorization: Bearer <token>)")
    log.info("default target = %s", CFG["default_target"] or "(none — watch must pick one)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        log.info("shutting down")
        httpd.shutdown()


if __name__ == "__main__":
    main()
