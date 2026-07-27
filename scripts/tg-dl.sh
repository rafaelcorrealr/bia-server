#!/usr/bin/env bash
# tg-dl.sh — download do Telegram (tdl) com confirmação/rename, multi-link e intervalo.
#
# Launcher (chamado pelo n8n):
#   tg-dl.sh --job <base64(JSON)>       -> dispara worker DETACHED, imprime "JOB\t<id>" (<1s)
#   tg-dl.sh <link> <chat_id>           -> compat: um link só, modo single
# JSON do job: { chat_id, mode: single|multi|range, links:[...], rchat, rmin, rmax }
#
# Worker (interno):  tg-dl.sh __worker <job_id>   (lê $STATE/<job>/job.json)
#
# Coordenação c/ o n8n (modo single): nome final escolhido é gravado em
#   $STATE_ROOT/<job>/final   (conteúdo = nome desejado, ou "__KEEP__")
set -u
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

DL_DIR="${TG_DL_DIR:-/mnt/Hi0/Downloads}"
STATE_ROOT="${TG_DL_STATE:-/home/bia/.local/state/tg-dl}"
TOKEN_FILE="/home/bia/.config/tg-dl/token"
API="https://api.telegram.org"
TDL_BIN="${TG_DL_TDL:-tdl}"                 # sobrescrevível p/ teste
TODOIST_BIN="${TG_DL_TODOIST:-/home/bia/.local/bin/todoist-task.sh}"
CLEAN_TMPL='{{ filenamify .FileName }}'     # nome sem o prefixo <dialog>_<msg>_ (modo batch)
# batch: prefixa com MessageID (sempre único) → dedupe_rename limpa depois quando o nome está livre.
# Resolve colisão: N mensagens com o mesmo nome não se sobrescrevem mais (ex.: sticker.webp ×8, @Bot.mp4 ×64).
BATCH_TMPL='{{ .MessageID }}_{{ filenamify .FileName }}'

tg_send() {  # tg_send <chat_id> <text>
  local chat="$1" text="$2" tok
  if [ -n "${TG_DL_SEND_LOG:-}" ]; then
    printf '>>> [%s]\n%s\n' "$chat" "$text" >>"$TG_DL_SEND_LOG"; return 0
  fi
  tok="$(cat "$TOKEN_FILE" 2>/dev/null)"
  [ -z "$tok" ] && return 0
  [ -z "$chat" ] && return 0
  curl -s -o /dev/null --max-time 25 "$API/bot${tok}/sendMessage" \
    --data-urlencode "chat_id=${chat}" --data-urlencode "text=${text}" >/dev/null 2>&1
}

# manda e DEVOLVE o message_id (pra editar depois). Em dry-run devolve um id fake.
tg_send_id() {  # tg_send_id <chat> <text>  -> echo <message_id>
  local chat="$1" text="$2" tok resp
  if [ -n "${TG_DL_SEND_LOG:-}" ]; then
    printf '>>> SEND [%s]\n%s\n' "$chat" "$text" >>"$TG_DL_SEND_LOG"
    printf '%s' "$(( (RANDOM % 90000) + 10000 ))"; return 0
  fi
  tok="$(cat "$TOKEN_FILE" 2>/dev/null)"; [ -z "$tok" ] && return 0
  [ -z "$chat" ] && return 0
  resp="$(curl -s --max-time 25 "$API/bot${tok}/sendMessage" \
    --data-urlencode "chat_id=${chat}" --data-urlencode "text=${text}" 2>/dev/null)"
  printf '%s' "$resp" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("result",{}).get("message_id",""))
except Exception: pass' 2>/dev/null
}

# edita uma msg já enviada; se não houver message_id, cai pra mandar nova.
tg_edit() {  # tg_edit <chat> <msg_id> <text>
  local chat="$1" mid="$2" text="$3" tok
  [ -z "$mid" ] && { tg_send "$chat" "$text"; return; }
  if [ -n "${TG_DL_SEND_LOG:-}" ]; then
    printf '>>> EDIT [%s#%s]\n%s\n' "$chat" "$mid" "$text" >>"$TG_DL_SEND_LOG"; return 0
  fi
  tok="$(cat "$TOKEN_FILE" 2>/dev/null)"; [ -z "$tok" ] && return 0
  curl -s -o /dev/null --max-time 25 "$API/bot${tok}/editMessageText" \
    --data-urlencode "chat_id=${chat}" --data-urlencode "message_id=${mid}" \
    --data-urlencode "text=${text}" >/dev/null 2>&1
}

# nome de pasta seguro: sem barras, sem ../, sem control chars; trim; cap 80
sanitize_dir() {  # sanitize_dir <name> -> echo <safe>
  local s="$1"
  s="${s//\//}"                                                 # remove barras
  s="$(printf '%s' "$s" | tr -d '\000-\037')"                   # remove control chars
  s="$(sed -E 's/^[[:space:].]+//; s/[[:space:]]+$//' <<<"$s")"  # trim espaços/pontos do início
  case "$s" in .|..) s="";; esac
  printf '%s' "${s:0:80}"
}

