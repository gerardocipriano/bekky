setup_confsync() {
  CONFSYNC="$BATS_TEST_DIRNAME/../confsync"
  # gh legge il token dal keyring della sessione, non da HOME: senza questo
  # i test impacchetterebbero il token vero
  export CONFSYNC_NO_EXPORTS=1
}

make_fake_gsutil() {
  local dir="$1"
  cat > "$dir/gsutil" <<'EOF'
#!/usr/bin/env bash
# mock: registra le chiamate e simula un bucket su $FAKE_BUCKET_DIR
echo "gsutil $*" >> "$FAKE_BUCKET_DIR/calls.log"
case "$1$2" in
  *-mcp*|*cp*) : ;;
esac
exit 0
EOF
  chmod +x "$dir/gsutil"
}

make_fs_gsutil() {
  local dir="$1" root="$2"
  cat > "$dir/gsutil" <<EOF
#!/usr/bin/env bash
ROOT="$root"
to_fs() {
  case "\$1" in
    gs://*) echo "\$ROOT/\${1#gs://*/}" ;;
    *) echo "\$1" ;;
  esac
}
EOF
  cat >> "$dir/gsutil" <<'FIXEOF'
args=("$@"); [ "${args[0]}" = "-m" ] && args=("${args[@]:1}")
cmd="${args[0]}"
case "$cmd" in
  cp)
    if [ "${args[1]}" = "-r" ]; then
      i=2; last_idx=$((${#args[@]} - 1))
      dst="$(to_fs "${args[$last_idx]}")"; mkdir -p "$dst"
      while [ $i -lt $last_idx ]; do
        src="$(to_fs "${args[$i]}")"
        cp -r $src "$dst"/ 2>/dev/null || true
        i=$((i + 1))
      done
    elif [ "${args[1]}" = "-" ]; then
      dst="$(to_fs "${args[2]}")"; mkdir -p "$(dirname "$dst")"; cat > "$dst"
    else
      src="${args[1]}"; dst="$(to_fs "${args[2]}")"; mkdir -p "$(dirname "$dst")"; cp "$src" "$dst" 2>/dev/null || true
    fi ;;
  cat) cat "$(to_fs "${args[1]}")" 2>/dev/null || true ;;
  ls)
    case "${args[1]}" in
      gs://*/) for e in $(ls "$(to_fs "${args[1]}")" 2>/dev/null); do echo "${args[1]}$e"; done ;;
      *) ls "$(to_fs "${args[1]}")" 2>/dev/null || true ;;
    esac ;;
  rm)
    for u in "${args[@]:1}"; do [ "$u" = -r ] || rm -rf "$(to_fs "$u")"; done ;;
esac
exit 0
FIXEOF
  chmod +x "$dir/gsutil"
}

# HOME di prova per il set quick: config Claude, memory, un transcript,
# credenziali (solo nei secrets), una chiave ssh e il file di stato confsync.
make_quick_fixture() {
  local h="$1"
  mkdir -p "$h/.claude/projects/-home-x/memory" "$h/.claude/file-history" \
           "$h/.claude/skills" "$h/.ssh" "$h/.config/confsync" "$h/.local/bin" \
           "$h/.config/gcloud" "$h/.config/gh"
  echo '{"hooks":{}}'  > "$h/.claude/settings.json"
  echo '{"mcp":1}'     > "$h/.claude.json"
  echo "# globale"      > "$h/CLAUDE.md"
  echo "ricordo"       > "$h/.claude/projects/-home-x/memory/MEMORY.md"
  echo '{"t":1}'       > "$h/.claude/projects/-home-x/sess1.jsonl"
  mkdir -p "$h/.claude/projects/-home-x/sess1"; echo x > "$h/.claude/projects/-home-x/sess1/tool.txt"
  echo "vecchio"       > "$h/.claude/file-history/h1"
  echo '{"tok":"cred-claude"}' > "$h/.claude/.credentials.json"; chmod 600 "$h/.claude/.credentials.json"
  echo "PRIVATE"       > "$h/.ssh/id_test"; chmod 600 "$h/.ssh/id_test"
  echo "locale"        > "$h/.config/confsync/passphrase"
  echo "alias x=y"     > "$h/.zshrc"
  printf '#!/bin/sh\necho ciao\n' > "$h/.local/bin/mio"; chmod +x "$h/.local/bin/mio"
  echo '{"c":"gc"}'    > "$h/.config/gcloud/credentials.db"
  echo "oauth: gh"     > "$h/.config/gh/hosts.yml"
  echo "[core]"        > "$h/.config/gcloud/properties"
  mkdir -p "$h/.claude/plugins/marketplaces/m1"; echo "plugin" > "$h/.claude/plugins/marketplaces/m1/p.txt"
  mkdir -p "$h/.nvm/alias"; echo 22 > "$h/.nvm/alias/default"
}

# backup --quick con gsutil su filesystem. $1 = HOME, $2 = tmp dir (usa $2/bucket e $2/bin)
run_quick_backup() {
  local h="$1" tmp="$2"
  mkdir -p "$tmp/bucket" "$tmp/bin"
  make_fs_gsutil "$tmp/bin" "$tmp/bucket"
  env HOME="$h" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$tmp/bin:$PATH" bash "$CONFSYNC" backup --quick
}
