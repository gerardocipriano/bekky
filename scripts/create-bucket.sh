#!/usr/bin/env bash
set -euo pipefail

# Carica config locale se presente (non versionata)
CONFSYNC_CONFIG="${CONFSYNC_CONFIG:-$HOME/.config/confsync/config}"
# shellcheck disable=SC1090
[ -f "$CONFSYNC_CONFIG" ] && . "$CONFSYNC_CONFIG"

# Tutti i parametri vengono da env/config — nessun dato hardcoded nel repo pubblico.
PROJECT="${CONFSYNC_PROJECT:?imposta CONFSYNC_PROJECT (es. in $CONFSYNC_CONFIG)}"
BUCKET="${CONFSYNC_BUCKET:?imposta CONFSYNC_BUCKET (es. gs://il-tuo-bucket)}"
ACCOUNT="${CONFSYNC_ACCOUNT:-$(gcloud config get-value account 2>/dev/null)}"
LOCATION="${CONFSYNC_LOCATION:-europe-west1}"
CLASS="${CONFSYNC_STORAGE_CLASS:-NEARLINE}"

echo ">> Account: $ACCOUNT  Project: $PROJECT"
[ -n "$ACCOUNT" ] && gcloud config set account "$ACCOUNT" >/dev/null

if gsutil ls -b -p "$PROJECT" "$BUCKET" >/dev/null 2>&1; then
  echo ">> Bucket già esistente: $BUCKET"
else
  echo ">> Creo bucket $BUCKET ($CLASS, $LOCATION)"
  gcloud storage buckets create "$BUCKET" \
    --project="$PROJECT" \
    --location="$LOCATION" \
    --default-storage-class="$CLASS" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

echo ">> Abilito versioning"
gcloud storage buckets update "$BUCKET" --versioning

echo ">> Applico lifecycle (max 5 versioni non-correnti, elimina >90gg)"
LC="$(mktemp)"
cat >"$LC" <<'JSON'
{
  "rule": [
    { "action": {"type": "Delete"},
      "condition": {"daysSinceNoncurrentTime": 90} },
    { "action": {"type": "Delete"},
      "condition": {"numNewerVersions": 5} }
  ]
}
JSON
gcloud storage buckets update "$BUCKET" --lifecycle-file="$LC"
rm -f "$LC"

echo ">> Fatto. Config attuale:"
gcloud storage buckets describe "$BUCKET" \
  --format="yaml(storageClass,location,versioning,iamConfiguration)"