# chave estável do chat (mesmo valor no preview e no download → reusa o export)
preview_key() {  # preview_key <tg> [topic]  -> echo <key>
  local k; k="$(printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_')"
  [ -n "${2:-}" ] && k="${k}_t$2"
  printf '%s' "$k"
}

# conta arquivos novos (fora .tmp) surgidos em <dir> desde $S/before.lst
count_new() {  # count_new <S> [dir]  -> echo <n>
  local S="$1" dir="${2:-$DL_DIR}" c=0 f
  while IFS= read -r f; do
    [ -n "$f" ] && case "$f" in *.tmp) ;; *) c=$((c+1));; esac
  done < <(comm -13 "$S/before.lst" <(ls -1 "$dir" 2>/dev/null | sort))
  printf '%s' "$c"
}

# loop de progresso de lote: manda "📥 0/N…" e edita "k/N" enquanto o tdl (DPID) roda.
# tdl não expõe % legível -> progresso por CONTAGEM de arquivos. Grava o msg_id em $S/pmsg.
batch_progress() {  # batch_progress <chat> <S> <N> <dpid> [dir]
  local CHAT="$1" S="$2" N="$3" DPID="$4" DIR="${5:-$DL_DIR}"
  local INTERVAL="${TG_DL_PROGRESS_INTERVAL:-60}" mid k last=-1
  mid="$(tg_send_id "$CHAT" "📥 Baixando 0/${N}…")"
  printf '%s' "$mid" >"$S/pmsg"
  while kill -0 "$DPID" 2>/dev/null; do
    sleep "$INTERVAL"
    kill -0 "$DPID" 2>/dev/null || break
    k="$(count_new "$S" "$DIR")"
    if [ "$k" != "$last" ]; then
      tg_edit "$CHAT" "$mid" "📥 Baixando ${k}/${N}…"
      last="$k"
    fi
  done
}

clean_name() { sed -E 's/^[0-9]+_[0-9]+_//' <<<"$1"; }   # tira prefixo "<dialog>_<msg>_"

# conjunto de MessageIDs válidos (1 por linha) p/ o dedupe_rename validar o prefixo
msgids_from_export() {  # <export.json>
  python3 -c "import json,sys
try: ms=json.load(open(sys.argv[1])).get('messages',[])
except Exception: ms=[]
[print(m['id']) for m in ms if m.get('file') and m.get('id') is not None]" "$1" 2>/dev/null
}
msgids_from_links() {  # <link...>
  python3 -c "import sys,re
for l in sys.argv[1:]:
    l=l.split('?')[0].split('#')[0].rstrip('/')
    m=re.search(r'/(\d+)\$', l)
    if m: print(m.group(1))" "$@" 2>/dev/null
}

# renomeia '<MessageID>_<nome>' -> '<nome>' quando o nome limpo está LIVRE; mantém o prefixo em
# colisão real (nada se sobrescreve). Valida o prefixo contra o conjunto de ids (não corta '2024_x').
dedupe_rename() {  # dedupe_rename <dir> <idsfile>
  python3 - "$1" "$2" <<'PY'
import sys, os, re
d, idsfile = sys.argv[1], sys.argv[2]
try: ids = set(x.strip() for x in open(idsfile) if x.strip())
except OSError: ids = set()
if not os.path.isdir(d) or not ids: sys.exit(0)
for name in sorted(os.listdir(d)):
    m = re.match(r'^(\d+)_(.+)$', name)
    if not m: continue
    mid, clean = m.group(1), m.group(2)
    if mid not in ids or not clean: continue
    src = os.path.join(d, name); dst = os.path.join(d, clean)
    if os.path.exists(dst): continue          # colisão real → mantém o prefixo (nada se perde)
    try: os.rename(src, dst)
    except OSError: pass
PY
}

todoist_for() {  # todoist_for <path>  — cria tarefa no Todoist (ignora erro/sem-token)
  local p="$1" sz
  sz="$(du -h "$p" 2>/dev/null | cut -f1)"
  "$TODOIST_BIN" "📥 Organizar: «$(basename "$p")»" "Origem: Telegram (tdl)
Arquivo: $p
Tamanho: ${sz:-?}" >/dev/null 2>&1 || true
}

# aplica a extensão original se o nome escolhido não tiver uma de mídia conhecida
apply_ext() {  # apply_ext <final> <clean_orig>  -> imprime final ajustado
  local FINAL="$1" CLEAN="$2" lext oext
  lext="$(printf '%s' "${FINAL##*.}" | tr 'A-Z' 'a-z')"
  case " mp4 mkv avi mov m4v webm ts m2ts flv wmv mpg mpeg 3gp cbr cbz pdf epub zip 7z rar mp3 flac m4a wav opus aac ogg srt ass " in
    *" $lext "*) : ;;
    *) oext="${CLEAN##*.}"
       [ "$oext" != "$CLEAN" ] && [ -n "$oext" ] && FINAL="${FINAL}.${oext}" ;;
  esac
  printf '%s' "$FINAL"
}

