load helper

setup() { setup_confsync; }

@test "detect_distro riconosce arch da os-release" {
  run env CONFSYNC_OS_RELEASE=<(printf 'ID=arch\n') bash -c \
    'source "$0" --source-only; detect_distro' "$CONFSYNC"
  [ "$status" -eq 0 ]
  [ "$output" = "arch" ]
}

@test "require_deps fallisce con messaggio se manca openssl" {
  run env PATH="/usr/bin:/bin" CONFSYNC_FAKE_MISSING=openssl bash -c \
    'source "$0" --source-only; require_deps' "$CONFSYNC"
  [ "$status" -ne 0 ]
  [[ "$output" == *"openssl"* ]]
}

@test "pack_encrypt + decrypt_unpack round-trip preserva i file" {
  tmp="$(mktemp -d)"; src="$tmp/src"; dest="$tmp/dest"
  mkdir -p "$src/sub"; echo "ciao" > "$src/sub/file.txt"
  run env CONFSYNC_PASSPHRASE=testpass bash -c \
    'source "$0" --source-only; pack_encrypt "$1" "$2" sub' \
    "$CONFSYNC" "$src" "$tmp/out.tar.enc"
  [ "$status" -eq 0 ]; [ -f "$tmp/out.tar.enc" ]
  run grep -aq "ciao" "$tmp/out.tar.enc"; [ "$status" -ne 0 ]
  mkdir -p "$dest"
  run env CONFSYNC_PASSPHRASE=testpass bash -c \
    'source "$0" --source-only; decrypt_unpack "$1" "$2"' \
    "$CONFSYNC" "$tmp/out.tar.enc" "$dest"
  [ "$status" -eq 0 ]
  [ "$(cat "$dest/sub/file.txt")" = "ciao" ]
}

@test "decrypt con passphrase errata fallisce" {
  tmp="$(mktemp -d)"; mkdir -p "$tmp/src"; echo x > "$tmp/src/f"
  env CONFSYNC_PASSPHRASE=right bash -c \
    'source "$0" --source-only; pack_encrypt "$1" "$2" f' "$CONFSYNC" "$tmp/src" "$tmp/o.tar.enc"
  run env CONFSYNC_PASSPHRASE=wrong bash -c \
    'source "$0" --source-only; decrypt_unpack "$1" "$2"' "$CONFSYNC" "$tmp/o.tar.enc" "$tmp/d"
  [ "$status" -ne 0 ]
}

@test "collect_repos produce JSON con path e remote" {
  tmp="$(mktemp -d)"; r="$tmp/code/clientX/repo"
  mkdir -p "$r"; ( cd "$r"; git init -q; git remote add origin https://example.com/x.git )
  run bash -c 'source "$0" --source-only; REPO_SCAN_DIRS=("$1/code"); collect_repos "$2"' \
    "$CONFSYNC" "$tmp" "$tmp/repos.json"
  [ "$status" -eq 0 ]
  run grep -q "example.com/x.git" "$tmp/repos.json"; [ "$status" -eq 0 ]
  run grep -q "$r" "$tmp/repos.json"; [ "$status" -eq 0 ]
}

@test "is_secret_path riconosce .env e *.key" {
  run bash -c 'source "$0" --source-only; is_secret_path ".env"' "$CONFSYNC"; [ "$status" -eq 0 ]
  run bash -c 'source "$0" --source-only; is_secret_path "id_rsa.key"' "$CONFSYNC"; [ "$status" -eq 0 ]
  run bash -c 'source "$0" --source-only; is_secret_path "README.md"' "$CONFSYNC"; [ "$status" -ne 0 ]
}

@test "cmd_backup genera tutti gli artefatti e chiama upload" {
  tmp="$(mktemp -d)"; export FAKE_BUCKET_DIR="$tmp/bucket"; mkdir -p "$FAKE_BUCKET_DIR"
  fakebin="$tmp/bin"; mkdir -p "$fakebin"; make_fake_gsutil "$fakebin"
  fakehome="$tmp/home"; mkdir -p "$fakehome/.ssh" "$fakehome/code/clientX/repo"
  echo "alias x=y" > "$fakehome/.zshrc"
  echo "PRIVATE"   > "$fakehome/.ssh/id_rsa"
  ( cd "$fakehome/code/clientX/repo"; git init -q; echo "ENV=1" > .env; echo "# ctx" > CLAUDE.md )
  run env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" CONFSYNC_WORKDIR_KEEP="$tmp/work" \
      bash "$CONFSYNC" backup
  [ "$status" -eq 0 ]
  [ -f "$tmp/work/dotfiles.tar.enc" ]
  [ -f "$tmp/work/secrets.tar.enc" ]
  [ -f "$tmp/work/repos.manifest.json" ]
  [ -f "$tmp/work/MANIFEST.txt" ]
  run grep -q "gsutil" "$FAKE_BUCKET_DIR/calls.log"; [ "$status" -eq 0 ]
}

@test "restore dotfiles ripristina i file in HOME" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"; mkdir -p "$fakehome"
  echo "alias x=y" > "$fakehome/.zshrc"
  export FAKE_BUCKET_DIR="$tmp/bucket"; mkdir -p "$FAKE_BUCKET_DIR"
  fakebin="$tmp/bin"; mkdir -p "$fakebin"; make_fs_gsutil "$fakebin" "$FAKE_BUCKET_DIR"
  env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket PATH="$fakebin:$PATH" bash "$CONFSYNC" backup
  newhome="$tmp/new"; mkdir -p "$newhome"
  run env HOME="$newhome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket PATH="$fakebin:$PATH" \
      bash "$CONFSYNC" restore --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$newhome/.zshrc")" = "alias x=y" ]
}
