#!/bin/bash
set -euo pipefail

MOUNT_POINT="/mnt/Se0"
CONTAINERS=("jellyfin" "nextcloud" "big-bear-nextcloud-cron-1")

if mountpoint -q "$MOUNT_POINT"; then
    exit 0
fi

logger -t se0-recovery "Se0 not mounted at boot, attempting recovery..."
mount "$MOUNT_POINT"
logger -t se0-recovery "Se0 mounted successfully"

sleep 3

for container in "${CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -qx "$container"; then
        logger -t se0-recovery "Restarting $container"
        docker restart "$container"
    fi
done

logger -t se0-recovery "Recovery complete"
