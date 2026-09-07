#!/usr/bin/env bash
# Riscrive i path assoluti del vecchio $HOME nelle config ripristinate, per
# quando il nuovo sistema ha username diverso.
#   ./scripts/rehome.sh              elenca cosa cambierebbe (default)
#   ./scripts/rehome.sh --apply      applica, con backup .rehome-bak
set -uo pipefail

OLD_FILE="$HOME/.config/confsync/origin.home"
[ -r "$OLD_FILE" ] || { echo "origin.home assente: backup troppo vecchio, passa il vecchio HOME a mano" >&2; exit 1; }
OLD="$(cat "$OLD_FILE")"
[ -n "$OLD" ] || { echo "origin.home vuoto" >&2; exit 1; }
[ "$OLD" != "$HOME" ] || { echo "HOME invariato ($HOME): niente da fare"; exit 0; }

APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1

# Solo config che vengono *eseguite*. Fuori: .zsh_history e i transcript di
# .claude (archivio: riscriverli falsifica ciò che è stato realmente digitato),
# i log applicativi e i database LevelDB, che non sono testo da editare.
ROOTS=(.zshrc .bashrc .profile .zprofile .aliases .gitconfig .tmux.conf
       .config .claude/settings.json .claude/settings.local.json
       .local/share/applications .local/bin bin)
# origin.home tiene il vecchio path per definizione: riscriverlo renderebbe
# lo script non ripetibile.
SKIP_RE='/\.config/confsync/origin\.home$|/(transcripts|projects|session-data|homunculus|jobs|sessions|backups|shell-snapshots)/|\.(log|log\.[0-9]+|bak|jsonl)$|\.rehome-bak$|(^|/)LOG(\.old)?$|/leveldb/|/Local Storage/|/Session Storage/'

mapfile -t targets < <(
  for r in "${ROOTS[@]}"; do
    [ -e "$HOME/$r" ] || continue
    grep -rlI -- "$OLD" "$HOME/$r" 2>/dev/null
  done | sort -u | grep -Ev "$SKIP_RE"
)

[ "${#targets[@]}" -gt 0 ] || { echo "nessun riferimento a $OLD nelle config attive"; exit 0; }

echo "$OLD -> $HOME   (${#targets[@]} file)"
for f in "${targets[@]}"; do
  n="$(grep -c -- "$OLD" "$f" 2>/dev/null)"
  printf '  %3s  %s\n' "$n" "${f#"$HOME"/}"
  if [ "$APPLY" -eq 1 ]; then
    cp -a "$f" "$f.rehome-bak" && sed -i "s|$OLD|$HOME|g" "$f"
  fi
done

if [ "$APPLY" -eq 1 ]; then
  echo "applicato (originali in *.rehome-bak)"
  command -v systemctl >/dev/null && systemctl --user daemon-reload 2>/dev/null
else
  echo "dry-run: rilancia con --apply per scrivere"
fi
