# shellcheck shell=bash
# shellcheck disable=SC2034
# Cosa includere nei dotfiles (path relativi a $HOME)
INCLUDE_DOTFILES=(
  .zshrc .bashrc .profile .zprofile .aliases
  .config .CLAUDE.md CLAUDE.md .claude
  .gitconfig .tmux.conf .vimrc
  # History e personalizzazioni shell: preziose quanto le config
  .zsh_history .zhistory .bash_history
  .oh-my-zsh/custom
  # Eseguibili utente: le unit in .config/systemd/user e gli alias di .zshrc
  # li invocano per path assoluto, quindi senza questi il restore lascia
  # servizi e alias rotti.
  .local/bin bin
  .local/share/applications
  # Config di Claude Code fuori da .claude: server MCP, account, progetti.
  .claude.json .claude-mem .agentmemory .agents
  # Altri agenti e tool AI con config/stato scritti a mano
  .opencode .opencode-shared .gemini .hermes .multica .pixel-agents
  .cline .copilot .kilo .qodo .understand-anything .tokenjuice .modelrelay.json
  .iii .holmes .env0 .gateguard .lhotse
  .local/share/opencode .local/share/opencode-working-memory
  .local/share/clarvis .local/share/tirith .local/share/k9s
  .local/share/DBeaverData .local/share/icons .local/share/wallpapers
  .local/share/konsole .local/share/plasma .local/share/dolphin .local/share/remmina
  '.local/share/Foxit Software' .dbclient .gitignore .psql_history
  # Script e config di tool usati da cron, alias e unit
  scripts tools Wallpapers
  .terraformrc .terraform.d .gitlab .nanorc .dir_colors .fonts.conf
  .gtkrc-2.0 .xinitrc .Xclients .bash_profile .bash_logout
  .m2/settings.xml .gsutil .krew/receipts .pyenv/version
  Documents Pictures Desktop Templates
)
# File di init della shell che il restore sovrascrive: l'originale locale va
# in ~/.config/confsync/pre-restore/ (vedi cmd_restore)
SHELL_INIT_FILES=( .profile .bash_profile .bashrc .zprofile .zshrc )
# Pattern esclusi (glob su path tar), per evitare cache/spazzatura voluminosa.
# Tengono il backup piccolo e veloce: cache browser/VSCode, log, crash dump, ecc.
EXCLUDE_PATTERNS=(
  '*/Cache/*' '*/Cache*' '*/CachedData/*' '*/CachedExtensions*' '*/CachedExtensionVSIXs*'
  '*/Code Cache/*' '*/GPUCache/*' '*/ShaderCache/*' '*/DawnCache/*' '*/DawnGraphiteCache/*'
  '*/Service Worker/CacheStorage/*' '*/Service Worker/ScriptCache/*'
  '*/blob_storage/*' '*/Crashpad/*' '*/component_crx_cache/*' '*/GrShaderCache/*'
  '*.log' '*/logs/*' '*/.git/*' '*/node_modules/*' '*.sock' '*.lock'
  # Stato runtime di Claude Code: marker e offset ricreati a ogni sessione.
  '.claude/.telegram-pending/*' '.claude/.telegram-offset'
  '.claude/jobs' '.claude/paste-cache' '.claude/shell-snapshots' '.claude/session-env'
  # Codice o dati rigenerabili dentro le dir dei tool
  '.hermes/hermes-agent' '.hermes/venv' '.hermes/cache' '.hermes/audio_cache'
  '.hermes/image_cache' '.hermes/*.lock' '.hermes/*.pid'
  '.understand-anything/repo' '.understand-anything-plugin' '.tokenjuice/artifacts'
  '.gemini/tmp' '.kilo/bin' '.qodo/bin' '.local/share/opencode/snapshot'
  '*/__pycache__/*' '*/.venv/*'
  # Stato di confsync: config e passphrase sono della macchina (host tag),
  # il resto (inventario, bundle, log del restore) e' rigenerato
  '.config/confsync'
)
# App pesanti: stato/cache voluminoso e non portabile (no customizzazioni utili).
# Escluse per tenere il backup piccolo/economico (vedi requisito costo minimo).
# Aggiungi/togli qui in base alle tue app.
EXCLUDE_PATTERNS+=(
  '.config/rambox' '.config/Code' '.config/google-chrome'
  '.config/BraveSoftware' '.config/Antigravity'
  '.config/Slack' '.config/discord' '.config/Cypress' '.config/chromium'
)
# Credenziali gcloud e token gh: vivono SOLO nell'archivio secrets cifrato
# (SECRET_PATHS), mai nei dotfiles. Escluse anche logs/cache voluminosi di
# gcloud. Vanno qui, non in EXCLUDE_PATTERNS: i --exclude di tar matchano su
# qualunque suffisso del path, quindi finirebbero per cancellare le credenziali
# anche da secrets.tar.enc. Sono applicate solo col PACK_DOTFILES=1
# (vedi pack_encrypt in confsync).
DOTFILES_ONLY_EXCLUDES=(
  '.config/gcloud/credentials.db' '.config/gcloud/access_tokens.db'
  '.config/gcloud/legacy_credentials' '.config/gcloud/logs'
  '.config/gh/hosts.yml'
  '.claude/.credentials.json'
  '.local/share/opencode/auth.json' '.local/share/opencode/account.json'
)
# Binari precompilati in .local/bin e bin: pesano ~175M e sono linkati contro
# la glibc di questa macchina, quindi non sopravvivono a una distro con glibc
# più vecchia. Si riscaricano; gli script accanto a loro invece si backuppano.
EXCLUDE_PATTERNS+=(
  '.local/bin/uv' '.local/bin/uvx' '.local/bin/magika' '.local/bin/iii'
  '.local/bin/rtk' '.local/bin/deno' '.local/bin/__pycache__' 'bin/rclone'
)
# Path sensibili -> secrets.tar.enc (relativi a $HOME)
SECRET_PATHS=(
  .ssh .gnupg .netrc .secrets
  .config/gcloud/credentials.db .config/gcloud/legacy_credentials
  .kube/config .kube/kubectx .docker/config.json .azure .boto .vault-token .env
  .config/gh/hosts.yml .git-credentials .pgpass .npmrc .pypirc
  .local/share/keyrings .local/share/kwalletd .claude/.credentials.json
  # login dei provider di opencode (il resto di .local/share/opencode e' nei dotfiles)
  .local/share/opencode/auth.json .local/share/opencode/account.json
)
# Pattern che marcano un file come sensibile (usati anche nelle repo)
SECRET_PATTERNS=( '.env' '.env.*' '*.key' '*.pem' '*secret*' '*token*' '*credential*'
                  '*.tfstate' '*.tfstate.*' '*.tfvars' '*.p12' '*.jks' 'kubeconfig*' )
