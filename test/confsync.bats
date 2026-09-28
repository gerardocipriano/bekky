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

@test "credenziali gcloud e gh: solo in secrets.tar.enc, mai in dotfiles.tar.enc" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"
  mkdir -p "$fakehome/.config/gcloud" "$fakehome/.config/gh"
  echo "alias x=y" > "$fakehome/.zshrc"
  echo '{"cred":"segreto"}' > "$fakehome/.config/gcloud/credentials.db"
  echo "oauth: segreto"     > "$fakehome/.config/gh/hosts.yml"
  export FAKE_BUCKET_DIR="$tmp/bucket"; mkdir -p "$FAKE_BUCKET_DIR"
  fakebin="$tmp/bin"; mkdir -p "$fakebin"; make_fs_gsutil "$fakebin" "$FAKE_BUCKET_DIR"
  env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" CONFSYNC_WORKDIR_KEEP="$tmp/work" bash "$CONFSYNC" backup
  [ -f "$tmp/work/dotfiles.tar.enc" ]; [ -f "$tmp/work/secrets.tar.enc" ]
  for a in dotfiles secrets; do
    env CONFSYNC_PASSPHRASE=tp bash -c \
      'source "$0" --source-only; decrypt_unpack "$1" "$2"' \
      "$CONFSYNC" "$tmp/work/$a.tar.enc" "$tmp/ext-$a"
  done
  # i dotfiles non devono contenere credenziali...
  [ "$(cat "$tmp/ext-dotfiles/.zshrc")" = "alias x=y" ]
  [ ! -e "$tmp/ext-dotfiles/.config/gcloud/credentials.db" ]
  [ ! -e "$tmp/ext-dotfiles/.config/gh/hosts.yml" ]
  # ...ma l'archivio secrets cifrato sì
  [ "$(cat "$tmp/ext-secrets/.config/gcloud/credentials.db")" = '{"cred":"segreto"}' ]
  [ "$(cat "$tmp/ext-secrets/.config/gh/hosts.yml")" = "oauth: segreto" ]
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

@test "backup registra la distro di origine e restore avverte se non coincide" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"; mkdir -p "$fakehome"
  echo "alias x=y" > "$fakehome/.zshrc"
  export FAKE_BUCKET_DIR="$tmp/bucket"; mkdir -p "$FAKE_BUCKET_DIR"
  fakebin="$tmp/bin"; mkdir -p "$fakebin"; make_fs_gsutil "$fakebin" "$FAKE_BUCKET_DIR"
  srcosr="$tmp/os-release.src"; printf 'ID=arch\n' > "$srcosr"
  env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" CONFSYNC_OS_RELEASE="$srcosr" \
      CONFSYNC_WORKDIR_KEEP="$tmp/work" bash "$CONFSYNC" backup
  [ "$(cat "$tmp/work/packages.distro")" = "arch" ]
  # restore su una distro diversa da quella che ha prodotto il backup
  newhome="$tmp/new"; mkdir -p "$newhome"
  osr="$tmp/os-release"; printf 'ID=ubuntu\nID_LIKE=debian\n' > "$osr"
  run env HOME="$newhome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" CONFSYNC_OS_RELEASE="$osr" \
      bash "$CONFSYNC" restore --yes --packages
  [ "$status" -eq 0 ]
  [[ "$output" == *"ATTENZIONE"* ]]
}

@test "backup registra HOME di origine e restore avverte se cambia" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"; mkdir -p "$fakehome"
  echo "alias x=y" > "$fakehome/.zshrc"
  export FAKE_BUCKET_DIR="$tmp/bucket"; mkdir -p "$FAKE_BUCKET_DIR"
  fakebin="$tmp/bin"; mkdir -p "$fakebin"; make_fs_gsutil "$fakebin" "$FAKE_BUCKET_DIR"
  env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" CONFSYNC_WORKDIR_KEEP="$tmp/work" bash "$CONFSYNC" backup
  [ "$(cat "$tmp/work/origin.home")" = "$fakehome" ]
  newhome="$tmp/new"; mkdir -p "$newhome"
  run env HOME="$newhome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" bash "$CONFSYNC" restore --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"i path assoluti nelle config vanno riscritti"* ]]
  [ "$(cat "$newhome/.config/confsync/origin.home")" = "$fakehome" ]
}

