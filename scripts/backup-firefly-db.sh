#!/usr/bin/env bash
# Backup do banco do Firefly III (MariaDB) com restic.
# mysqldump via docker exec -> restic --stdin -> repos local (Se0) e externo (Sa2).
set -euo pipefail

ENV_FILE=/home/bia/homelab/compose/firefly/.env
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

log "=== backup-firefly-db iniciando ==="

if ! mountpoint -q /mnt/Se0; then
  log "ERRO: /mnt/Se0 nao montado — abortando"
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q '^firefly_db$'; then
  log "ERRO: container firefly_db nao esta rodando — abortando"
  exit 1
fi

# Dump + backup incremental -> repo local
docker exec firefly_db \
  mariadb-dump -u firefly -p"${FIREFLY_DB_PASSWORD}" --single-transaction firefly \
  | restic -r "$LOCAL" backup --stdin --stdin-filename firefly-db.sql --tag firefly-db

# Retencao + prune (apenas snapshots firefly-db)
restic -r "$LOCAL" forget --tag firefly-db "${RETENCAO[@]}" --prune

# Espelhar para o repo externo (Sa2), se montado
if mountpoint -q /mnt/Sa2; then
  restic -r "$EXT" copy --from-repo "$LOCAL" --tag firefly-db
  restic -r "$EXT" forget --tag firefly-db "${RETENCAO[@]}" --prune
else
  log "AVISO: /mnt/Sa2 nao montado — pulei o espelho externo"
fi

log "=== backup-firefly-db concluido ==="
