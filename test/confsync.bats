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

# /etc finto: l'inventario non deve mai guardare il sistema vero
setup_fake_etc() {
  local root="$1"
  mkdir -p "$root/etc/systemd/system" "$root/etc/sudoers.d"
  printf 'ID=fakelinux\n' > "$root/etc/os-release"
  printf '127.0.0.1 localhost\n' > "$root/etc/hosts"
  printf '[Service]\nExecStart=/x\n' > "$root/etc/systemd/system/mia.service"
  printf 'Defaults\ttimestamp_timeout=30\n' > "$root/etc/sudoers.d/mio"
  # symlink: mai copiato, non e' un file
  ln -s /etc/hosts "$root/etc/systemd/system/link.service"
}

@test "T3: inventario col /etc finto dentro inventory.tar.enc, ripristinato sempre" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"; mkdir -p "$fakehome"
  echo "alias x=y" > "$fakehome/.zshrc"
  export FAKE_BUCKET_DIR="$tmp/bucket"; mkdir -p "$FAKE_BUCKET_DIR"
  fakebin="$tmp/bin"; mkdir -p "$fakebin"; make_fs_gsutil "$fakebin" "$FAKE_BUCKET_DIR"
  setup_fake_etc "$tmp/etcroot"

  # PATH ridotto: l'inventario non deve dipendere dai tool della macchina
  env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:/usr/bin:/bin" CONFSYNC_ETC_ROOT="$tmp/etcroot" \
      CONFSYNC_WORKDIR_KEEP="$tmp/work" bash "$CONFSYNC" backup

  [ -f "$tmp/work/inventory.tar.enc" ]
  run grep -q "inventory.tar.enc" "$tmp/work/MANIFEST.txt"; [ "$status" -eq 0 ]
  env CONFSYNC_PASSPHRASE=tp bash -c \
    'source "$0" --source-only; decrypt_unpack "$1" "$2"' \
    "$CONFSYNC" "$tmp/work/inventory.tar.enc" "$tmp/ext-inv"

  # /etc finto, path mantenuto (/etc/hosts -> system/etc/etc/hosts)
  [ "$(cat "$tmp/ext-inv/system/etc/etc/hosts")" = "127.0.0.1 localhost" ]
  [ -f "$tmp/ext-inv/system/etc/etc/systemd/system/mia.service" ]
  [ -f "$tmp/ext-inv/system/etc/etc/sudoers.d/mio" ]
  # i symlink non vengono copiati
  [ ! -e "$tmp/ext-inv/system/etc/etc/systemd/system/link.service" ]
  # il resto dell'inventario e' documentato
  [ -f "$tmp/ext-inv/README.txt" ]
  run grep -q "system/etc/etc/hosts" "$tmp/ext-inv/README.txt"; [ "$status" -eq 0 ]
  [ "$(cat "$tmp/ext-inv/system/os-release")" = "ID=fakelinux" ]
  # la shell di login arriva dal campo giusto di passwd
  [ -n "$(cat "$tmp/ext-inv/system/shell.txt")" ]

  # restore --yes: l'inventario esce senza flag, in ~/.config/confsync/inventory
  newhome="$tmp/new"; mkdir -p "$newhome/.config/confsync/inventory"
  printf 'vecchio\n' > "$newhome/.config/confsync/inventory/vecchio.txt"
  run env HOME="$newhome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:/usr/bin:/bin" bash "$CONFSYNC" restore --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"inventario"* ]]
  [ -f "$newhome/.config/confsync/inventory/README.txt" ]
  [ "$(cat "$newhome/.config/confsync/inventory/system/etc/etc/hosts")" = "127.0.0.1 localhost" ]
  # il contenuto precedente e' sostituito, non accodato
  [ ! -e "$newhome/.config/confsync/inventory/vecchio.txt" ]
}

