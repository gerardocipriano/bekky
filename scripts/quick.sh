#!/usr/bin/env bash
# PC vuoto, qualsiasi distro Linux:
#   curl -fsSL https://raw.githubusercontent.com/gerardocipriano/bekky/main/scripts/quick.sh | bash
# Chiede passphrase e login gcloud, ripristina config di Claude Code e credenziali, poi
# in background installa i tool e clona le repo. Idempotente.
# Env: BEKKY_DIR, BEKKY_SRC (dir locale), CONFSYNC_PASSPHRASE, CONFSYNC_QUICK_SRC,
#      BEKKY_NO_TOOLS=1, BEKKY_NO_REPOS=1
set -euo pipefail

say() { printf '\n\033[1;36m>> %s\033[0m\n' "$*"; }
err() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

ask_passphrase() {
  local p=""
  [ -r /dev/tty ] || err "serve un terminale per la passphrase: esportala in CONFSYNC_PASSPHRASE"
  # /dev/tty solo qui: lo stdin resta quello dello script
  read -rsp "Passphrase bekky (1Password: 'bekky passphrase'): " p </dev/tty
  printf '\n' >&2
  [ -n "$p" ] || err "passphrase vuota"
  printf '%s' "$p"
}

# Tutto in una funzione: con curl | bash lo stdin e' lo script stesso, e un
# comando figlio che legge stdin ne mangerebbe il resto.
main() {
  local BEKKY="${BEKKY_DIR:-$HOME/code/misc/bekky}"
  local CONF="$HOME/.config/confsync" start=$SECONDS
  local ORIG_PATH="$PATH"
  export PATH="$HOME/.local/bin:$PATH"

  # --- 2. dipendenze minime ---
  local missing=() c
  for c in curl tar gzip openssl; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  if [ ${#missing[@]} -gt 0 ]; then
    say "installo ${missing[*]}"
    local sudo=""
    if [ "$(id -u)" -ne 0 ]; then
      command -v sudo >/dev/null 2>&1 || err "mancano ${missing[*]} e non c'e' sudo: installali a mano e rilancia"
      sudo=sudo
    fi
    if   command -v apt-get >/dev/null 2>&1; then $sudo apt-get update -qq && $sudo apt-get install -y -qq "${missing[@]}"
    elif command -v dnf     >/dev/null 2>&1; then $sudo dnf install -y -q "${missing[@]}"
    elif command -v pacman  >/dev/null 2>&1; then $sudo pacman -S --noconfirm --needed "${missing[@]}"
    elif command -v zypper  >/dev/null 2>&1; then $sudo zypper -n install "${missing[@]}"
    elif command -v apk     >/dev/null 2>&1; then $sudo apk add "${missing[@]}"
    else err "package manager non riconosciuto: installa ${missing[*]} e rilancia"
    fi
    for c in "${missing[@]}"; do command -v "$c" >/dev/null 2>&1 || err "$c ancora assente dopo l'installazione"; done
  fi

  # --- 3. bekky ---
  say "bekky in $BEKKY"
  mkdir -p "$BEKKY"
  if [ -n "${BEKKY_SRC:-}" ]; then
    tar -C "$BEKKY_SRC" --exclude=.git -cf - . | tar -C "$BEKKY" -xf -
  elif [ -d "$BEKKY/.git" ] && command -v git >/dev/null 2>&1; then
    git -C "$BEKKY" pull -q --ff-only || true
  elif [ -x "$BEKKY/confsync" ]; then
    :
  elif command -v git >/dev/null 2>&1; then
    git clone -q https://github.com/gerardocipriano/bekky.git "$BEKKY.tmp" \
      && cp -a "$BEKKY.tmp/." "$BEKKY/" && rm -rf "${BEKKY:?}.tmp"
  else
    curl -fsSL https://github.com/gerardocipriano/bekky/archive/refs/heads/main.tar.gz \
      | tar -xz --strip-components=1 -C "$BEKKY"
  fi
  [ -x "$BEKKY/confsync" ] || err "confsync non trovato in $BEKKY"

  mkdir -p "$CONF"; chmod 700 "$CONF"

  # --- 4. passphrase, bucket (se non passato) e login gcloud: i soli prompt ---
  local pass="" saved=0
  if [ -n "${CONFSYNC_PASSPHRASE:-}" ]; then pass="$CONFSYNC_PASSPHRASE"
  elif [ -s "$CONF/passphrase" ]; then pass="$(cat "$CONF/passphrase")"; saved=1; fi
  if [ -z "$pass" ]; then
    pass="$(ask_passphrase)"
  fi
  export CONFSYNC_PASSPHRASE="$pass"

  if [ -z "${CONFSYNC_QUICK_SRC:-}" ]; then
    # Niente default nel repo (e' pubblico): bucket e account arrivano da
    # BEKKY_BUCKET/BEKKY_ACCOUNT/BEKKY_PROJECT davanti al one-liner (la console,
    # vista "Nuovo PC", stampa il comando completo) oppure da un prompt.
    if [ ! -f "$CONF/config" ]; then
      local b="${BEKKY_BUCKET:-}" a="${BEKKY_ACCOUNT:-}"
      if [ -z "$b" ]; then
        [ -r /dev/tty ] || err "manca BEKKY_BUCKET (es. BEKKY_BUCKET=gs://il-tuo-bucket) e non c'e' un terminale per chiederlo"
        read -rp "Bucket dei salvataggi (gs://...): " b </dev/tty
        [ -n "${BEKKY_ACCOUNT+x}" ] || read -rp "Account Google (invio = lo scegli nel browser): " a </dev/tty
      fi
      case "$b" in gs://*) ;; *) b="gs://$b" ;; esac
      [[ "$b" =~ ^gs://[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$ ]] || err "bucket non valido: $b"
      [[ "$a" =~ ^[A-Za-z0-9._%+@-]*$ ]] || err "account non valido: $a"
      [[ "${BEKKY_PROJECT:-}" =~ ^[a-z0-9:.-]*$ ]] || err "progetto non valido: ${BEKKY_PROJECT:-}"
      cat > "$CONF/config" <<EOF
export CONFSYNC_BUCKET="$b"
export CONFSYNC_PROJECT="${BEKKY_PROJECT:-}"
export CONFSYNC_ACCOUNT="$a"
EOF
      chmod 600 "$CONF/config"
    fi
    # shellcheck disable=SC1090,SC1091
    . "$CONF/config"
    if ! command -v gcloud >/dev/null 2>&1; then
      say "gcloud (userland)"
      # shellcheck disable=SC1091
      . "$BEKKY/lib/tools.sh"
      local rc=0
      ( tool_gcloud ) || rc=$?
      [ "$rc" -eq 0 ] || [ "$rc" -eq "$SKIP" ] || err "installazione di gcloud fallita (rc=$rc)"
      export PATH="$HOME/google-cloud-sdk/bin:$PATH"
    fi
    local acct="${CONFSYNC_ACCOUNT:-}" logged
    logged="$(gcloud auth list --format='value(account)' 2>/dev/null || true)"
    # con un account in config serve quello; senza, basta un account qualsiasi
    if { [ -n "$acct" ] && ! grep -qx "$acct" <<<"$logged"; } || [ -z "$logged" ]; then
      say "login gcloud${acct:+: $acct}"
      local flags=()
      # senza browser (SSH, server): il flusso con codice da incollare
      if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then flags+=(--no-launch-browser); fi
      [ -r /dev/tty ] || err "serve un terminale per gcloud auth login: esegui 'gcloud auth login $acct' e rilancia"
      # shellcheck disable=SC2086  # acct vuoto = nessun argomento
      gcloud auth login $acct "${flags[@]}" </dev/tty
    fi
  fi

  # --- 5-6. restore (passphrase errata: nuovi tentativi) ---
  say "restore quick"
  local t0=$SECONDS tries=0 rlog; rlog="$(mktemp)"
  while :; do
    if "$BEKKY/confsync" restore --quick --yes 2>&1 | tee "$rlog" >&2 && [ "${PIPESTATUS[0]}" -eq 0 ]; then break; fi
    if grep -q 'bad decrypt' "$rlog" && [ "$tries" -lt 2 ] && [ -r /dev/tty ]; then
      echo "Passphrase errata, riprova." >&2
      tries=$((tries + 1)); saved=0
      pass="$(ask_passphrase)"; export CONFSYNC_PASSPHRASE="$pass"
      continue
    fi
    rm -f "$rlog"; err "restore quick fallito"
  done
  rm -f "$rlog"
  [ "$saved" -eq 1 ] || ( umask 077; printf '%s' "$pass" > "$CONF/passphrase" )
  chmod 600 "$CONF/passphrase"
  echo "restore quick: $((SECONDS - t0))s"

  # --- 7. rehome ---
  if [ -f "$CONF/origin.home" ] && [ "$(cat "$CONF/origin.home")" != "$HOME" ]; then
    say "rehome ($(cat "$CONF/origin.home") -> $HOME)"
    "$BEKKY/scripts/rehome.sh" --apply || true
  fi

  # --- 8. Claude Code ---
  if [ "${BEKKY_NO_TOOLS:-0}" != 1 ]; then
    if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
      say "Claude Code"
      curl -fsSL https://claude.ai/install.sh | bash
    fi
  fi

  # --- 9. tool e repo in background ---
  local logs="$CONF/quick-logs"; mkdir -p "$logs"
  local runner=(nohup); command -v setsid >/dev/null 2>&1 && runner=(setsid nohup)
  local started=()
  if [ "${BEKKY_NO_TOOLS:-0}" != 1 ]; then
    "${runner[@]}" "$BEKKY/scripts/quick-tools.sh" >"$logs/tools.log" 2>&1 </dev/null &
    started+=(tools)
  fi
  if [ "${BEKKY_NO_REPOS:-0}" != 1 ]; then
    "${runner[@]}" "$BEKKY/scripts/quick-repos.sh" >"$logs/repos.log" 2>&1 </dev/null &
    started+=(repos)
  fi

  # --- 10. riepilogo ---
  say "pronto in $((SECONDS - start))s"
  cat <<EOF
Ripristinati: config e credenziali di Claude Code, git, shell, ssh.
In background: ${started[*]:-niente}
Log: $logs/
  tools: tail -f $logs/tools.log   (stato: $logs/tools-status.txt)
  repos: tail -f $logs/repos.log   (falliti: $logs/repos-failed.txt)
Avvia Claude con:  $HOME/.local/bin/claude
EOF
  case ":$ORIG_PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "$HOME/.local/bin non e' nel PATH di questa shell: apri un nuovo terminale." ;;
  esac
}

main "$@"; exit $?
