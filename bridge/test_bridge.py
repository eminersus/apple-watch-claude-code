#!/usr/bin/env python3
"""
End-to-end test for the Claude Watch Bridge.

Spins up the server with a throwaway token + real tmux sessions, then checks:
  * /health
  * auth rejection on protected endpoints
  * /sessions lists running tmux panes and flags Claude-looking ones
  * /prompt injects keystrokes into the chosen pane
  * bad requests and missing targets give clear errors

Run:  python3 test_bridge.py
Requires: tmux on PATH (session/inject tests skip if missing).
"""
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOKEN = "test-token-do-not-use-in-prod"
SESS_PLAIN = "wb-test-plain"
SESS_CLAUDE = "wb-test-claudey"   # window renamed to look like a claude session


def free_port() -> int:
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close()
    return p


def req(method, url, payload=None, token=TOKEN):
    data = json.dumps(payload).encode() if payload is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    if data is not None:
        r.add_header("Content-Type", "application/json")
    if token is not None:
        r.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(r, timeout=10) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


passed = failed = 0


def check(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1; print(f"  PASS  {name}")
    else:
        failed += 1; print(f"  FAIL  {name}   {detail}")


def kill_sessions():
    for s in (SESS_PLAIN, SESS_CLAUDE):
        subprocess.run(["tmux", "kill-session", "-t", s], capture_output=True)


def main():
    port = free_port()
    base = f"http://127.0.0.1:{port}"
    have_tmux = bool(shutil.which("tmux"))

    if have_tmux:
        kill_sessions()
        subprocess.run(["tmux", "new-session", "-d", "-s", SESS_PLAIN, "cat"], check=True)
        subprocess.run(["tmux", "new-session", "-d", "-s", SESS_CLAUDE, "cat"], check=True)
        # Make this one look like a Claude session by naming its window.
        subprocess.run(["tmux", "rename-window", "-t", f"{SESS_CLAUDE}:0", "claude"], check=True)

    env = dict(os.environ)
    env.update({
        "WATCH_BRIDGE_TOKEN": TOKEN,
        "WATCH_BRIDGE_PORT": str(port),
        "WATCH_BRIDGE_HOST": "127.0.0.1",
        "WATCH_BRIDGE_CONFIG": "/nonexistent-so-defaults-are-used",
    })
    server = subprocess.Popen([sys.executable, str(HERE / "server.py")], env=env)

    try:
        for _ in range(50):
            try:
                req("GET", f"{base}/health"); break
            except Exception:
                time.sleep(0.1)
        else:
            check("server starts", False, "never healthy"); return

        # health (public)
        st, body = req("GET", f"{base}/health")
        check("health 200", st == 200 and body.get("ok"), str((st, body)))

        # auth
        st, _ = req("GET", f"{base}/sessions", token=None)
        check("sessions needs auth -> 401", st == 401)
        st, _ = req("POST", f"{base}/prompt", {"prompt": "hi"}, token="wrong")
        check("prompt wrong token -> 401", st == 401)

        # bad requests
        st, _ = req("POST", f"{base}/prompt", {}, token=TOKEN)
        check("no prompt -> 400", st == 400)

        if have_tmux:
            # sessions listing
            st, body = req("GET", f"{base}/sessions")
            targets = {s["target"]: s for s in body.get("sessions", [])}
            check("sessions 200", st == 200 and body.get("ok"), str((st, body)))
            check("plain session listed", f"{SESS_PLAIN}:0.0" in targets, str(list(targets)))
            claudey = targets.get(f"{SESS_CLAUDE}:0.0")
            check("claude-looking session flagged claude_like",
                  claudey is not None and claudey["claude_like"] is True, str(claudey))
            check("claude-looking session sorts first",
                  body["sessions"][0]["target"] == f"{SESS_CLAUDE}:0.0",
                  str([s["target"] for s in body["sessions"]]))

            # inject into the plain session
            marker = "hello-from-the-watch-98765"
            st, body = req("POST", f"{base}/prompt",
                           {"prompt": marker, "target": f"{SESS_PLAIN}:0.0"})
            check("inject 200", st == 200 and body.get("ok"), str((st, body)))
            time.sleep(0.4)
            cap = subprocess.run(["tmux", "capture-pane", "-t", f"{SESS_PLAIN}:0.0", "-p"],
                                 capture_output=True, text=True)
            check("inject delivered to pane", marker in cap.stdout, repr(cap.stdout))

            # missing target
            st, body = req("POST", f"{base}/prompt",
                           {"prompt": "x", "target": "no-such-xyz:0.0"})
            check("missing target -> 500 with message",
                  st == 500 and "not found" in body.get("error", ""), str((st, body)))

            # no target + no default -> clear error
            st, body = req("POST", f"{base}/prompt", {"prompt": "x"})
            check("no target -> 500 with message",
                  st == 500 and "no target" in body.get("error", "").lower(), str((st, body)))
        else:
            print("  SKIP  session/inject tests (tmux not installed)")
    finally:
        server.send_signal(signal.SIGINT)
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
        if have_tmux:
            kill_sessions()

    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