@test "T3: restore --repos estrae i bundle dove serve a ripristinare le repo" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"
  export FAKE_BUCKET_DIR="$tmp/bucket"; mkdir -p "$FAKE_BUCKET_DIR"
  fakebin="$tmp/bin"; mkdir -p "$fakebin"; make_fs_gsutil "$fakebin" "$FAKE_BUCKET_DIR"
  # repo senza remote: tutto da mettere nel bundle
  repo="$fakehome/code/acme/repo"; mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name test
  printf 'x\n' > "$repo/f.txt"
  git -C "$repo" add f.txt && git -C "$repo" commit -qm init
  headsha="$(git -C "$repo" rev-parse HEAD)"

  env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" bash "$CONFSYNC" backup

  newhome="$tmp/new"; mkdir -p "$newhome"
  run env HOME="$newhome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" bash "$CONFSYNC" restore --yes --repos
  [ "$status" -eq 0 ]
  local b="$newhome/.config/confsync/bundles/code/acme/repo/repo.bundle"
  [ -f "$b" ]
  run git bundle list-heads "$b"
  [ "$status" -eq 0 ]
  grep -q "$headsha" <<<"$output"
}

@test "T3: in /etc nell'inventario ci sono solo i file non posseduti da un pacchetto" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"; mkdir -p "$fakehome"
  etcroot="$tmp/etcroot"; mkdir -p "$etcroot/etc/sudoers.d"
  printf 'ID=debian\n' > "$etcroot/etc/os-release"
  printf 'del pacchetto\n' > "$etcroot/etc/sudoers.d/dpkg.conf"
  printf 'mio\n'          > "$etcroot/etc/sudoers.d/mio.conf"
  # dpkg finto: dice di possedere solo dpkg.conf
  fakebin="$tmp/bin"; mkdir -p "$fakebin"
  cat > "$fakebin/dpkg" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-S" ] && case "$2" in */sudoers.d/dpkg.conf) exit 0 ;; esac
exit 1
EOF
  chmod +x "$fakebin/dpkg"

  run env HOME="$fakehome" CONFSYNC_ETC_ROOT="$etcroot" PATH="$fakebin:/usr/bin:/bin" \
      bash -c 'source "$0" --source-only; collect_inventory "$1"' "$CONFSYNC" "$tmp/inv"
  [ "$status" -eq 0 ]
  [ -f "$tmp/inv/system/etc/etc/sudoers.d/mio.conf" ]
  [ ! -e "$tmp/inv/system/etc/etc/sudoers.d/dpkg.conf" ]
  # su una distro non riconosciuta la ownership non e' verificabile: copia tutto
  run env HOME="$fakehome" CONFSYNC_ETC_ROOT="$etcroot" CONFSYNC_OS_RELEASE=/dev/null \
      PATH="$fakebin:/usr/bin:/bin" \
      bash -c 'source "$0" --source-only; collect_inventory "$1"' "$CONFSYNC" "$tmp/inv2"
  [ "$status" -eq 0 ]
  [ -f "$tmp/inv2/system/etc/etc/sudoers.d/mio.conf" ]
  [ -f "$tmp/inv2/system/etc/etc/sudoers.d/dpkg.conf" ]
}

@test "T3: output dell'inventario deterministico (dedup) e ordinato" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"; mkdir -p "$fakehome/.nvm/versions/node"
  setup_fake_etc "$tmp/etcroot"
  for d in "$fakehome/.nvm/versions/node/v20" "$fakehome/.nvm/versions/node/v22"; do mkdir -p "$d"; done
  mkdir -p "$fakehome/go/bin"; printf 'k9s\n' > "$fakehome/go/bin/k9s"
  collect_twice() {
    env HOME="$fakehome" CONFSYNC_ETC_ROOT="$tmp/etcroot" PATH="/usr/bin:/bin" \
        bash -c 'source "$0" --source-only; collect_inventory "$1"' "$CONFSYNC" "$1"
  }
  collect_twice "$tmp/inv1"
  collect_twice "$tmp/inv2"
  # stesso contenuto, stesso sha: altrimenti il dedup scarta i backup con modifiche vere
  run bash -c 'cd "$1" && find . -type f | sort | xargs sha256sum' _ "$tmp/inv1"
  sha1="$output"
  run bash -c 'cd "$1" && find . -type f | sort | xargs sha256sum' _ "$tmp/inv2"
  [ "$output" = "$sha1" ]
  [ -f "$tmp/inv1/dev/nvm-versions.txt" ]
  # le versioni nvm sono ordinate, non nell'ordine di ls
  [ "$(cat "$tmp/inv1/dev/nvm-versions.txt")" = "$(printf 'v20\nv22')" ]
}

