load helper

setup() { setup_confsync; }

# Oggetto (path relativo al prefisso) di un nome logico nel MANIFEST
obj_of() { awk -v n="$2" '$1 == n { print $2 }' "$1/MANIFEST.txt"; }

# Estrae un archivio quick in $3 con la passphrase di prova
unpack() {
  env CONFSYNC_PASSPHRASE=tp CONFSYNC_COMP=gzip bash -c \
    'source "$0" --source-only; decrypt_unpack "$1" "$2"' "$CONFSYNC" "$1" "$2"
}

@test "backup --quick: core senza transcript ma con memory, credenziali solo nei secrets" {
  tmp="$(mktemp -d)"; make_quick_fixture "$tmp/home"
  run run_quick_backup "$tmp/home" "$tmp"
  [ "$status" -eq 0 ]
  q="$tmp/bucket/quick"
  [ -f "$q/MANIFEST.txt" ]
  [ ! -e "$q/BUNDLE.sha" ]
  for f in core.tar.enc plugins.tar.enc secrets.tar.enc inventory.tar.enc repos.manifest.json origin.home; do
    [ -f "$q/$(obj_of "$q" "$f")" ]
  done
  # MANIFEST: "nome oggetto sha-del-cifrato", sha coerente col file
  [ "$(wc -l < "$q/MANIFEST.txt")" -eq 6 ]
  [ "$(awk '$1=="core.tar.enc"{print $3}' "$q/MANIFEST.txt")" = "$(sha256sum "$q/$(obj_of "$q" core.tar.enc)" | cut -d' ' -f1)" ]
  unpack "$q/$(obj_of "$q" core.tar.enc)" "$tmp/core"
  unpack "$q/$(obj_of "$q" plugins.tar.enc)" "$tmp/plug"
  unpack "$q/$(obj_of "$q" secrets.tar.enc)" "$tmp/sec"
  # plugins separati dal core
  [ -f "$tmp/plug/.claude/plugins/marketplaces/m1/p.txt" ]
  [ ! -e "$tmp/core/.claude/plugins" ]
  [ -f "$tmp/core/.claude/settings.json" ]
  [ -f "$tmp/core/.claude.json" ]
  [ -f "$tmp/core/.claude/projects/-home-x/memory/MEMORY.md" ]
  [ ! -e "$tmp/core/.claude/projects/-home-x/sess1.jsonl" ]
  [ ! -e "$tmp/core/.claude/projects/-home-x/sess1" ]
  [ ! -e "$tmp/core/.claude/file-history" ]
  [ -x "$tmp/core/.local/bin/mio" ]
  # credenziali: non nel core
  [ ! -e "$tmp/core/.claude/.credentials.json" ]
  [ ! -e "$tmp/core/.config/gcloud/credentials.db" ]
  [ ! -e "$tmp/core/.config/gh/hosts.yml" ]
  [ -f "$tmp/core/.config/gcloud/properties" ]
  [ ! -e "$tmp/core/.ssh" ]
  # ...ma nei secrets
  [ -f "$tmp/sec/.claude/.credentials.json" ]
  [ -f "$tmp/sec/.ssh/id_test" ]
  [ -f "$tmp/sec/.config/gcloud/credentials.db" ]
  [ -f "$tmp/sec/.config/gh/hosts.yml" ]
  [ ! -e "$tmp/sec/.zshrc" ]
  # stato confsync mai nel core
  [ ! -e "$tmp/core/.config/confsync" ]
  # inventario dev
  unpack "$q/$(obj_of "$q" inventory.tar.enc)" "$tmp/inv"
  [ "$(cat "$tmp/inv/dev/nvm-default.txt")" = "22" ]
}