# Directory dove cercare repo git da manifestare
REPO_SCAN_DIRS=( "$HOME/code" )
# File/dir che non vanno MAI nel backup, anche dentro una repo: dipendenze,
# output di build e cache rigenerabili. Regex estesa sul path relativo a HOME.
IGNORED_JUNK_RE='(^|/)(node_modules|\.terraform|\.venv|venv|__pycache__|dist|build|target|\.next|\.nuxt|\.angular|coverage|\.pytest_cache|\.mypy_cache|\.ruff_cache|\.gradle|vendor|\.cache|\.codegraph|worktrees|test-results|playwright-report|\.cxx|\.tmp|\.vite|binaries)(/|$)|\.(pyc|o|so|tsbuildinfo)$'
# Sopra questa soglia (MiB) i file non entrano nel backup delle repo
CONFSYNC_MAX_FILE_MB=${CONFSYNC_MAX_FILE_MB:-20}
# Sotto-dir di REPO_SCAN_DIRS escluse dal backup dei file fuori repo (relative a HOME)
# Sono nomi di cartelle tue: si dichiarano nella config locale, separati da
# spazio, es. export CONFSYNC_CODE_EXCLUDE_DIRS="code/archivio code/vendor"
read -r -a CODE_EXCLUDE_DIRS <<< "${CONFSYNC_CODE_EXCLUDE_DIRS:-}"
# Dir di /etc fotografate nell'inventario (vedi _inv_copy_etc in confsync).
# Solo i file NON posseduti da un pacchetto vengono copiati: il resto torna
# reinstallando il pacchetto che li fornisce. Aggiungi qui le dir tue.
ETC_SCAN=(
  /etc/systemd/system /etc/modprobe.d /etc/udev/rules.d /etc/X11/xorg.conf.d
  /etc/sysctl.d /etc/docker /etc/NetworkManager/conf.d
  /etc/NetworkManager/dispatcher.d /etc/profile.d /etc/environment.d
  /etc/security/limits.d /etc/modules-load.d /etc/tmpfiles.d /etc/sudoers.d
)

