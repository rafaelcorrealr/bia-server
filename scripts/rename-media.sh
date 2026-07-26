#!/usr/bin/env bash
# rename-media.sh — renomeia mídia baixada pra um nome parseável e organiza numa pasta.
#
# Anime  (--type anime):  "<Nome> S<TT>E<EE>.<ext>"     -> dest/<Nome>/
# Mangá  (--type manga):  "capitulo <N> - <Nome>.<ext>"  ou  "volume <N> - <Nome>.<ext>"  -> dest/<Nome>/
#
# Uso:  rename-media.sh --dir <pasta_origem> --name "<Nome do anime/mangá>" [opções]
#   --type anime|manga   (default anime)
#   --season <n>         temporada p/ anime (default 1)
#   --offset <n>         soma no número do episódio (default 0)
#   --dest <path>        destino (default: anime=/mnt/Hi0/Media/Animes  manga=/mnt/Hi0/Media/Mangas)
#   --apply              aplica de verdade (default = dry-run, só mostra o plano)
#
# Dry-run mostra a tabela antes→depois e sinaliza (?) os que não deu pra numerar.
# Ao aplicar: move (rename no mesmo disco = instantâneo) e grava .rename-log na pasta destino.
set -u
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

DIR=""; NAME=""; TYPE="anime"; SEASON="1"; OFFSET="0"; DEST=""; APPLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)     DIR="${2:-}"; shift 2;;
    --name)    NAME="${2:-}"; shift 2;;
    --type)    TYPE="${2:-}"; shift 2;;
    --season)  SEASON="${2:-}"; shift 2;;
    --offset)  OFFSET="${2:-}"; shift 2;;
    --dest)    DEST="${2:-}"; shift 2;;
    --apply)   APPLY=1; shift;;
    -*) echo "opção desconhecida: $1" >&2; exit 2;;
    *)  echo "argumento inesperado: $1" >&2; exit 2;;
  esac
done
[ -z "$DIR" ] || [ -z "$NAME" ] && { echo "ERR: --dir e --name são obrigatórios" >&2; exit 2; }
[ -d "$DIR" ] || { echo "ERR: pasta não existe: $DIR" >&2; exit 2; }
TYPE="$(printf '%s' "$TYPE" | tr 'A-Z' 'a-z')"
case "$TYPE" in anime|manga) ;; *) echo "ERR: --type anime|manga" >&2; exit 2;; esac
if [ -z "$DEST" ]; then
  [ "$TYPE" = anime ] && DEST="/mnt/Hi0/Media/Animes" || DEST="/mnt/Hi0/Media/Mangas"
fi

DIR="$DIR" NAME="$NAME" TYPE="$TYPE" SEASON="$SEASON" OFFSET="$OFFSET" DEST="$DEST" APPLY="${APPLY:-}" python3 <<'PY'
import os, re, sys, shutil

DIR=os.environ["DIR"]; NAME=os.environ["NAME"]; TYPE=os.environ["TYPE"]
SEASON=int(os.environ["SEASON"]); OFFSET=int(os.environ["OFFSET"])
DEST=os.environ["DEST"]; APPLY=bool(os.environ["APPLY"])

VID={".mkv",".mp4",".avi",".m4v",".mov",".webm",".ts"}
MANGA={".cbr",".cbz",".zip",".rar",".pdf",".7z"}
exts = VID if TYPE=="anime" else MANGA

# tokens de "tag" que NÃO são número de episódio (incluindo os que contêm dígitos)
TAG=re.compile(r'^(x26[45]|h26[45]|hevc|avc|hi10p?|10bit|8bit|\d{3,4}p|aac|ac3|eac3|flac|opus|dts|dual|multi|bd|bluray|blu|web|webrip|webdl|hdtv|dvd|remux|rip|batch|uncensored|cc|eng|por|jpn|dub|sub|legendado|dualaudio)$', re.I)
YEAR=re.compile(r'^(19|20)\d{2}$')

def norm(s): return re.sub(r'[^a-z0-9]+',' ', s.lower()).strip()
NAME_TOKS=set(norm(NAME).split())