@test "round-trip backup --quick -> restore --quick via CONFSYNC_QUICK_SRC in un'altra HOME" {
  tmp="$(mktemp -d)"; make_quick_fixture "$tmp/home"
  run run_quick_backup "$tmp/home" "$tmp"; [ "$status" -eq 0 ]
  new="$tmp/new"; mkdir -p "$new/.config/confsync" "$new/.claude"
  echo "# config-locale" > "$new/.config/confsync/config"
  echo "login-vecchio" > "$new/.claude/.credentials.json"
  echo "init-ubuntu" > "$new/.profile"
  run env HOME="$new" CONFSYNC_PASSPHRASE=tp CONFSYNC_QUICK_SRC="file://$tmp/bucket/quick" \
      bash "$CONFSYNC" restore --quick --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$new/CLAUDE.md")" = "# globale" ]
  [ "$(cat "$new/.claude/settings.json")" = '{"hooks":{}}' ]
  [ "$(cat "$new/.claude/plugins/marketplaces/m1/p.txt")" = "plugin" ]
  [ "$(cat "$new/.claude/projects/-home-x/memory/MEMORY.md")" = "ricordo" ]
  [ ! -e "$new/.claude/projects/-home-x/sess1.jsonl" ]
  # credenziali Claude sovrascritte, permessi stretti
  [ "$(cat "$new/.claude/.credentials.json")" = '{"tok":"cred-claude"}' ]
  [ "$(stat -c %a "$new/.claude/.credentials.json")" = 600 ]
  [ "$(stat -c %a "$new/.ssh/id_test")" = 600 ]
  [ "$(stat -c %a "$new/.ssh")" = 700 ]
  # .config/confsync non sovrascritto (ne' config ne' passphrase della fixture)
  [ "$(cat "$new/.config/confsync/config")" = "# config-locale" ]
  [ ! -s "$new/.config/confsync/passphrase" ] || [ "$(cat "$new/.config/confsync/passphrase")" != "locale" ]
  # init file originale conservato
  [ "$(cat "$new/.config/confsync/pre-restore/.profile")" = "init-ubuntu" ]
  [ "$(cat "$new/.config/confsync/inventory-quick/dev/nvm-default.txt")" = "22" ]
  [ -f "$new/.config/confsync/quick/repos.manifest.json" ]
  [ "$(cat "$new/.config/confsync/origin.home")" = "$tmp/home" ]
}

@test "restore --quick: passphrase errata fallisce" {
  tmp="$(mktemp -d)"; make_quick_fixture "$tmp/home"
  run run_quick_backup "$tmp/home" "$tmp"; [ "$status" -eq 0 ]
  mkdir -p "$tmp/new"
  run env HOME="$tmp/new" CONFSYNC_PASSPHRASE=sbagliata CONFSYNC_QUICK_SRC="file://$tmp/bucket/quick" \
      bash "$CONFSYNC" restore --quick --yes
  [ "$status" -ne 0 ]
}

@test "restore --quick: archivio manomesso fallisce sul checksum" {
  tmp="$(mktemp -d)"; make_quick_fixture "$tmp/home"
  run run_quick_backup "$tmp/home" "$tmp"; [ "$status" -eq 0 ]
  echo corrotto >> "$tmp/bucket/quick/$(obj_of "$tmp/bucket/quick" core.tar.enc)"
  mkdir -p "$tmp/new"
  run env HOME="$tmp/new" CONFSYNC_PASSPHRASE=tp CONFSYNC_QUICK_SRC="file://$tmp/bucket/quick" \
      bash "$CONFSYNC" restore --quick --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum"* ]]
}

@test "backup --quick: secondo run senza modifiche non carica (dedup)" {
  tmp="$(mktemp -d)"; make_quick_fixture "$tmp/home"
  run run_quick_backup "$tmp/home" "$tmp"; [ "$status" -eq 0 ]
  q="$tmp/bucket/quick"
  cp "$q/MANIFEST.txt" "$tmp/manifest.first"
  ls -l --time-style=full-iso "$q/objects" > "$tmp/objs.first"
  run run_quick_backup "$tmp/home" "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dedup"* ]]
  cmp "$tmp/manifest.first" "$q/MANIFEST.txt"
  [ "$(ls -l --time-style=full-iso "$q/objects")" = "$(cat "$tmp/objs.first")" ]
  [ "$(tail -1 "$tmp/home/.config/confsync/history.tsv" | cut -f2-4)" = "quick	dedup	0" ]
}