# ---------------------------------------------------------------- worker: single (rename)
worker_single() {  # <link> <chat> <job>
  local LINK="$1" CHAT="$2" JOB="$3"
  local S="$STATE_ROOT/$JOB"; mkdir -p "$S"
  local before REL BASE CLEAN SRC FINAL DEST b e rc
  mapfile -t before < <(ls -1 "$DL_DIR" 2>/dev/null)
  [ "${#before[@]}" -eq 0 ] && before=("")

  exec 200>"$STATE_ROOT/.tdl.lock"; flock 200        # serializa o tdl (bolt = 1 processo por vez)
  "$TDL_BIN" dl -u "$LINK" -d "$DL_DIR" >"$S/tdl.log" 2>&1 &
  local TPID=$!
  REL=""
  for _ in $(seq 1 60); do
    while IFS= read -r f; do [ -n "$f" ] && { REL="$f"; break; }; done \
      < <(comm -13 <(printf '%s\n' "${before[@]}" | sort) <(ls -1 "$DL_DIR" 2>/dev/null | sort))
    [ -n "$REL" ] && break
    kill -0 "$TPID" 2>/dev/null || break
    sleep 0.5
  done
  if [ -z "$REL" ]; then
    wait "$TPID" 2>/dev/null; flock -u 200; echo "failed-no-file" >"$S/state"
    tg_send "$CHAT" "❌ Não consegui baixar (link inválido ou erro do tdl). Confira o link e tente de novo."
    return 1
  fi
  BASE="${REL%.tmp}"; CLEAN="$(clean_name "$BASE")"
  printf '%s' "$CLEAN" >"$S/orig"; printf '%s' "$BASE" >"$S/base"; echo "await" >"$S/state"
  tg_send "$CHAT" "📥 Baixando: «${CLEAN}»
Nome final? Responda OK pra manter, ou mande o novo nome (com extensão)."
  wait "$TPID"; rc=$?; flock -u 200        # libera o lock do tdl (a espera do nome não segura a fila)
  if [ "$rc" -ne 0 ]; then echo "failed-dl" >"$S/state"; tg_send "$CHAT" "❌ O download de «${CLEAN}» falhou (tdl rc=$rc)."; return 1; fi
  SRC="$DL_DIR/$BASE"; [ -f "$SRC" ] || SRC="$DL_DIR/$REL"

  FINAL=""
  for _ in $(seq 1 3600); do [ -f "$S/final" ] && { FINAL="$(cat "$S/final")"; break; }; sleep 0.5; done
  [ -z "$FINAL" ] && FINAL="$CLEAN"; [ "$FINAL" = "__KEEP__" ] && FINAL="$CLEAN"
  FINAL="$(tr -d '/\000-\037' <<<"$FINAL")"; [ -z "$FINAL" ] && FINAL="$CLEAN"
  FINAL="$(apply_ext "$FINAL" "$CLEAN")"

  DEST="$DL_DIR/$FINAL"
  if [ -e "$DEST" ] && [ "$SRC" != "$DEST" ]; then
    b="${FINAL%.*}"; e="${FINAL##*.}"
    if [ "$b" = "$e" ]; then DEST="$DL_DIR/${FINAL} (${JOB})"; else DEST="$DL_DIR/${b} (${JOB}).${e}"; fi
  fi
  if [ "$SRC" = "$DEST" ]; then tg_send "$CHAT" "✅ Pronto: «$(basename "$DEST")»"
  elif mv -- "$SRC" "$DEST" 2>>"$S/tdl.log"; then tg_send "$CHAT" "✅ Pronto: «$(basename "$DEST")»"
  else DEST="$SRC"; tg_send "$CHAT" "⚠️ Baixei, mas não consegui renomear. Ficou «$(basename "$SRC")»."; fi

  todoist_for "$DEST"
  echo "done" >"$S/state"; return 0
}

# ---------------------------------------------------------------- batch: comum (multi/range)
finish_batch() {  # finish_batch <chat> <job> [descricao] [dir]   (usa $S/before.lst)
  local CHAT="$1" JOB="$2" DESC="${3:-download}" DIR="${4:-$DL_DIR}" MT="${5:-}" S="$STATE_ROOT/$JOB"
  local PMSG=""; [ -f "$S/pmsg" ] && PMSG="$(cat "$S/pmsg")"   # msg de progresso p/ editar no fim
  local FOLDER=""; [ "$DIR" != "$DL_DIR" ] && FOLDER=" 📁 $(basename "$DIR")"
  local newf=() f
  while IFS= read -r f; do
    [ -n "$f" ] && case "$f" in *.tmp) ;; *) newf+=("$f");; esac
  done < <(comm -13 "$S/before.lst" <(ls -1 "$DIR" 2>/dev/null | sort))
  local n="${#newf[@]}"
  if [ "$n" -eq 0 ]; then
    tg_edit "$CHAT" "$PMSG" "⚠️ Terminei mas não vi arquivos novos. Veja o log do job ($JOB)."
    echo "done-empty" >"$S/state"; return 0
  fi
  # lista resumida (máx 12 nomes — evita estourar o limite de 4096 chars do Telegram)
  local list="" i=0
  for f in "${newf[@]}"; do
    i=$((i+1)); [ "$i" -le 12 ] && list+="• $(clean_name "$f")"$'\n'
  done
  [ "$n" -gt 12 ] && list+="… e mais $((n-12)) arquivo(s)"$'\n'
  # UMA tarefa no Todoist p/ o lote inteiro (não uma por arquivo) — pula se vai auto-organizar (anime/mangá)
  case "$MT" in anime|manga) : ;; *)
  "$TODOIST_BIN" "📥 Organizar: $n arquivo(s) ($DESC)" "Origem: Telegram (tdl) — lote de $n arquivo(s)
