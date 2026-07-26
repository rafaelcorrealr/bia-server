#!/usr/bin/env bash
# jellyfin-retitle.sh — Fase B: pega o título REAL do episódio no Jellyfin e regrava no nome do arquivo.
#   "<Série> SxxEyy.ext"  →  "<Série> SxxEyy - <Título>.ext"
# Fonte = API do Jellyfin (já identificou a série). Renomeia no HOST (o mount do container é ro, mas o host escreve).
# Fallback: se o ep não tem título no Jellyfin, deixa como está (sem título).
#
# Uso:  jellyfin-retitle.sh [--lib "Animes (Hi0)"] [--name "<só uma série>"] [--apply]
#   sem --apply = dry-run.  Depois de aplicar, dispara um scan p/ o Jellyfin recasar pelos SxxEyy.
set -u
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

LIB="Animes (Hi0)"; ONLY=""; APPLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --lib)   LIB="${2:-}"; shift 2;;
    --name)  ONLY="${2:-}"; shift 2;;
    --apply) APPLY=1; shift;;
    -*) echo "opção desconhecida: $1" >&2; exit 2;;
    *)  echo "arg inesperado: $1" >&2; exit 2;;
  esac
done
KEY="$(cat /home/bia/.config/tg-dl/jellyfin-key 2>/dev/null)"
BASE="$(cat /home/bia/.config/tg-dl/jellyfin-url 2>/dev/null)"; BASE="${BASE:-http://localhost:8097}"
[ -z "$KEY" ] && { echo "ERR: sem jellyfin-key" >&2; exit 3; }

LIBID="$(curl -s -H "X-Emby-Token: $KEY" "$BASE/Library/VirtualFolders" \
  | LIB="$LIB" python3 -c 'import sys,json,os; [print(v["ItemId"]) for v in json.load(sys.stdin) if v["Name"]==os.environ["LIB"]]')"
[ -z "$LIBID" ] && { echo "ERR: library \"$LIB\" não achada" >&2; exit 4; }

eps="$(curl -s -H "X-Emby-Token: $KEY" \
  "$BASE/Items?ParentId=$LIBID&Recursive=true&IncludeItemTypes=Episode&Fields=Path&EnableImages=false")"

TMP="$(mktemp)"; printf '%s' "$eps" > "$TMP"
EPSFILE="$TMP" ONLY="$ONLY" APPLY="${APPLY:-}" python3 <<'PY'
import sys, os, json, re, shutil
d=json.load(open(os.environ["EPSFILE"])); items=d.get("Items",[])
ONLY=os.environ.get("ONLY",""); APPLY=bool(os.environ.get("APPLY",""))
CMAP=("/MediaHi0","/mnt/Hi0/Media")   # container → host

def sane(t):
    t=t.replace("/","-").replace("\\","-")
    t=re.sub(r'[:*?"<>|]','',t)          # ilegais em alguns FS
    t=re.sub(r'\s+',' ',t).strip().strip('.')
    return t

plan=[]; skip_notitle=0; skip_noid=0; missing=0
for it in items:
    path=it.get("Path"); title=it.get("Name") or ""; pi=it.get("ParentIndexNumber"); ix=it.get("IndexNumber")
    if not path: continue
    host=path.replace(CMAP[0],CMAP[1],1)
    dname=os.path.dirname(host); series=os.path.basename(dname)
    if ONLY and series!=ONLY: continue
    ext=os.path.splitext(host)[1]
    if pi is None or ix is None: skip_noid+=1; continue
    st=sane(title)
    # título "genérico" do Jellyfin (Episode 8 / Episódio 8) não vale a pena gravar
    if not st or re.match(r'(?i)^epis[oó]dio?\s*\d+$', st) or re.match(r'(?i)^episode\s*\d+$', st):
        skip_notitle+=1; continue
    new="%s S%02dE%02d - %s%s" % (series, pi, ix, st, ext)
    dst=os.path.join(dname,new)
    if os.path.basename(host)==new: continue          # já está com o título (idempotente)
    if not os.path.exists(host): missing+=1; print("  ⚠️ sumiu (rescan?):", os.path.basename(host)); continue
    plan.append((host,dst,os.path.basename(host),new))

print("=== Fase B%s: %d episódio(s) p/ retitular%s ===" % (
    (" ["+ONLY+"]") if ONLY else "", len(plan), "" if APPLY else "   [DRY-RUN]"))
for _,_,o,n in plan[:12]:
    print("  %-42s → %s" % (o[:42], n))
if len(plan)>12: print("  ... (+%d)" % (len(plan)-12))
if skip_notitle: print("  (%d sem título real no Jellyfin → mantidos sem título)" % skip_notitle)
if skip_noid:    print("  (%d sem S/E identificado → pulados)" % skip_noid)

if not APPLY:
    print("\n(dry-run — nada renomeado.)"); sys.exit(0)
done=0
for src,dst,o,n in plan:
    if os.path.exists(dst): print("  PULADO (existe):",n); continue
    shutil.move(src,dst); done+=1
print("\n✅ %d renomeados com título. (rode um scan no Jellyfin p/ recasar)" % done)
PY
rm -f "$TMP"
