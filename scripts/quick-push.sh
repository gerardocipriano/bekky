#!/usr/bin/env bash
# Hook SessionEnd di Claude Code: lancia "confsync backup --quick" in background
# e ritorna subito. Passphrase da ~/.config/confsync/passphrase, log in
# ~/.config/confsync/quick-push.log (troncato a ogni run). Lo stdin (JSON) si ignora.
set -uo pipefail

exec </dev/null
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$HOME/.config/confsync"
# shellcheck disable=SC1091
. "$DIR/lib/history.sh"
LOG="$CONF/quick-push.log"

if [ "${1:-}" != --run ]; then
  mkdir -p "$CONF"
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup "$0" --run >/dev/null 2>&1 &
  else
    nohup "$0" --run >/dev/null 2>&1 &
  fi
  exit 0
fi

# gcloud userland e ~/.local/bin possono mancare dal PATH dell'hook
export PATH="$HOME/google-cloud-sdk/bin:$HOME/.local/bin:$PATH:/usr/local/bin:/usr/bin:/bin:/snap/bin"

notify_fail() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -u critical "Bekky: backup quick FALLITO" "$1 (log: $LOG)" 2>/dev/null || true
}

mkdir -p "$CONF"
: > "$LOG"
if [ ! -r "$CONF/passphrase" ]; then
  echo "passphrase non leggibile in $CONF/passphrase" >> "$LOG"
  notify_fail "passphrase mancante"
  history_add quick fail 0
  exit 1
fi
CONFSYNC_PASSPHRASE="$(cat "$CONF/passphrase")"
export CONFSYNC_PASSPHRASE

if "$DIR/confsync" backup --quick >> "$LOG" 2>&1; then
  exit 0
else
  rc=$?
  history_add quick fail 0
  notify_fail "exit code $rc"
  exit "$rc"
fi
