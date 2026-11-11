#!/usr/bin/env bats
# Console web: sempre in mock (BEKKY_UI_MOCK), con HOME finta. Mai gcloud o backup reali.

setup() {
  UI_HOME="$(mktemp -d)"
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
  start_ui ok
}

teardown() {
  [ -z "${UI_PID:-}" ] || kill "$UI_PID" 2>/dev/null || true
  rm -rf "$UI_HOME"
}

# start_ui <scenario>: avvia il server e legge il token dall'URL stampato
start_ui() {
  [ -z "${UI_PID:-}" ] || { kill "$UI_PID" 2>/dev/null || true; wait "$UI_PID" 2>/dev/null || true; }
  HOME="$UI_HOME" BEKKY_UI_MOCK="$1" python3 "$BATS_TEST_DIRNAME/../ui/server.py" \
    --port "$PORT" --no-open > "$UI_HOME/out" 2>&1 &
  UI_PID=$!
  local i
  for i in $(seq 50); do grep -q 'http://' "$UI_HOME/out" 2>/dev/null && break; sleep 0.1; done
  TOKEN="$(sed -n 's/.*[?]t=//p' "$UI_HOME/out" | head -1)"
  [ -n "$TOKEN" ]
}

api() { curl -s -H "X-Bekky-Token: $TOKEN" "$@"; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

@test "status: 200 e JSON valido" {
  [ "$(code -H "X-Bekky-Token: $TOKEN" "http://127.0.0.1:$PORT/api/status")" = 200 ]
  api "http://127.0.0.1:$PORT/api/status" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["host"]; assert "checks" in d and "history" in d'
}

@test "senza token 403, token errato 403" {
  [ "$(code "http://127.0.0.1:$PORT/api/status")" = 403 ]
  [ "$(code -H "X-Bekky-Token: sbagliato" "http://127.0.0.1:$PORT/api/status")" = 403 ]
}

@test "Host errato 403 anche con token giusto" {
  [ "$(code -H "Host: evil.example:$PORT" -H "X-Bekky-Token: $TOKEN" "http://127.0.0.1:$PORT/api/status")" = 403 ]
  [ "$(code -H "Host: evil.example" "http://127.0.0.1:$PORT/")" = 403 ]
}

@test "azione sconosciuta 400, log sconosciuto 400" {
  [ "$(code -X POST -H "X-Bekky-Token: $TOKEN" -d '{"name":"rm-rf"}' "http://127.0.0.1:$PORT/api/action")" = 400 ]
  [ "$(code -H "X-Bekky-Token: $TOKEN" "http://127.0.0.1:$PORT/api/log?name=../../etc/passwd")" = 400 ]
}

@test "doppio quick-push: 202 poi 409" {
  [ "$(code -X POST -H "X-Bekky-Token: $TOKEN" -d '{"name":"quick-push"}' "http://127.0.0.1:$PORT/api/action")" = 202 ]
  [ "$(code -X POST -H "X-Bekky-Token: $TOKEN" -d '{"name":"quick-push"}' "http://127.0.0.1:$PORT/api/action")" = 409 ]
  api "http://127.0.0.1:$PORT/api/status" | python3 -c 'import json,sys; assert json.load(sys.stdin)["quick"]["running"]'
}

@test "la pagina e i file statici si servono con Host giusto" {
  [ "$(code "http://127.0.0.1:$PORT/")" = 200 ]
  [ "$(code "http://127.0.0.1:$PORT/app.js")" = 200 ]
  [ "$(code "http://127.0.0.1:$PORT/style.css")" = 200 ]
  [ "$(code "http://127.0.0.1:$PORT/theme.js")" = 200 ]
  [ "$(code "http://127.0.0.1:$PORT/../confsync")" = 404 ]
}

@test "scenari: ognuno risponde con il suo quadro" {
  local sc
  for sc in ok reauth stale fresh setup; do
    start_ui "$sc"
    api "http://127.0.0.1:$PORT/api/status" > "$UI_HOME/s.json"
    api "http://127.0.0.1:$PORT/api/checks" > "$UI_HOME/c.json"
    SC="$sc" python3 - "$UI_HOME" <<'PY'
import json, os, sys
d = sys.argv[1]
s, c, sc = json.load(open(d + "/s.json")), json.load(open(d + "/c.json")), os.environ["SC"]
assert s["mock"] == sc
if sc == "ok":
    assert c["gcloud"]["ok"] and s["checks"]["hook"] and s["quick"]["last"]["result"] != "fail"
elif sc == "reauth":
    assert not c["gcloud"]["ok"] and s["quick"]["last"]["result"] == "fail"
elif sc == "stale":
    assert not s["checks"]["hook"] and s["full"]["last"]["ts"] < s["now"]
elif sc == "fresh":
    r = s["restore"]
    assert any(t["status"] == "FAIL" for t in r["tools"]) and len(r["reposFailed"]) == 3
    assert s["history"] == []
else:
    assert s["configured"] == {"bucket": False, "passphrase": False}
    assert s["bucket"] == "" and s["history"] == []
if sc != "setup":
    assert s["configured"] == {"bucket": True, "passphrase": True}
PY
  done
}

@test "core, backups e log rispondono in mock" {
  api "http://127.0.0.1:$PORT/api/core" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["totalBytes"]>0 and d["entries"][0]["bytes"]>=d["entries"][-1]["bytes"]'
  api "http://127.0.0.1:$PORT/api/backups" | python3 -c 'import json,sys; assert json.load(sys.stdin)["backups"]'
  [ "$(code -H "X-Bekky-Token: $TOKEN" "http://127.0.0.1:$PORT/api/log?name=quick")" = 200 ]
}

@test "il mock non scrive nella HOME" {
  api -X POST -d '{"name":"hook-install"}' "http://127.0.0.1:$PORT/api/action" >/dev/null
  sleep 0.3
  [ ! -e "$UI_HOME/.config" ]
  [ ! -e "$UI_HOME/.claude" ]
}

@test "history_add: riga TSV e tetto a 500 righe" {
  HOME="$UI_HOME" bash -c '. "'"$BATS_TEST_DIRNAME"'/../lib/history.sh"; for i in $(seq 505); do history_add quick dedup 7; done; history_add full fail'
  f="$UI_HOME/.config/confsync/history.tsv"
  [ "$(wc -l < "$f")" = 500 ]
  tail -1 "$f" | grep -qP '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\tfull\tfail\t0$'
}

@test "confsync quick-list stampa i path del core" {
  mkdir -p "$UI_HOME/.claude" "$UI_HOME/.config/confsync"
  echo '{}' > "$UI_HOME/.claude/settings.json"
  run env HOME="$UI_HOME" CONFSYNC_CONFIG=/dev/null "$BATS_TEST_DIRNAME/../confsync" quick-list
  [ "$status" -eq 0 ]
  [[ "$output" == *".claude/settings.json"* ]]
}

post() { curl -s -o "$UI_HOME/body" -w '%{http_code}' -X POST -H "X-Bekky-Token: $TOKEN" -d "$2" "http://127.0.0.1:$PORT$1"; }

# jpost <path> <campo=valore>...: costruisce il JSON con python, cosi' i valori ostili arrivano interi
jpost() {
  local path="$1"; shift
  post "$path" "$(python3 -c 'import json,sys; print(json.dumps(dict(a.split("=",1) for a in sys.argv[1:])))' "$@")"
}

@test "config: GET restituisce i campi e i default, senza passphrase" {
  api "http://127.0.0.1:$PORT/api/config" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["bucket"].startswith("gs://") and d["project"] and d["account"]
assert d["defaults"]["bucket"] == "gs://il-tuo-bucket"
assert d["configPath"] and d["passphrasePath"]
assert not [k for k in d if "passphrase" in k.lower() and k != "passphrasePath"]'
  [ "$(code "http://127.0.0.1:$PORT/api/config")" = 403 ]
}

@test "config: POST in mock aggiorna lo stato in memoria e non scrive su disco" {
  [ "$(jpost /api/config bucket=gs://nuovo-spazio project=progetto-nuovo account=a@b.it)" = 200 ]
  api "http://127.0.0.1:$PORT/api/config" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["bucket"]=="gs://nuovo-spazio" and d["account"]=="a@b.it"'
  api "http://127.0.0.1:$PORT/api/status" | python3 -c 'import json,sys; assert json.load(sys.stdin)["bucket"]=="gs://nuovo-spazio"'
  [ ! -e "$UI_HOME/.config" ]
}

@test "config: valori malformati o con caratteri di shell sono rifiutati" {
  local bad
  for bad in 'gs://MAIUSCOLO' 'gs://a' 'nogs://spazio-ok' 'gs://spazio"; touch x; "' 'gs://spazio$(id)' 'gs://spazio`id`' $'gs://spazio-ok\n' 'gs://sp ace' $'gs://ok-ok\nexport X=1'; do
    [ "$(jpost /api/config "bucket=$bad" project= account=)" = 400 ]
  done
  [ "$(jpost /api/config bucket=gs://ok-ok 'project=p"x' account=)" = 400 ]
  [ "$(jpost /api/config bucket=gs://ok-ok project= 'account=a$b@c.it')" = 400 ]
  [ "$(jpost /api/config bucket=gs://ok-ok 'project=proj`id`' account=)" = 400 ]
  [ "$(jpost /api/config bucket=gs://ok-ok project= $'account=a@b.it\nexport X=1')" = 400 ]
  [ "$(post /api/config '[1]')" = 400 ]
  api "http://127.0.0.1:$PORT/api/config" | python3 -c 'import json,sys; assert json.load(sys.stdin)["bucket"]=="gs://bekky-esempio"'
}

@test "config/verify: ok, bucket inesistente, input non valido" {
  [ "$(jpost /api/config/verify bucket=gs://bekky-esempio account=a@b.it)" = 200 ]
  python3 -c 'import json; assert json.load(open("'"$UI_HOME"'/body"))["ok"]'
  [ "$(jpost /api/config/verify bucket=gs://spazio-nonesiste account=)" = 200 ]
  python3 -c 'import json; d=json.load(open("'"$UI_HOME"'/body")); assert not d["ok"] and d["error"]'
  [ "$(jpost /api/config/verify 'bucket=gs://x$(id)' account=)" = 400 ]
}

# Scrittura reale del file di config su una HOME finta, senza avviare il server
@test "write_config: cambia solo le tre righe, conserva il resto, 600, config.bak" {
  mkdir -p "$UI_HOME/.config/confsync"
  local f="$UI_HOME/.config/confsync/config"
  printf '%s\n' '# commento mio' 'export CONFSYNC_BUCKET="gs://vecchio-spazio"  # nota' \
    'export CONFSYNC_ACCOUNT="vecchio@x.it"' 'export CONFSYNC_OP_REF="op://Personal/bekky passphrase/password"' \
    'export CONFSYNC_HOST_TAG="mio-pc"' > "$f"
  chmod 644 "$f"
  HOME="$UI_HOME" python3 - "$BATS_TEST_DIRNAME/../ui" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import server
server.write_config({"bucket": "gs://nuovo-spazio", "project": "progetto-nuovo", "account": "nuovo@x.it"})
PY
  grep -qx '# commento mio' "$f"
  grep -qx 'export CONFSYNC_BUCKET="gs://nuovo-spazio"  # nota' "$f"
  grep -qx 'export CONFSYNC_ACCOUNT="nuovo@x.it"' "$f"
  grep -qx 'export CONFSYNC_PROJECT="progetto-nuovo"' "$f"
  grep -qx 'export CONFSYNC_OP_REF="op://Personal/bekky passphrase/password"' "$f"
  grep -qx 'export CONFSYNC_HOST_TAG="mio-pc"' "$f"
  [ "$(stat -c %a "$f")" = 600 ]
  grep -q 'vecchio-spazio' "$f.bak"
  [ "$(stat -c %a "$f.bak")" = 600 ]
  [ "$(bash -c '. "$1"; echo "$CONFSYNC_BUCKET $CONFSYNC_PROJECT"' _ "$f")" = "gs://nuovo-spazio progetto-nuovo" ]
}

@test "write_config: crea il file 600 se manca" {
  HOME="$UI_HOME" python3 - "$BATS_TEST_DIRNAME/../ui" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import server
server.write_config({"bucket": "gs://primo-spazio", "project": "", "account": ""})
PY
  local f="$UI_HOME/.config/confsync/config"
  [ "$(stat -c %a "$f")" = 600 ]
  [ "$(bash -c '. "$1"; echo "$CONFSYNC_BUCKET"' _ "$f")" = "gs://primo-spazio" ]
}

@test "setup: niente bucket e niente passphrase" {
  start_ui setup
  api "http://127.0.0.1:$PORT/api/config" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["bucket"]=="" and d["opRef"]==""'
  api "http://127.0.0.1:$PORT/api/status" | python3 -c 'import json,sys; s=json.load(sys.stdin); assert s["configured"]["bucket"] is False and s["checks"]["passphrase"] is False'
  [ "$(jpost /api/config bucket=gs://primo-spazio project= account=)" = 200 ]
  api "http://127.0.0.1:$PORT/api/status" | python3 -c 'import json,sys; s=json.load(sys.stdin); assert s["configured"]["bucket"] is True and s["configured"]["passphrase"] is False'
}

@test "buckets: elenco finto, creazione finta, nome gia' usato e nome non valido" {
  api "http://127.0.0.1:$PORT/api/buckets" | python3 -c 'import json,sys; b=json.load(sys.stdin)["buckets"]; assert len(b)==3 and "bekky-esempio" in b'
  [ "$(jpost /api/buckets name=mio-nuovo-spazio)" = 201 ]
  api "http://127.0.0.1:$PORT/api/buckets" | python3 -c 'import json,sys; assert "mio-nuovo-spazio" in json.load(sys.stdin)["buckets"]'
  [ "$(jpost /api/buckets name=nome-gia-usato)" = 409 ]
  [ "$(jpost /api/buckets name=archivio-famiglia)" = 409 ]
  local bad
  for bad in 'Maiuscolo' 'a' 'con spazio' 'x$(id)' 'x`id`' 'x";y' 'goog-nome' '-inizio' 'fine-' $'ok-ok\n'; do
    [ "$(jpost /api/buckets "name=$bad")" = 400 ]
  done
  [ "$(post /api/buckets '{"name":5}')" = 400 ]
  [ "$(code -X POST -d '{"name":"abc-def"}' "http://127.0.0.1:$PORT/api/buckets")" = 403 ]
}
