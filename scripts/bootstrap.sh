#!/usr/bin/env bash
# Primo avvio su un PC Ubuntu/Debian appena installato. Uso:
#   curl -fsSL https://raw.githubusercontent.com/gerardocipriano/bekky/main/scripts/bootstrap.sh | bash
# Fa solo i passi interattivi (sudo, login gcloud, passphrase); il resto lo fa
# Claude seguendo docs/RESTORE-PLAYBOOK.md.
set -euo pipefail

BEKKY="$HOME/code/misc/bekky"
CONF="$HOME/.config/confsync"
SUDOERS=/etc/sudoers.d/99-bekky-restore

say() { printf '\n\033[1;36m>> %s\033[0m\n' "$*"; }

# Con curl | bash lo stdin è la pipe: i prompt vanno letti dal terminale.
exec </dev/tty

command -v apt-get >/dev/null || { echo "serve Ubuntu/Debian (apt-get)"; exit 1; }

say "sudo (una volta sola)"
sudo -v
# NOPASSWD temporaneo: Claude lancia decine di apt/systemctl in shell non
# interattive. Il playbook lo rimuove come ultimo passo.
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "$SUDOERS" >/dev/null
sudo chmod 440 "$SUDOERS"
sudo visudo -cf "$SUDOERS" >/dev/null || { sudo rm -f "$SUDOERS"; echo "sudoers non valido"; exit 1; }

say "pacchetti base"
sudo apt-get update -qq
sudo apt-get install -y -qq git curl ca-certificates gnupg openssl zstd cron jq zsh apt-transport-https

if ! command -v gcloud >/dev/null; then
  say "google-cloud-cli"
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo gpg --dearmor --yes -o /usr/share/keyrings/cloud.google.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  sudo apt-get update -qq && sudo apt-get install -y -qq google-cloud-cli
fi

if ! command -v claude >/dev/null && [ ! -x "$HOME/.local/bin/claude" ]; then
  say "Claude Code"
  curl -fsSL https://claude.ai/install.sh | bash
fi

say "bekky"
if [ ! -d "$BEKKY/.git" ]; then
  mkdir -p "$(dirname "$BEKKY")"
  git clone -q https://github.com/gerardocipriano/bekky.git "$BEKKY"
fi

mkdir -p "$CONF" && chmod 700 "$CONF"
if [ ! -f "$CONF/config" ]; then
  # HOST_TAG del vecchio PC: il nuovo ha un altro hostname e senza questo
  # restore non trova il backup.
  cat > "$CONF/config" <<'EOF'
export CONFSYNC_BUCKET="gs://confsync-gerardo-cipriano"
export CONFSYNC_PROJECT="formazione-gerardo-cipriano"
export CONFSYNC_ACCOUNT="gerardo.cipriano@dinova.one"
export CONFSYNC_HOST_TAG="INJ-NB-250"
EOF
  chmod 600 "$CONF/config"
fi

if [ ! -s "$CONF/passphrase" ]; then
  say "passphrase bekky (1Password: 'bekky passphrase')"
  read -rsp "Passphrase: " p; echo
  printf '%s' "$p" > "$CONF/passphrase"; chmod 600 "$CONF/passphrase"
fi

say "login gcloud (si apre il browser)"
gcloud auth list --format='value(account)' 2>/dev/null | grep -qx gerardo.cipriano@dinova.one \
  || gcloud auth login gerardo.cipriano@dinova.one
CLOUDSDK_CORE_ACCOUNT=gerardo.cipriano@dinova.one gsutil cat gs://confsync-gerardo-cipriano/INJ-NB-250/latest >/dev/null \
  && echo "backup raggiungibile"

cat <<EOF

Fatto. Ora:
  cd $BEKKY && ~/.local/bin/claude
e scrivi:  siamo sul nuovo pc, prendi il backup e riconfigurami tutto come prima
EOF
