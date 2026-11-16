#!/bin/bash
# Backup diário do MongoDB Atlas para o container aprovia-backups (Blob Storage).
# Instalado pelo cloud-init da VM em /usr/local/bin/aprovia-backup-mongodb e agendado em /etc/cron.d/aprovia-backup.
# Lê URL_CONNECTION_MONGODB e AZURE_STORAGE_CONNECTION_STRING do arquivo de ambiente da API.
# A política de ciclo de vida do Terraform move os dumps para Cool (7 dias), Archive (30) e apaga em 90.

set -euo pipefail

API_DIR="${API_DIR:-/opt/aprovia/api}"
ENV_FILE="${ENV_FILE:-/etc/aprovia/api.env}"
CONTAINER="${BACKUP_CONTAINER:-aprovia-backups}"
DATA=$(date -u +%Y-%m-%dT%H%M%SZ)
ARQUIVO="/tmp/mongodb-$DATA.archive.gz"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

echo "[$(date -Is)] Iniciando dump do MongoDB"
mongodump --uri="$URL_CONNECTION_MONGODB" --archive="$ARQUIVO" --gzip

echo "[$(date -Is)] Enviando $(du -h "$ARQUIVO" | cut -f1) para $CONTAINER/mongodb/$DATA.archive.gz"
"$API_DIR/venv/bin/python" - "$ARQUIVO" "$CONTAINER" "mongodb/$DATA.archive.gz" <<'PY'
import os, sys
from azure.storage.blob import BlobServiceClient

arquivo, container, destino = sys.argv[1:4]
servico = BlobServiceClient.from_connection_string(os.environ["AZURE_STORAGE_CONNECTION_STRING"])
with open(arquivo, "rb") as dados:
    servico.get_blob_client(container, destino).upload_blob(dados, overwrite=False)
PY

rm -f "$ARQUIVO"
echo "[$(date -Is)] Backup concluído"
