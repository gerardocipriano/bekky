<div align="center">

# 🐢 bekky

### Backup e restore **cifrati** delle configurazioni del tuo OS — in un comando.

*Si rompe la macchina? Cambi distro? Riparti in pochi minuti, senza perdere una sola customizzazione.*

![shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![crypto](https://img.shields.io/badge/crypto-AES--256%20%2B%20PBKDF2-blue)
![storage](https://img.shields.io/badge/storage-Google%20Cloud-4285F4?logo=googlecloud&logoColor=white)
![cross-distro](https://img.shields.io/badge/cross--distro-Arch%20%7C%20Debian%20%7C%20Fedora-success)
![license](https://img.shields.io/badge/license-MIT-lightgrey)

</div>

---

## ✨ Perché bekky

I tuoi dotfiles, le tue chiavi, i tuoi alias, le repo dei clienti, i `CLAUDE.md`: settimane di
piccole customizzazioni che vivono in un solo posto fragile — il tuo disco. **bekky** le mette
al sicuro su un bucket cloud, **cifrate sul tuo computer prima di partire**, e te le rimette
esattamente dove stavano quando ne hai bisogno.

> **Security first.** Niente lascia la tua macchina in chiaro. Anche con un bucket mal
> configurato, i tuoi dati restano un blocco di byte illeggibili senza la tua passphrase.

---

## 🚀 Cosa fa

| | |
|---|---|
| 🔐 **Cifratura client-side** | AES-256-CBC + PBKDF2 (600k iterazioni) prima di ogni upload |
| 🗂️ **Tre archivi separati** | dotfiles · secrets · file locali delle repo — i segreti si ripristinano solo se *vuoi* |
| 🧠 **Dedup intelligente** | niente cambia → niente upload (firma sul contenuto, pre-cifratura) |
| 🪶 **Leggero** | esclude cache/app pesanti: 24 GB di `.config` → ~100 MB di backup |
| 🌍 **Cross-distro** | Arch · Debian/Ubuntu · Fedora — rileva la distro e adatta tutto |
| 📦 **Repo-aware** | salva path + remote + branch e i file non versionati; al restore **ri-clona** tutto |
| 💸 **Cheap by design** | bucket Nearline, single-region, lifecycle e versioning |
| 🛎️ **Cron + alert** | backup settimanale automatico, notifica desktop se qualcosa va storto |

---

## 🧬 Come funziona

```
              raccolta            compressione        cifratura            upload
  ~/  ───►  tar (con exclude) ───► zstd ─────────► openssl AES-256 ──────► gs://bucket/<host>/<ts>/
 .config                                          (passphrase, fd:3)        ├─ dotfiles.tar.enc
 .ssh ──────────────────────────────────────────────────────────────►      ├─ secrets.tar.enc
 ~/code (repo) ──► manifest (path+remote+branch) ──────────────────────►    ├─ repo-localfiles.tar.enc
                                                                            ├─ repos.manifest.json
                                                                            ├─ packages.txt
                                                                            └─ MANIFEST.txt (sha256)
```

Il **restore** percorre la pipeline al contrario: scarica → verifica i checksum → decifra →
estrae. Le repo vengono **ri-clonate nella stessa identica posizione** e i file locali rideposti.

---

## ⚡ Quick start

```bash
# 1. Dipendenze
#    Arch:   sudo pacman -S openssl zstd
#    Debian: sudo apt install openssl zstd
#    + Google Cloud SDK (gcloud / gsutil)

# 2. Configura (niente dati sensibili nel repo)
cp config.example ~/.config/confsync/config
chmod 600 ~/.config/confsync/config
$EDITOR ~/.config/confsync/config      # imposta CONFSYNC_BUCKET, ecc.

# 3. Crea il bucket (una tantum)
./scripts/create-bucket.sh

# 4. Vai
./confsync backup
```

Comodo con un alias:

```bash
alias bekky="$HOME/code/misc/bekky/confsync"
```

---

## 🎮 Comandi

```bash
bekky backup                 # backup cifrato (dedup automatico)
bekky list                   # elenca i backup nel bucket
bekky diff                   # cosa è cambiato dall'ultimo backup
bekky restore                # ripristina i dotfiles
bekky restore --secrets      # + chiavi SSH/GPG (permessi 600)
bekky restore --repos        # ri-clona le repo + file locali
bekky restore --packages     # comando di reinstallazione pacchetti per la distro
bekky restore --dry-run      # anteprima, non tocca nulla
bekky restore --no-dotfiles --repos   # secondo passaggio: non annulla rehome e modifiche
CONFSYNC_RESTORE_TS=<ts> bekky restore   # un backup diverso dall'ultimo
```

Il restore non tocca `~/.config/confsync` (config e passphrase della macchina).
I file di init della shell che sovrascrive (`.profile`, `.bashrc`, ...) restano
in `~/.config/confsync/pre-restore/`.

---

## ⚡ Quick: operativo in un minuto su un PC vuoto

```bash
curl -fsSL https://raw.githubusercontent.com/gerardocipriano/bekky/main/scripts/quick.sh | bash
# senza curl (Ubuntu desktop):  wget -qO- <stesso URL> | bash
```

Chiede due cose, una dopo l'altra: la passphrase e il login gcloud. Poi:

1. ripristina config e memoria di Claude Code, plugin, skill, shell, git, profili
   gcloud e i secrets (chiavi SSH, credenziali gcloud, kube, token gh);
2. installa Claude Code;
3. in background installa i tool in `~/.local/bin`, senza sudo (node + npm
   globali, rtk, uv, opencode, gcloud, terraform, kubectl, gh, glab, jq, op) e
   clona le repo di `~/code`.

Stato e log: `~/.config/confsync/quick-logs/`. Commit non pushati, stash e file
non versionati delle repo arrivano dopo, dal backup completo:
`bekky restore --yes --no-dotfiles --repos`.

Il set quick (~65 MB) vive in `$BUCKET/quick/`, non dipende dall'hostname e si
aggiorna con:

```bash
bekky backup --quick             # carica solo gli archivi cambiati
./scripts/install-hooks.sh       # lo fa da solo a ogni fine sessione di Claude Code
```

Cosa entra nel core si regola in `lib/manifest.sh` (`QUICK_INCLUDE`,
`QUICK_EXCLUDES`, `QUICK_SPLIT`, `QUICK_TOOLS`); i file oltre
`CONFSYNC_QUICK_MAX_FILE_MB` (default 5) restano fuori.

## 🖥️ Console web

```bash
bekky ui        # http://127.0.0.1:7842, solo locale, protetta da token
```

Stato in una frase, storico degli ultimi 30 giorni, push e backup con log,
hook e controlli (gcloud, bucket, passphrase), composizione del core. Il
restore non si lancia da qui: sovrascrive la HOME. Per provarla con dati finti:
`BEKKY_UI_MOCK=ok bekky ui` (scenari: `ok`, `reauth`, `stale`, `fresh`).

---

## 🆘 Disaster recovery (macchina nuova / appena formattata)

```bash
# installa openssl, zstd e google-cloud-sdk, poi:
gcloud auth login
git clone git@github.com:gerardocipriano/bekky.git ~/code/misc/bekky
cp ~/code/misc/bekky/config.example ~/.config/confsync/config && $EDITOR ...   # imposta il bucket

cd ~/code/misc/bekky
./confsync restore                 # dotfiles
./confsync restore --secrets       # chiavi
./confsync restore --repos         # tutte le tue repo, dove stavano
./confsync restore --packages      # reinstalla i pacchetti espliciti

./scripts/post-restore.sh          # passi di sistema fuori da $HOME
```

`post-restore.sh` copre ciò che il backup non può: abilita `paccache.timer`
(pulizia cache pacman), disabilita baloo, reinstalla il cron di bekky e
ricorda i login gcloud. Idempotente.

> 🔑 **La passphrase è l'unica cosa che bekky non può recuperare per te.** Custodiscila nel tuo
> password manager: senza, i backup sono — *by design* — irrecuperabili.

---

## ⏰ Backup automatico (cron + notifica)

Lo script `scripts/bekky-cron.sh` legge la passphrase da un file `0600`, lancia il backup e
manda una **notifica desktop** (`notify-send`) se fallisce. Esempio settimanale:

```cron
# Mercoledì alle 13:00
0 13 * * 3 /home/USER/code/misc/bekky/scripts/bekky-cron.sh
```

Log dell'ultima esecuzione: `~/.config/confsync/last-run.log`.

---

## 🔒 Sicurezza

- **Cifratura sul client**, sempre, prima dell'upload. Sul bucket non transita nulla in chiaro.
- **Passphrase** mai salvata, mai passata in `argv`/`ps` (consegnata a `openssl` via `fd:3`).
- **Secrets isolati** in un archivio dedicato, ripristinabili solo con `--secrets` e a `chmod 600`.
- I file sensibili trovati nelle repo (`.env`, `*.key`, `*secret*`, …) finiscono **automaticamente**
  nell'archivio cifrato dei secrets, mai nei dotfiles.
- **Integrità verificata**: ogni restore controlla gli SHA-256 in `MANIFEST.txt` prima di estrarre.
- **Nessun dato di infrastruttura nel repo**: bucket, progetto e account vivono solo nella tua
  config locale (vedi `config.example`).

---

## ⚙️ Configurazione

Tutto in `~/.config/confsync/config` (vedi [`config.example`](config.example)):

| Variabile | Default | Descrizione |
|---|---|---|
| `CONFSYNC_BUCKET` | — *(obbligatoria)* | bucket GCS di destinazione (`gs://...`) |
| `CONFSYNC_PROJECT` | — | progetto GCP (solo per `create-bucket.sh`) |
| `CONFSYNC_ACCOUNT` | account gcloud attivo | account per il provisioning |
| `CONFSYNC_HOST_TAG` | `$(hostname)` | namespace del backup nel bucket |
| `CONFSYNC_ZSTD_LEVEL` | `10` | livello di compressione zstd |
| `CONFSYNC_RESTORE_TS` | contenuto di `latest` | timestamp del backup da ripristinare |

**Cosa viene incluso/escluso** si regola in [`lib/manifest.sh`](lib/manifest.sh):
`INCLUDE_DOTFILES`, `EXCLUDE_PATTERNS`, `SECRET_PATHS`, `SECRET_PATTERNS`, `REPO_SCAN_DIRS`.

---

## 🧪 Sviluppo

```bash
bats test/confsync.bats        # test (round-trip, dedup, secret split, ...)
shellcheck confsync lib/*.sh scripts/*.sh
```

---

## 📁 Struttura

```
bekky/
├── confsync                 # lo script (tutta la logica)
├── lib/manifest.sh          # cosa includere/escludere/cifrare
├── lib/tools.sh             # installer userland condivisi
├── scripts/
│   ├── create-bucket.sh     # provisioning del bucket GCS
│   ├── bekky-cron.sh        # wrapper per il cron + notifica
│   ├── quick.sh             # one-liner per il PC vuoto
│   ├── quick-tools.sh       # tool in ~/.local/bin
│   ├── quick-repos.sh       # clone parallelo delle repo
│   ├── quick-push.sh        # push del set quick (hook SessionEnd)
│   └── install-hooks.sh     # installa/rimuove l'hook
├── ui/                      # console web locale (Python stdlib + JS vanilla)
├── test/                    # suite bats
├── config.example           # template di configurazione
└── docs/                    # design & implementation plan
```

---

<div align="center">
<sub>Fatto per non perdere mai più una customizzazione. 🐢</sub>
</div>
