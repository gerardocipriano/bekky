#!/usr/bin/env bash
# Wrapper per il backup automatico (cron settimanale) di bekky/confsync.
# Legge la passphrase da file 0600, esegue il backup, e su fallimento manda
# una notifica desktop (notify-send). Non-interattivo.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS_FILE="$HOME/.config/confsync/passphrase"
LOG="$HOME/.config/confsync/last-run.log"
# shellcheck disable=SC1091
. "$DIR/lib/history.sh"

# Ambiente per uso da cron (PATH ridotto). L'SDK sta in $HOME se installato da
# tarball, in /usr/bin se dal pacchetto della distro: teniamo entrambi.
export PATH="$HOME/google-cloud-sdk/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/snap/bin"
export CLOUDSDK_CONFIG="$HOME/.config/gcloud"

notify_fail() {
  local msg="$1" title="${2:-Bekky: backup FALLITO}"
  # Aggancia la sessione grafica dell'utente (necessario da cron)
  export DISPLAY="${DISPLAY:-:0}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
  notify-send -u critical "$title" "$msg (log: $LOG)" 2>/dev/null || true
}

if [ ! -r "$PASS_FILE" ]; then
  notify_fail "passphrase non leggibile in $PASS_FILE"
  history_add full fail 0
  exit 1
fi

CONFSYNC_PASSPHRASE="$(cat "$PASS_FILE")"
export CONFSYNC_PASSPHRASE

# Config agenti generale su git (awesome-agent-config): best effort, non deve
# mai far fallire o saltare il backup cifrato. Il timeout evita che un push
# appeso blocchi la run. Exit 1 = il gate segreti ha bloccato la pubblicazione.
echo "== agent-config --push ==" >"$LOG"
timeout 300 "$DIR/confsync" agent-config --push >>"$LOG" 2>&1
ac_rc=$?
echo "== agent-config exit code: $ac_rc ==" >>"$LOG"
if [ "$ac_rc" -eq 1 ]; then
  notify_fail "agent-config NON pubblicata su git: gate segreti fallito" "Bekky: agent-config bloccata"
fi
echo "== confsync backup ==" >>"$LOG"

if "$DIR/confsync" backup >>"$LOG" 2>&1; then
  exit 0
else
  rc=$?
  history_add full fail 0
  notify_fail "exit code $rc"
  exit "$rc"
fi
