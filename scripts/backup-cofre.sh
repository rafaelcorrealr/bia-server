#!/usr/bin/env bash
# Backup do cofre Obsidian (Second Brain) com restic — Camada 2 do plano
# "Backup e Versionamento". Roda diariamente via systemd timer (backup-cofre.timer).
#   1. backup incremental -> repo local (Se0)
#   2. retencao + prune no local
#   3. espelho para repo externo (Sa2) via restic copy, se montado
set -euo pipefail

export RESTIC_PASSWORD_FILE=/home/bia/.config/restic/cofre.pw
export RESTIC_FROM_PASSWORD_FILE=/home/bia/.config/restic/cofre.pw

LOCAL=/mnt/Se0/20-Backups/restic-cofre
EXT=/mnt/Sa2/Backup/restic-cofre
SRC="/DATA/AppData/big-bear-syncthing/data/obsidian/Second Brain"
RETENCAO=(--keep-daily 7 --keep-weekly 4 --keep-monthly 6)

log() { echo "[$(date '+%F %T')] $*"; }

log "=== backup-cofre iniciando ==="

if ! mountpoint -q /mnt/Se0; then
  log "ERRO: /mnt/Se0 nao montado — abortando"
  exit 1
fi

# 1. Backup incremental -> repo local
restic -r "$LOCAL" backup "$SRC" \
  --exclude ".stversions" --exclude ".stfolder" \
  --tag cofre

# 2. Retencao + prune no repo local
restic -r "$LOCAL" forget "${RETENCAO[@]}" --prune

# 3. Espelhar para o repo externo (Sa2), se montado
if mountpoint -q /mnt/Sa2; then
  restic -r "$EXT" copy --from-repo "$LOCAL"
  restic -r "$EXT" forget "${RETENCAO[@]}" --prune
else
  log "AVISO: /mnt/Sa2 nao montado — pulei o espelho externo"
fi

log "=== backup-cofre concluido ==="
