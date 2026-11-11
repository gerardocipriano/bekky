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
  [ "$(code "http://127.0.0.1:$PORT/../confsync")" = 404 ]
}

@test "scenari: ognuno risponde con il suo quadro" {
  local sc
  for sc in ok reauth stale fresh; do
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
else:
    r = s["restore"]
    assert any(t["status"] == "FAIL" for t in r["tools"]) and len(r["reposFailed"]) == 3
    assert s["history"] == []
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
