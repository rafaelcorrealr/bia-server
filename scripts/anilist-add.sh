#!/usr/bin/env bash
# anilist-add.sh — adiciona/atualiza um anime (ou mangá) na SUA lista do AniList.
#
# Uso:  anilist-add.sh [opções] "<título ou busca>"
#       anilist-add.sh --id 154587 --status completo
#
# Opções:
#   --id <n>           usa o mediaId direto (pula a busca — mais confiável)
#   --status <s>       quero|planning · assistindo|watching · completo|completed
#                      · pausado|paused · desisti|dropped · revendo|repeating   (default: quero)
#   --progress <n>     episódios (anime) ou capítulos (mangá) já vistos
#   --list <nome>      adiciona a uma lista custom sua (ex.: "Baixado"); vírgula p/ várias
#   --score <f>        nota (na escala da sua conta)
#   --type ANIME|MANGA (default ANIME)
#   --dry              só RESOLVE e mostra, NÃO grava (não precisa de token)
#
# Token OAuth do AniList em ~/.config/tg-dl/anilist-token (600).  Log: ~/.local/state/tg-dl/anilist.log
# ⚠️ A API fica atrás do Cloudflare → sempre manda User-Agent de navegador (senão dá 403).
set -u
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

TOKEN_FILE="${ANILIST_TOKEN_FILE:-/home/bia/.config/tg-dl/anilist-token}"
API="${ANILIST_API:-https://graphql.anilist.co}"
LOG="${ANILIST_LOG:-/home/bia/.local/state/tg-dl/anilist.log}"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36"

MID=""; STATUS="quero"; PROGRESS=""; SCORE=""; MTYPE="ANIME"; DRY=""; SEARCH=""; LISTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --id)       MID="${2:-}"; shift 2;;
    --status)   STATUS="${2:-}"; shift 2;;
    --progress) PROGRESS="${2:-}"; shift 2;;
    --list)     LISTS="${2:-}"; shift 2;;
    --score)    SCORE="${2:-}"; shift 2;;
    --type)     MTYPE="${2:-}"; shift 2;;
    --dry)      DRY=1; shift;;
    --)         shift; SEARCH="$*"; break;;
    -*)         echo "opção desconhecida: $1" >&2; exit 2;;
    *)          SEARCH="$1"; shift;;
  esac
done

# normaliza status -> enum do AniList
case "$(printf '%s' "$STATUS" | tr 'A-Z' 'a-z')" in
  quero|planning|plan)          STATUS="PLANNING";;
  assistindo|watching|vendo)    STATUS="CURRENT";;
  completo|completed|assisti)   STATUS="COMPLETED";;
  pausado|paused)               STATUS="PAUSED";;
  desisti|dropped|larguei)      STATUS="DROPPED";;
  revendo|rewatch|repeating)    STATUS="REPEATING";;
  *) echo "status inválido: $STATUS" >&2; exit 2;;
esac
MTYPE="$(printf '%s' "$MTYPE" | tr 'a-z' 'A-Z')"
case "$MTYPE" in ANIME|MANGA) ;; *) echo "type inválido: $MTYPE" >&2; exit 2;; esac
[ -z "$MID" ] && [ -z "$SEARCH" ] && { echo "ERR: informe um título ou --id" >&2; exit 2; }

tok=""
if [ -z "$DRY" ]; then
  tok="$(tr -d '[:space:]' <"$TOKEN_FILE" 2>/dev/null)"
  [ -z "$tok" ] && { echo "ERR sem token do AniList ($TOKEN_FILE) — gere e salve lá (600)" >&2; exit 3; }
fi

out="$(ANILIST_UA="$UA" ANILIST_LISTS="$LISTS" python3 - "$API" "$tok" "$MTYPE" "$STATUS" "$MID" "$PROGRESS" "$SCORE" "${DRY:-}" "$SEARCH" <<'PY'
import json, sys, os, urllib.request, urllib.error
api, tok, mtype, status, mid, progress, score, dry, search = sys.argv[1:10]
ua = os.environ.get("ANILIST_UA", "Mozilla/5.0")
lists = os.environ.get("ANILIST_LISTS", "").strip()

def gql(query, variables, auth=False):
    body = json.dumps({"query": query, "variables": variables}).encode()
    hdr = {"Content-Type": "application/json", "Accept": "application/json", "User-Agent": ua}
    if auth and tok:
        hdr["Authorization"] = "Bearer " + tok
    req = urllib.request.Request(api, body, hdr)
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        try: return json.load(e)
        except Exception: return {"errors": [{"message": "HTTP %s" % e.code}]}
    except Exception as e:
        return {"errors": [{"message": str(e)}]}

title = None
if not mid:
    SQ = "query($s:String,$t:MediaType){Media(search:$s,type:$t){id title{romaji english}}}"
    d = gql(SQ, {"s": search, "t": mtype})
    m = (d.get("data") or {}).get("Media")
    if not m:
        msg = (d.get("errors") or [{}])[0].get("message", "")
        print("ERRO: não achei '%s' no AniList %s" % (search, ("(%s)" % msg) if msg else ""))
        sys.exit(4)
    mid = str(m["id"]); title = m["title"]["english"] or m["title"]["romaji"]
elif dry:
    d = gql("query($id:Int,$t:MediaType){Media(id:$id,type:$t){title{romaji english}}}", {"id": int(mid), "t": mtype})
    m = (d.get("data") or {}).get("Media")
    if m: title = m["title"]["english"] or m["title"]["romaji"]

mid = int(mid)
if dry:
    print("DRY: %s (id=%d) → status=%s%s%s" % (title or "?", mid, status,
          (" progress=%s" % progress) if progress else "",
          (" lists=[%s]" % lists) if lists else ""))
    sys.exit(0)

# mutation SaveMediaListEntry — só inclui os campos que vieram
vardef = ["$id:Int", "$status:MediaListStatus"]
args   = ["mediaId:$id", "status:$status"]
variables = {"id": mid, "status": status}
if progress:
    vardef.append("$progress:Int"); args.append("progress:$progress"); variables["progress"] = int(progress)
if score:
    vardef.append("$score:Float"); args.append("score:$score"); variables["score"] = float(score)
if lists:
    names = [x.strip() for x in lists.split(",") if x.strip()]
    vardef.append("$lists:[String]"); args.append("customLists:$lists"); variables["lists"] = names
MU = "mutation(%s){SaveMediaListEntry(%s){status progress customLists media{title{romaji english}}}}" % (",".join(vardef), ",".join(args))
d = gql(MU, variables, auth=True)
if d.get("errors"):
    print("ERRO AniList: %s" % d["errors"][0].get("message", "?")); sys.exit(1)
e = d["data"]["SaveMediaListEntry"]
t = e["media"]["title"]["english"] or e["media"]["title"]["romaji"]
cl = e.get("customLists") or {}
inlists = [k for k, v in cl.items() if v]
print("OK: %s → %s (progress %s)%s" % (t, e["status"], e["progress"],
      (" | listas: " + ", ".join(inlists)) if inlists else ""))
PY
)"
rc=$?
mkdir -p "$(dirname "$LOG")"
printf '%s  %s\n' "$(date '+%F %T')" "$out" >>"$LOG"
printf '%s\n' "$out"
exit $rc
