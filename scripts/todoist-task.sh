#!/usr/bin/env bash
# todoist-task.sh — cria uma tarefa no Todoist (Inbox, etiquetas Werus+HOMELAB, venc. hoje).
#
# Uso:  todoist-task.sh <content> [description]
#
# Token da API do Todoist em ~/.config/tg-dl/todoist-token (600).
#   (Todoist → Configurações → Integrações → Desenvolvedor → API token)
# Log em ~/.local/state/tg-dl/todoist.log
#
# Sai 0 em sucesso; !=0 em erro (sem token, HTTP != 2xx). Nunca deve derrubar quem chama.
set -u
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

TOKEN_FILE="${TODOIST_TOKEN_FILE:-/home/bia/.config/tg-dl/todoist-token}"
LABELS="${TODOIST_LABELS:-Werus,HOMELAB}"   # etiquetas em CSV (padrão: Werus + HOMELAB)
DUE="${TODOIST_DUE:-today}"
API="${TODOIST_API:-https://api.todoist.com/api/v1/tasks}"   # API unificada v1 (REST v2 foi migrada)
LOG="${TODOIST_LOG:-/home/bia/.local/state/tg-dl/todoist.log}"

content="${1:-}"; desc="${2:-}"
[ -z "$content" ] && { echo "ERR sem content" >&2; exit 2; }
tok="$(tr -d '[:space:]' <"$TOKEN_FILE" 2>/dev/null)"
[ -z "$tok" ] && { echo "ERR sem token ($TOKEN_FILE)" >&2; exit 3; }

# monta o JSON de forma segura (unicode/aspas nos nomes) via python3
payload="$(python3 - "$content" "$desc" "$LABELS" "$DUE" <<'PY'
import json, sys
content, desc, labels_csv, due = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
labels = [l.strip() for l in labels_csv.split(",") if l.strip()]
t = {"content": content, "labels": labels}
if desc: t["description"] = desc
if due:  t["due_string"] = due
print(json.dumps(t, ensure_ascii=False))
PY
)"

resp="$(mktemp)"
code="$(curl -s -o "$resp" -w '%{http_code}' --max-time 25 \
  -X POST "$API" \
  -H "Authorization: Bearer $tok" \
  -H "Content-Type: application/json" \
  --data "$payload")"

mkdir -p "$(dirname "$LOG")"
printf '%s  HTTP %s  %s\n' "$(date '+%F %T')" "$code" "$content" >>"$LOG"
case "$code" in
  200|204) rm -f "$resp"; exit 0 ;;
  *) { echo "  resp: $(cat "$resp" 2>/dev/null)"; } >>"$LOG"; rm -f "$resp"
     echo "ERR Todoist HTTP $code" >&2; exit 1 ;;
esac
