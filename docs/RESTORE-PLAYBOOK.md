# Playbook di restore per Claude (Manjaro -> Ubuntu)

Istruzioni per l'agente che gira sul PC nuovo. L'utente ha già lanciato
`scripts/bootstrap.sh`: sudo senza password (temporaneo), gcloud autenticato,
passphrase in `~/.config/confsync/passphrase`, config in `~/.config/confsync/config`.

Obiettivo: stesso ambiente del vecchio Manjaro (host in `CONFSYNC_HOST_TAG`), senza fare
domande all'utente. Chiedi solo se un passo richiede davvero lui (GUI di
1Password, login a servizi web, VPN). Per tutto il resto decidi da solo e annota.

## Regole di esecuzione

- Stato in `~/.config/confsync/restore-status.md`: una riga per fase
  (`[x]`, `[ ]`, `[!] motivo`). Leggilo all'avvio: se esiste, riprendi dalla
  prima fase non completata. Aggiornalo alla fine di ogni fase.
- Log dei comandi lunghi in `~/.config/confsync/restore-logs/<fase>.log`.
- Ogni fase deve essere idempotente: rilanciare non fa danni.
- Un pacchetto che non si installa non ferma la fase. Annotalo in
  `restore-status.md` sotto "Da sistemare" e vai avanti.
- `export CONFSYNC_PASSPHRASE="$(cat ~/.config/confsync/passphrase)"` in ogni
  shell che lancia confsync.
- Profilo gcloud per bekky: `CLOUDSDK_CORE_ACCOUNT="$CONFSYNC_ACCOUNT"` (da `~/.config/confsync/config`).

## Fase 1: restore dei dati

Il restore sovrascrive `~/.claude.json` e `~/.claude/.credentials.json` della
sessione in corso. Salva il login fatto su questo PC e rimettilo subito dopo:

```bash
cd ~/code/misc/bekky
mkdir -p ~/.config/confsync/restore-logs ~/.config/confsync/new-login
cp -a ~/.claude/.credentials.json ~/.claude.json ~/.config/confsync/new-login/ 2>/dev/null
export CONFSYNC_PASSPHRASE="$(cat ~/.config/confsync/passphrase)"
./confsync restore --yes --secrets --packages 2>&1 | tee ~/.config/confsync/restore-logs/restore.log
```

```bash
L=~/.config/confsync/new-login
cp -a "$L/.credentials.json" ~/.claude/.credentials.json
jq --slurpfile n "$L/.claude.json" '.oauthAccount = $n[0].oauthAccount | .userID = $n[0].userID' \
  ~/.claude.json > ~/.claude.json.new && mv ~/.claude.json.new ~/.claude.json
rm -rf "$L"   # copia delle credenziali: non lasciarla in giro
```

Se un archivio non si decifra (`bad decrypt`, o `zstd: unsupported format`) ma
gli altri sì, quel backup è stato cifrato con passphrase diverse (bug corretto,
ma i backup vecchi restano così). Prova il precedente:
`gsutil ls $CONFSYNC_BUCKET/<host>/`, poi `CONFSYNC_RESTORE_TS=<timestamp>`
davanti a ogni comando `confsync restore` di questo playbook.

Il restore non tocca più `~/.config/confsync` (config, passphrase, host tag).
I file di init della shell sovrascritti (`.profile`, `.bashrc`, ...) restano in
`~/.config/confsync/pre-restore/`: se il log li segnala, rimetti nel PATH quello
che aggiungevano gli originali (su Ubuntu `.profile` aggiunge `~/.local/bin`).

Le repo si ripristinano in fase 3: le chiavi SSH stanno nell'agent di
1Password, prima non c'è modo di clonare. Controlla il log: nessun `ERRORE`.
L'inventario del vecchio sistema ora sta in
`~/.config/confsync/inventory/` (leggi il suo `README.txt`). Da qui in poi è la
fonte di verità per cosa installare.

