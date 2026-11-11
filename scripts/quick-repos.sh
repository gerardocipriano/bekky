#!/usr/bin/env bash
# Clona le repo del manifest quick (~/.config/confsync/quick/repos.manifest.json)
# che mancano su disco, in parallelo. Log in ~/.config/confsync/quick-logs/.
set -uo pipefail

CONF="$HOME/.config/confsync"
LOGS="$CONF/quick-logs"
MANIFEST="$CONF/quick/repos.manifest.json"
FAILED="$LOGS/repos-failed.txt"
mkdir -p "$LOGS"

# Un clone: riga "path<TAB>remote<TAB>branch". Richiamato da xargs.
clone_one() {
  local path remote branch rel out tmp
  IFS=$'\t' read -r path remote branch <<<"$1"
  rel="${path#"$HOME"/}"
  if [ -d "$path/.git" ]; then echo "gia' presente: $rel"; return 0; fi
  # La dir puo' esistere senza .git (file locali estratti prima): git clone
  # rifiuta una dir non vuota, quindi si clona a parte e si sposta solo .git.
  tmp="$path.bekky-clone"
  rm -rf "$tmp"; mkdir -p "$(dirname "$path")"
  if ! out="$(GIT_TERMINAL_PROMPT=0 git clone --no-checkout "$remote" "$tmp" 2>&1)"; then
    rm -rf "$tmp"
    echo "FAIL clone $rel ($remote): $(printf '%s' "$out" | tail -1)"
    printf '%s\t%s\n' "$rel" "$remote" >> "$FAILED"
    return 0
  fi
  mkdir -p "$path" && mv "$tmp/.git" "$path/.git" && rm -rf "$tmp"
  git -C "$path" reset -q --hard >/dev/null 2>&1 || true
  if [ -n "$branch" ] && ! git -C "$path" checkout -q "$branch" >/dev/null 2>&1; then
    echo "checkout di '$branch' non riuscito in $rel"
  fi
  echo "clonata: $rel"
}

# Host SSH di un remote: git@host:path e ssh://[user@]host[:port]/path.
# Stampa "user host port"; vuoto per https e path locali.
ssh_target() {
  case "$1" in
    ssh://*)
      printf '%s' "$1" | sed -n 's#^ssh://\(\([^@/]*\)@\)\{0,1\}\([^:/]*\)\(:\([0-9]*\)\)\{0,1\}/.*#\2 \3 \5#p' ;;
    *@*:*)
      case "$1" in *://*) return 0 ;; esac
      printf '%s' "$1" | sed -n 's#^\([^@]*\)@\([^:/]*\):.*#\1 \2 #p' ;;
  esac
}

main() {
  if [ "${1:-}" = --clone-one ]; then clone_one "$2"; return; fi
  : > "$FAILED"
  command -v git >/dev/null 2>&1 || { echo "git non installato: installalo e rilancia"; return 1; }
  [ -f "$MANIFEST" ] || { echo "manifest assente: $MANIFEST"; return 1; }
  local origin; origin="$(cat "$CONF/quick/origin.home" 2>/dev/null || echo "$HOME")"

  local entry path remote branch todo rows
  todo="$(mktemp)"
  while read -r entry; do
    path="$(echo "$entry"   | sed -n 's/.*"path":"\([^"]*\)".*/\1/p')"
    remote="$(echo "$entry" | sed -n 's/.*"remote":"\([^"]*\)".*/\1/p')"
    branch="$(echo "$entry" | sed -n 's/.*"branch":"\([^"]*\)".*/\1/p')"
    [ -n "$path" ] && [ -n "$remote" ] || continue
    if [ -n "$origin" ] && [ "${path#"$origin"/}" != "$path" ]; then path="$HOME/${path#"$origin"/}"; fi
    [ -d "$path/.git" ] && continue
    printf '%s\t%s\t%s\n' "$path" "$remote" "$branch" >> "$todo"
  done < <(grep -o '{[^}]*}' "$MANIFEST")
  rows="$(wc -l < "$todo")"
  echo "repo da clonare: $rows"

  # Un controllo SSH per host: gli host che non rispondono si saltano.
  # git@github.com esce con 1 anche se l'auth riesce; 255 = connessione/auth.
  local bad="" seen="" t user host port rc
  while IFS=$'\t' read -r path remote branch; do
    t="$(ssh_target "$remote")"
    [ -n "$t" ] || continue
    read -r user host port <<<"$t"
    case " $seen " in *" $host:$port "*) continue ;; esac
    seen="$seen $host:$port"
    rc=0
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        ${port:+-p "$port"} -T "${user:-git}@$host" </dev/null >/dev/null 2>&1 || rc=$?
    if [ "$rc" -gt 1 ]; then
      bad="$bad $host:$port"
      echo "SKIP host $host: SSH non risponde"
      printf 'SKIP host %s: sblocca 1Password / agent SSH e rilancia\n' "$host" >> "$FAILED"
    fi
  done < "$todo"

  local run; run="$(mktemp)"
  while IFS=$'\t' read -r path remote branch; do
    t="$(ssh_target "$remote")"
    if [ -n "$t" ]; then
      read -r user host port <<<"$t"
      case " $bad " in *" $host:$port "*) continue ;; esac
    fi
    printf '%s\t%s\t%s\n' "$path" "$remote" "$branch"
  done < "$todo" > "$run"

  xargs -d '\n' -P 6 -I{} bash "$0" --clone-one {} < "$run"
  rm -f "$todo" "$run"

  if [ -s "$FAILED" ]; then echo "Problemi: vedi $FAILED"; fi
  echo "Fatto. Commit locali, stash e file non versionati arrivano con:"
  echo "  confsync restore --yes --no-dotfiles --repos"
}

main "$@"