# Repo di prova con remote bare locale, commit non pushato, stash e un file
# tracciato modificato: il caso completo del T4.
setup_repo_sporca() {
  local home="$1" origin="$2"
  local repo="$home/code/acme/repo"; mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name test
  git init -q --bare "$origin/repo.git"
  git -C "$repo" remote add origin "$origin/repo.git"
  printf 'base\n'    > "$repo/readme.md"
  printf 'tracked\n' > "$repo/tracked.txt"
  git -C "$repo" add readme.md tracked.txt
  git -C "$repo" commit -qm init
  git -C "$repo" push -q origin main
  # commit locale non pushato
  printf 'nuovo\n' >> "$repo/readme.md"
  git -C "$repo" add readme.md && git -C "$repo" commit -qm unpushed
  # branch con slash mai pushato
  git -C "$repo" checkout -qb feat/x
  printf 'feat\n' > "$repo/feat.txt"
  git -C "$repo" add feat.txt && git -C "$repo" commit -qm feat
  git -C "$repo" checkout -q main
  # due stash in successione: al restore l'ordine deve restare lo stesso
  printf 'traccia1\n' > "$repo/tracked.txt"
  git -C "$repo" add tracked.txt && git -C "$repo" stash push -qm "stash vecchio"
  printf 'traccia2\n' > "$repo/altro.txt"
  git -C "$repo" add altro.txt && git -C "$repo" stash push -qm "stash recente"
  # file tracciato modificato di nuovo: torna da repo-localfiles
  printf 'dal-backup\n' > "$repo/tracked.txt"
  # file fuori da ogni repo
  printf 'contest\n' > "$home/code/acme/CLAUDE.md"
}

@test "T4: restore --repos porta indietro commit non pushati, stash e file locali" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"
  export FAKE_BUCKET_DIR="$tmp/bucket"; mkdir -p "$FAKE_BUCKET_DIR"
  fakebin="$tmp/bin"; mkdir -p "$fakebin"; make_fs_gsutil "$fakebin" "$FAKE_BUCKET_DIR"
  setup_repo_sporca "$fakehome" "$tmp/origin"
  repo="$fakehome/code/acme/repo"
  headsha="$(git -C "$repo" rev-parse HEAD)"
  stashesha0="$(git -C "$repo" rev-parse 'stash@{0}')"
  stashesha1="$(git -C "$repo" rev-parse 'stash@{1}')"
  featsha="$(git -C "$repo" rev-parse feat/x)"

  env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" bash "$CONFSYNC" backup

  newhome="$tmp/new"; mkdir -p "$newhome"
  run env HOME="$newhome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" bash "$CONFSYNC" restore --yes --repos
  [ "$status" -eq 0 ]

  newrepo="$newhome/code/acme/repo"
  [ -d "$newrepo/.git" ]
  # il commit non pushato e' sul branch, non solo nel remote
  [ "$(git -C "$newrepo" symbolic-ref --short HEAD)" = "main" ]
  [ "$(git -C "$newrepo" rev-parse HEAD)" = "$headsha" ]
  [ "$(cat "$newrepo/readme.md")" = "base
nuovo" ]
  # lo stash torna indietro, con lo stesso ordine (stash@{0} era il piu' recente)
  [ -n "$(git -C "$newrepo" stash list)" ]
  [ "$(git -C "$newrepo" rev-parse 'stash@{0}')" = "$stashesha0" ]
  [ "$(git -C "$newrepo" rev-parse 'stash@{1}')" = "$stashesha1" ]
  # i file locali sovrascrivono i tracciati modificati col contenuto del backup
  [ "$(cat "$newrepo/tracked.txt")" = "dal-backup" ]
  [ "$(cat "$newhome/code/acme/CLAUDE.md")" = "contest" ]
  [ "$(git -C "$newrepo" rev-parse feat/x)" = "$featsha" ]
  # nessun ref temporaneo resta nella repo ripristinata
  [ -z "$(git -C "$newrepo" for-each-ref refs/bekky-restore)" ]
  # un secondo restore non duplica gli stash
  run env HOME="$newhome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" bash "$CONFSYNC" restore --yes --repos
  [ "$status" -eq 0 ]
  [ "$(git -C "$newrepo" stash list | wc -l)" -eq 2 ]
  [ "$(cat "$newrepo/tracked.txt")" = "dal-backup" ]
}