def clean_tokens(base):
    w=re.sub(r'\[[^\]]*\]',' ',base)          # tira [ ... ]
    w=re.sub(r'\([^)]*\)',' ',w)              # tira ( ... )
    w=re.sub(r'[_\.]+',' ',w)                 # _ e . viram espaço
    w=re.sub(r'\s+',' ',w).strip()
    toks=[t for t in re.split(r'[\s]+',w) if t]
    # remove tokens do nome da série e tags
    out=[]
    for t in toks:
        nt=norm(t)
        if nt and nt in NAME_TOKS: continue
        if TAG.match(t): continue
        if YEAR.match(t): continue
        out.append(t)
    return out

def season_ep(base):
    # já vem com SxxEyy explícito (S01E01, S01.E01, S1E1)? preserva temporada+episódio
    m=re.search(r's(\d{1,2})[ ._-]*e(\d{1,3})', base, re.I)
    if m: return (int(m.group(1)), int(m.group(2)))
    return (None, None)

def ep_num(base):
    for t in clean_tokens(base):
        m=re.match(r'(?:s\d+e)?(?:ep?|e|#)?0*(\d{1,3})$', t, re.I)  # token INTEIRO: E01, EP01, #12, 01 (não pega cauda de id gigante)
        if m:
            n=int(m.group(1))
            if 0 < n <= 999: return n
    return None

def manga_num(base):
    # volume primeiro (mais específico), depois capítulo/range
    m=re.search(r'vol(?:ume)?\.?\s*0*(\d+(?:\s*-\s*\d+)?)', base, re.I)
    if m: return ("volume", re.sub(r'\s*-\s*','-',m.group(1)))
    m=re.search(r'(?:cap(?:[íi]tulo)?|chapter|ch|c)\.?\s*0*(\d+(?:\s*-\s*\d+)?)', base, re.I)
    if m: return ("capitulo", re.sub(r'\s*-\s*','-',m.group(1)))
    return (None, None)

files=sorted(f for f in os.listdir(DIR) if os.path.splitext(f)[1].lower() in exts and os.path.isfile(os.path.join(DIR,f)))
if not files:
    print("(nenhum arquivo de mídia %s em %s)" % (TYPE, DIR)); sys.exit(0)

target_dir=os.path.join(DEST, NAME)
plan=[]; unresolved=0; order=0
for f in files:
    base,ext=os.path.splitext(f); ext=ext.lower()
    if TYPE=="anime":
        flag=""
        s,e=season_ep(base)
        if e is not None:
            sea,n=s,e                                      # SxxEyy explícito → preserva
        else:
            n=ep_num(base); sea=SEASON
            if n is None:
                order+=1; n=order; flag=" (?)"; unresolved+=1   # sem número → ordem (confirmar)
            n+=OFFSET
        new="%s S%02dE%02d%s" % (NAME, sea, n, ext)
        plan.append((f,new,flag))
    else:
        kind,num=manga_num(base)
        if not kind:
            new="%s - %s%s" % (NAME, base, ext); plan.append((f,new," (?)")); unresolved+=1
        else:
            new="%s %s - %s%s" % (kind, num, NAME, ext); plan.append((f,new,""))

print("=== %s: %s  (%d arquivos) → %s%s ===" % (TYPE.upper(), NAME, len(files), target_dir, "" if APPLY else "   [DRY-RUN]"))
for old,new,flag in plan:
    print("  %-55s → %s%s" % (old[:55], new, flag))
if unresolved:
    print("  ⚠️ %d sem número identificável%s" % (unresolved,
          " (numerados pela ORDEM — confira!)" if TYPE=="anime" else " (mantido nome original)"))

if not APPLY:
    print("\n(dry-run — nada movido. Rode com --apply pra aplicar.)"); sys.exit(0)

os.makedirs(target_dir, exist_ok=True)
logp=os.path.join(target_dir, ".rename-log")
moved=0
with open(logp,"a") as log:
    for old,new,flag in plan:
        src=os.path.join(DIR,old); dst=os.path.join(target_dir,new)
        if os.path.exists(dst):
            print("  PULADO (já existe): %s" % new); continue
        shutil.move(src,dst); log.write("%s\t%s\n" % (old,new)); moved+=1
print("\n✅ %d movidos p/ %s  (log: %s)" % (moved, target_dir, logp))
PY