Pasta: $DIR
Ex.: $(clean_name "${newf[0]}")" >/dev/null 2>&1 || true
  ;; esac
  tg_edit "$CHAT" "$PMSG" "✅ Baixei ${n} arquivo(s)${FOLDER}:
${list}"
  echo "done" >"$S/state"; return 0
}

# ---------------------------------------------------------------- organiza (anime/mangá) no fim do batch
organize_batch() {  # <chat> <job> <type> <name> <dir>
  local CHAT="$1" JOB="$2" MT="$3" NAME="$4" DIR="$5" S="$STATE_ROOT/$JOB"
  case "$MT" in anime|manga) ;; *) return 0;; esac              # só anime/mangá organizam
  [ -n "$NAME" ] && [ "$DIR" != "$DL_DIR" ] || return 0         # precisa de pasta própria
  "$HOME/.local/bin/rename-media.sh" --type "$MT" --name "$NAME" --dir "$DIR" --apply >"$S/organize.log" 2>&1 || true
  if [ "$MT" = anime ]; then
    local JK JU NEPS
    JK="$(cat "$HOME/.config/tg-dl/jellyfin-key" 2>/dev/null)"
    JU="$(cat "$HOME/.config/tg-dl/jellyfin-url" 2>/dev/null)"; JU="${JU:-http://localhost:8097}"
    [ -n "$JK" ] && curl -s -o /dev/null --max-time 15 -X POST -H "X-Emby-Token: $JK" "$JU/Library/Refresh" 2>/dev/null || true
    NEPS="$(find "/mnt/Hi0/Media/Animes/$NAME" -maxdepth 1 -type f \( -iname '*.mkv' -o -iname '*.mp4' -o -iname '*.avi' -o -iname '*.m4v' \) 2>/dev/null | wc -l)"
    "$HOME/.local/bin/anilist-add.sh" --status quero --list "Baixado" --type ANIME ${NEPS:+--progress "$NEPS"} "$NAME" >>"$S/organize.log" 2>&1 || true
    # Fase B atrasada: o título só fica pronto ~1-3min após o scan → processo destacado retitula a lib e reescaneia
    setsid bash -c 'sleep 200; "$HOME/.local/bin/jellyfin-retitle.sh" --apply >/dev/null 2>&1; k="$(cat "$HOME/.config/tg-dl/jellyfin-key" 2>/dev/null)"; u="$(cat "$HOME/.config/tg-dl/jellyfin-url" 2>/dev/null)"; curl -s -o /dev/null --max-time 15 -X POST -H "X-Emby-Token: $k" "${u:-http://localhost:8097}/Library/Refresh" 2>/dev/null' </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
    tg_send "$CHAT" "🎬 Organizado no Jellyfin: $NAME ($NEPS ep). Os títulos dos episódios entram em alguns minutos. Marcado no AniList → Baixado."
  else
    "$HOME/.local/bin/anilist-add.sh" --status quero --list "Baixado" --type MANGA "$NAME" >>"$S/organize.log" 2>&1 || true
    tg_send "$CHAT" "📚 Mangá organizado: $NAME. Marcado no AniList → Baixado."
  fi
}

# ================================================================ download web (MEGA/aria2/yt-dlp)
# se o download criou UMA subpasta só (ex.: pasta do MEGA) e nenhum arquivo solto, sobe o conteúdo p/ <ddir>
flatten_single() {  # flatten_single <ddir>
  python3 - "$1" <<'PY'
import sys, os, shutil
d = sys.argv[1]
if not os.path.isdir(d): sys.exit(0)
ent   = [e for e in os.listdir(d) if not e.startswith('.')]
subs  = [e for e in ent if os.path.isdir(os.path.join(d, e))]
files = [e for e in ent if os.path.isfile(os.path.join(d, e))]
if len(subs) == 1 and not files:                       # só achata o caso simples (1 subpasta, 0 arquivos)
    src = os.path.join(d, subs[0])
    for name in os.listdir(src):
        try: shutil.move(os.path.join(src, name), os.path.join(d, name))
        except Exception: pass
    try: os.rmdir(src)
    except OSError: pass
PY
}

