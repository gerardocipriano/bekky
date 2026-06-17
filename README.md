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
```

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
```

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
├── scripts/
│   ├── create-bucket.sh     # provisioning del bucket GCS
│   └── bekky-cron.sh        # wrapper per il cron + notifica
├── test/                    # suite bats
├── config.example           # template di configurazione
└── docs/                    # design & implementation plan
```

---

<div align="center">
<sub>Fatto per non perdere mai più una customizzazione. 🐢</sub>
</div>
