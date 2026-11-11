# shellcheck shell=bash
# Helper e installer userland condivisi da scripts/quick.sh e quick-tools.sh.
# Chi li sourcia definisce BIN (default ~/.local/bin); fail() esce: chiamare
# i tool_* in una subshell o in un job.
BIN="${BIN:-$HOME/.local/bin}"
SKIP=10   # exit code di tool_*: gia' presente

fail() { echo "FAIL: $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
dl()   { curl -fsSL --retry 3 --retry-delay 2 -o "$2" "$1"; }

ARCH=""
case "$(uname -m)" in
  x86_64|amd64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
esac
need_arch() { [ -n "$ARCH" ] || fail "architettura $(uname -m) non supportata"; }

# unzip, poi python3 -m zipfile, poi bsdtar: sul PC vuoto non c'e' niente di certo
unzip_to() {
  local zip="$1" dest="$2"
  mkdir -p "$dest"
  if   have unzip;   then unzip -oq "$zip" -d "$dest"
  elif have python3; then python3 -m zipfile -e "$zip" "$dest"
  elif have bsdtar;  then bsdtar -xf "$zip" -C "$dest"
  else fail "serve unzip (o python3 o bsdtar) per estrarre $zip: installa 'unzip' e rilancia"
  fi
}

# Tag dell'ultima release da un redirect (niente API: nessun rate limit, niente jq)
latest_tag() {
  local url
  url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "$1")" || return 1
  printf '%s' "${url##*/}"
}

tool_gcloud() {
  have gcloud && return $SKIP
  need_arch
  mkdir -p "$BIN"
  local sdk="$HOME/google-cloud-sdk" tmp f arch=x86_64
  [ "$ARCH" = arm64 ] && arch=arm
  if [ ! -x "$sdk/bin/gcloud" ]; then
    tmp="$(mktemp -d)"
    dl "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-$arch.tar.gz" "$tmp/sdk.tgz" || fail "download gcloud"
    tar -xzf "$tmp/sdk.tgz" -C "$HOME" || fail "estrazione gcloud"
    rm -rf "$tmp"
    "$sdk/install.sh" --quiet --path-update=false --command-completion=false --usage-reporting=false || fail "install.sh gcloud"
  fi
  for f in gcloud gsutil bq; do ln -sfn "$sdk/bin/$f" "$BIN/$f"; done
}

