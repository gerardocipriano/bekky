# bekky

Backup/restore cifrato delle config OS su GCS. Logica in `confsync`, liste in
`lib/manifest.sh`, test in `test/confsync.bats` (`bats test/confsync.bats`,
`shellcheck confsync lib/*.sh scripts/*.sh`).

## PC nuovo

Se l'utente dice che è sul PC nuovo e vuole il restore ("prendi il backup",
"riconfigurami tutto"), esegui `docs/RESTORE-PLAYBOOK.md` dall'inizio alla fine
senza chiedere conferme per le singole fasi. Il playbook dice quali sono le poche
eccezioni. Se `~/.config/confsync/restore-status.md` esiste, riprendi da lì.

Se `~/.config/confsync/passphrase` o il login gcloud mancano, l'utente non ha
lanciato il bootstrap: digli di eseguire
`! curl -fsSL https://raw.githubusercontent.com/gerardocipriano/bekky/main/scripts/bootstrap.sh | bash`.

## Lezioni

- I `--exclude` di GNU tar matchano su qualunque suffisso del path: un pattern
  pensato per i dotfiles toglie lo stesso file anche dall'archivio secrets.
  Gli exclude validi solo per i dotfiles vanno in `DOTFILES_ONLY_EXCLUDES`.
- Gli output dell'inventario devono essere deterministici (ordinati, niente
  timestamp), altrimenti il dedup via `BUNDLE.sha` non scatta mai.
- gsutil da cron fallisce con `ReauthUnattendedError` quando scade il reauth
  Workspace: serve un `gcloud auth login` interattivo.
