#!/usr/bin/env bash
# Espelha os transcripts do Claude Code (Bia) para o staging do Syncthing,
# de onde a pasta "claude-bia" (send-only) leva até a Anna, alimentando o
# claude_ai_usage_widget (tracker local de tokens/custo). Roda a cada 30min
# via systemd timer (sync-claude-transcripts.timer).
#
# IMPORTANTE: sincronizar SÓ projects/ — nunca ~/.claude inteiro, pois
# .credentials.json (token OAuth) não pode viajar.
set -euo pipefail

SRC="/home/bia/.claude/projects/"
DST="/DATA/AppData/big-bear-syncthing/data/claude-bia/"

log() { echo "[$(date '+%F %T')] $*"; }

log "=== sync-claude-transcripts iniciando ==="
rsync -a --delete "$SRC" "$DST"
log "=== sync-claude-transcripts concluído ==="