@test "backup --quick: modifica fuori da plugins carica solo core, orfani rimossi, byte contati" {
  tmp="$(mktemp -d)"; make_quick_fixture "$tmp/home"
  run run_quick_backup "$tmp/home" "$tmp"; [ "$status" -eq 0 ]
  q="$tmp/bucket/quick"
  plug1="$(obj_of "$q" plugins.tar.enc)"; core1="$(obj_of "$q" core.tar.enc)"
  inv1="$(obj_of "$q" inventory.tar.enc)"
  bytes1="$(tail -1 "$tmp/home/.config/confsync/history.tsv" | cut -f4)"
  echo "nuovo" > "$tmp/home/CLAUDE.md"
  run run_quick_backup "$tmp/home" "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(1 oggetti nuovi)"* ]]
  [ "$(obj_of "$q" plugins.tar.enc)" = "$plug1" ]
  [ "$(obj_of "$q" inventory.tar.enc)" = "$inv1" ]
  core2="$(obj_of "$q" core.tar.enc)"; [ "$core2" != "$core1" ]
  # il core vecchio non e' piu' referenziato: sparito. Restano 6 oggetti.
  [ ! -e "$q/$core1" ]
  [ "$(ls "$q/objects" | wc -l)" -eq 6 ]
  # i byte contati sono solo quelli caricati: core nuovo + MANIFEST
  bytes2="$(tail -1 "$tmp/home/.config/confsync/history.tsv" | cut -f4)"
  [ "$bytes2" -eq $(( $(stat -c %s "$q/$core2") + $(stat -c %s "$q/MANIFEST.txt") )) ]
  [ "$bytes2" -lt "$bytes1" ]
}

@test "restore --quick: upload interrotto (oggetti nuovi, MANIFEST vecchio) ripristina lo stato precedente" {
  tmp="$(mktemp -d)"; make_quick_fixture "$tmp/home"
  run run_quick_backup "$tmp/home" "$tmp"; [ "$status" -eq 0 ]
  cp -a "$tmp/bucket/quick" "$tmp/stale"
  echo "nuovo" > "$tmp/home/CLAUDE.md"
  run run_quick_backup "$tmp/home" "$tmp"; [ "$status" -eq 0 ]
  # stato dopo un push interrotto: gli oggetti nuovi ci sono, il MANIFEST e' il vecchio
  cp -n "$tmp/bucket/quick/objects/"* "$tmp/stale/objects/"
  mkdir -p "$tmp/new"
  run env HOME="$tmp/new" CONFSYNC_PASSPHRASE=tp CONFSYNC_QUICK_SRC="file://$tmp/stale" \
      bash "$CONFSYNC" restore --quick --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$tmp/new/CLAUDE.md")" = "# globale" ]
}

@test "restore --quick: MANIFEST con nome o oggetto malformato viene rifiutato" {
  tmp="$(mktemp -d)"; make_quick_fixture "$tmp/home"
  run run_quick_backup "$tmp/home" "$tmp"; [ "$status" -eq 0 ]
  q="$tmp/bucket/quick"; good="$(cat "$q/MANIFEST.txt")"
  h64="$(printf 'a%.0s' $(seq 64))"
  mkdir -p "$tmp/new"
  for bad in "core.tar.enc objects/../../etc/passwd $h64" \
             "core.tar.enc objects/$h64/x $h64" \
             "core.tar.enc /objects/$h64 $h64" \
             "core.tar.enc objects/zz$h64 $h64" \
             "../core.tar.enc objects/$h64 $h64" \
             "a/b objects/$h64 $h64" \
             "core.tar.enc objects/$h64 corto"; do
    printf '%s\n' "$bad" > "$q/MANIFEST.txt"
    run env HOME="$tmp/new" CONFSYNC_PASSPHRASE=tp CONFSYNC_QUICK_SRC="file://$q" \
        bash "$CONFSYNC" restore --quick --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"non valid"* ]]
  done
  [ ! -e "$tmp/new/CLAUDE.md" ]
  printf '%s\n' "$good" > "$q/MANIFEST.txt"
}

@test "confsync quick-list stampa la lista completa, plugins inclusi" {
  tmp="$(mktemp -d)"; make_quick_fixture "$tmp/home"
  run env HOME="$tmp/home" bash "$CONFSYNC" quick-list
  [ "$status" -eq 0 ]
  [[ "$output" == *".claude/plugins/marketplaces/m1/p.txt"* ]]
  [[ "$output" == *"CLAUDE.md"* ]]
}