# MEGA (link público de arquivo ou pasta) — megatools, síncrono. Pasta do MEGA vira subpasta → achata.
web_mega() {  # web_mega <url> <ddir> <S>
  local URL="$1" DDIR="$2" S="$3"
  megadl --no-progress --path "$DDIR" "$URL" >"$S/web.log" 2>&1 || return 1
  flatten_single "$DDIR"
}

# link direto de arquivo — via aria2 (container já rodando). dir do RPC = path DENTRO do container.
web_aria2() {  # web_aria2 <url> <ddir> <S> <chat> <mid>
  local URL="$1" DDIR="$2" S="$3" CHAT="$4" MID="$5"
  local SEC RPC CDIR addp gid st comp total spd pct last=-1
  SEC="$(cat "$HOME/.config/tg-dl/aria2-secret" 2>/dev/null)"
  RPC="$(cat "$HOME/.config/tg-dl/aria2-rpc" 2>/dev/null)"; RPC="${RPC:-http://localhost:6800/jsonrpc}"
  CDIR="/downloads${DDIR#"$DL_DIR"}"                    # host /mnt/Hi0/Downloads/X → container /downloads/X
  addp="$(python3 -c 'import sys,json;print(json.dumps({"jsonrpc":"2.0","id":"a","method":"aria2.addUri","params":["token:"+sys.argv[1],[sys.argv[2]],{"dir":sys.argv[3]}]}))' "$SEC" "$URL" "$CDIR")"
  gid="$(curl -s --max-time 15 "$RPC" -d "$addp" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("result","") or "")
except Exception: pass' 2>/dev/null)"
  [ -z "$gid" ] && { echo "aria2 addUri falhou" >"$S/web.log"; return 1; }
  printf '%s' "$gid" >"$S/aria2.gid"
  local INTERVAL="${TG_DL_PROGRESS_INTERVAL:-10}" statp
  statp="$(python3 -c 'import sys,json;print(json.dumps({"jsonrpc":"2.0","id":"s","method":"aria2.tellStatus","params":["token:"+sys.argv[1],sys.argv[2],["status","completedLength","totalLength","downloadSpeed","errorMessage"]]}))' "$SEC" "$gid")"
  while :; do
    sleep "$INTERVAL"
    read -r st comp total spd < <(curl -s --max-time 15 "$RPC" -d "$statp" | python3 -c 'import sys,json
try:
 r=json.load(sys.stdin)["result"]; print(r.get("status",""), r.get("completedLength","0"), r.get("totalLength","0"), r.get("downloadSpeed","0"))
except Exception: print("gone 0 0 0")')
    case "$st" in
      complete) return 0 ;;
      error|removed|gone) echo "aria2 status=$st" >>"$S/web.log"; return 1 ;;
    esac
    if [ "${total:-0}" -gt 0 ] 2>/dev/null; then
      pct=$(( comp * 100 / total ))
      if [ "$pct" != "$last" ]; then
        tg_edit "$CHAT" "$MID" "⬇️ ${pct}% · $(awk -v b="${spd:-0}" 'BEGIN{if(b>=1048576)printf "%.1f MB/s",b/1048576; else printf "%.0f KB/s",b/1024}')"
        last="$pct"
      fi
    fi
  done
}

# páginas de vídeo/stream + GDrive + genérico — yt-dlp, síncrono.
web_ytdlp() {  # web_ytdlp <url> <ddir> <S>
  local URL="$1" DDIR="$2" S="$3"
  yt-dlp --no-warnings --no-playlist -P "$DDIR" -o '%(title)s.%(ext)s' "$URL" >"$S/web.log" 2>&1 || return 1
  flatten_single "$DDIR"
}

