#!/usr/bin/env bash
# qbit-progress.sh — progresso de download do qBittorrent no Telegram (1 msg EDITADA por torrent).
#
# Rodado por timer systemd (a cada ~1 min). Para cada torrent BAIXANDO manda/edita UMA
# mensagem "⬇️ NN% · X MB/s · faltam ETA · «nome»"; ao chegar a 100% edita pra "✅ 100%"
# e para (remove do tracking). Nada baixando = nenhuma mensagem (sem spam).
#
# Estado: ~/.local/state/qbit-progress/track  (linhas: <hash>\t<message_id>\t<sig>)
# Config: ~/.config/tg-dl/qbit-cred (qBit) · ~/.config/tg-dl/token (bot) · ~/.config/tg-dl/owner (chat_id)
#
# Teste: QBIT_JSON_FILE=arq.json  (usa esse JSON em vez do qBit ao vivo)
#        TG_DL_SEND_LOG=log.txt    (loga as chamadas em vez de mandar no Telegram)
set -u
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

CRED="${QBIT_CRED_FILE:-/home/bia/.config/tg-dl/qbit-cred}"
TOKEN_FILE="${TG_DL_TOKEN_FILE:-/home/bia/.config/tg-dl/token}"
OWNER_FILE="${TG_DL_OWNER_FILE:-/home/bia/.config/tg-dl/owner}"
STATE="${QBIT_PROGRESS_DIR:-/home/bia/.local/state/qbit-progress}"
TRACK="$STATE/track"
mkdir -p "$STATE"

TOKEN="${TG_DL_TOKEN:-$(cat "$TOKEN_FILE" 2>/dev/null)}"
CHAT="${TG_DL_OWNER:-$(cat "$OWNER_FILE" 2>/dev/null)}"
# em modo dry-run (TG_DL_SEND_LOG) token/owner não são obrigatórios
if [ -z "${TG_DL_SEND_LOG:-}" ]; then
  [ -z "$TOKEN" ] && { echo "ERR sem token do bot ($TOKEN_FILE)" >&2; exit 4; }
  [ -z "$CHAT" ]  && { echo "ERR sem owner chat_id ($OWNER_FILE)" >&2; exit 5; }
fi

# --- obtém o JSON dos torrents (ao vivo, ou de arquivo p/ teste) ---
if [ -n "${QBIT_JSON_FILE:-}" ]; then
  J="$(cat "$QBIT_JSON_FILE")"
else
  QBIT_URL="http://localhost:8181"; QBIT_USER="admin"; QBIT_PASS=""
  # shellcheck disable=SC1090
  [ -f "$CRED" ] && . "$CRED"
  [ -z "$QBIT_PASS" ] && { echo "ERR sem qbit-cred ($CRED)" >&2; exit 3; }
  C="$(mktemp)"; trap 'rm -f "$C"' EXIT
  curl -s -c "$C" -X POST "$QBIT_URL/api/v2/auth/login" \
    --data-urlencode "username=$QBIT_USER" --data-urlencode "password=$QBIT_PASS" >/dev/null
  J="$(curl -s -b "$C" "$QBIT_URL/api/v2/torrents/info")"
fi
[ -z "$J" ] && { echo "ERR sem resposta do qBit" >&2; exit 1; }

TMPJ="$(mktemp)"; printf '%s' "$J" >"$TMPJ"
TG_API="${TG_API:-https://api.telegram.org}" \
TG_DL_SEND_LOG="${TG_DL_SEND_LOG:-}" \
python3 - "$TRACK" "$TMPJ" "$TOKEN" "$CHAT" <<'PY'
import json, sys, os, urllib.request, urllib.parse, hashlib

track_file, jf, token, chat = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
api = os.environ.get("TG_API", "https://api.telegram.org")
dry = os.environ.get("TG_DL_SEND_LOG") or ""

data = json.load(open(jf))

# estado: hash -> {"mid": message_id, "sig": assinatura do último texto}
track = {}
if os.path.exists(track_file):
    for ln in open(track_file):
        p = ln.rstrip("\n").split("\t")
        if len(p) >= 2:
            track[p[0]] = {"mid": p[1], "sig": p[2] if len(p) > 2 else ""}

