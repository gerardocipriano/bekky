# shellcheck shell=bash
# history_add <quick|full> <upload|dedup|fail> [bytes]: una riga in
# ~/.config/confsync/history.tsv (ts, kind, result, bytes), ultime 500 righe.
# Non fallisce mai: lo storico non deve rompere un backup.
history_add() {
  local f="${CONFSYNC_HISTORY:-$HOME/.config/confsync/history.tsv}" tmp
  {
    mkdir -p "$(dirname "$f")"
    printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "${3:-0}" >> "$f"
    tmp="$(mktemp "$f.XXXXXX")"
    tail -n 500 "$f" > "$tmp" && mv "$tmp" "$f"
  } 2>/dev/null || true
}

# Somma dei byte dei file di una dir di lavoro (dimensione di un backup)
history_dir_bytes() {
  du -sb "$1" 2>/dev/null | awk '{print $1}' || echo 0
}
