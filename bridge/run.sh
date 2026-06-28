#!/usr/bin/env bash
# Launch the Claude Watch Bridge.
#   ./run.sh            # uses config.json (or env vars)
# First time:
#   cp config.example.json config.json   &&   edit it (set a token)
set -euo pipefail
# LaunchAgents and GUI shells often have a minimal PATH, so include the
# standard Homebrew locations where tmux is installed on Apple Silicon/Intel.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
cd "$(dirname "$0")"
exec python3 server.py
