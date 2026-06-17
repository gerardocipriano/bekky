# confsync — Design

**Data:** 2026-06-17
**Autore:** Gerardo Cipriano (tua.email@example.com)

## Obiettivo

Tool *molto easy ma efficiente* per backuppare e ripristinare in modo seamless tutte
le customizzazioni del sistema operativo. Se la macchina si rompe o si cambia distro,
ripartire in pochi minuti senza perdere nulla. **Security first assoluto**: zero data
leak sul bucket. Cross-distro (non solo Manjaro).

## Principi

- **Cifratura client-side**: nulla lascia la macchina in chiaro. Anche con un bucket
  mal-configurato i dati restano illeggibili.
- **Singolo script Bash POSIX**, zero dipendenze esotiche (`tar`, `age`, `gsutil`/`gcloud`).
- **Separazione dotfiles / secrets**: un restore "leggero" non espone mai le chiavi.
- **Portabilità**: si salva ciò che è portabile (dotfiles, liste, manifest), non binari
  o storia git ridondante.

## Forma

Singolo script `confsync` in `~/code/misc/bekky/`.

```
confsync backup            # raccoglie -> archivia -> cifra -> upload
confsync restore           # download -> decifra -> estrae -> ripristina dotfiles
confsync restore --secrets # ripristina anche secrets (esplicito, permessi 600)
confsync restore --repos   # ri-clona repo dal manifest e ridepone file locali
confsync list              # elenca i backup presenti nel bucket
confsync diff              # (opz.) mostra cosa cambierebbe un restore
```

## Cosa viene backuppato — 3 artefatti cifrati/separati

### 1. `dotfiles.tar.enc`
Customizzazioni utente, 100% portabili:
- `~/.zshrc`, `~/.bashrc`, `~/.profile`, alias e snippet shell
- `~/.config/` (esclusi `Cache*`, `*/Cache/*`, `*.log`, socket, lock)
- profili browser (esclusi cache/temp pesanti)
- `~/CLAUDE.md`, `~/.claude/` (config, skills, settings — **escluso** materiale sensibile, vedi sotto)
- crontab utente (`crontab -l`)
- preferenze generiche elencate nel manifest

### 2. `secrets.tar.enc`
Materiale sensibile — **stessa passphrase**, file separato, restore esplicito, permessi `600`:
- `~/.ssh/`
- `~/.gnupg/`
- token/credenziali note (`~/.config/gcloud` credenziali, `~/.netrc`, ecc.)
- file locali sensibili trovati nelle repo (vedi sezione Repo): `.env`, `*.key`, `*secret*`

### 3. `repos.manifest.json` (+ `repo-localfiles.tar.enc`)
Per ogni repo clonata sotto i path scansionati (default `~/code`):
- path esatto, URL remote(s), branch corrente
- file **non tracciati** non-sensibili (es. `CLAUDE.md`) -> `repo-localfiles.tar.enc`
- file non tracciati sensibili (`.env`, ecc.) -> confluiscono in `secrets.tar.enc`

Restore repos: ri-clona ogni repo nella **stessa identica posizione**, fa checkout del
branch, poi ridepone i file locali. Niente `.git`/codice nel bucket (vive nei remote).

### 4. `packages.txt`
Lista pacchetti rilevata per distro:
- Arch/Manjaro: `pacman -Qqe`
- Debian/Ubuntu: `apt-mark showmanual`
- Fedora: `dnf repoquery --userinstalled`
- universale: `flatpak list --app --columns=application`

Al restore: rigenera il comando di reinstallazione per la distro **target** e chiede
conferma esplicita prima di eseguire (mai auto-install silenzioso).

## Manifest interno

Una sezione `INCLUDE`/`EXCLUDE`/`SECRET_PATTERNS` in cima allo script definisce cosa
catturare. Facile da estendere senza toccare la logica.

## Cifratura

- **`openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt`** con passphrase.
  Scelto al posto di `age` perché `age` con passphrase richiede obbligatoriamente
  un TTY e non è pilotabile in modo non-interattivo (verificato: fallisce da pipe
  stdin e da env). openssl è ubiquo, scriptabile al 100% e di sicurezza equivalente.
- Passphrase fornita non-interattivamente via `-pass stdin`; archivi: `*.tar.enc`.
- Stessa passphrase per dotfiles e secrets (richiesta utente), archivi comunque separati.
- La passphrase non viene mai salvata; chiesta interattivamente con `read -rs`
  (o via env `CONFSYNC_PASSPHRASE` per test/automazione, sconsigliato).