# --- Set "quick" (confsync backup/restore --quick) ---------------------------
# Archivio core: il minimo per lavorare subito con Claude Code su un PC vuoto.
QUICK_INCLUDE=(
  .claude .claude.json CLAUDE.md .CLAUDE.md
  .gitconfig .gitignore .zshrc .bashrc .profile .zprofile .aliases
  .oh-my-zsh/custom .agents .opencode .config/opencode
  .config/gcloud .config/gh .config/glab-cli .config/git .config/1Password/ssh
  .terraformrc .tokenjuice
  # modello scelto in opencode (il db e' troppo grande, non entra)
  .local/state/opencode/model.json
  # solo script: i binari li taglia il tetto CONFSYNC_QUICK_MAX_FILE_MB
  .local/bin scripts
)
# Path (relativi a HOME) potati dalla lista file del core: peso inutile subito
# dopo il restore. Non sono pattern tar: la lista si genera con find.
QUICK_EXCLUDES=(
  .claude/projects .claude/file-history .claude/transcripts
  .claude/shell-snapshots .claude/paste-cache .claude/session-env
  .claude/jobs .claude/todos .claude/debug .claude/statsig .claude/telemetry
  .tokenjuice/artifacts .opencode/bin .opencode/node_modules
  .config/gcloud/logs .config/gcloud/virtenv .config/gcloud/cache
)
# Glob di dir che restano per intero anche dentro un QUICK_EXCLUDES: la
# memoria di Claude vive in .claude/projects/<cwd>/memory
QUICK_KEEP=( '.claude/projects/*/memory' )
# Archivi separati dal core ("nome:prefisso" relativo a HOME): cambiano di rado,
# cosi' non si ricaricano a ogni sessione. Una lista file e un .tar.enc ciascuno.
QUICK_SPLIT=( 'plugins:.claude/plugins' 'code:code' )
# File e dir di progetto sotto REPO_SCAN_DIRS (sia fuori che dentro le repo):
# istruzioni e stato di Claude non finiscono mai in git, ma servono su un PC nuovo.
# Le dir si salvano per intero, tranne .claude/worktrees e il junk (vedi quick_list_code).
QUICK_CODE_FILES=( CLAUDE.md CLAUDE.local.md AGENTS.md )
QUICK_CODE_DIRS=( handoff .claude )
# Estensioni (senza maiuscole/minuscole) saltate nel set quick sotto ~/code: media
# pesanti e rigenerabili. Restano nel backup completo.
QUICK_CODE_SKIP_EXT=( png jpg jpeg gif webp svg pdf mp4 )
# Tool installati da scripts/quick-tools.sh (una funzione tool_<nome> ciascuno)
QUICK_TOOLS=( node rtk uv opencode gcloud terraform kubectl gh glab jq op )
