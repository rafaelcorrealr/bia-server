#!/usr/bin/env bash
# qbit-todoist-poll.sh — cria uma tarefa no Todoist p/ cada torrent recém-concluído no qBittorrent.
#
# Rodado por timer systemd (a cada ~3 min). Guarda os hashes já vistos em
#   ~/.local/state/qbit-todoist/seen
# Na PRIMEIRA execução faz só o baseline (registra os já concluídos SEM criar tarefa),
# pra não spammar tudo que já está pronto. Idempotente (não duplica).
#
# Credenciais do qBit em ~/.config/tg-dl/qbit-cred (600). Usa o helper todoist-task.sh.
set -u
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

CRED="${QBIT_CRED_FILE:-/home/bia/.config/tg-dl/qbit-cred}"
STATE="${QBIT_STATE_DIR:-/home/bia/.local/state/qbit-todoist}"
SEEN="$STATE/seen"
HOSTDL="${QBIT_HOST_DL:-/mnt/Hi0/Downloads}"          # /downloads (container) → host
TODOIST="${TODOIST_BIN:-/home/bia/.local/bin/todoist-task.sh}"
mkdir -p "$STATE"

QBIT_URL="http://localhost:8181"; QBIT_USER="admin"; QBIT_PASS=""
# shellcheck disable=SC1090
[ -f "$CRED" ] && . "$CRED"
[ -z "$QBIT_PASS" ] && { echo "ERR sem qbit-cred ($CRED)" >&2; exit 3; }

C="$(mktemp)"; trap 'rm -f "$C"' EXIT
curl -s -c "$C" -X POST "$QBIT_URL/api/v2/auth/login" \
  --data-urlencode "username=$QBIT_USER" --data-urlencode "password=$QBIT_PASS" >/dev/null
J="$(curl -s -b "$C" "$QBIT_URL/api/v2/torrents/info")"
[ -z "$J" ] && { echo "ERR sem resposta do qBit" >&2; exit 1; }

first=0; [ -f "$SEEN" ] || first=1

TMPJ="$(mktemp)"; printf '%s' "$J" >"$TMPJ"
python3 - "$SEEN" "$first" "$HOSTDL" "$TODOIST" "$TMPJ" <<'PY'
import json, sys, os, subprocess
seenfile, first, hostdl, todoist, jf = sys.argv[1], sys.argv[2] == '1', sys.argv[3], sys.argv[4], sys.argv[5]
data = json.load(open(jf))
seen = set(open(seenfile).read().split()) if os.path.exists(seenfile) else set()

def human(b):
    b = float(b or 0)
    for u in ('B', 'K', 'M', 'G', 'T'):
        if b < 1024: return f"{b:.0f}{u}"
        b /= 1024
    return f"{b:.0f}P"

new = []
for t in data:
    if t.get('progress', 0) >= 1.0:
        h = t['hash']
        if h not in seen:
            seen.add(h)
            new.append(t)

open(seenfile, 'w').write('\n'.join(sorted(seen)) + '\n')   # persiste hashes vistos

if first:            # baseline: registrou os concluídos, mas não cria tarefas
    sys.exit(0)

for t in new:
    name = t['name']
    cp = t.get('content_path') or (t.get('save_path', '') + '/' + name)
    hp = cp.replace('/downloads', hostdl, 1) if cp.startswith('/downloads') else cp
    desc = f"Origem: Torrent (qBittorrent)\nArquivo: {hp}\nTamanho: {human(t.get('total_size') or t.get('size'))}"
    subprocess.run([todoist, f"\U0001F4E5 Organizar: «{name}»", desc],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
PY
rm -f "$TMPJ"