@test "backup --quick: prefisso CONFSYNC_QUICK_PREFIX e lock occupato" {
  tmp="$(mktemp -d)"; make_quick_fixture "$tmp/home"
  mkdir -p "$tmp/bucket" "$tmp/bin"; make_fs_gsutil "$tmp/bin" "$tmp/bucket"
  run env HOME="$tmp/home" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      CONFSYNC_QUICK_PREFIX=altro PATH="$tmp/bin:$PATH" bash "$CONFSYNC" backup --quick
  [ "$status" -eq 0 ]
  [ -f "$tmp/bucket/altro/MANIFEST.txt" ]
  [ ! -e "$tmp/bucket/quick" ]
  # lock tenuto da un altro processo: esce 0 senza caricare
  rm -rf "$tmp/bucket/altro"
  ( flock 9; sleep 8 ) 9>"$tmp/home/.config/confsync/quick.lock" &
  sleep 1
  run env HOME="$tmp/home" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$tmp/bin:$PATH" bash "$CONFSYNC" backup --quick
  [ "$status" -eq 0 ]
  [[ "$output" == *"gia' in corso"* ]]
  [ ! -e "$tmp/bucket/quick/MANIFEST.txt" ]
  wait
}

@test "restore --quick via gcloud: token Bearer + API JSON di GCS (server finto)" {
  command -v python3 >/dev/null || skip "serve python3 per il server finto"
  tmp="$(mktemp -d)"; make_quick_fixture "$tmp/home"
  run run_quick_backup "$tmp/home" "$tmp"; [ "$status" -eq 0 ]
  cat > "$tmp/srv.py" <<'PY'
import http.server, sys, urllib.parse, os
root, portfile = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Authorization") != "Bearer tok123":
            self.send_response(401); self.end_headers(); return
        u = urllib.parse.urlparse(self.path)
        pre = "/storage/v1/b/testbucket/o/"
        if not u.path.startswith(pre) or "alt=media" not in u.query:
            self.send_response(404); self.end_headers(); return
        name = urllib.parse.unquote(u.path[len(pre):])
        f = os.path.join(root, name)
        if not os.path.isfile(f):
            self.send_response(404); self.end_headers(); return
        d = open(f, "rb").read()
        self.send_response(200); self.send_header("Content-Length", str(len(d))); self.end_headers()
        self.wfile.write(d)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(portfile, "w").write(str(s.server_address[1]))
s.serve_forever()
PY
  python3 "$tmp/srv.py" "$tmp/bucket" "$tmp/port" &
  srv=$!
  for i in $(seq 50); do [ -s "$tmp/port" ] && break; sleep 0.1; done
  printf '#!/bin/sh\n[ "$1 $2" = "auth print-access-token" ] && echo tok123\n' > "$tmp/bin/gcloud"
  chmod +x "$tmp/bin/gcloud"
  mkdir -p "$tmp/new"
  run env HOME="$tmp/new" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      CONFSYNC_GCS_URL="http://127.0.0.1:$(cat "$tmp/port")" PATH="$tmp/bin:$PATH" \
      bash "$CONFSYNC" restore --quick --yes
  kill $srv
  [ "$status" -eq 0 ]
  [[ "$output" == *"(gcloud)"* ]]
  [ "$(cat "$tmp/new/CLAUDE.md")" = "# globale" ]
}

@test "install-hooks.sh: idempotente, conserva gli altri hook, --uninstall" {
  command -v jq >/dev/null || skip "serve jq"
  tmp="$(mktemp -d)"; s="$tmp/settings.json"; hooks="$BATS_TEST_DIRNAME/../scripts/install-hooks.sh"
  cat > "$s" <<'JSON'
{"model":"x","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo hi"}]}],
 "SessionEnd":[{"hooks":[{"type":"command","command":"echo bye"}]}]}}
JSON
  run env CLAUDE_SETTINGS="$s" bash "$hooks"; [ "$status" -eq 0 ]
  run env CLAUDE_SETTINGS="$s" bash "$hooks"; [ "$status" -eq 0 ]
  [[ "$output" == *"gia' presente"* ]]
  [ "$(jq '[.hooks.SessionEnd[].hooks[]] | length' "$s")" = 2 ]
  [ "$(jq -r '.hooks.SessionEnd[0].hooks[0].command' "$s")" = "echo bye" ]
  [ "$(jq '[.hooks.SessionEnd[].hooks[] | select(.command | endswith("quick-push.sh"))] | length' "$s")" = 1 ]
  [ "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$s")" = "echo hi" ]
  [ "$(jq -r .model "$s")" = x ]
  [ "$(ls "$tmp" | grep -c bekky-bak)" = 1 ]
  run env CLAUDE_SETTINGS="$s" bash "$hooks" --uninstall; [ "$status" -eq 0 ]
  [ "$(jq '[.hooks.SessionEnd[].hooks[]] | length' "$s")" = 1 ]
  [ "$(jq -r '.hooks.SessionEnd[0].hooks[0].command' "$s")" = "echo bye" ]
}

