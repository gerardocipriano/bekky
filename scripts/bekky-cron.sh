#!/usr/bin/env bash
# Wrapper per il backup automatico (cron settimanale) di bekky/confsync.
# Legge la passphrase da file 0600, esegue il backup, e su fallimento manda
# una notifica desktop (notify-send). Non-interattivo.
set -uo pipefail

DIR="$HOME/code/misc/bekky"
PASS_FILE="$HOME/.config/confsync/passphrase"
LOG="$HOME/.config/confsync/last-run.log"

# Ambiente per uso da cron (PATH ridotto)
export PATH="$HOME/google-cloud-sdk/bin:/usr/local/bin:/usr/bin:/bin"
export CLOUDSDK_CONFIG="$HOME/.config/gcloud"

notify_fail() {
  local msg="$1"
  # Aggancia la sessione grafica dell'utente (necessario da cron)
  export DISPLAY="${DISPLAY:-:0}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
  notify-send -u critical "Bekky: backup FALLITO" "$msg (log: $LOG)" 2>/dev/null || true
}

if [ ! -r "$PASS_FILE" ]; then
  notify_fail "passphrase non leggibile in $PASS_FILE"
  exit 1
fi

CONFSYNC_PASSPHRASE="$(cat "$PASS_FILE")"
export CONFSYNC_PASSPHRASE

if "$DIR/confsync" backup >"$LOG" 2>&1; then
  exit 0
else
  rc=$?
  notify_fail "exit code $rc"
  exit "$rc"
fi
