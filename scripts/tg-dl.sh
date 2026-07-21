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

clean_name() { sed -E 's/^[0-9]+_[0-9]+_//' <<<"$1"; }   # tira prefixo "<dialog>_<msg>_"

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
finish_batch() {  # finish_batch <chat> <job> [descricao]   (usa $S/before.lst)
  local CHAT="$1" JOB="$2" DESC="${3:-download}" S="$STATE_ROOT/$JOB"
  local newf=() f
  while IFS= read -r f; do
    [ -n "$f" ] && case "$f" in *.tmp) ;; *) newf+=("$f");; esac
  done < <(comm -13 "$S/before.lst" <(ls -1 "$DL_DIR" 2>/dev/null | sort))
  local n="${#newf[@]}"
  if [ "$n" -eq 0 ]; then
    tg_send "$CHAT" "⚠️ Terminei mas não vi arquivos novos. Veja o log do job ($JOB)."
    echo "done-empty" >"$S/state"; return 0
  fi
  # lista resumida (máx 12 nomes — evita estourar o limite de 4096 chars do Telegram)
  local list="" i=0
  for f in "${newf[@]}"; do
    i=$((i+1)); [ "$i" -le 12 ] && list+="• $(clean_name "$f")"$'\n'
  done
  [ "$n" -gt 12 ] && list+="… e mais $((n-12)) arquivo(s)"$'\n'
  # UMA tarefa no Todoist p/ o lote inteiro (não uma por arquivo)
  "$TODOIST_BIN" "📥 Organizar: $n arquivo(s) ($DESC)" "Origem: Telegram (tdl) — lote de $n arquivo(s)
Pasta: $DL_DIR
Ex.: $(clean_name "${newf[0]}")" >/dev/null 2>&1 || true
  tg_send "$CHAT" "✅ Baixei ${n} arquivo(s):
${list}"
  echo "done" >"$S/state"; return 0
}

# ---------------------------------------------------------------- worker: multi (vários links)
worker_multi() {  # <chat> <job> <link...>
  local CHAT="$1" JOB="$2"; shift 2
  local S="$STATE_ROOT/$JOB"; mkdir -p "$S"
  ls -1 "$DL_DIR" 2>/dev/null | sort >"$S/before.lst"
  local args=() l; for l in "$@"; do args+=(-u "$l"); done
  echo "run" >"$S/state"
  tg_send "$CHAT" "📥 Baixando ${#} arquivo(s)…"
  ( flock 200; "$TDL_BIN" dl "${args[@]}" -d "$DL_DIR" --template "$CLEAN_TMPL" ) 200>"$STATE_ROOT/.tdl.lock" >"$S/tdl.log" 2>&1
  finish_batch "$CHAT" "$JOB" "multi-link"
}

# ---------------------------------------------------------------- worker: range (intervalo)
worker_range() {  # <chat> <job> <tgchat> <min> <max> [topic]
  local CHAT="$1" JOB="$2" TG="$3" MIN="$4" MAX="$5" TOPIC="${6:-}"
  local S="$STATE_ROOT/$JOB"; mkdir -p "$S"
  ls -1 "$DL_DIR" 2>/dev/null | sort >"$S/before.lst"
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
  echo "run" >"$S/state"
  tg_send "$CHAT" "📥 Baixando o intervalo (msg $MIN a $MAX) — ${n} arquivo(s)…"
  "$TDL_BIN" dl -f "$S/export.json" -d "$DL_DIR" --template "$CLEAN_TMPL" >"$S/tdl.log" 2>&1
  flock -u 200
  finish_batch "$CHAT" "$JOB" "intervalo msg $MIN-$MAX"
}

# ================================================================ dispatch
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
links = j.get("links", []) or []
print("LINKS=(" + " ".join(q(x) for x in links) + ")")
PY
)"
  case "$MODE" in
    multi) worker_multi "$CHAT" "$JOB" "${LINKS[@]}" ;;
    range) worker_range "$CHAT" "$JOB" "$RCHAT" "$RMIN" "$RMAX" "$RTOPIC" ;;
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