# ---------------------------------------------------------------- worker: web (MEGA / direto / vídeo)
worker_web() {  # <chat> <job> <url> <subdir>
  local CHAT="$1" JOB="$2" URL="$3" SUBDIR="$4"
  local S="$STATE_ROOT/$JOB"; mkdir -p "$S"
  local DDIR="$DL_DIR"                                  # pasta destino (subpasta se pedida)
  if [ -n "$SUBDIR" ]; then
    SUBDIR="$(sanitize_dir "$SUBDIR")"
    [ -n "$SUBDIR" ] && { DDIR="$DL_DIR/$SUBDIR"; mkdir -p "$DDIR"; }
  fi
  ls -1 "$DDIR" 2>/dev/null | sort >"$S/before.lst"
  echo "run" >"$S/state"

  # despacho por tipo de URL
  local backend low
  low="$(printf '%s' "$URL" | tr 'A-Z' 'a-z')"
  case "$low" in
    *mega.nz/*|*mega.co.nz/*) backend=mega ;;
    *)
      case "${low%%[?#]*}" in                           # ignora query/fragmento pra achar a extensão
        *.zip|*.rar|*.7z|*.tar|*.gz|*.tgz|*.xz|*.iso|*.bin|*.mkv|*.mp4|*.avi|*.m4v|*.mov|*.webm|*.ts|*.pdf|*.cbz|*.cbr|*.epub|*.mobi|*.mp3|*.flac|*.m4a|*.wav) backend=aria2 ;;
        *) backend=ytdlp ;;
      esac ;;
  esac

  local mid rc
  mid="$(tg_send_id "$CHAT" "⬇️ Baixando ($backend)…")"
  printf '%s' "$mid" >"$S/pmsg"

  case "$backend" in
    mega)  web_mega  "$URL" "$DDIR" "$S" ;;
    aria2) web_aria2 "$URL" "$DDIR" "$S" "$CHAT" "$mid" ;;
    ytdlp) web_ytdlp "$URL" "$DDIR" "$S" ;;
  esac
  rc=$?

  if [ "$rc" -ne 0 ]; then
    tg_edit "$CHAT" "$mid" "❌ Falhou o download ($backend). Confere o link (alguns hosts pedem captcha/login). Log: job $JOB."
    echo "failed" >"$S/state"; return 1
  fi
  finish_batch "$CHAT" "$JOB" "web ($backend)${SUBDIR:+ → $SUBDIR}" "$DDIR" "${RTYPE:-}"
  organize_batch "$CHAT" "$JOB" "${RTYPE:-}" "$(basename "$DDIR")" "$DDIR"
}

# ---------------------------------------------------------------- worker: multi (vários links)
worker_multi() {  # <chat> <job> <subdir> <link...>
  local CHAT="$1" JOB="$2" SUBDIR="$3"; shift 3
  local S="$STATE_ROOT/$JOB"; mkdir -p "$S"
  local DDIR="$DL_DIR"                                    # pasta destino (subpasta se pedida)
  if [ -n "$SUBDIR" ]; then
    SUBDIR="$(sanitize_dir "$SUBDIR")"
    [ -n "$SUBDIR" ] && { DDIR="$DL_DIR/$SUBDIR"; mkdir -p "$DDIR"; }
  fi
  ls -1 "$DDIR" 2>/dev/null | sort >"$S/before.lst"
  local N=$# args=() l; for l in "$@"; do args+=(-u "$l"); done
  msgids_from_links "$@" >"$S/ids.lst"                    # p/ o dedupe_rename validar o prefixo
  echo "run" >"$S/state"
  exec 200>"$STATE_ROOT/.tdl.lock"; flock 200            # serializa o tdl (bolt = 1 processo por vez)
  "$TDL_BIN" dl "${args[@]}" -d "$DDIR" --template "$BATCH_TMPL" >"$S/tdl.log" 2>&1 &
  local DPID=$!
  batch_progress "$CHAT" "$S" "$N" "$DPID" "$DDIR"       # 📥 0/N → k/N (edita a mesma msg)
  wait "$DPID"; flock -u 200
  dedupe_rename "$DDIR" "$S/ids.lst"                      # tira o prefixo <id>_ quando o nome está livre
  finish_batch "$CHAT" "$JOB" "multi-link${SUBDIR:+ → $SUBDIR}" "$DDIR" "${RTYPE:-}"   # edita p/ ✅ final
  organize_batch "$CHAT" "$JOB" "${RTYPE:-}" "$(basename "$DDIR")" "$DDIR"
}

# ---------------------------------------------------------------- worker: range (intervalo)
worker_range() {  # <chat> <job> <tgchat> <min> <max> [topic] [subdir]
  local CHAT="$1" JOB="$2" TG="$3" MIN="$4" MAX="$5" TOPIC="${6:-}" SUBDIR="${7:-}"
  local S="$STATE_ROOT/$JOB"; mkdir -p "$S"
  local DDIR="$DL_DIR"                               # pasta destino (subpasta se pedida)
  if [ -n "$SUBDIR" ]; then
    SUBDIR="$(sanitize_dir "$SUBDIR")"
    [ -n "$SUBDIR" ] && { DDIR="$DL_DIR/$SUBDIR"; mkdir -p "$DDIR"; }
  fi
  ls -1 "$DDIR" 2>/dev/null | sort >"$S/before.lst"
  echo "export" >"$S/state"
  exec 200>"$STATE_ROOT/.tdl.lock"; flock 200        # serializa o tdl (segura export + dl)
  local texp=(); [ -n "$TOPIC" ] && texp=(--topic "$TOPIC")   # grupo com tópicos (fórum)
  "$TDL_BIN" chat export -c "$TG" "${texp[@]}" -T id -i "$MIN" -i "$MAX" -o "$S/export.json" >"$S/export.log" 2>&1
  local n
  n="$(python3 -c "import json,sys;print(len(json.load(open('$S/export.json')).get('messages',[])))" 2>/dev/null || echo 0)"
  if [ "${n:-0}" -eq 0 ]; then
    flock -u 200
    tg_send "$CHAT" "🤷 Não achei mídia no intervalo (msg $MIN a $MAX)."
    echo "empty" >"$S/state"; return 1
  fi
  msgids_from_export "$S/export.json" >"$S/ids.lst"  # p/ o dedupe_rename validar o prefixo
  echo "run" >"$S/state"
  "$TDL_BIN" dl -f "$S/export.json" -d "$DDIR" --template "$BATCH_TMPL" >"$S/tdl.log" 2>&1 &
  local DPID=$!
  batch_progress "$CHAT" "$S" "$n" "$DPID" "$DDIR"   # 📥 0/n → k/n (edita a mesma msg)
  wait "$DPID"; flock -u 200
  dedupe_rename "$DDIR" "$S/ids.lst"                 # tira o prefixo <id>_ quando o nome está livre
  finish_batch "$CHAT" "$JOB" "intervalo msg $MIN-$MAX${SUBDIR:+ → $SUBDIR}" "$DDIR" "${RTYPE:-}"
  organize_batch "$CHAT" "$JOB" "${RTYPE:-}" "$(basename "$DDIR")" "$DDIR"
}

# ---------------------------------------------------------------- worker: chat (chat inteiro)
worker_chat() {  # <chat> <job> <tgchat> [topic] [subdir]
  local CHAT="$1" JOB="$2" TG="$3" TOPIC="${4:-}" SUBDIR="${5:-}"
  local S="$STATE_ROOT/$JOB"; mkdir -p "$S"
  local DDIR="$DL_DIR"                               # pasta destino (subpasta se pedida)
  if [ -n "$SUBDIR" ]; then
    SUBDIR="$(sanitize_dir "$SUBDIR")"
    [ -n "$SUBDIR" ] && { DDIR="$DL_DIR/$SUBDIR"; mkdir -p "$DDIR"; }
  fi
  ls -1 "$DDIR" 2>/dev/null | sort >"$S/before.lst"
  local key PF EF texp n age
  key="$(preview_key "$TG" "$TOPIC")"; PF="$STATE_ROOT/.preview/$key.json"; EF="$S/export.json"
  echo "export" >"$S/state"
  exec 200>"$STATE_ROOT/.tdl.lock"; flock 200        # serializa o tdl (segura export + dl)
  age=999999; [ -f "$PF" ] && age=$(( $(date +%s) - $(stat -c %Y "$PF" 2>/dev/null || echo 0) ))
  if [ -f "$PF" ] && [ "$age" -lt 1800 ]; then
    cp "$PF" "$EF"                                   # reusa o preview recente (não exporta 2x)
  else
    texp=(); [ -n "$TOPIC" ] && texp=(--topic "$TOPIC")
    "$TDL_BIN" chat export -c "$TG" "${texp[@]}" -o "$EF" >"$S/export.log" 2>&1
  fi
  n="$(python3 -c "import json,sys;print(len(json.load(open('$EF')).get('messages',[])))" 2>/dev/null || echo 0)"
  if [ "${n:-0}" -eq 0 ]; then
    flock -u 200
    tg_send "$CHAT" "🤷 Não achei mídia nesse chat."
    echo "empty" >"$S/state"; return 1
  fi
  msgids_from_export "$EF" >"$S/ids.lst"            # p/ o dedupe_rename validar o prefixo
  echo "run" >"$S/state"
  "$TDL_BIN" dl -f "$EF" -d "$DDIR" --template "$BATCH_TMPL" >"$S/tdl.log" 2>&1 &
  local DPID=$!
  batch_progress "$CHAT" "$S" "$n" "$DPID" "$DDIR"  # 📥 0/n → k/n (edita a mesma msg)
  wait "$DPID"; flock -u 200
  dedupe_rename "$DDIR" "$S/ids.lst"                # tira o prefixo <id>_ quando o nome está livre
  finish_batch "$CHAT" "$JOB" "chat inteiro${SUBDIR:+ → $SUBDIR}" "$DDIR" "${RTYPE:-}"
  organize_batch "$CHAT" "$JOB" "${RTYPE:-}" "$(basename "$DDIR")" "$DDIR"
}

# preview do chat inteiro (rodado INLINE pelo n8n via SSH): exporta os metadados, conta e
# devolve a MENSAGEM pronta pro Telegram (pede o nome da pasta). O export vira cache p/ o download.
preview_chat() {  # preview_chat <tg> [topic]  -> imprime o texto da resposta
  local TG="$1" TOPIC="${2:-}"
  [ -z "$TG" ] && { echo "⚠️ Link do chat inválido."; return 0; }
  local key PDIR PF rc n SUG texp
  key="$(preview_key "$TG" "$TOPIC")"
  PDIR="$STATE_ROOT/.preview"; mkdir -p "$PDIR"
  PF="$PDIR/$key.json"
  exec 200>"$STATE_ROOT/.tdl.lock"
  if ! flock -w 5 200; then                          # tem download rolando → não bloqueia o n8n
    echo "⏳ Tem um download rolando agora. Me diga o nome da pasta que eu começo assim que liberar (ou \"cancelar\")."
    return 0
  fi
  texp=(); [ -n "$TOPIC" ] && texp=(--topic "$TOPIC")
  timeout 100 "$TDL_BIN" chat export -c "$TG" "${texp[@]}" -o "$PF" >"$PDIR/$key.log" 2>&1
  rc=$?; flock -u 200
  if [ "$rc" -eq 124 ]; then
    echo "🐘 Esse chat é grande demais pra baixar de uma vez. Use /download_range <início> <fim> ou um link de tópico. (mande \"cancelar\" pra encerrar)"
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    echo "⚠️ Não consegui ler esse chat (link errado ou sem acesso). Confira o link. (mande \"cancelar\" pra encerrar)"
    return 0
  fi
  n="$(python3 -c "import json,sys;print(len(json.load(open('$PF')).get('messages',[])))" 2>/dev/null || echo 0)"
  if [ "${n:-0}" -eq 0 ]; then
    echo "🤷 Não achei mídia nesse chat. (mande \"cancelar\" pra encerrar)"
    return 0
  fi
  SUG=""; case "$TG" in *[!0-9]*) SUG="
💡 Sugestão de pasta: $TG";; esac
  printf '🔎 Achei %s arquivo(s) no chat.\n📁 Nome da pasta pra baixar tudo? (responda o nome, ou "sem" pra raiz, ou "cancelar")%s' "$n" "$SUG"
}

# ================================================================ dispatch
# preview do chat inteiro (chamado inline pelo n8n; imprime a resposta pro Telegram)
if [ "${1:-}" = "--preview" ]; then
  preview_chat "${2:-}" "${3:-}"
  exit 0
fi

if [ "${1:-}" = "__worker" ]; then
  JOB="${2:-}"; S="$STATE_ROOT/$JOB"; mkdir -p "$S"
  JSON="$(cat "$S/job.json" 2>/dev/null)"
  eval "$(python3 - "$JSON" <<'PY'
import json, sys, shlex
try: j = json.loads(sys.argv[1])
except Exception: j = {}
q = lambda v: shlex.quote(str(v))
print("MODE="  + q(j.get("mode", "single")))
print("CHAT="  + q(j.get("chat_id", "")))
print("RCHAT=" + q(j.get("rchat", "")))
print("RMIN="  + q(j.get("rmin", "")))
print("RMAX="  + q(j.get("rmax", "")))
_rt = j.get("rtopic")
print("RTOPIC=" + q("" if _rt is None else _rt))
print("RSUBDIR=" + q(j.get("rsubdir", "")))
print("RTYPE=" + q(j.get("mtype", "")))
print("URL=" + q(j.get("url", "")))
links = j.get("links", []) or []
print("LINKS=(" + " ".join(q(x) for x in links) + ")")
PY
)"
  case "$MODE" in
    multi) worker_multi "$CHAT" "$JOB" "$RSUBDIR" "${LINKS[@]}" ;;
    range) worker_range "$CHAT" "$JOB" "$RCHAT" "$RMIN" "$RMAX" "$RTOPIC" "$RSUBDIR" ;;
    chat)  worker_chat  "$CHAT" "$JOB" "$RCHAT" "$RTOPIC" "$RSUBDIR" ;;
    web)   worker_web   "$CHAT" "$JOB" "$URL" "$RSUBDIR" ;;
    *)     worker_single "${LINKS[0]:-}" "$CHAT" "$JOB" ;;
  esac
  exit $?
fi

# ---------------------------------------------------------------- launcher
if [ "${1:-}" = "--job" ]; then
  JSON="$(printf '%s' "${2:-}" | base64 -d 2>/dev/null)"
else
  LINK="${1:-}"; CHAT="${2:-}"
  [ -z "$LINK" ] && { echo "ERR no-link"; exit 1; }
  JSON="$(python3 -c 'import json,sys;print(json.dumps({"chat_id":sys.argv[2],"mode":"single","links":[sys.argv[1]]}))' "$LINK" "$CHAT" 2>/dev/null)"
fi
[ -z "$JSON" ] && { echo "ERR bad-job"; exit 1; }

# dedup: corrida de polls concorrentes pode disparar 2x o mesmo job → devolve o 1º
DEDUP="$STATE_ROOT/.recent"; mkdir -p "$DEDUP"
SIG="$(printf '%s' "$JSON" | sha1sum 2>/dev/null | cut -c1-16)"
NOW="$(date +%s)"
if [ -n "$SIG" ] && [ -f "$DEDUP/$SIG" ]; then
  read -r PREV_T PREV_J < "$DEDUP/$SIG"
  if [ $(( NOW - ${PREV_T:-0} )) -lt 120 ]; then
    printf 'JOB\t%s\n' "${PREV_J:-dup}"; exit 0     # ignora a duplicata
  fi
fi

JOB="$(date +%s)$$"; S="$STATE_ROOT/$JOB"; mkdir -p "$S"
[ -n "$SIG" ] && printf '%s %s\n' "$NOW" "$JOB" >"$DEDUP/$SIG"
printf '%s' "$JSON" >"$S/job.json"
setsid bash "$0" __worker "$JOB" </dev/null >>"$S/launch.log" 2>&1 &
disown 2>/dev/null || true
printf 'JOB\t%s\n' "$JOB"
exit 0
