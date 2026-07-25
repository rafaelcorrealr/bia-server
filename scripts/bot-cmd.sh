#!/usr/bin/env bash
# bot-cmd.sh <sub> [arg] — comandos utilitários do Download Bot (chamado via SSH pelo n8n).
#   subs: ajuda | pastas | espaco | fila | quero
# Imprime texto pronto pro Telegram no stdout. Nunca falha feio (mensagem amigável).
set -u
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

DL="${TG_DL_DIR:-/mnt/Hi0/Downloads}"
STATE="${TG_DL_STATE:-/home/bia/.local/state/tg-dl}"
ANILIST="${TG_DL_ANILIST:-/home/bia/.local/bin/anilist-add.sh}"
QCRED="${QBIT_CRED_FILE:-/home/bia/.config/tg-dl/qbit-cred}"
SUB="${1:-ajuda}"; ARG="${2:-}"

case "$SUB" in
  ajuda|help|start)
    cat <<'EOF'
🤖 Download Bot — o que eu faço

📥 Baixar
• Link t.me/… → baixo e pergunto o nome final
• Vários links do mesmo canal → pergunto o intervalo, e você pode dar um NOME de pasta 📁
• magnet: / .torrent → adiciono no qBittorrent

🗂️ Organização
/lista — inventário de Downloads
/pastas — pastas em Downloads
/espaco — uso dos discos
/fila — downloads em andamento

📊 Torrents
/status — velocidade e progresso
/parar [nome] — pausa o seeding
/retomar [nome] — volta o seeding

🎬 AniList
/quero <título> — adiciono na sua lista "quero assistir"

/ajuda — esta mensagem
EOF
    ;;

  pastas)
    found=0
    for x in "$DL"/*/; do
      [ -d "$x" ] || continue
      nm="$(basename "$x")"
      sz="$(du -sh "$x" 2>/dev/null | cut -f1)"
      cnt="$(find "$x" -maxdepth 6 -type f 2>/dev/null | wc -l)"
      printf '📁 %s — %s (%s arq)\n' "$nm" "$sz" "$cnt"
      found=1
    done
    [ "$found" = 0 ] && echo "(nenhuma pasta em Downloads ainda)"
    ;;

  espaco)
    echo "💾 Discos:"
    for m in Hi0 Se0 Sa1 Sa2; do
      read -r avail size pct < <(df -h --output=avail,size,pcent "/mnt/$m" 2>/dev/null | tail -1)
      [ -n "${avail:-}" ] && printf '• %s: %s livre de %s (%s usado)\n' "$m" "$avail" "$size" "$pct"
    done
    ;;

  fila)
    any=0
    for d in "$STATE"/*/; do
      [ -d "$d" ] || continue
      st="$(cat "$d/state" 2>/dev/null)"
      case "$st" in
        run|export|await)
          md="$(python3 -c "import json;print(json.load(open('$d/job.json')).get('mode','?'))" 2>/dev/null || echo '?')"
          echo "⏳ Telegram ($md) — $st"; any=1 ;;
      esac
    done
    if [ -f "$QCRED" ]; then
      # shellcheck disable=SC1090
      . "$QCRED"
      C="$(mktemp)"
      curl -s -c "$C" -X POST "$QBIT_URL/api/v2/auth/login" \
        --data-urlencode "username=$QBIT_USER" --data-urlencode "password=$QBIT_PASS" >/dev/null 2>&1
      out="$(curl -s -b "$C" "$QBIT_URL/api/v2/torrents/info?filter=downloading" 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for t in d:
    print("⬇️ %d%% — %s" % (int(t.get("progress",0)*100), t.get("name","?")[:42]))
' 2>/dev/null)"
      rm -f "$C"
      [ -n "$out" ] && { echo "$out"; any=1; }
    fi
    [ "$any" = 0 ] && echo "✅ Nada baixando agora."
    ;;

  quero)
    [ -z "$ARG" ] && { echo "Uso: /quero <título do anime>"; exit 0; }
    r="$("$ANILIST" --status quero "$ARG" 2>&1)"
    if [ "${r#OK: }" != "$r" ]; then
      t="${r#OK: }"; t="${t%% → *}"
      echo "🎬 «$t» — adicionado na sua lista do AniList (quero assistir) ✅"
    else
      echo "🤷 Não achei «$ARG» no AniList. Tenta o nome em inglês ou romaji."
    fi
    ;;

  *) echo "Comando desconhecido: $SUB" ;;
esac