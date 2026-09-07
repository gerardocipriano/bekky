#!/usr/bin/env bash
# Passi post-restore che vivono FUORI da $HOME e quindi non possono essere
# coperti dal backup (unit systemd, servizi utente). Da lanciare una volta
# sul nuovo sistema, DOPO `confsync restore [--secrets --repos --packages]`.
# Idempotente: rilanciarlo non fa danni.
set -uo pipefail

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
skip() { printf '  \033[33m-\033[0m %s\n' "$1"; }

echo ">> post-restore: passi di sistema non coperti dal backup"

# 1. paccache.timer — pulizia settimanale della cache pacman (Arch/Manjaro)
if command -v pacman >/dev/null; then
  if ! command -v paccache >/dev/null; then
    sudo pacman -S --needed --noconfirm pacman-contrib
  fi
  sudo systemctl enable --now paccache.timer \
    && ok "paccache.timer attivo (pulizia cache pacman settimanale)" \
    || skip "paccache.timer non abilitato"
else
  skip "non-Arch: paccache saltato"
fi

# 2. baloo — l'indexer KDE resta disabilitato via ~/.config/baloofilerc
#    (ripristinato dai dotfiles), ma se un processo è già partito lo fermiamo
if command -v balooctl6 >/dev/null; then
  balooctl6 suspend >/dev/null 2>&1
  balooctl6 disable >/dev/null 2>&1
  ok "baloo disabilitato"
else
  skip "baloo non presente"
fi

# 3. cron settimanale di bekky (crontab non è in $HOME)
CRON_LINE="0 13 * * 3 $HOME/code/misc/bekky/scripts/bekky-cron.sh"
if ! command -v crontab >/dev/null; then
  skip "crontab assente: installa il pacchetto cron, poi rilancia questo script"
elif crontab -l 2>/dev/null | grep -qF "bekky-cron.sh"; then
  skip "cron bekky già presente"
else
  ( crontab -l 2>/dev/null; echo "$CRON_LINE" ) | crontab - \
    && ok "cron bekky installato (mercoledì 13:00)"
fi

# 4. unit utente ripristinate che puntano a eseguibili inesistenti. Capita per
#    venv Python, toolchain nvm e binari esclusi dal backup: systemd le carica
#    e poi falliscono a ogni avvio, in silenzio.
UNITDIR="$HOME/.config/systemd/user"
if [ -d "$UNITDIR" ]; then
  broken=0
  while read -r exe; do
    [ -n "$exe" ] || continue
    [ -x "${exe/#\%h/$HOME}" ] || { printf '  \033[33m!\033[0m ExecStart mancante: %s\n' "$exe"; broken=$((broken+1)); }
  done < <(grep -h '^ExecStart=' "$UNITDIR"/*.service 2>/dev/null | sed 's/^ExecStart=//' | awk '{print $1}' | sort -u)
  [ "$broken" -eq 0 ] && ok "unit utente: tutti gli ExecStart risolvibili" \
    || skip "$broken eseguibili da ricreare (venv, nvm, binari non backuppati) prima di abilitare le unit"
fi

# 5. username diverso da quello di origine: i path assoluti nelle config
#    ripristinate vanno riscritti prima di abilitare qualsiasi unit.
ORIGIN="$HOME/.config/confsync/origin.home"
if [ -r "$ORIGIN" ] && [ "$(cat "$ORIGIN")" != "$HOME" ]; then
  skip "HOME cambiato ($(cat "$ORIGIN") -> $HOME): lancia ./scripts/rehome.sh --apply"
fi

# 6. promemoria manuali
if command -v apt-get >/dev/null; then
  ONEPW="scaricare il .deb da 1password.com e aggiungere il repo apt"
else
  ONEPW="yay -S 1password 1password-cli"
fi
cat <<EOF

Passi manuali rimanenti:
  - 1Password: installare app + CLI ($ONEPW), attivare in Settings → Developer
    sia "Integrate with CLI" sia "Use the SSH agent"; le chiavi SSH e la
    passphrase bekky sono nel vault
  - gcloud: \`gcloud auth login\` per ogni account (le config dei profili sono
    già ripristinate in ~/.config/gcloud, mancano solo i token)
  - binari esclusi dal backup, da riscaricare: uv, rclone, magika, iii, rtk, deno
  - packages.txt viene da un'altra distro: usalo come lista di riferimento per
    un triage manuale, non passarlo in blocco al package manager
  - passphrase bekky: verificare ~/.config/confsync/passphrase (chmod 600)
EOF