@test "T4: repo senza remote ripristinata dal bundle, senza origin pendente" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"
  export FAKE_BUCKET_DIR="$tmp/bucket"; mkdir -p "$FAKE_BUCKET_DIR"
  fakebin="$tmp/bin"; mkdir -p "$fakebin"; make_fs_gsutil "$fakebin" "$FAKE_BUCKET_DIR"
  # nessun remote: il bundle e' l'unica copia
  repo="$fakehome/code/solo/repo"; mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name test
  printf 'uno\n' > "$repo/f.txt"; git -C "$repo" add f.txt; git -C "$repo" commit -qm primo
  printf 'due\n' > "$repo/g.txt"; git -C "$repo" add g.txt; git -C "$repo" commit -qm secondo
  printf 'stash\n' > "$repo/f.txt"
  git -C "$repo" stash push -qm "stash locale"
  headsha="$(git -C "$repo" rev-parse HEAD)"
  stashsha="$(git -C "$repo" rev-parse 'stash@{0}')"

  env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" bash "$CONFSYNC" backup

  newhome="$tmp/new"; mkdir -p "$newhome"
  run env HOME="$newhome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" bash "$CONFSYNC" restore --yes --repos
  [ "$status" -eq 0 ]
  newrepo="$newhome/code/solo/repo"
  [ -d "$newrepo/.git" ]
  [ "$(git -C "$newrepo" rev-parse HEAD)" = "$headsha" ]
  [ "$(git -C "$newrepo" rev-parse 'stash@{0}')" = "$stashsha" ]
  # il remote origin punterebbe al bundle, che il restore successivo rimpiazza
  [ -z "$(git -C "$newrepo" remote)" ]
  [ -z "$(git -C "$newrepo" for-each-ref refs/bekky-restore)" ]
}

@test "T4: restore --repos su repo gia' presente non riclona e non perde il branch locale" {
  tmp="$(mktemp -d)"; fakehome="$tmp/home"
  export FAKE_BUCKET_DIR="$tmp/bucket"; mkdir -p "$FAKE_BUCKET_DIR"
  fakebin="$tmp/bin"; mkdir -p "$fakebin"; make_fs_gsutil "$fakebin" "$FAKE_BUCKET_DIR"
  setup_repo_sporca "$fakehome" "$tmp/origin"
  repo="$fakehome/code/acme/repo"
  headsha="$(git -C "$repo" rev-parse HEAD)"
  stashesha0="$(git -C "$repo" rev-parse 'stash@{0}')"

  env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" bash "$CONFSYNC" backup

  # dopo il backup il branch e' stato resettato e rilanciato altrove: il
  # bundle non puo' piu' essere applicato con un fast-forward
  git -C "$repo" checkout -q main
  git -C "$repo" reset --hard -q origin/main
  printf 'altra-strada\n' > "$repo/readme.md"
  git -C "$repo" add readme.md && git -C "$repo" commit -qm "reset e ricominciato"
  localsha="$(git -C "$repo" rev-parse HEAD)"

  # backup e restore sulla stessa HOME: la repo c'e' gia', non si riclona
  run env HOME="$fakehome" CONFSYNC_PASSPHRASE=tp CONFSYNC_BUCKET=gs://testbucket \
      PATH="$fakebin:$PATH" bash "$CONFSYNC" restore --yes --repos
  [ "$status" -eq 0 ]
  [[ "$output" == *"divergente"* ]]
  [ -n "$(git -C "$repo" remote get-url origin)" ]
  [ "$(git -C "$repo" rev-parse HEAD)" = "$localsha" ]
  # il branch locale vince, il bundle resta su bekky/main
  [ "$(git -C "$repo" rev-parse refs/heads/bekky/main)" = "$headsha" ]
  # gli stash identici non si duplicano
  [ "$(git -C "$repo" stash list | wc -l)" -eq 2 ]
  [ "$(git -C "$repo" rev-parse 'stash@{0}')" = "$stashesha0" ]
  # i file locali tornano col contenuto del backup
  [ "$(cat "$repo/tracked.txt")" = "dal-backup" ]
  [ -z "$(git -C "$repo" for-each-ref refs/bekky-restore)" ]
}

