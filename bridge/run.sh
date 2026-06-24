#!/usr/bin/env bash
# Launch the Claude Watch Bridge.
#   ./run.sh            # uses config.json (or env vars)
# First time:
#   cp config.example.json config.json   &&   edit it (set a token)
set -euo pipefail
cd "$(dirname "$0")"
exec python3 server.py
