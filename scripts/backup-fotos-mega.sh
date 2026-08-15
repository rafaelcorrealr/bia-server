#!/usr/bin/env bash
# Backup das fotos pessoais (10.Pessoal/Fotos) pro MEGA via rclone — camada offsite.
# Roda diariamente via systemd timer (backup-fotos-mega.timer).
#   rclone copy (NUNCA sync): só adiciona/atualiza no MEGA, nunca apaga lá se sumir daqui —
#   protege contra deleção local acidental derrubar o backup na nuvem junto.
set -euo pipefail

SRC="/mnt/Se0/00-Arquivos/10.Pessoal/Fotos"
DEST="mega_fotos:Backup Fotos"

log() { echo "[$(date '+%F %T')] $*"; }

log "=== backup-fotos-mega iniciando ==="

if ! mountpoint -q /mnt/Se0; then
  log "ERRO: /mnt/Se0 nao montado — abortando"
  exit 1
fi

rclone copy "$SRC" "$DEST" \
  --exclude "desktop.ini" \
  --transfers 4 --checkers 4 \
  --log-level INFO

log "=== backup-fotos-mega concluido ==="
