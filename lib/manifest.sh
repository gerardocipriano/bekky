# shellcheck shell=bash
# shellcheck disable=SC2034
# Cosa includere nei dotfiles (path relativi a $HOME)
INCLUDE_DOTFILES=(
  .zshrc .bashrc .profile .zprofile .aliases
  .config .CLAUDE.md CLAUDE.md .claude
  .gitconfig .tmux.conf .vimrc
)
# Pattern esclusi (glob su path tar), per evitare cache/spazzatura voluminosa.
# Tengono il backup piccolo e veloce: cache browser/VSCode, log, crash dump, ecc.
EXCLUDE_PATTERNS=(
  '*/Cache/*' '*/Cache*' '*/CachedData/*' '*/CachedExtensions*' '*/CachedExtensionVSIXs*'
  '*/Code Cache/*' '*/GPUCache/*' '*/ShaderCache/*' '*/DawnCache/*' '*/DawnGraphiteCache/*'
  '*/Service Worker/CacheStorage/*' '*/Service Worker/ScriptCache/*'
  '*/blob_storage/*' '*/Crashpad/*' '*/component_crx_cache/*' '*/GrShaderCache/*'
  '*.log' '*/logs/*' '*/.git/*' '*/node_modules/*' '*.sock' '*.lock'
)
# App pesanti: stato/cache voluminoso e non portabile (no customizzazioni utili).
# Escluse per tenere il backup piccolo/economico (vedi requisito costo minimo).
# Aggiungi/togli qui in base alle tue app.
EXCLUDE_PATTERNS+=(
  '.config/rambox' '.config/Code' '.config/google-chrome'
  '.config/BraveSoftware' '.config/Antigravity'
  '.config/Slack' '.config/discord' '.config/Cypress' '.config/chromium'
)
# Credenziali gcloud: vivono SOLO nell'archivio secrets cifrato (SECRET_PATHS),
# mai nei dotfiles. Escluse anche logs/cache voluminosi di gcloud.
EXCLUDE_PATTERNS+=(
  '.config/gcloud/credentials.db' '.config/gcloud/access_tokens.db'
  '.config/gcloud/legacy_credentials' '.config/gcloud/logs'
)
# Path sensibili -> secrets.tar.enc (relativi a $HOME)
SECRET_PATHS=(
  .ssh .gnupg .netrc
  .config/gcloud/credentials.db .config/gcloud/legacy_credentials
)
# Pattern che marcano un file come sensibile (usati anche nelle repo)
SECRET_PATTERNS=( '.env' '*.key' '*.pem' '*secret*' '*token*' '*credential*' )
# Directory dove cercare repo git da manifestare
REPO_SCAN_DIRS=( "$HOME/code" )
