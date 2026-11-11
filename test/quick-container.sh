#!/usr/bin/env bash
# End-to-end del percorso quick in un ubuntu:24.04 pulito (serve docker).
#   test/quick-container.sh            restore + asserzioni, senza installare tool
#   test/quick-container.sh --tools    in piu' esegue quick-tools.sh (rete reale)
# Nessun accesso al bucket vero: gsutil finto su filesystem, CONFSYNC_QUICK_SRC=file://.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${QUICK_TEST_IMAGE:-ubuntu:24.04}"
TOOLS=0; [ "${1:-}" != --tools ] || TOOLS=1

# shellcheck disable=SC1091
. "$ROOT/test/helper.bash"
CONFSYNC="$ROOT/confsync"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/fixhome"
make_quick_fixture "$FIX"
# un path assoluto della HOME di origine, per verificare il rehome
printf '{"hooks":{},"statusLine":"%s/.local/bin/mio"}\n' "$FIX" > "$FIX/.claude/settings.json"
export CONFSYNC
export CONFSYNC_NO_EXPORTS=1
echo ">> backup --quick della fixture ($FIX)"
run_quick_backup "$FIX" "$TMP" >/dev/null
Q="$TMP/bucket/quick"
[ -f "$Q/MANIFEST.txt" ] || { echo "backup quick non prodotto"; exit 1; }

cat > "$TMP/inner.sh" <<'INNER'
set -uo pipefail
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
chk() { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

# il PC "vuoto": con curl|bash lo stdin e' lo script
cat /bekky-src/scripts/quick.sh | BEKKY_NO_TOOLS=1 BEKKY_NO_REPOS=1 bash 2>&1 | tee /tmp/quick.out
[ "${PIPESTATUS[1]}" -eq 0 ] || bad "quick.sh uscito con errore"

chk "CLAUDE.md ripristinato"        grep -q '# globale' "$HOME/CLAUDE.md"
chk "memory ripristinata"           test -f "$HOME/.claude/projects/-home-x/memory/MEMORY.md"
chk "plugins ripristinati (archivio separato)" test -f "$HOME/.claude/plugins/marketplaces/m1/p.txt"
chk "transcript assente"            test ! -e "$HOME/.claude/projects/-home-x/sess1.jsonl"
chk "file-history assente"          test ! -e "$HOME/.claude/file-history"
chk "credenziali Claude presenti"   grep -q cred-claude "$HOME/.claude/.credentials.json"
chk "credenziali Claude 600"        test "$(stat -c %a "$HOME/.claude/.credentials.json")" = 600
chk "chiave ssh 600"                test "$(stat -c %a "$HOME/.ssh/id_test")" = 600
chk ".ssh 700"                      test "$(stat -c %a "$HOME/.ssh")" = 700
chk "script in .local/bin eseguibile" test -x "$HOME/.local/bin/mio"
chk "passphrase salvata 600"        test "$(stat -c %a "$HOME/.config/confsync/passphrase")" = 600
chk "passphrase salvata" test "$(cat "$HOME/.config/confsync/passphrase")" = tp
chk "inventario dev"                grep -q '^22$' "$HOME/.config/confsync/inventory-quick/dev/nvm-default.txt"
chk "repos.manifest copiato"        test -f "$HOME/.config/confsync/quick/repos.manifest.json"
chk "rehome applicato"              grep -q "$HOME/.local/bin/mio" "$HOME/.claude/settings.json"
chk "tempo stampato"                grep -Eq 'restore quick: [0-9]+s' /tmp/quick.out
chk "riepilogo con tempo totale"    grep -Eq 'pronto in [0-9]+s' /tmp/quick.out
chk "idempotente (secondo run)"     bash -c 'cat /bekky-src/scripts/quick.sh | BEKKY_NO_TOOLS=1 BEKKY_NO_REPOS=1 bash >/dev/null 2>&1'

if [ "${RUN_TOOLS:-0}" = 1 ]; then
  echo ">> quick-tools.sh in foreground"
  "$HOME/code/misc/bekky/scripts/quick-tools.sh"; echo "quick-tools rc=$?"
  echo "--- tools-status.txt"; cat "$HOME/.config/confsync/quick-logs/tools-status.txt"
  export PATH="$HOME/.local/bin:$PATH"
  echo "--- versioni"
  for c in "node --version" "npm --version" "rtk --version" "uv --version" "opencode --version" \
           "gcloud --version" "terraform version" "kubectl version --client" "gh --version" \
           "glab --version" "jq --version" "op --version"; do
    printf '%s: ' "${c%% *}"; $c 2>&1 | head -1
  done
  chk "gcloud --version risponde" bash -c 'gcloud --version >/dev/null 2>&1'
fi
exit $fail
INNER

PKGS="curl ca-certificates openssl"
[ "$TOOLS" -eq 0 ] || PKGS="$PKGS unzip"
echo ">> docker $IMAGE (pacchetti extra: $PKGS)"
# Root solo per installare i pacchetti, poi utente normale con HOME diversa da quella della fixture
docker run --rm \
  -v "$ROOT:/bekky-src:ro" -v "$Q:/quick:ro" -v "$TMP/inner.sh:/inner.sh:ro" \
  -e PKGS="$PKGS" -e RUN_TOOLS="$TOOLS" \
  "$IMAGE" bash -c '
    set -e
    for c in curl tar gzip openssl unzip git python3; do
      command -v $c >/dev/null 2>&1 && echo "presente nell immagine: $c" || echo "assente nell immagine: $c"
    done
    apt-get update -qq >/dev/null && apt-get install -y -qq $PKGS >/dev/null
    useradd -m -u 1500 tester
    runuser -u tester -- env HOME=/home/tester USER=tester CONFSYNC_PASSPHRASE=tp \
      CONFSYNC_QUICK_SRC=file:///quick BEKKY_SRC=/bekky-src RUN_TOOLS="$RUN_TOOLS" \
      PATH=/usr/local/bin:/usr/bin:/bin bash /inner.sh
  '
