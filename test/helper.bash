setup_confsync() {
  CONFSYNC="$BATS_TEST_DIRNAME/../confsync"
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
  ls)  ls "$(to_fs "${args[1]}")" 2>/dev/null || true ;;
esac
exit 0
FIXEOF
  chmod +x "$dir/gsutil"
}
