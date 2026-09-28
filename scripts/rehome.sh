#!/usr/bin/env bash
# Riscrive i path assoluti del vecchio $HOME nelle config ripristinate, per
# quando il nuovo sistema ha username diverso.
#   ./scripts/rehome.sh                     elenca cosa cambierebbe (default)
#   ./scripts/rehome.sh --apply             applica, con backup .rehome-bak
#   ./scripts/rehome.sh --old-home PATH     per i backup anteriori a origin.home
set -uo pipefail

APPLY=0; OLD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)    APPLY=1 ;;
    --old-home) shift; OLD="${1:-}" ;;
    *) echo "argomento sconosciuto: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$OLD" ]; then
  OLD_FILE="$HOME/.config/confsync/origin.home"
  [ -r "$OLD_FILE" ] || { echo "origin.home assente (backup anteriore a questa versione): rilancia con --old-home /home/vecchio-utente" >&2; exit 1; }
  OLD="$(cat "$OLD_FILE")"
fi
[ -n "$OLD" ] || { echo "vecchio HOME non determinato" >&2; exit 1; }
[ "$OLD" != "$HOME" ] || { echo "HOME invariato ($HOME): niente da fare"; exit 0; }

# Solo config che vengono *eseguite*. Fuori: .zsh_history e i transcript di
# .claude (archivio: riscriverli falsifica ciò che è stato realmente digitato),
# i log applicativi e i database LevelDB, che non sono testo da editare.
ROOTS=(.zshrc .bashrc .profile .zprofile .aliases .gitconfig .tmux.conf
       .config .claude .claude.json .local/share/applications .local/bin bin
       scripts .hermes .opencode .gemini .agents .pixel-agents .claude-mem
       .config/confsync/inventory/system/etc)
# origin.home tiene il vecchio path per definizione: riscriverlo renderebbe
# lo script non ripetibile.
SKIP_RE='/\.config/confsync/origin\.home$|/(transcripts|projects|session-data|homunculus|jobs|sessions|backups|shell-snapshots|file-history|\.doctor-backup|statsig)/|\.(log|log\.[0-9]+|jsonl)$|\.(bak|doctor-bak)[^/]*$|\.rehome-bak$|(^|/)LOG(\.old)?$|/leveldb/|/Local Storage/|/Session Storage/'

mapfile -t targets < <(
  for r in "${ROOTS[@]}"; do
    [ -e "$HOME/$r" ] || continue
    grep -rlI -- "$OLD" "$HOME/$r" 2>/dev/null
  done | sort -u | grep -Ev "$SKIP_RE"
)

[ "${#targets[@]}" -gt 0 ] || echo "nessun riferimento a $OLD nelle config attive"

echo "$OLD -> $HOME   (${#targets[@]} file)"
for f in "${targets[@]}"; do
  n="$(grep -c -- "$OLD" "$f" 2>/dev/null)"
  printf '  %3s  %s\n' "$n" "${f#"$HOME"/}"
  if [ "$APPLY" -eq 1 ]; then
    cp -a "$f" "$f.rehome-bak" && sed -i "s|$OLD|$HOME|g" "$f"
  fi
done

# Claude Code tiene memoria e sessioni in ~/.claude/projects/<cwd codificata>:
# con un altro HOME le directory vanno rinominate o la memoria non si aggancia.
enc() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
PROJ="$HOME/.claude/projects"
if [ -d "$PROJ" ]; then
  oldp="$(enc "$OLD")"; newp="$(enc "$HOME")"
  for d in "$PROJ/$oldp" "$PROJ/$oldp"-*; do
    [ -d "$d" ] || continue
    dst="$PROJ/$newp${d#"$PROJ/$oldp"}"
    [ -e "$dst" ] && { echo "  skip ${d#"$PROJ"/}: esiste già $(basename "$dst")"; continue; }
    echo "  rinomina projects/${d#"$PROJ"/} -> $(basename "$dst")"
    [ "$APPLY" -eq 1 ] && mv "$d" "$dst"
  done
fi

if [ "$APPLY" -eq 1 ]; then
  echo "applicato (originali in *.rehome-bak)"
  command -v systemctl >/dev/null && systemctl --user daemon-reload 2>/dev/null
else
  echo "dry-run: rilancia con --apply per scrivere"
fi
