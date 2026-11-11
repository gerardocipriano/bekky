#!/usr/bin/env bash
# Installa in userland (~/.local/bin, niente sudo) i tool di QUICK_TOOLS, in
# parallelo e idempotente. Un log per tool e lo stato in
# ~/.config/confsync/quick-logs/tools-status.txt (ok / skip / FAIL).
#   scripts/quick-tools.sh [tool...]     senza argomenti: tutti
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/manifest.sh"

CONF="$HOME/.config/confsync"
LOGS="$CONF/quick-logs"
STATUS="$LOGS/tools-status.txt"
BIN="$HOME/.local/bin"
ORIG_PATH="$PATH"
export PATH="$BIN:$HOME/google-cloud-sdk/bin:$PATH"
mkdir -p "$LOGS" "$BIN"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/tools.sh"

# --- node: nvm + versione del PC di origine + npm globali --------------------
tool_node() {
  local did=0 nvm="${NVM_DIR:-$HOME/.nvm}" inv="$CONF/inventory-quick/dev" ver="" settings="$HOME/.claude/settings.json"
  if [ -s "$inv/nvm-default.txt" ]; then ver="$(head -1 "$inv/nvm-default.txt" | tr -d '[:space:]')"; fi
  if [ -z "$ver" ] && [ -f "$settings" ]; then
    ver="$(grep -o 'nvm/versions/node/v[0-9][0-9.]*' "$settings" | head -1 | sed 's#.*/##')"
  fi
  if [ ! -s "$nvm/nvm.sh" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE=/dev/null NVM_DIR="$nvm" bash || fail "install nvm"
    did=1
  fi
  # nvm.sh non regge set -u
  set +u
  # shellcheck disable=SC1091
  . "$nvm/nvm.sh"
  local target
  case "$ver" in
    ""|"lts/*") target="lts/*" ;;
    stable)     target="node" ;;
    *)          target="$ver" ;;
  esac
  if [ "$(nvm version "$target" 2>/dev/null)" = "N/A" ]; then
    if [ "$target" = "lts/*" ]; then nvm install --lts || fail "nvm install --lts"
    else nvm install "$target" || fail "nvm install $target"; fi
    did=1
  fi
  nvm alias default "$target" >/dev/null || fail "nvm alias default"
  local node; node="$(nvm which default)" || fail "nvm which default"
  ln -sfn "$node" "$BIN/node"
  # Gli hook di settings.json citano la versione esatta del PC di origine
  # (.nvm/versions/node/vX.Y.Z/bin/tokenjuice): se qui e' uscita un'altra patch,
  # il vecchio path punta alla versione installata.
  local vdir want; vdir="$(dirname "$(dirname "$node")")"
  if [ -f "$settings" ]; then
    while read -r want; do
      [ -e "$nvm/versions/node/$want" ] || ln -sfn "$vdir" "$nvm/versions/node/$want"
    done < <(grep -o 'nvm/versions/node/v[0-9][0-9.]*' "$settings" | sed 's#.*/##' | sort -u)
  fi

  # npm globali del PC di origine: salta npm/corepack e i pacchetti linkati
  local list="$inv/npm-global.txt" pkgs=() name rest installed
  if [ -s "$list" ]; then
    installed="$(npm ls -g --depth=0 --parseable 2>/dev/null | sed -n 's#.*/node_modules/##p')"
    while read -r name rest; do
      [ -n "$name" ] || continue
      case "$name" in npm|corepack) continue ;; esac
      case "$name $rest" in *"->"*|*file:*|*linked*) continue ;; esac
      grep -qxF "$name" <<<"$installed" || pkgs+=("$name")
    done < "$list"
    if [ ${#pkgs[@]} -gt 0 ]; then
      echo "npm install -g ${pkgs[*]}"
      if ! npm install -g "${pkgs[@]}"; then
        local p bad=0
        for p in "${pkgs[@]}"; do npm install -g "$p" || { echo "FAIL pacchetto: $p"; bad=1; }; done
        [ "$bad" -eq 0 ] || fail "alcuni pacchetti npm non installati"
      fi
      did=1
    fi
  fi
  [ "$did" -eq 1 ] || return "$SKIP"
}

tool_rtk() {
  have rtk && return "$SKIP"
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | bash || fail "install rtk"
  have rtk || fail "rtk non e' nel PATH dopo l'installazione"
}

tool_uv() {
  have uv && return "$SKIP"
  curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh || fail "install uv"
}

tool_opencode() {
  have opencode && return "$SKIP"
  [ -x "$HOME/.opencode/bin/opencode" ] && { ln -sfn "$HOME/.opencode/bin/opencode" "$BIN/opencode"; return "$SKIP"; }
  curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path || fail "install opencode"
  [ -x "$HOME/.opencode/bin/opencode" ] && ln -sfn "$HOME/.opencode/bin/opencode" "$BIN/opencode"
  have opencode || fail "opencode non e' nel PATH dopo l'installazione"
}

tool_terraform() {
  have terraform && return "$SKIP"
  need_arch
  local v tmp
  v="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | tr -d '\n' \
        | sed -n 's/.*"current_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  [ -n "$v" ] || fail "versione terraform non risolta"
  tmp="$(mktemp -d)"
  dl "https://releases.hashicorp.com/terraform/$v/terraform_${v}_linux_${ARCH}.zip" "$tmp/tf.zip" || fail "download terraform $v"
  unzip_to "$tmp/tf.zip" "$tmp/out"
  install -m 755 "$tmp/out/terraform" "$BIN/terraform" || fail "install terraform"
  rm -rf "$tmp"
}

tool_kubectl() {
  have kubectl && return "$SKIP"
  need_arch
  local v
  v="$(curl -fsSL https://dl.k8s.io/release/stable.txt)" || fail "versione kubectl non risolta"
  dl "https://dl.k8s.io/release/$v/bin/linux/$ARCH/kubectl" "$BIN/kubectl" || fail "download kubectl $v"
  chmod 755 "$BIN/kubectl"
}

# Il token di gh arriva dal set quick (sul PC di origine stava nel keyring):
# login senza browser, poi il file sparisce.
gh_login_from_export() {
  local t="$CONF/quick/exports/gh-token"
  [ -s "$t" ] || return 0
  if ! gh auth status >/dev/null 2>&1; then
    gh auth login --hostname github.com --with-token < "$t" || { echo "gh auth login fallito"; return 0; }
    gh auth setup-git || true
  fi
  rm -f "$t"
}

tool_gh() {
  if have gh; then gh_login_from_export; return "$SKIP"; fi
  need_arch
  local tag v tmp
  tag="$(latest_tag https://github.com/cli/cli/releases/latest)" || fail "tag gh non risolto"
  v="${tag#v}"
  tmp="$(mktemp -d)"
  dl "https://github.com/cli/cli/releases/download/$tag/gh_${v}_linux_${ARCH}.tar.gz" "$tmp/gh.tgz" || fail "download gh $tag"
  tar -xzf "$tmp/gh.tgz" -C "$tmp" || fail "estrazione gh"
  install -m 755 "$tmp/gh_${v}_linux_${ARCH}/bin/gh" "$BIN/gh" || fail "install gh"
  rm -rf "$tmp"
  gh_login_from_export
}

tool_glab() {
  have glab && return "$SKIP"
  need_arch
  local tag v tmp
  tag="$(latest_tag https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest)" || fail "tag glab non risolto"
  v="${tag#v}"
  tmp="$(mktemp -d)"
  dl "https://gitlab.com/gitlab-org/cli/-/releases/$tag/downloads/glab_${v}_linux_${ARCH}.tar.gz" "$tmp/glab.tgz" || fail "download glab $tag"
  tar -xzf "$tmp/glab.tgz" -C "$tmp" || fail "estrazione glab"
  install -m 755 "$tmp/bin/glab" "$BIN/glab" || fail "install glab"
  rm -rf "$tmp"
}

tool_jq() {
  have jq && return "$SKIP"
  need_arch
  dl "https://github.com/jqlang/jq/releases/latest/download/jq-linux-$ARCH" "$BIN/jq" || fail "download jq"
  chmod 755 "$BIN/jq"
}

# La versione di op arriva dall'endpoint di update-check di 1Password; se non
# risponde o lo zip non esiste si dice FAIL, senza URL inventati.
tool_op() {
  have op && return "$SKIP"
  need_arch
  local v tmp url
  v="$(curl -fsSL "https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N" 2>/dev/null | tr -d '\n' \
        | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p')"
  [ -n "$v" ] || fail "versione di op non risolta: scarica 1password-cli da https://developer.1password.com/docs/cli/get-started/ e metti op in ~/.local/bin"
  url="https://cache.agilebits.com/dist/1P/op2/pkg/v$v/op_linux_${ARCH}_v$v.zip"
  tmp="$(mktemp -d)"
  dl "$url" "$tmp/op.zip" || fail "download op $v non riuscito ($url): scaricalo a mano da https://developer.1password.com/docs/cli/get-started/"
  unzip_to "$tmp/op.zip" "$tmp/out"
  install -m 755 "$tmp/out/op" "$BIN/op" || fail "install op"
  rm -rf "$tmp"
}

run_tool() {
  local t="$1" rc=0
  : > "$LOGS/tool-$t.log"
  if ! declare -F "tool_$t" >/dev/null; then
    echo "FAIL: nessuna funzione tool_$t" >> "$LOGS/tool-$t.log"; rc=1
  else
    "tool_$t" >> "$LOGS/tool-$t.log" 2>&1 || rc=$?
  fi
  case "$rc" in
    0) echo "$t ok" ;;
    "$SKIP") echo "$t skip" ;;
    *) echo "$t FAIL $(tail -1 "$LOGS/tool-$t.log" | tr '\n' ' ')" ;;
  esac >> "$STATUS"
}

main() {
  local tools=("$@") t
  [ ${#tools[@]} -gt 0 ] || tools=("${QUICK_TOOLS[@]}")
  : > "$STATUS"
  for t in "${tools[@]}"; do run_tool "$t" & done
  wait
  LC_ALL=C sort -o "$STATUS" "$STATUS"
  cat "$STATUS"
  case ":$ORIG_PATH:" in
    *":$BIN:"*) ;;
    *) echo "ATTENZIONE: $BIN non e' nel PATH: aggiungi 'export PATH=\"\$HOME/.local/bin:\$PATH\"' al profilo." ;;
  esac
  if grep -q ' FAIL' "$STATUS"; then return 1; fi
}

main "$@"