Se `origin.home` è diverso da `$HOME`: `./scripts/rehome.sh --apply` subito
(riscrive anche i symlink). Rilancialo dopo ogni `restore --repos`, che
riestrae l'inventario.

## Fase 2: tool da cui dipende Claude Code

Gli hook in `~/.claude/settings.json` chiamano `tokenjuice` (path assoluto sotto
nvm), `rtk` e `node`. Installali prima di tutto il resto:

1. nvm + tutte le versioni in `inventory/dev/nvm-versions.txt`; default quello
   di `inventory/dev/nvm-default.txt` (`nvm alias default <versione>`).
2. npm globali di `inventory/dev/npm-global.txt` sulla versione default. Salta
   `npm` e `corepack`. I pacchetti linkati (`-> ./...`) da ignorare, salvo che
   la sorgente esista su disco.
3. rtk: `curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh`
   (poi `rtk --version`).
4. uv: `curl -LsSf https://astral.sh/uv/install.sh | sh`; poi i tool di
   `inventory/dev/uv-tools.txt` con `uv tool install`.
5. Controllo: `jq -r '..|.command? // empty' ~/.claude/settings.json` e verifica
   che ogni eseguibile citato esista.
6. Gli hook girano con `/bin/sh` e il PATH del processo `claude`, che spesso non
   ha nvm (il `.bashrc` di Manjaro non lo carica). Serve `node` nel PATH di
   sistema: `sudo ln -sfn ~/.nvm/versions/node/<default>/bin/node /usr/local/bin/node`.

## Fase 3: 1Password e SSH

