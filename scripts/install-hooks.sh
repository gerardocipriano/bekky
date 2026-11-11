#!/usr/bin/env bash
# Aggiunge (o con --uninstall toglie) l'hook SessionEnd di Claude Code che lancia
# scripts/quick-push.sh. Idempotente, conserva gli altri hook, backup prima di
# ogni modifica. File: ${CLAUDE_SETTINGS:-~/.claude/settings.json}. Richiede jq.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
CMD="$SCRIPT_DIR/quick-push.sh"
MODE=install
[ "${1:-}" != --uninstall ] || MODE=uninstall

command -v jq >/dev/null 2>&1 || { echo "ERRORE: serve jq" >&2; exit 1; }
if [ ! -f "$SETTINGS" ]; then
  [ "$MODE" = install ] || { echo "nessun $SETTINGS: niente da togliere"; exit 0; }
  mkdir -p "$(dirname "$SETTINGS")"; echo '{}' > "$SETTINGS"
fi
jq -e . "$SETTINGS" >/dev/null || { echo "ERRORE: $SETTINGS non e' JSON valido" >&2; exit 1; }

present() { jq -e --arg c "$CMD" 'any(.hooks.SessionEnd[]?.hooks[]?; .command == $c)' "$SETTINGS" >/dev/null 2>&1; }

if [ "$MODE" = install ]; then
  if present; then echo "hook gia' presente in $SETTINGS"; exit 0; fi
  # shellcheck disable=SC2016  # $c e' una variabile jq, non shell
  filter='.hooks //= {} | .hooks.SessionEnd //= [] | .hooks.SessionEnd += [{"hooks":[{"type":"command","command":$c}]}]'
else
  if ! present; then echo "hook non presente in $SETTINGS"; exit 0; fi
  # shellcheck disable=SC2016  # $c e' una variabile jq, non shell
  filter='.hooks.SessionEnd |= (map(.hooks |= map(select(.command != $c))) | map(select((.hooks | length) > 0)))
          | if (.hooks.SessionEnd | length) == 0 then del(.hooks.SessionEnd) else . end
          | if (.hooks | length) == 0 then del(.hooks) else . end'
fi

cp -a "$SETTINGS" "$SETTINGS.bekky-bak-$(date +%Y%m%dT%H%M%S)"
tmp="$(mktemp "$SETTINGS.XXXXXX")"
jq --arg c "$CMD" "$filter" "$SETTINGS" > "$tmp"
chmod --reference="$SETTINGS" "$tmp"
mv "$tmp" "$SETTINGS"
echo "hook $MODE: $SETTINGS"