def h_speed(b):
    b = float(b or 0)
    if b >= 1048576: return f"{b/1048576:.1f} MB/s"
    if b >= 1024:    return f"{b/1024:.0f} KB/s"
    return f"{b:.0f} B/s"

def h_eta(s):
    s = int(s or 0)
    if s <= 0 or s >= 8640000: return "—"
    h, r = divmod(s, 3600); m, sec = divmod(r, 60)
    if h: return f"{h}h{m:02d}m"
    if m: return f"{m}min"
    return f"{sec}s"

DL_STATES = {"downloading", "forcedDL", "metaDL", "stalledDL",
             "checkingDL", "queuedDL", "allocating", "checkingResumeData"}
EMOJI = {"downloading": "⬇️", "forcedDL": "⬇️", "metaDL": "🧲", "stalledDL": "⏳",
         "checkingDL": "🔎", "queuedDL": "🕒", "allocating": "💾", "checkingResumeData": "🔎"}

def tg(method, params):
    if dry:
        with open(dry, "a") as f:
            f.write(f">>> {method} {json.dumps(params, ensure_ascii=False)}\n")
        # devolve um message_id fake estável p/ o fluxo de teste
        seed = (params.get("text", "") + str(params.get("chat_id", ""))).encode()
        return {"ok": True, "result": {"message_id": int(hashlib.sha1(seed).hexdigest()[:6], 16)}}
    url = f"{api}/bot{token}/{method}"
    body = urllib.parse.urlencode(params).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, body), timeout=25) as r:
            return json.load(r)
    except Exception as e:
        return {"ok": False, "error": str(e)}

def line(t):
    st = t.get("state", "")
    pct = int((t.get("progress") or 0) * 100)
    name = t.get("name", "?")
    spd = int(t.get("dlspeed") or 0)
    if st == "stalledDL":
        mid = f"⏳ {pct}% · sem peers no momento"
    elif st == "metaDL":
        mid = f"🧲 {pct}% · obtendo metadados"
    elif st in ("checkingDL", "checkingResumeData"):
        mid = f"🔎 {pct}% · verificando"
    elif st == "queuedDL":
        mid = f"🕒 {pct}% · na fila"
    else:
        mid = f"{EMOJI.get(st, '⬇️')} {pct}% · {h_speed(spd)} · faltam {h_eta(t.get('eta'))}"
    return f"{mid}\n«{name}»", f"{st}:{pct}:{spd // 1024}"

newtrack = {}
for t in data:
    h = t.get("hash")
    if not h:
        continue
    prog = t.get("progress") or 0
    st = t.get("state", "")

    if prog >= 1.0:
        # concluiu: se estava sendo acompanhado, fecha em ✅ e NÃO re-adiciona (para)
        if h in track:
            tg("editMessageText", {"chat_id": chat, "message_id": track[h]["mid"],
                                   "text": f"✅ 100% — «{t.get('name', '?')}»"})
        continue

    if st not in DL_STATES:
        # pausado/erro/seed incompleto: mantém tracking se já existia, sem editar
        if h in track:
            newtrack[h] = track[h]
        continue

    txt, sig = line(t)
    if h in track:
        if track[h].get("sig") != sig:            # só edita se algo mudou
            tg("editMessageText", {"chat_id": chat, "message_id": track[h]["mid"], "text": txt})
        newtrack[h] = {"mid": track[h]["mid"], "sig": sig}
    else:
        r = tg("sendMessage", {"chat_id": chat, "text": txt})
        if r.get("ok"):
            newtrack[h] = {"mid": str(r["result"]["message_id"]), "sig": sig}

# torrents removidos não entram em newtrack -> tracking limpo automaticamente
with open(track_file, "w") as f:
    for h, v in newtrack.items():
        f.write(f"{h}\t{v['mid']}\t{v.get('sig', '')}\n")
PY
rm -f "$TMPJ"
