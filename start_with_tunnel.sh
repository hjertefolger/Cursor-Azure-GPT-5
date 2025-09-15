#!/usr/bin/env bash
set -euo pipefail

# Start local Flask app and expose it via Cloudflare Tunnel.
# Prints the public tunnel URL for quick copy into Cursor's OpenAI Base URL override.
#
# Usage:
#   ./start_with_tunnel.sh [PORT]
#
# Notes:
# - Defaults to PORT from args, then FLASK_RUN_PORT, then PORT, then 9090.
# - Requires cloudflared installed (brew install cloudflared on macOS).
# - Loads env from .env if present.
# - Leaves both Flask and cloudflared running until Ctrl+C.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${1:-${FLASK_RUN_PORT:-${PORT:-9090}}}"
HOST="${HOST:-127.0.0.1}"
export FLASK_APP="${FLASK_APP:-autoapp.py}"
CF_BIN="${CLOUDFLARED_BIN:-cloudflared}"

echo ">> Starting Cursor-Azure-GPT-5 on http://$HOST:$PORT and exposing via Cloudflare Tunnel"

# Ensure virtualenv
if [[ ! -d "$ROOT_DIR/.venv" ]]; then
  echo ">> Creating virtualenv .venv"
  python3 -m venv "$ROOT_DIR/.venv"
  source "$ROOT_DIR/.venv/bin/activate"
  if [[ -f "$ROOT_DIR/requirements/dev.txt" ]]; then
    pip install -r "$ROOT_DIR/requirements/dev.txt"
  else
    pip install -r "$ROOT_DIR/requirements/prod.txt" || pip install -r "$ROOT_DIR/requirements.txt"
  fi
else
  source "$ROOT_DIR/.venv/bin/activate"
fi

# Load env from .env if present
if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

# Check cloudflared
if ! command -v "$CF_BIN" >/dev/null 2>&1; then
  echo "!! cloudflared not found. Install it, e.g. on macOS: brew install cloudflared"
  exit 1
fi

# Logs and run dir
RUN_DIR="$ROOT_DIR/.run"
mkdir -p "$RUN_DIR"
FLASK_LOG="$RUN_DIR/flask_$PORT.log"
CF_LOG="$RUN_DIR/cloudflared_$PORT.log"
URL_FILE="$RUN_DIR/tunnel_$PORT.url"
rm -f "$URL_FILE"

# Start Flask in background
echo ">> Launching Flask... (logs: $FLASK_LOG)"
( flask run -p "$PORT" -h "$HOST" >"$FLASK_LOG" 2>&1 ) &
FLASK_PID=$!

# Wait for health
attempts=0
until curl -fsS "http://$HOST:$PORT/health" >/dev/null 2>&1; do
  attempts=$((attempts+1))
  if [[ $attempts -gt 60 ]]; then
    echo "!! Flask did not become healthy on $HOST:$PORT within timeout. See $FLASK_LOG"
    kill "$FLASK_PID" 2>/dev/null || true
    exit 1
  fi
  sleep 0.5
done
echo ">> Flask healthy on http://$HOST:$PORT"

# Start Cloudflare tunnel in background
echo ">> Launching Cloudflare Tunnel... (logs: $CF_LOG)"
( "$CF_BIN" tunnel --url "http://$HOST:$PORT" >"$CF_LOG" 2>&1 ) &
CF_PID=$!

cleanup() {
  echo ">> Stopping processes..."
  kill "$CF_PID" "$FLASK_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Wait for the public URL to appear
echo -n ">> Waiting for tunnel URL..."
for i in {1..60}; do
  if grep -Eo "https://[a-zA-Z0-9.-]+trycloudflare.com" "$CF_LOG" | head -n1 > "$URL_FILE"; then
    :
  fi
  if [[ -s "$URL_FILE" ]]; then
    TUNNEL_URL=$(cat "$URL_FILE")
    echo
    echo "TUNNEL_URL=$TUNNEL_URL"
    echo ">> Paste this URL into Cursor > Settings > Models > OpenAI Base URL override"
    break
  fi
  sleep 0.5
  echo -n "."
done

if [[ ! -s "$URL_FILE" ]]; then
  echo
  echo "!! Could not detect tunnel URL. Check $CF_LOG for details."
fi

echo ">> Flask PID: $FLASK_PID  Cloudflared PID: $CF_PID"
echo ">> Press Ctrl+C to stop both."

# Keep the script attached so Ctrl+C stops both processes
wait
