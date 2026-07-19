#!/usr/bin/env bash
# tg-dl.sh — download do Telegram (tdl) com confirmação/rename via bot.
#
# Uso (n8n, modo launcher):
#   tg-dl.sh <link> <chat_id>
#     -> dispara um worker DETACHED e imprime "JOB\t<id>" na hora (<1s).
#
# Interno (modo worker, chamado por si mesmo via setsid):
#   tg-dl.sh __worker <link> <chat_id> <job>
#     -> baixa em background, detecta o nome, manda msg1 pedindo confirmação,
#        espera o fim + a decisão de nome (arquivo state/final), renomeia e avisa.
#
# Coordenação com o n8n: o n8n grava o nome final escolhido em
#   $STATE_ROOT/<job>/final   (conteúdo = nome desejado, ou "__KEEP__" p/ manter o original limpo)
set -u
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

DL_DIR="${TG_DL_DIR:-/mnt/Hi0/Downloads}"
STATE_ROOT="${TG_DL_STATE:-/home/bia/.local/state/tg-dl}"
TOKEN_FILE="/home/bia/.config/tg-dl/token"
API="https://api.telegram.org"
TDL_BIN="${TG_DL_TDL:-tdl}"   # sobrescrevível p/ teste (TG_DL_TDL=./mock-tdl)

tg_send() {  # tg_send <chat_id> <text>
  local chat="$1" text="$2" tok
  if [ -n "${TG_DL_SEND_LOG:-}" ]; then    # teste: só registra, não manda
    printf '>>> [%s]\n%s\n' "$chat" "$text" >>"$TG_DL_SEND_LOG"; return 0
  fi
  tok="$(cat "$TOKEN_FILE" 2>/dev/null)"
  [ -z "$tok" ] && return 0
  [ -z "$chat" ] && return 0
  curl -s -o /dev/null --max-time 25 \
    "$API/bot${tok}/sendMessage" \
    --data-urlencode "chat_id=${chat}" \
    --data-urlencode "text=${text}" >/dev/null 2>&1
}

clean_name() { sed -E 's/^[0-9]+_[0-9]+_//' <<<"$1"; }  # tira prefixo "<chatid>_<msgid>_"

# ---------------------------------------------------------------- worker mode
if [ "${1:-}" = "__worker" ]; then
  LINK="${2:-}"; CHAT="${3:-}"; JOB="${4:-}"
  S="$STATE_ROOT/$JOB"; mkdir -p "$S"

  # snapshot da pasta ANTES de baixar
  mapfile -t before < <(ls -1 "$DL_DIR" 2>/dev/null)
  [ "${#before[@]}" -eq 0 ] && before=("")

  "$TDL_BIN" dl -u "$LINK" -d "$DL_DIR" >"$S/tdl.log" 2>&1 &
  TPID=$!

  # detecta o arquivo novo (tdl cria "<nome>.tmp" em ~1-2s)
  REL=""
  for _ in $(seq 1 60); do            # até ~30s
    while IFS= read -r f; do
      [ -n "$f" ] && { REL="$f"; break; }
    done < <(comm -13 <(printf '%s\n' "${before[@]}" | sort) <(ls -1 "$DL_DIR" 2>/dev/null | sort))
    [ -n "$REL" ] && break
    kill -0 "$TPID" 2>/dev/null || break   # tdl morreu sem criar nada
    sleep 0.5
  done

  if [ -z "$REL" ]; then
    wait "$TPID" 2>/dev/null
    echo "failed-no-file" >"$S/state"
    tg_send "$CHAT" "❌ Não consegui baixar (link inválido ou erro do tdl). Confira o link e tente de novo."
    exit 1
  fi

  BASE="${REL%.tmp}"                  # nome final que o tdl vai deixar (sem .tmp)
  CLEAN="$(clean_name "$BASE")"       # nome limpo (sem o prefixo numérico)
  printf '%s' "$CLEAN" >"$S/orig"
  printf '%s' "$BASE"  >"$S/base"
  echo "await" >"$S/state"

  tg_send "$CHAT" "📥 Baixando: «${CLEAN}»
Nome final? Responda OK pra manter, ou mande o novo nome (com extensão)."

  # espera o download terminar
  wait "$TPID"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "failed-dl" >"$S/state"
    tg_send "$CHAT" "❌ O download de «${CLEAN}» falhou (tdl rc=$rc)."
    exit 1
  fi

  SRC="$DL_DIR/$BASE"
  [ -f "$SRC" ] || SRC="$DL_DIR/$REL"   # fallback improvável

  # espera a decisão de nome (n8n grava em $S/final); default = manter nome limpo
  FINAL=""
  for _ in $(seq 1 3600); do            # até 30 min
    [ -f "$S/final" ] && { FINAL="$(cat "$S/final")"; break; }
    sleep 0.5
  done
  [ -z "$FINAL" ] && FINAL="$CLEAN"
  [ "$FINAL" = "__KEEP__" ] && FINAL="$CLEAN"
  FINAL="$(tr -d '/\000-\037' <<<"$FINAL")"   # sem barra nem controle
  [ -z "$FINAL" ] && FINAL="$CLEAN"

  # se o nome escolhido não terminar numa extensão de mídia conhecida,
  # reusa a extensão original (ex.: "Noragami S01E12" -> "Noragami S01E12.mp4")
  lext="$(printf '%s' "${FINAL##*.}" | tr 'A-Z' 'a-z')"
  case " mp4 mkv avi mov m4v webm ts m2ts flv wmv mpg mpeg 3gp cbr cbz pdf epub zip 7z rar mp3 flac m4a wav opus aac ogg srt ass " in
    *" $lext "*) : ;;                                # já tem extensão conhecida
    *) oext="${CLEAN##*.}"
       [ "$oext" != "$CLEAN" ] && [ -n "$oext" ] && FINAL="${FINAL}.${oext}" ;;
  esac

  DEST="$DL_DIR/$FINAL"
  if [ -e "$DEST" ] && [ "$SRC" != "$DEST" ]; then   # anti-colisão
    b="${FINAL%.*}"; e="${FINAL##*.}"
    if [ "$b" = "$e" ]; then DEST="$DL_DIR/${FINAL} (${JOB})"; else DEST="$DL_DIR/${b} (${JOB}).${e}"; fi
  fi

  if [ "$SRC" = "$DEST" ]; then
    tg_send "$CHAT" "✅ Pronto: «$(basename "$DEST")»"
  elif mv -- "$SRC" "$DEST" 2>>"$S/tdl.log"; then
    tg_send "$CHAT" "✅ Pronto: «$(basename "$DEST")»"
  else
    tg_send "$CHAT" "⚠️ Baixei, mas não consegui renomear. Ficou «$(basename "$SRC")»."
  fi
  echo "done" >"$S/state"
  exit 0
fi

# --------------------------------------------------------------- launcher mode
LINK="${1:-}"; CHAT="${2:-}"
if [ -z "$LINK" ]; then echo "ERR no-link"; exit 1; fi
JOB="$(date +%s)$$"
S="$STATE_ROOT/$JOB"; mkdir -p "$S"
printf '%s' "$LINK" >"$S/link"
printf '%s' "$CHAT" >"$S/chat"
setsid bash "$0" __worker "$LINK" "$CHAT" "$JOB" </dev/null >>"$S/launch.log" 2>&1 &
disown 2>/dev/null || true
printf 'JOB\t%s\n' "$JOB"
exit 0
