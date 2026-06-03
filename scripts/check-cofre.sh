#!/usr/bin/env bash
# Verificacao de integridade dos repos restic do cofre — Camada 2.
# Roda semanalmente via systemd timer (check-cofre.timer).
set -euo pipefail

export RESTIC_PASSWORD_FILE=/home/bia/.config/restic/cofre.pw

LOCAL=/mnt/Se0/20-Backups/restic-cofre
EXT=/mnt/Sa2/Backup/restic-cofre

log() { echo "[$(date '+%F %T')] $*"; }

log "=== check-cofre: repo local ==="
restic -r "$LOCAL" check

if mountpoint -q /mnt/Sa2; then
  log "=== check-cofre: repo externo (Sa2) ==="
  restic -r "$EXT" check
else
  log "AVISO: /mnt/Sa2 nao montado — pulei check do externo"
fi

log "=== check-cofre concluido ==="