## Bucket

Da creare su progetto `il-tuo-progetto-gcp` con account `tua.email@example.com`:

- Nome: `gs://il-tuo-bucket`
- Location: `europe-west1` (region singola, matcha il progetto, più economica del multi-region)
- Storage class default: **Nearline** (backup letti raramente — vedi sezione costi)
- **Uniform bucket-level access** abilitato
- **Public access prevention = enforced**
- **Object versioning = ON** (recupero di versioni precedenti)
- Lifecycle: mantiene le ultime N versioni non-correnti, elimina quelle più vecchie di
  X giorni (default configurabile, es. 90gg)

Layout oggetti:
```
gs://il-tuo-bucket/<hostname>/<timestamp>/dotfiles.tar.enc
                                                     /secrets.tar.enc
                                                     /repo-localfiles.tar.enc
                                                     /repos.manifest.json
                                                     /packages.txt
                                                     /MANIFEST.txt   (indice + checksum sha256)
gs://il-tuo-bucket/<hostname>/latest -> puntatore all'ultimo timestamp
```

## Minimizzazione costi di storage

Obiettivo: tenere il costo del bucket quasi a zero (i backup si scrivono spesso, si
leggono solo in caso di disastro).

- **Compressione forte prima della cifratura**: `tar | zstd -19` (fallback `gzip -9`).
  `age` non comprime, quindi si comprime a monte. Riduce drasticamente i byte stoccati.
- **Dedup per contenuto**: lo script calcola lo SHA256 dell'archivio compresso *prima*
  della cifratura; se identico all'ultimo backup per quell'host, **non ri-uploada** —
  aggiorna solo il puntatore `latest`. Evita versioni duplicate inutili.
- **Storage class Nearline** come default del bucket (letture rare). Opzione
  `--cold` per usare **Coldline/Archive** se i backup sono molto sporadici.
  Nota: minimo di permanenza (Nearline 30gg, Coldline 90gg, Archive 365gg) — la
  lifecycle è tarata per non cancellare prima di quei minimi ed evitare early-deletion fee.
- **Single region** `europe-west1` (più economica del multi-region).
- **Lifecycle aggressiva**: mantiene solo le ultime N versioni non-correnti (default 5)
  ed elimina le più vecchie oltre X giorni (default 90), così lo storico non cresce
  illimitato.
- I file enormi/rigenerabili (cache browser, `.git`, build artifact) sono già esclusi
  dal manifest: non finiscono mai nel bucket.

## Restore seamless cross-distro

Macchina nuova/rotta:
```
# 1. bootstrap: lo script rileva mancanza di openssl/gcloud e guida l'installazione
# 2. copia lo script (da git o curl)
gcloud auth login           # account dinova
confsync restore            # chiede passphrase, ripristina dotfiles
confsync restore --secrets  # ripristina chiavi (permessi 600)
confsync restore --repos    # ri-clona repo nella stessa posizione
confsync restore --packages # mostra/chiede reinstallazione pacchetti per la distro target
```
Lo script rileva la distro target (`/etc/os-release`) e adatta path/comandi pacchetti.

## Error handling

- Verifica preliminare dipendenze (`age`, `gsutil`/`gcloud`, `tar`) con messaggi chiari.
- Verifica autenticazione gcloud e accesso bucket prima di operare.
- Checksum SHA256 in `MANIFEST.txt`; restore verifica integrità prima di estrarre.
- Operazioni distruttive (overwrite dotfiles, reinstall pacchetti) chiedono conferma o
  supportano `--dry-run`.
- `set -euo pipefail`, cleanup dei file temporanei via `trap` (mai temp in chiaro persistenti).

## Testing

- Test in sandbox: backup verso un bucket/prefix di test, restore in `$HOME` fittizia
  (`HOME=/tmp/confsync-test`), verifica round-trip e checksum.
- Verifica che `secrets.tar.enc` non sia decifrabile senza passphrase.
- Verifica permessi `600` sui secret ripristinati.
- Lint con `shellcheck`.

## Implementazione

Scrittura dello script delegata a **opencode** (manovalanza), orchestrata e
rivista/testata da Claude Code. Bucket creato via `gcloud`/`gsutil`.

## Fuori scope (YAGNI)

- Backup di `/etc` o config di sistema (poco portabile, rigenerabile).
- Tarball integrale delle repo con storia git.
- Backup automatico schedulato (eventuale fase 2 con cronjob).
- GUI.
