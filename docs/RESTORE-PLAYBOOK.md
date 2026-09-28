# Playbook di restore per Claude (Manjaro -> Ubuntu)

Istruzioni per l'agente che gira sul PC nuovo. L'utente ha già lanciato
`scripts/bootstrap.sh`: sudo senza password (temporaneo), gcloud autenticato,
passphrase in `~/.config/confsync/passphrase`, config in `~/.config/confsync/config`.

Obiettivo: stesso ambiente del vecchio Manjaro (host `INJ-NB-250`), senza fare
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
- Profilo gcloud per bekky: `CLOUDSDK_CORE_ACCOUNT=gerardo.cipriano@dinova.one`.

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
```

Le repo si ripristinano in fase 3: le chiavi SSH stanno nell'agent di
1Password, prima non c'è modo di clonare. Controlla il log: nessun `ERRORE`.
L'inventario del vecchio sistema ora sta in
`~/.config/confsync/inventory/` (leggi il suo `README.txt`). Da qui in poi è la
fonte di verità per cosa installare.

Se `origin.home` è diverso da `$HOME`: `./scripts/rehome.sh --apply` subito.

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

## Fase 3: 1Password e SSH

1. Repo apt di 1Password (https://support.1password.com/install-linux/#debian-or-ubuntu),
   pacchetti `1password` e `1password-cli`.
2. Chiedi all'utente, in un unico messaggio: aprire 1Password, fare login,
   attivare Settings -> Developer -> "Integrate with CLI" e "Use the SSH agent".
   È l'unico passo con la GUI. Aspetta la conferma.
3. `ssh -T git@github.com` e `ssh -T git@gitlab.com` devono rispondere.
4. Restore delle repo (~339 clone, 20-40 minuti, in background con log):
   `./confsync restore --yes --repos > ~/.config/confsync/restore-logs/repos.log 2>&1`.
   Ricrea anche commit non pushati, branch locali e stash dai bundle.
   Idempotente: se qualche clone fallisce, sistema la causa e rilancialo.
5. Controllo: `grep -c 'clone fallito' ~/.config/confsync/restore-logs/repos.log`
   deve dare 0, oppure elenca le repo rimaste in "Da sistemare".
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
Installa in blocchi con `apt-get install -y --no-install-recommends` e, se un
blocco fallisce, un pacchetto alla volta per isolare il colpevole.

AUR, fonti ufficiali dei vendor:
| AUR | Ubuntu |
|---|---|
| 1password, 1password-cli | fase 3 |
| google-chrome | .deb da dl.google.com |
| visual-studio-code-bin | repo apt Microsoft (`code`) |
| spotify | repo apt Spotify |
| webex-bin | .deb da webex.com |
| forticlient-vpn | repo apt Fortinet (`forticlient`) |
| cloud-sql-proxy | componente gcloud o binario da GitHub release |
| kubecolor, terraform-docs, tfswitch | binari da GitHub release in `~/.local/bin` |
| tauri-cli | `cargo install tauri-cli` |
| masterpdfeditor-free | .deb da code-industry.net |
| rambox-pro-bin | .deb/AppImage da rambox.app |
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
  qui (`cronie` -> `cron`, `sddm` -> salta, `paccache`/`pamac*`/`pacman-*` -> salta).
- Unit utente: `inventory/system/user-units-enabled.txt`. Prima esegui
  `./scripts/post-restore.sh` per vedere quali ExecStart mancano. Ricrea il
  necessario (venv, binari), poi `systemctl --user enable --now`.
  Hermes: `~/.hermes/hermes-agent` e il venv sono esclusi dal backup; config,
  memorie, sessioni e db sono ripristinati. Reinstalla con
  `curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash`
  (lo stesso usato sul vecchio PC) e verifica che non sovrascriva `config.yaml`.
- crontab: `crontab inventory/system/crontab.txt`, dopo aver riscritto il
  vecchio HOME se cambiato. Il job di bekky deve esserci; togli la riga
  marcata `bekky-migrazione` (backup giornaliero temporaneo del vecchio PC).
- Connessioni NetworkManager: sono solo nomi in `nm-connections.txt` (le
  credenziali stanno in /etc, root-only). Elencale all'utente nel report finale.

## Fase 7: verifica

Controlla ognuno e annota il risultato:
1. `zsh -ic 'alias | wc -l'` restituisce gli alias, nessun errore all'avvio.
2. `gcloud config configurations list` mostra i profili default/tea/telepass.
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
