#!/usr/bin/env bash
# Backup do banco PostgreSQL do Nextcloud com restic.
# pg_dump via docker exec -> restic --stdin -> repos local (Se0) e externo (Sa2).
set -euo pipefail

ENV_FILE=/home/bia/homelab/compose/nextcloud/.env
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[$(date '+%F %T')] ERRO: $ENV_FILE nao encontrado" >&2
  exit 1
fi
# shellcheck source=/dev/null
set -a; source "$ENV_FILE"; set +a

export RESTIC_PASSWORD_FILE=/home/bia/.config/restic/cofre.pw
export RESTIC_FROM_PASSWORD_FILE=/home/bia/.config/restic/cofre.pw

LOCAL=/mnt/Se0/20-Backups/restic-cofre
EXT=/mnt/Sa2/Backup/restic-cofre
RETENCAO=(--keep-daily 7 --keep-weekly 4 --keep-monthly 6)

log() { echo "[$(date '+%F %T')] $*"; }

log "=== backup-nextcloud-db iniciando ==="

if ! mountpoint -q /mnt/Se0; then
  log "ERRO: /mnt/Se0 nao montado — abortando"
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q '^db-nextcloud$'; then
  log "ERRO: container db-nextcloud nao esta rodando — abortando"
  exit 1
fi

# Dump + backup incremental -> repo local
docker exec -e PGPASSWORD="${NEXTCLOUD_DB_PASSWORD}" db-nextcloud \
  pg_dump -U "${NEXTCLOUD_DB_USER}" "${NEXTCLOUD_DB_NAME}" \
  | restic -r "$LOCAL" backup --stdin --stdin-filename nextcloud-db.sql --tag nextcloud-db

# Retencao + prune (apenas snapshots nextcloud-db)
restic -r "$LOCAL" forget --tag nextcloud-db "${RETENCAO[@]}" --prune

# Espelhar para o repo externo (Sa2), se montado
if mountpoint -q /mnt/Sa2; then
  restic -r "$EXT" copy --from-repo "$LOCAL" --tag nextcloud-db
  restic -r "$EXT" forget --tag nextcloud-db "${RETENCAO[@]}" --prune
else
  log "AVISO: /mnt/Sa2 nao montado — pulei o espelho externo"
fi

log "=== backup-nextcloud-db concluido ==="