@test "T2: commit/stash non pushati in bundle, file locali di repo routati correttamente" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"
  export FAKE_BUCKET_DIR="$tmp/bucket"; mkdir -p "$FAKE_BUCKET_DIR"
  fakebin="$tmp/bin"; mkdir -p "$fakebin"; make_fs_gsutil "$fakebin" "$FAKE_BUCKET_DIR"
  repo="$fakehome/code/acme/repo"; mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name test
  git init -q --bare "$tmp/origin/repo.git"
  git -C "$repo" remote add origin "$tmp/origin/repo.git"
  printf 'terraform.tfvars\nnode_modules/\n' > "$repo/.gitignore"
  printf 'base\n'    > "$repo/readme.md"
  printf 'tracked\n' > "$repo/tracked.txt"
  git -C "$repo" add . && git -C "$repo" commit -qm init
  git -C "$repo" push -q origin main
  # commit locale non pushato
  printf 'nuovo\n' >> "$repo/readme.md"
  git -C "$repo" add readme.md && git -C "$repo" commit -qm unpushed
  # stash di un cambiamento tracciato
  printf 'mod\n' > "$repo/tracked.txt"
  git -C "$repo" add tracked.txt && git -C "$repo" stash push -qm "stash tracked"
  # file tracciato nuovamente modificato
  printf 'modv2\n' > "$repo/tracked.txt"
  # file ignorati: un .tfvars (segreto) e uno dentro node_modules/ (junk)
  printf 'secret=1\n' > "$repo/terraform.tfvars"
  mkdir -p "$repo/node_modules"; printf 'dep\n' > "$repo/node_modules/dep.js"

  env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" CONFSYNC_WORKDIR_KEEP="$tmp/work" \
      bash "$CONFSYNC" backup

  [ -f "$tmp/work/repo-bundles.tar.enc" ]
  [ -f "$tmp/work/repo-localfiles.tar.enc" ]
  headsha="$(git -C "$repo" rev-parse HEAD)"
  for a in repo-bundles repo-localfiles secrets; do
    env CONFSYNC_PASSPHRASE=tp bash -c \
      'source "$0" --source-only; decrypt_unpack "$1" "$2"' \
      "$CONFSYNC" "$tmp/work/$a.tar.enc" "$tmp/ext-$a"
  done
  # il bundle porta il branch locale (commit non pushato) e lo stash
  run git bundle list-heads "$tmp/ext-repo-bundles/code/acme/repo/repo.bundle"
  [ "$status" -eq 0 ]
  grep -q 'refs/heads/main'    <<<"$output"
  grep -q 'refs/bekky/stash/0' <<<"$output"
  grep -q "$headsha"           <<<"$output"
  # file tracciato modificato -> repo-localfiles
  [ "$(cat "$tmp/ext-repo-localfiles/code/acme/repo/tracked.txt")" = "modv2" ]
  # ignorato segreto -> secrets, ignorato in node_modules -> da nessuna parte
  [ "$(cat "$tmp/ext-secrets/code/acme/repo/terraform.tfvars")" = "secret=1" ]
  [ ! -e "$tmp/ext-repo-localfiles/code/acme/repo/node_modules" ]
  [ ! -e "$tmp/ext-secrets/code/acme/repo/node_modules" ]
  # i ref temporanei dei bundle NON restano nella repo sorgente
  [ -z "$(git -C "$repo" for-each-ref refs/bekky)" ]
}

@test "T2: file fuori da ogni repo (note/script sparsi) finiscono in repo-localfiles" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"
  export FAKE_BUCKET_DIR="$tmp/bucket"; mkdir -p "$FAKE_BUCKET_DIR"
  fakebin="$tmp/bin"; mkdir -p "$fakebin"; make_fs_gsutil "$fakebin" "$FAKE_BUCKET_DIR"
  # senza git: CLAUDE.md in una dir cliente e una cartella di script
  mkdir -p "$fakehome/code/clienteX"
  printf 'contest\n' > "$fakehome/code/clienteX/CLAUDE.md"
  mkdir -p "$fakehome/code/scripts"
  printf 'echo hi\n' > "$fakehome/code/scripts/helper.sh"

  env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" CONFSYNC_WORKDIR_KEEP="$tmp/work" \
      bash "$CONFSYNC" backup

  [ -f "$tmp/work/repo-localfiles.tar.enc" ]
  env CONFSYNC_PASSPHRASE=tp bash -c \
    'source "$0" --source-only; decrypt_unpack "$1" "$2"' \
    "$CONFSYNC" "$tmp/work/repo-localfiles.tar.enc" "$tmp/ext"
  [ "$(cat "$tmp/ext/code/clienteX/CLAUDE.md")" = "contest" ]
  [ "$(cat "$tmp/ext/code/scripts/helper.sh")" = "echo hi" ]
}