1. Repo apt di 1Password (https://support.1password.com/install-linux/#debian-or-ubuntu),
   pacchetti `1password` e `1password-cli`. Se c'è anche lo snap
   (`snap list 1password`), l'utente deve usare l'app apt (`/usr/bin/1password`):
   nello snap l'opzione dell'agent SSH è disattivata.
2. Chiedi all'utente, in un unico messaggio: aprire 1Password, fare login,
   attivare Settings -> Developer -> "Integrate with CLI" e "Use the SSH agent".
   È l'unico passo con la GUI. Aspetta la conferma.
3. `ssh -T git@github.com` e `ssh -T git@gitlab.com` devono rispondere. Prima del
   restore aggiungi a `known_hosts` anche bitbucket.org e ssh.dev.azure.com
   (`ssh-keyscan`): con `BatchMode` un host sconosciuto fa fallire il clone.
4. Restore delle repo (~339 clone, 20-40 minuti, in background con log):
   `./confsync restore --yes --no-dotfiles --repos > ~/.config/confsync/restore-logs/repos.log 2>&1`.
   Ricrea anche commit non pushati, branch locali e stash dai bundle.
   Idempotente: se qualche clone fallisce, sistema la causa e rilancialo.
5. Controllo: `grep -c 'clone fallito' ~/.config/confsync/restore-logs/repos.log`
   deve dare 0, oppure elenca le repo rimaste in "Da sistemare". Se `ssh-add -l`
   mostra poche chiavi, quelle che mancano stanno in vault che l'agent di
   1Password non espone di default (`~/.config/1Password/ssh/agent.toml`): è
   un passo dell'utente.
6. Se 1Password chiede di autorizzare ogni processo che usa l'agent, chiedi
   all'utente di scegliere "Approve for all applications" alla prima richiesta.

## Fase 4: pacchetti di sistema

Liste: `inventory/packages/native.txt` (pacman, ufficiali) e `aur.txt`.

Nativi. Per ogni nome:
- se `apt-cache show <nome>` esiste, installa;
- se no, cerca l'equivalente (`apt-cache search --names-only`), ad esempio
  `python-foo` -> `python3-foo`, `docker` -> `docker.io` o docker-ce,
  `kubectl` -> repo apt di Kubernetes, `terraform` -> repo HashiCorp, `helm` ->
  repo apt di helm, `github-cli` -> `gh`, `nodejs`/`npm` -> salta (usa nvm);
- salta: kernel, firmware, driver, `manjaro-*`, `pamac*`, `mhwd*`, `lib32-*`,
  base/base-devel (-> `build-essential`), pacchetti già presenti.
Installa in blocchi e, se un blocco fallisce, un pacchetto alla volta per
isolare il colpevole. `sudo` non passa `DEBIAN_FRONTEND` dall'ambiente: senza
metterlo nel comando, un conffile modificato (es. `sshd_config`) apre un prompt
whiptail e apt resta fermo:
`sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --no-install-recommends ...`.
Durante l'install metti un `/usr/sbin/policy-rc.d` con `exit 101`, così
postgresql, samba, sshd e simili non partono da soli (le unit le decide la
fase 6). Toglilo alla fine.

AUR, fonti ufficiali dei vendor:
| AUR | Ubuntu |
|---|---|
| 1password, 1password-cli | fase 3 |
| google-chrome | .deb da dl.google.com |
| visual-studio-code-bin | repo apt Microsoft (`code`) |
| spotify | snap `spotify` (la chiave del repo apt cambia spesso) |
| webex-bin | .deb da webex.com |
| forticlient-vpn | repo apt Fortinet (`forticlient`) |
| cloud-sql-proxy | binario da `storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/<tag>/cloud-sql-proxy.linux.amd64` (le release GitHub non hanno asset) |
| kubecolor, terraform-docs, tfswitch | binari da GitHub release in `~/.local/bin` |
| tauri-cli | `cargo install tauri-cli` |
| masterpdfeditor-free | .deb da code-industry.net |
| rambox-pro-bin | .deb dalle release GitHub `ramboxapp/download` |
| jmeter | tarball Apache in `~/tools` |
| oh-my-zsh-git | installer ufficiale oh-my-zsh con `KEEP_ZSHRC=yes RUNZSH=no`; la custom è già ripristinata |
| neofetch | `fastfetch` o `neofetch` da apt |
| tigervnc-server | `tigervnc-standalone-server` |
| altri python-*, khotkeys, kinit, lib32-*, manjaro-*, qt5-*, plasma-*, systemd-kcm | salta |

Altri tool:
- gcloud components: `inventory/dev/gcloud-components.txt` via apt
  (`google-cloud-cli-<componente>`, es. `gke-gcloud-auth-plugin`).
- pipx: `inventory/dev/pipx.txt` (`pipx install`).
- go: `sudo apt install golang` o tarball ufficiale; poi `go install` dei
  binari in `inventory/dev/go-bin.txt` (gopls: `golang.org/x/tools/gopls@latest`,
  staticcheck: `honnef.co/go/tools/cmd/staticcheck@latest`).
- krew: installer ufficiale, poi `inventory/dev/krew.txt`.
- pyenv: installer ufficiale, versioni in `inventory/dev/pyenv-versions.txt`.
- Binari esclusi dal backup (glibc): uv, rclone, magika, iii, deno, rtk. rclone
  da rclone.org/install.sh; magika via pipx; deno dal suo installer.
- VSCode: `code --install-extension` per ogni riga di
  `inventory/vscode/extensions.txt`; poi copia `inventory/vscode/User/*` in
  `~/.config/Code/User/`.

## Fase 5: desktop

Il vecchio desktop è in `inventory/system/desktop.txt` (KDE Plasma). Tutte le
config KDE sono già in `~/.config`. Per ritrovare lo stesso ambiente installa
`kde-plasma-desktop` accanto al desktop di Ubuntu, senza cambiare il display
manager. Alla fine dì all'utente di scegliere la sessione "Plasma" al login.
Poi i pacchetti KDE che erano nella lista nativa (konsole, dolphin, kate,
okular, spectacle, ark, ...).

## Fase 6: sistema

- Shell: `chsh -s "$(command -v zsh)" "$USER"` (in `inventory/system/shell.txt`).
- Gruppi: aggiungi l'utente ai gruppi di `inventory/system/groups.txt` che
  esistono anche qui (docker, input, lp, ...). `wheel` -> `sudo`.
- Timezone e locale da `inventory/system/timezone.txt` e `locale.txt`.
- `/etc/hosts`: aggiungi le righe custom di
  `inventory/system/etc/etc/hosts` che non ci sono già. Non toccare le righe
  di localhost e l'hostname.
- File di `inventory/system/etc/etc/...`: unit custom (agentmemory,
  docker-stop.*, docker.service.d), modprobe, udev, xorg. Copiali al loro path
  con `sudo install -m 644`, dopo aver riscritto il vecchio HOME se cambiato.
  Poi `sudo systemctl daemon-reload` e `sudo udevadm control --reload`.
  Salta i symlink `*.wants/*` (li crea `systemctl enable`).
- Unit di sistema: abilita quelle di `system-units-enabled.txt` che esistono
  qui (`cronie` -> `cron`, `sddm` -> salta, `paccache`/`pamac*`/`pacman-*` -> salta,
  `systemd-timesyncd` -> su Ubuntu c'è chrony).
  `agentmemory.service` non ha `User=`: gira come root e scrive file di root in
  `~/.npm` e `~/.agentmemory`. Aggiungi un drop-in
  `/etc/systemd/system/agentmemory.service.d/user.conf` con `User=`, `Group=` e
  `WorkingDirectory=$HOME/.agentmemory` (scrive `data/` relativo alla cwd).
- Unit utente: `inventory/system/user-units-enabled.txt`. Prima esegui
  `./scripts/post-restore.sh` per vedere quali ExecStart mancano. Ricrea il
  necessario (venv, binari), poi `systemctl --user enable --now`.
  Hermes: `~/.hermes/hermes-agent` e il venv sono esclusi dal backup; config,
  memorie, sessioni e db sono ripristinati. Salva una copia di
  `~/.hermes/config.yaml`, scarica l'installer
  (`https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh`)
  e lancialo con `bash install.sh --non-interactive < /dev/null`: può modificare
  `config.yaml`, rimetti la copia. Il layout nuovo non ha più `venv/`: il
  binario è `~/.hermes/hermes-agent/.hermes/bin/hermes`. Ripunta lì
  `~/.local/bin/hermes` e cambia l'ExecStart di `hermes-gateway.service` in
  `%h/.local/bin/hermes gateway run --replace`.
  Repo con `dist/` non versionato (es. `~/code/misc/pixel-agents`): `npm ci && npm run build`.
  `~/.understand-anything/repo` è escluso dal backup ma le skill `understand-*`
  ci puntano: reinstallalo o le skill restano link rotti.
- crontab: `crontab inventory/system/crontab.txt`, dopo aver riscritto il
  vecchio HOME se cambiato. Il job di bekky deve esserci; togli la riga
  marcata `bekky-migrazione` (backup giornaliero temporaneo del vecchio PC).
- Connessioni NetworkManager: sono solo nomi in `nm-connections.txt` (le
  credenziali stanno in /etc, root-only). Elencale all'utente nel report finale.

## Fase 7: verifica

Controlla ognuno e annota il risultato:
1. `zsh -ic 'alias | wc -l'` restituisce gli alias, nessun errore all'avvio.
2. `gcloud config configurations list` mostra gli stessi profili del vecchio PC.
3. `kubectl config get-contexts` funziona.
4. `claude mcp list`: agentmemory e codegraph connessi.
5. `systemctl --user --failed` e `systemctl --failed` vuoti.
6. `git -C ~/code/<repo con stash> stash list` non vuoto (vedi manifest).
7. `./confsync diff` non mostra differenze importanti.

## Fase 8: chiusura

1. Nuovo host tag: togli `CONFSYNC_HOST_TAG` da `~/.config/confsync/config`, così
   il nuovo PC fa i suoi backup con il suo hostname. Lancia `./confsync backup`
   una volta.
2. `sudo rm /etc/sudoers.d/99-bekky-restore`. Controlla con `sudo -n true`
   (deve fallire).
3. Report all'utente, breve: cosa funziona, cosa è in "Da sistemare", le
   azioni che restano a lui (sessione Plasma, VPN, login ai servizi web).