@test "install-hooks.sh: settings.json senza hooks" {
  command -v jq >/dev/null || skip "serve jq"
  tmp="$(mktemp -d)"; s="$tmp/settings.json"; echo '{"a":1}' > "$s"
  hooks="$BATS_TEST_DIRNAME/../scripts/install-hooks.sh"
  run env CLAUDE_SETTINGS="$s" bash "$hooks"; [ "$status" -eq 0 ]
  [ "$(jq '.hooks.SessionEnd | length' "$s")" = 1 ]
  run env CLAUDE_SETTINGS="$s" bash "$hooks" --uninstall; [ "$status" -eq 0 ]
  [ "$(jq -c . "$s")" = '{"a":1}' ]
}

@test "quick-push.sh ritorna subito e fa partire il backup in background" {
  tmp="$(mktemp -d)"; make_quick_fixture "$tmp/home"
  mkdir -p "$tmp/bucket" "$tmp/bin"; make_fs_gsutil "$tmp/bin" "$tmp/bucket"
  echo tp > "$tmp/home/.config/confsync/passphrase"
  push="$BATS_TEST_DIRNAME/../scripts/quick-push.sh"
  SECONDS=0
  echo '{"hook":"SessionEnd"}' | env HOME="$tmp/home" CONFSYNC_BUCKET=gs://testbucket PATH="$tmp/bin:$PATH" bash "$push"
  [ "$SECONDS" -lt 3 ]
  for i in $(seq 120); do [ -f "$tmp/bucket/quick/MANIFEST.txt" ] && break; sleep 0.5; done
  [ -f "$tmp/bucket/quick/MANIFEST.txt" ]
  grep -q "backup completato" "$tmp/home/.config/confsync/quick-push.log"
}

@test "quick-repos.sh clona le repo mancanti rimappando origin.home" {
  tmp="$(mktemp -d)"; home="$tmp/new"; old="/home/vecchio"
  git init -q --bare "$tmp/remote.git"
  ( cd "$tmp" && git clone -q remote.git w && cd w && git checkout -q -b main \
    && echo a > f && git add f && git -c user.email=a@b -c user.name=a commit -qm i && git push -q origin main )
  mkdir -p "$home/.config/confsync/quick"
  printf '[{"path":"%s/code/x/r1","remote":"%s","branch":"main","bundle":"0"},{"path":"%s/code/x/r2","remote":"","branch":"","bundle":"0"}]' \
    "$old" "$tmp/remote.git" "$old" > "$home/.config/confsync/quick/repos.manifest.json"
  printf '%s' "$old" > "$home/.config/confsync/quick/origin.home"
  run env HOME="$home" bash "$BATS_TEST_DIRNAME/../scripts/quick-repos.sh"
  [ "$status" -eq 0 ]
  [ -f "$home/code/x/r1/f" ]
  [ "$(git -C "$home/code/x/r1" rev-parse --abbrev-ref HEAD)" = main ]
  [ ! -s "$home/.config/confsync/quick-logs/repos-failed.txt" ]
  # seconda esecuzione: niente da fare
  run env HOME="$home" bash "$BATS_TEST_DIRNAME/../scripts/quick-repos.sh"
  [[ "$output" == *"repo da clonare: 0"* ]]
}

@test "quick-repos.sh annota i fallimenti" {
  tmp="$(mktemp -d)"; home="$tmp/h"; mkdir -p "$home/.config/confsync/quick"
  printf '[{"path":"%s/code/bad","remote":"%s/non-esiste.git","branch":"main","bundle":"0"}]' "$home" "$tmp" \
    > "$home/.config/confsync/quick/repos.manifest.json"
  run env HOME="$home" bash "$BATS_TEST_DIRNAME/../scripts/quick-repos.sh"
  [ "$status" -eq 0 ]
  grep -q "code/bad" "$home/.config/confsync/quick-logs/repos-failed.txt"
}
