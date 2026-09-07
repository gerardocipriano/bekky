# Ripristino su macchina nuova (es. portatile Ubuntu)

Prerequisiti da procurarsi PRIMA (non stanno nel backup):
1. **Passphrase confsync** (senza, gli archivi `.enc` sono irrecuperabili — tienila in un password manager)
2. Accesso GCP con `gerardo.cipriano@dinova.one`

## Procedura

```bash
# 1. Dipendenze (Ubuntu). zstd non è opzionale: gli archivi sono compressi con quello.
sudo apt-get update && sudo apt-get install -y git openssl zstd cron
# google-cloud-cli: repo apt di Google (il pacchetto Ubuntu non esiste)
# https://cloud.google.com/sdk/docs/install#deb

# 2. Login gcloud con l'account personale
gcloud auth login gerardo.cipriano@dinova.one

# 3. Clona bekky
git clone git@github.com:gerardocipriano/bekky.git ~/code/misc/bekky   # o https

# 4. Config locale (bucket + host tag del VECCHIO pc, perché il nuovo ha hostname diverso)
mkdir -p ~/.config/confsync && chmod 700 ~/.config/confsync
cat > ~/.config/confsync/config <<'EOF'
export CONFSYNC_BUCKET="gs://confsync-gerardo-cipriano"
export CONFSYNC_PROJECT="formazione-gerardo-cipriano"
export CONFSYNC_ACCOUNT="gerardo.cipriano@dinova.one"
export CONFSYNC_HOST_TAG="INJ-NB-250"   # host di origine del backup da ripristinare
EOF

# 5. Passphrase (chiesta interattivamente, oppure:)
printf '%s' 'LA-TUA-PASSPHRASE' > ~/.config/confsync/passphrase && chmod 600 ~/.config/confsync/passphrase

# 6. Ripristino completo
cd ~/code/misc/bekky
./confsync restore --secrets --repos --packages
```

Cosa ottieni: dotfiles (zsh/bash + history, .config filtrato, `.claude` completo, CLAUDE.md), secrets (.ssh/.gnupg/creds gcloud, permessi 600), repo di `~/code` ri-clonate + file locali non tracciati (inclusi CLAUDE.md/.claude gitignored).

Dopo il restore lancia `./scripts/post-restore.sh`: installa il cron settimanale e stampa i passi manuali rimanenti.

Note Ubuntu:
- `packages.txt` viene dal vecchio sistema (Arch/pacman): i nomi non mappano 1:1 su apt. Il restore rileva la differenza di distro e avvisa — trattala come lista di riferimento per un triage manuale, **non** passarla in blocco ad `apt-get install`, che morirebbe al primo pacchetto inesistente.
- Le config KDE Plasma (i file `k*rc` in `~/.config`) vengono ripristinate ma su GNOME sono inerti: si possono ignorare.
- I binari precompilati (uv, rclone, magika, iii, rtk, deno) sono esclusi dal backup perché legati alla glibc della macchina di origine: vanno riscaricati.
- Dopo il restore: `chsh -s $(which zsh)`, riapri la shell, verifica `gcloud auth list`.
- Rimuovi/aggiorna `CONFSYNC_HOST_TAG` quando vuoi che il nuovo host inizi a fare i PROPRI backup con il suo hostname.
