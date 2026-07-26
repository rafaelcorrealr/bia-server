# Changelog

## [2.18.0] — 2026-07-25

### Pipeline de organização de animes — manter no Hi0 + renomear + título real + AniList "Baixado"

Organiza os animes/mangás baixados **sem tirar do HD de download** (Hi0): integra ao Jellyfin, renomeia pro padrão de episódio e marca no AniList. Motor = script leve no `tg-dl` (Sonarr descartado — a ideia é manter no Hi0, que tem 1,7T livre, e não lotar o Se0 a 88%).

- **Jellyfin lê o Hi0 (read-only)**: `/mnt/Hi0/Media → /MediaHi0:ro` no compose do Jellyfin (`services.volumes` **e** `x-casaos.volumes`, editado com `sudo python3`, backup `.bak-20260725`) + library **"Animes (Hi0)"** → `/MediaHi0/Animes` (criada via API, HTTP 204). Disco "em risco" protegido pelo mount read-only.
- **`scripts/rename-media.sh` (novo)**: renomeia pro padrão parseável — anime `<Nome> SxxEyy.ext` em `Media/Animes/<Nome>/`; mangá `capitulo/volume N - <Nome>.ext` em `Media/Mangas/`. Preserva `SxxEyy` explícito (multi-temporada tipo Bluey), fallback pra ordem quando não há número (flag `(?)`), idempotente, grava `.rename-log`. Dry-run por padrão (`--apply`). Fix: `re.match` (âncora) pra não casar dígitos finais de IDs longos do Telegram como nº de episódio.
- **`scripts/jellyfin-retitle.sh` (novo, Fase B)**: puxa o **título real do episódio** (em PT) da API do Jellyfin (`/Items?...IncludeItemTypes=Episode&Fields=Path`) e regrava no arquivo (`<Nome> SxxEyy - <Título>.ext`). Fallback = nome limpo; pula título genérico ("Episódio N"); idempotente; mapeia container→host (`/MediaHi0`→`/mnt/Hi0/Media`). Gotcha: `echo|python3 <<'PY'` não funciona (heredoc rouba o stdin) → dados por arquivo temp.
- **`scripts/anilist-add.sh`**: novo `--list <nome>` → `customLists` no `SaveMediaListEntry`, marca na lista custom **"Baixado"** (mantendo o status obrigatório do AniList).
- **`scripts/tg-dl.sh`**: novo `organize_batch` (fim dos lotes multi/range/chat) — se anime/mangá: `rename-media.sh --apply` → scan Jellyfin → `anilist-add.sh --list Baixado` → **retitle atrasado destacado** (`setsid bash -c 'sleep 200; jellyfin-retitle --apply; rescan'`, sem depender de timer systemd por causa do `Linger=no`). `finish_batch` (5º arg `MT`) não cria mais a task "organizar manual" no Todoist p/ anime/mangá.
- **Bot pergunta o tipo** (classificador n8n): novo estágio `await_type` — depois da pasta, "🎬 anime/manga/outro?" (`cancelar` aborta); `mtype` viaja no job → `RTYPE` no tg-dl. Deploy com offset (`978296117`) e Schedule Trigger preservados; 31 nós, ativo. Harness (chat/range/multi/cancelar) ok.
- **Legado organizado**: 6 séries movidas pro Hi0 e identificadas pelo Jellyfin (FMA Brotherhood, Monogatari Off&Monster, Oshi no Ko, Sentenced to Be a Hero, Frieren 2nd Season, Umamusume S3); 99/112 eps com título real (13 do Uma S3 no fallback).

## [2.17.0] — 2026-07-25

### Comandos de download — Fases 2 e 3 + UX "toca→cola" (3 fases completas)

- **Fase 2 — `/download_chat`** (baixar o chat inteiro): `scripts/tg-dl.sh` ganhou modo `chat` (`worker_chat`) + `--preview` (`preview_chat`); o classificador n8n ganhou `parseChat` (link → chat+tópico), pending `await_chat_folder` e `kind:'chatpreview'` roteando pro **nó novo `SSH preview`** (Switch saída 11). O preview roda `tdl chat export` (só mídia) com `flock -w 5` (não trava o n8n se houver download) + `timeout 100`, conta os arquivos, sugere a pasta e vira **cache** reusado no download (`.preview/<key>.json`, <30 min). Workflow 30→**31 nós**, offset preservado.
- **UX "toca→cola"**: no Telegram, comando tocado no menu é sempre enviado na hora (limitação do cliente). Agora comando **sozinho** (sem link) seta pending `await_links` e pede "📎 manda o link"; a próxima mensagem com link é consumida (interceptor antes do guard `!isLink`). Helper `startDownload` unifica o disparo. `setMyCommands` com **13 comandos** (incluído `/download_chat`).
- **Fase 3 — anti-colisão** (só `scripts/tg-dl.sh`): batch baixa com `BATCH_TMPL='{{ .MessageID }}_{{ filenamify .FileName }}'` (sempre único) e `dedupe_rename` remove o prefixo `<id>_` **só quando o nome limpo está livre**, mantendo-o nos que realmente colidem (nada se sobrescreve). O prefixo é validado contra o conjunto de MessageIDs do lote (`ids.lst`), então nomes legítimos tipo `2024_x.mkv` não são cortados. Resolve o **Job B** (`@AniCatBot.mp4` ×64 → 64 arquivos).
- **Testes**: 13 cenários do classificador (`docker exec n8n node`) + 3 do anti-colisão (`tdl` falso). Werus validou ao vivo `/download_chat` e `/download_range`.

## [2.16.0] — 2026-07-25

### Organização por pasta nos lotes + comandos do bot + comandos de download explícitos

- **Pasta nos lotes**: `scripts/tg-dl.sh` — `worker_range` **e** `worker_multi` baixam numa subpasta; `sanitize_dir` bloqueia path-traversal (`../` não escapa); helpers `count_new`/`batch_progress`/`finish_batch` recebem o dir. O classificador n8n pergunta o nome da pasta.
- **Comandos do bot** (novo `scripts/bot-cmd.sh` + nós n8n `SSH cmd`/`Reply cmd ok/erro`): `/ajuda`, `/quero <título>` (add no AniList via `anilist-add.sh`), `/fila`, `/pastas`, `/espaco`. `/start` consertado (era "retomar" → agora ajuda). Menu registrado via `setMyCommands` (12 comandos).
- **Fix `/lista`**: estourava o limite de 4096 chars do Telegram (caminhos longos pós-pastas) → `sendMessage` falhava calado; agora com cap de ~3600 chars + "… use /pastas".
- **Fase 1 — comandos de download explícitos**: `/download_link`, `/download_list`, `/download_range` (+ `/download_chat` stub p/ Fase 2); **link solto sem comando → rejeitado** com orientação (+ o `/download_link` pronto). Novo pending `await_folder`. Classificador reescrito (14/14 testes via `docker exec n8n node`).
- Organizados em pastas: `Jackie Chan Adventures/` (95 `.avi`) e `Bluey/` (152 eps). Deploys n8n com offset preservado. Diagnóstico: colisão de nomes no Job B (`@AniCatBot.mp4` ×64 → 1 arquivo).

## [2.15.0] — 2026-07-24

### Sistema de progresso de download (Trilhas A + B)

- **Trilha A — torrents (qBit → Telegram)**: novo `scripts/qbit-progress.sh` + `system/qbit-progress.{service,timer}` (system unit, `User=bia`, 1 min). Uma mensagem **editada no lugar** por torrent baixando (`⬇️ NN% · MB/s · ETA · «nome»` → `✅ 100%` e para); ocioso = silêncio. Estado em `~/.local/state/qbit-progress/track` (edita só quando muda).
- **Trilha B — lote do Telegram (tdl)**: `scripts/tg-dl.sh` ganhou `tg_send_id`/`tg_edit`/`count_new`/`batch_progress`; os modos multi/range rodam o `tdl` em background e editam `📥 k/N` (por contagem de arquivos — tdl não expõe % legível); `finish_batch` edita a mesma msg pro `✅ Baixei N`. Single inalterado. Intervalo: `TG_DL_PROGRESS_INTERVAL` (default 60s).

### Todoist ativado + backfill + etiquetas Werus+HOMELAB

- Token pessoal **reaproveitado do plugin `werus-dashboard`** → `~/.config/tg-dl/todoist-token` (600). `scripts/todoist-task.sh` migrado **REST v2 → API v1** (`api.todoist.com/api/v1/tasks`) e etiquetas p/ **Werus + HOMELAB** (`TODOIST_LABELS` CSV). Agora `tg-dl.sh` **e** `qbit-todoist-poll.sh` criam tarefas de "Organizar" sozinhos.
- Backfill: 252 `.cbz` do Beelzebub apagados (após conferir 252/252 no Suwayomi) + **16 tarefas "Organizar" agrupadas por coleção** para o conteúdo já em `/mnt/Hi0/Downloads` (55 GB, 192 entradas).

### AniList integrado (rastreador "tenho/quero")

- `scripts/anilist-add.sh` (GraphQL; **User-Agent de navegador p/ furar o Cloudflare 403**; `search` + `SaveMediaListEntry`; status em pt). OAuth (client 46872) → token de acesso (1 ano) em `~/.config/tg-dl/anilist-token`. Conta **MrWerus**; **8 animes baixados semeados como *Planning***. Roadmap HomeLab 2.0: Jellyseerr → Ryot → Shoko.

## [2.14.1] — 2026-07-24

### Fix hotplug de discos externos + recuperação da fila de transcrição

- **Bug encontrado**: discos `Sa1`/`Sa2` (HDs USB) plugados depois do boot não montavam — fstab usa `nofail`, systemd só tenta 1x no boot. A fila de transcrição (`os.path.exists()`) leu os vídeos como sumidos e **encerrou achando que tinha terminado**, faltando na real 660 vídeos/296,7h (62,7% feito).
- **Fix imediato**: mount manual + `systemctl restart transcricao-cursos.service`.
- **Fix definitivo**: `/etc/udev/rules.d/99-hotplug-discos.rules` (versionado em `system/`) — dispara `ENV{SYSTEMD_WANTS}` da mount unit correspondente sempre que o udev detecta o disco (por `ID_FS_UUID`), cobrindo os 4 discos (Hi0/Se0/Sa1/Sa2). Validado com `udevadm test`, sem precisar de reboot.

## [2.14.0] — 2026-07-21

### Download Bot — multi-link + intervalo (grupos com tópicos) + encaminhado + robustez

`tg-dl.sh` reescrito com 3 modos via payload `--job` base64: **single** (com rename), **multi** (vários links), **range** (intervalo). Classificador n8n ("Offset e classificar") reescrito.

- **Vários links numa mensagem** → baixa todos (`tdl dl -u ... -u ...`).
- **Intervalo** (o caso "temporada/volumes inteiros"): 2+ links do mesmo canal → o bot pergunta "baixar tudo no intervalo? OK / só esses"; OK → `tdl chat export -c <id> --topic <t> -T id -i <min> -i <max>` + `dl -f`. Detecta **grupos com tópicos** (`t.me/c/<id>/<tópico>/<msg>`): a mensagem é o último número, o tópico vai via `--topic`.
- **Encaminhado**: reconstrói o `t.me/…` do metadado (`forward_origin`) e baixa (canais que permitem encaminhar).
- Nomes de lote limpos (`--template '{{ filenamify .FileName }}'`); mensagem final resumida (12 nomes + "e mais N"); 1 tarefa Todoist por lote.
- **Robustez**: `flock` serializa o `tdl` (banco bolt = 1 processo — antes 2 downloads simultâneos falhavam) + dedup no launcher (corrida de polls concorrentes não dispara o mesmo link 2×).
- Validado: 16/16 + 8/8 testes unitários (via `docker exec n8n node`); ao vivo baixou 252 capítulos de Beelzebub por intervalo.

### qBittorrent — resgate de dados + save path

- Movidos 12 GB (3 torrents) da camada efêmera do container (`/app/qBittorrent/downloads`) → `/downloads` (host) via `setLocation`, seeding intacto.
- **Save path padrão corrigido** (`/app/qBittorrent/downloads` → `/downloads`) via `setPreferences` — evita novos torrents caírem na camada efêmera.

### Bot → Todoist (scaffold — pendente token)

- `scripts/todoist-task.sh` (helper REST v2, Inbox + label HOMELAB), `scripts/qbit-todoist-poll.sh` + `system/qbit-todoist.{service,timer}` (timer de sistema, 3 min, baseline na 1ª execução). `tg-dl.sh` cria tarefa ao fim do download.
- ⚠️ Requer o token do Todoist em `~/.config/tg-dl/todoist-token` (Werus gera).

### Suwayomi — fonte local (Beelzebub)

- Configurada `server.localSourcePath` (reusa o mount `/mnt/Se0/30-Mangás(Suwayomi)` → `.../downloads/local`); 252 `.cbz` de Beelzebub copiados p/ `local/Beelzebub/`; manga na biblioteca (252 caps, ordenados).

## [2.13.0] — 2026-07-19

### Download Bot — confirmação/rename do nome + fim das mensagens duplicadas

Duas mudanças no `@MaestroTribalBot` (workflow `Download Bia`, **24→27 nós**, Switch 9→10 saídas):

**Regra de nome (baixa já → renomeia no fim)** — ao mandar um `t.me/…`:
- O download começa **destacado em background** e o bot detecta o nome real, já **limpo** do prefixo `<chatid>_<msgid>_`, e pergunta o nome final.
- **OK** mantém o nome limpo; um **novo nome** → bot **re-confirma** (`✏️ Renomear pra «…»?`) → guarda → **renomeia o arquivo ao terminar** o download.
- Estado: `staticData.pending` no n8n (`await_name`→`await_confirm`, TTL 2h) + `~/.local/state/tg-dl/<job>/final` (nome em base64, gravado pelo nó "SSH nome"; à prova de acento/injeção).
- **Preservação de extensão**: nome sem extensão de mídia conhecida reusa a original (ex.: `Noragami S01E12` → `Noragami S01E12.mp4`).

**Fim das mensagens duplicadas** (bug reportado):
- Causa: `tdl dl` bloqueante segurava a execução do n8n por todo o download → o `offset` só persiste no fim → o Telegram reservia as mensagens e cada poll reprocessava (re-download + eco).
- Correção: novo script host **`scripts/tg-dl.sh`** em modo *launcher* dispara um worker `setsid` destacado e retorna em <1s; a execução do n8n fecha rápido, o offset persiste, o eco some.

Novos nós: Code "Store pending", SSH "SSH nome", Telegram "Reply naming". Deploy via API com offset preservado, deactivate→activate. Validado ao vivo (Noragami: `AnV-12.mp4` → `Noragami-S01E12.mp4`, uma mensagem só).

## [2.12.0] — 2026-07-18

### Download Bot — operar downloads/qBittorrent pelo Telegram

Quatro comandos novos no `@MaestroTribalBot` (workflow `Download Bia`, 16→24 nós, Switch 5→9 saídas):

- **`/lista`** (`/ls`, `/downloads`) — inventário de `/mnt/Hi0/Downloads/` via `find`+`awk` (40 maiores + total + espaço livre).
- **`/status`** (`/torrents`) — taxa ⬆️/⬇️ global (soma dos torrents) + lista com estado (⬆️/💤/⏸️/⬇️), %, ratio e upload de cada.
- **`/parar`** / **`/parar todos`** / **`/parar <trecho>`** — pausa seeding de todos (`hashes=all`) ou por substring do nome.
- **`/retomar`** — simétrico (`torrents/start`).

Detalhes técnicos:
- Cada galho = nó **SSH** roda `curl`+`jq` no host (`localhost:8181`, login+consulta numa tacada, sem plumbing de cookie no n8n) → nó **Reply** manda o `stdout`. `/status`+`/parar`+`/retomar` compartilham 1 Reply-ok (`{{ $json.stdout }}`) + 1 Reply-erro.
- Code node extrai `arg` sanitizado (whitelist `[A-Za-z0-9 ._-]`, ≤60 chars) → anti-injeção no shell (bot single-user, mas prevenido).
- qBittorrent **v5.0.4** (WebAPI 2.11.2): endpoints nativos v5 `torrents/stop` / `torrents/start`.
- Deploy via API n8n com `staticData.offset` preservado + deactivate→activate (re-registra cron). Scripts validados no host antes de subir. Validado ao vivo.
- ⚠️ Achado: 3 dos 4 torrents salvam em `/app/qBittorrent/downloads` (caminho interno do container, fora do host — dado some se recriar).
- Organização/renomear de mídia: motor será **Sonarr** (decidido, planejado, **não implementado** nesta versão).

---

## [2.11.2] — 2026-07-16

### Download Bot — aviso para arquivo enviado/encaminhado

- Novo galho **`arquivo`** no workflow (15→16 nós): mensagem com mídia mas **sem texto** (documento/vídeo/áudio/voz/animação — arquivo enviado ou encaminhado) → reply "📎 Recebi um arquivo, mas não dá pra baixar assim (limite 20 MB da API de bots). Me mande o LINK t.me/… da mensagem." Antes era silenciosamente ignorada (`if (!text) continue`).
- **Motivo**: arquivo encaminhado chega sem `text`, só com `document` + `forward_origin`. A API de bot do Telegram não baixa arquivos > 20 MB; o `tdl` baixa, mas precisa do link `t.me/…`, não do arquivo.
- Deploy via API n8n, offset preservado. Validado ao vivo (reply confirmado).

---

## [2.11.1] — 2026-07-16

### Download Bot — galhos tdl/magnet validados, DDL desativado + rede de proteção

- **Verificação ao vivo**: workflow "Download Bia" (n8n `qLUHOaZrAqtqXwGR`, `@MaestroTribalBot`) ativo, polling 5s confirmado (conexões n8n→api.telegram.org observadas). Runtime deps OK: tdl v0.20.3 autenticado, qBittorrent login, sshd, `/mnt/Hi0/Downloads/` gravável.
- **Galho t.me→tdl**: validado por 2 downloads reais do dia (Jujutsu Kaisen 199 MB + Fate/Zero 244 MB).
- **Galho magnet→qBittorrent**: validado ao vivo (torrent adicionado via API, savepath `/downloads` OK).
- **Galho DDL http→curl DESATIVADO** (Werus não usa — sites de DDL só têm anúncio): Code node não classifica mais `ddl`; nós SSH curl ficam dormentes.
- **Rede de proteção**: qualquer envio que não seja `t.me`/`magnet` → 4ª saída do Switch (`nao_suportado`) → novo nó Telegram "Reply nao suportado" ("❌ Não reconheci esse envio…", nada é baixado). Deploy via API n8n (14→15 nós), offset preservado, reativação limpa deactivate→activate.
- **Diagnóstico**: execuções "error" no histórico do n8n = `ECONNRESET` intermitente no getUpdates (~12/dia de ~17k polls); `saveDataSuccessExecution: none` faz só erros aparecerem — não é quebra.

---

## [2.11.0] — 2026-07-15

### ConFin — comprovantes de pagamento (Pix/boleto) + deduplicação por ID de transação

- **Comprovantes via Telegram** (imagem OU PDF): novo `app/comprovante.py` (OCR tesseract-por p/ foto, `pdftotext`/poppler p/ PDF, fallback OCR se escaneado) + parser que extrai valor/data/tipo/contraparte, calibrado em 3 comprovantes reais (Inter Pix, MP boleto, MP Pix). Endpoint único `POST /api/imagem/triagem` (QR NFC-e → comprovante → senão guarda como imagem) cria a pendência server-side.
- **Caixa de imagens**: arquivo não reconhecido vai p/ `/data/inbox` e aparece no grupo "Imagens p/ revisar" em `/pendentes`; o comprovante fica anexado à pendência (thumbnail/📄) e visível no form de confirmação.
- **Deduplicação**: extrai o id único da transação (Pix E2E `E0041…` / código de autenticação / nº do comprovante); índice único parcial em `lancamentos_pendentes.transacao_id` (à prova da corrida do poll de 5s) + grava no `nfce_chave` do lançamento ao confirmar — reenvio/corrida nunca duplicam; bot responde "♻️ já está na caixa". De brinde, conserta a dedup de NFC-e confirmada.
- **N8N** "Project ConFin" (11→10 nós): `Offset e classificar` captura `document` (PDF), ramo foto → `HTTP triagem`, "Enviar recebido" com resposta 3-vias (recebido/imagem/duplicado).
- Dockerfile: `tesseract-ocr-por` + `poppler-utils`; `pytesseract` no requirements. **51 testes verdes**. Commit confin `e8afab6` (pushed).

---

## [2.10.1] — 2026-07-14

### Transcrição de Cursos — fix loop infinito de OOM + tuning de prioridade/threads

- **Bug crítico**: `transcricao-cursos.service` preso havia 2h+ num loop de OOM-kill (153 restarts) no mesmo vídeo de 2h51min — `MemoryMax=2G` estourava durante `model.transcribe`; SIGKILL não é capturável pelo script, então a fila nunca marcava falha e reiniciava pra sempre.
- **Fix**: `MemoryMax` `2G→6G`; novo `falhas.json` no `transcrever_fila.py` — contador de tentativas persistido *antes* do `transcribe()` (sobrevive a SIGKILL), pula o vídeo automaticamente após 2 falhas seguidas em vez de travar a fila inteira.
- **Tuning de performance** (a pedido do Werus): `Nice` `19→-10`, `IOSchedulingClass` `idle→best-effort` `IOSchedulingPriority=0`, `cpu_threads` do faster-whisper `~4→20` (era o real gargalo, não a prioridade). RAM mantida conservadora (`MemoryMax=6G`) de propósito — é o único recurso que pode travar o host.

## [2.10.0] — 2026-07-14

### ConFin — deploy `60ee693` + migração N8N (Caixa de Pendências) + feature no dashboard

- **Deploy** do commit `60ee693` (pull da Anna): parser de notificação bancária (`/api/notificacao/parse-text`), itens em qualquer lançamento, nome fantasia de cartão e **Caixa de Pendências**. Rebuild via `docker compose up -d --build` (⚠️ `docker restart` não troca imagem); tabela `lancamentos_pendentes` criada no boot.
- **Workflow N8N "Project ConFin" migrado (19 → 11 nós)**: foto/link → parse → `POST /api/pendentes` → "🧾 Recebido, confirme no app". Removida a máquina de botões/callback; confirmação agora na tela `/pendentes`. Aplicado via API (backup do fluxo antigo salvo).
- **Feature no dashboard do ConFin** (repo confin, commit `5f4ccba`): aviso "!" vermelho de pendências no card de Atividade recente (alterna recentes ↔ pendências) e no nav.

---

## [2.9.0] — 2026-07-11

### Transcrição de Cursos — escopo final + fila ativa

- Sa1 incluído no escopo (confirmado pelo Werus): fila unificada **2472 vídeos, 796,1h, 39 cursos**
- Monitor de progresso: nota `📊 Progresso.md` regravada a cada vídeo + página web via workflow N8N `/webhook/transcricao`
- Fila batch **ligada** via `transcricao-cursos.service` (systemd, enabled, `MemoryMax=2G`, `Nice=19`) — processando 796h em background

### ConFin — deploy do commit `f879e03`

- `git pull` + rebuild + recriação via `casaos-cli app-management apply` — ⚠️ `docker restart` sozinho **não troca a imagem** (gotcha novo)
- Novo endpoint `GET /api/resumo` validado (200 c/ token, 401 sem) — alimenta o widget financeiro da Anna

## [2.8.0] — 2026-07-11

### Suwayomi (leitor de mangás)

- App CasaOS `suwayomi` (`ghcr.io/suwayomi/suwayomi-server:stable`, :4567, 1GB RAM, CBZ); biblioteca em `/mnt/Se0/30-Mangás(Suwayomi)/`
- Gotcha: DNS do roteador não resolve `github.com` na porta 80 (Azure IP sem HTTP) → `dns: [1.1.1.1, 8.8.8.8]` no compose; IPv6 dos containers desabilitado (quebrado)
- Índice Keiyoushi (1356 extensões, 106 pt-BR) + MANGA Plus instalada; e2e validado (download de capítulo pt-BR)

### Transcrição de Cursos (handoff Anna → Bia)

- faster-whisper `small` int8 + VAD, CPU-only (venv `/home/bia/transcricao/`); piloto a 4-4,7x tempo real
- Inventário: 2472 vídeos / 796h (Se0 + Sa1, que não era backup como se pensava) em `inventario.tsv`
- Cofre Obsidian novo "Transcrições" (curso/módulo/aula, propriedade `revisao`), sincronizado via Syncthing (share "Obsidian" existente) com Anna/C85/Tablet-SE
- Monitor de progresso: nota `📊 Progresso.md` no cofre + página web via workflow N8N (`/webhook/transcricao`)
- Fila batch (`transcricao-cursos.service`) pronta, aguardando validação de qualidade do piloto

## [2.7.0] — 2026-07-11

### Download Bot no Telegram (@MaestroTribalBot)

- Workflow N8N "Download Bia" reconstruído via API (14 nós, ativo) com bot dedicado — sem conflito de getUpdates com o ConFin (@Kuro8Bot)
- Roteamento por tipo de link: `t.me/` → SSH tdl · `magnet:`/`.torrent` → qBittorrent (cookie SID do login) · `http(s)` → curl com UA Chrome em background
- Galho de erro em cada rota: bot responde "❌ ... falhou: <motivo>"
- Downloads em `/mnt/Hi0/Downloads/`; polling 5s + `timeout=1` + `allowed_updates` explícito
- Testes end-to-end pendentes (Todoist 12/07)

## [2.6.0] — 2026-07-11

### ConFin Bot completo (Telegram + app) e sync de transcripts p/ widget de tokens

**ConFin (repo confin, commit `5429942`):**
- Fluxo NFC-e no app web: página `/nfce` (foto ou link do QR → confirmação com itens editáveis → grava)
- Itens da nota: tabela `lancamento_itens` + coluna `nfce_chave` com dedup (409 "cupom já lançado")
- `app/nfce.py`: parsing NFC-e compartilhado; endpoint novo `POST /api/nfce/parse-url` (fallback p/ QR ilegível)
- Histórico com expandível "ver itens"; `PRAGMA foreign_keys=ON` por conexão (cascade de itens)

**N8N — workflow "Project ConFin" (19 nós, ativo):**
- Reconstruído via API REST após perda do trabalho não salvo; polling 5s + `timeout=1`
- Fixes: thumbnail do Telegram (`photo[last]`), botões inline mortos (`allowed_updates` preso — agora explícito), galho de erro do parse-image pede o link, galho de erro do POST avisa cupom duplicado
- ⚠️ Bot @Kuro8Bot compartilhado com "Download Bia" — nunca ativar os dois juntos

**Sync transcripts Claude Bia→Anna (widget de tokens):**
- Pasta Syncthing `claude-bia` (send-only) + `scripts/sync-claude-transcripts.sh` + timer systemd 30min
- Sincroniza SÓ `~/.claude/projects/` (nunca credenciais); units versionadas em `system/`

## [2.5.0] — 2026-07-09

### ConFin Bot — migração para Bia + API JSON + N8N workflow

- ConFin containerizado: `Dockerfile` (python:3.12-slim + libzbar0), porta `8765`, `TZ=America/Sao_Paulo`, dados em `/DATA/AppData/confin/data/`
- API JSON: `app/routers/api.py` — `GET /api/contas`, `/api/categorias`, `POST /api/lancamentos`, `POST /api/nfce/parse-image`; auth Bearer via `CONFIN_API_TOKEN`
- N8N: workflow polling `getUpdates` (nós 1–7); nós 8–16 pendentes

---

## [2.4.0] — 2026-06-29

### Firefly III removido — substituído por WY Finance (app próprio na Anna)

- Containers `firefly_iii` e `firefly_db` parados e removidos
- Volumes `firefly_firefly_db` e `firefly_firefly_upload` deletados
- Timer systemd `backup-firefly-db.timer` desativado e removido
- Arquivos removidos: `compose/firefly/`, `scripts/backup-firefly-db.sh`, `system/backup-firefly-db.{timer,service}`

---

## [2.3.0] — 2026-06-06

### Aria2 + AriaNg — Gerenciador de downloads DDL

- **Aria2-pro**: daemon de download HTTP/FTP/torrent/magnet, porta RPC `6800`, download dir `/mnt/Hi0/Downloads/`.
- **AriaNg**: interface web em `http://192.168.15.11:6880`. Compose em `compose/aria2/docker-compose.yml`; token RPC em `compose/aria2/.env` (gitignored).
- Mem limit: aria2 512 MB · ariang 64 MB. Ambos `restart: unless-stopped`.

### Syncthing — `.obsidian/` excluído da Bia

- `.stignore` criado em `/data/obsidian/.stignore` (local por device, não sincroniza) com padrão `**/.obsidian`.
- Pastas `.obsidian/` deletadas da Bia após backup em `/mnt/Sa2/Backup/.obsidian-vault-backup-2026-06-06`.
- Elimina os conflitos recorrentes de `appearance.json` que chegavam na Anna.

### Jellyfin — novos animes adicionados

- **Sousou no Frieren — 2ª Temporada**: pasta `Season 02/` criada, E01–E10 com nomenclatura `S02Exx.mkv`.
- **Yuusha-kei ni Shosu**: E05–E12 adicionados (ep 04 pendente via AriaNg).
- **Monogatari Off & Monster Season**: S01E06.5 (793 MB) recuperado de overlay do container e adicionado.

---

## [2.2.0] — 2026-06-06

### Backup PostgreSQL do Nextcloud + Watchtower

- **Backup `db-nextcloud` (PostgreSQL):** `pg_dump` via `docker exec` → `restic backup --stdin --tag nextcloud-db` — mesmos repos já existentes (Se0 + Sa2), retenção daily 7 / weekly 4 / monthly 6. Primeiro snapshot: `78acc224` (Se0) / `8347eb3e` (Sa2), 80 MB.
- Script: `scripts/backup-nextcloud-db.sh` — credenciais em `compose/nextcloud/.env` (gitignored).
- Timer systemd: `backup-nextcloud-db.timer` 03:30 BRT diário (15 min após Firefly DB). Enabled e testado ✅.
- **Watchtower 1.7.1:** `compose/watchtower/docker-compose.yml` — modo monitor-only (`WATCHTOWER_MONITOR_ONLY=true`), verifica atualizações diariamente às 08:00 BRT, sem auto-update. Notificações Telegram a adicionar quando o bot tiver `chat_id` configurado (item 3 do Roadmap).

---

## [2.1.0] — 2026-06-04

### Firefly III — App de finanças pessoais (BRL + pt_BR)

- Novo serviço: `firefly_iii` (porta `7590`) + `firefly_db` (MariaDB 11).
- Compose em `compose/firefly/docker-compose.yml`; mem_limit 512 MB em ambos.
- Configurado com `DEFAULT_LANGUAGE=pt_BR`, `DEFAULT_LOCALE=pt_BR`, `TZ=America/Sao_Paulo`.
- `APP_KEY` e senha do banco geradas com `/dev/urandom`; senha **fora do git**.
- Acesso: `http://192.168.15.11:7590` — setup inicial (conta admin + moeda BRL) pendente pelo usuário.
- Próximos passos: Personal Access Token para Werus Dashboard; subir `data-importer` (CSV/OFX); incluir `firefly_db` no backup restic.

---

## [2.0.0] — 2026-06-03

### Backup e Versionamento do cofre Obsidian (duas camadas independentes)

Princípio: **Syncthing é sincronização, não backup** — ele replica exclusões e
corrupção. Implementadas duas camadas independentes para proteger o cofre
(`/DATA/AppData/big-bear-syncthing/data/obsidian/Second Brain/`, ~136 MB).

**Camada 1 — Versionamento do Syncthing (recupera exclusão/edição acidental)**
- Folder "Obsidian" configurado com versionamento **Staggered, maxAge 90 dias**
  (via API REST do Syncthing, sem reiniciar o container).
- Ao receber uma exclusão/edição de outro device (Anna, celular), a Bia move a
  cópia local antiga para `.stversions/` **antes** de aplicar. Bia é sempre-ligada
  → vira o ponto de recuperação central.

**Camada 2 — Backup real com restic (snapshots imunes ao sync)**
- `restic 0.16.4` instalado.
- **Repo local:** `/mnt/Se0/20-Backups/restic-cofre` (disco diferente da fonte).
- **Repo externo:** `/mnt/Sa2/Backup/restic-cofre` (espelho via `restic copy`,
  mesmos chunker params para dedupe).
- Senha do repo em `~/.config/restic/cofre.pw` (chmod 600, **fora do git**).
  ⚠️ Sem a senha o backup é irrecuperável.
- **Retenção:** `--keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune`.
- **Automação (systemd):**
  - `scripts/backup-cofre.sh` + `system/backup-cofre.{service,timer}` — diário 03:00
    (backup local → forget/prune → copy externo → forget/prune).
  - `scripts/check-cofre.sh` + `system/check-cofre.{service,timer}` — `restic check`
    semanal (domingo 04:00) nos dois repos.
  - Services rodam como `User=bia`, `Nice`/`IOSchedulingClass=idle`.
- **Teste de restauração validado:** `restic restore latest` confere byte a byte
  com a origem (2633 arquivos) nos dois repos; `restic check` sem erros.

**Fase 2 (pendente):** repositório offsite (rclone + Backblaze B2/Storj).

---

## [1.1.4] — 2026-05-29

### Limites de RAM aplicados em todos os containers

Todos os containers agora possuem `memory limit` definido no compose,
garantindo que nenhum app possa esgotar a RAM do servidor individualmente.

| Container | Limite |
|---|---|
| jellyfin | 4GB (definido em v1.1.2) |
| n8n | 1GB |
| tika | 1GB |
| nextcloud | 1GB |
| big-bear-scrutiny | 512MB |
| big-bear-syncthing | 512MB |
| db-nextcloud | 512MB |
| qbittorrent | 512MB |
| myspeed | 256MB (já existia) |
| redis-nextcloud | 256MB |
| big-bear-nextcloud-cron-1 | 256MB |

---

## [1.1.3] — 2026-05-29

### Corrigido — montagem automática do Se0 após desligamento forçado

**Causa raiz:** após shutdown forçado, o filesystem do Se0 ficava "sujo". No boot seguinte, `udisks2` interferia com o `systemd-fsck` durante a recuperação do journal, causando SIGTERM no fsck (~6s). Com `nofail` no fstab, o sistema bootava sem o disco, deixando Jellyfin e Nextcloud sem dados.

**Fix 1 — `system/99-se0-internal.rules`**
- Regra udev: `UDISKS_IGNORE=1` para o UUID do Se0 (c7d5b681-...)
- Impede udisks2/devmon de gerenciar sdb1 — fsck completa sem ser interrompido
- Instalar em: `/etc/udev/rules.d/99-se0-internal.rules`

**Fix 2 — `system/se0-recovery.service` + `system/se0-recovery.sh`**
- Serviço systemd que roda no boot após docker e devmon
- Se Se0 não estiver montado: monta e reinicia jellyfin + nextcloud
- Fallback de segurança para qualquer falha futura de montagem
- Instalar: script em `/usr/local/bin/`, serviço em `/etc/systemd/system/`, `systemctl enable se0-recovery.service`

---

## [1.1.2] — 2026-05-29

### Prevenção de OOM

- **Jellyfin `MaxSimultaneousConvertingLimit`: 1** — transcodificação limitada a 1 stream simultâneo
- **Jellyfin `LibraryScanFanoutConcurrency`: 0 → 2** — scan de biblioteca limitado; antes ilimitado, causou o crash
- **Jellyfin `LibraryMetadataRefreshConcurrency`: 0 → 2** — idem para refresh de metadados
- **Jellyfin memória Docker: 8GB → 4GB** — container limitado à metade da RAM, deixando margem para os demais serviços
- **Swap: 3.7GB → 8GB** — reserva extra de segurança

---

## [1.1.1] — 2026-05-29

### Corrigido
- **Jellyfin sem mídia após renomear pasta:** ao renomear o volume do host (`30-Mídias` → `10-Mídias`) e atualizar o compose, o container continuava apontando para o path antigo pois o Docker preserva a configuração de volumes da criação original. Solução: `docker stop jellyfin && docker rm jellyfin && docker compose up -d` para recriar o container com os novos volumes.

### Incidente — OOM Crash (2026-05-29 ~02:09)

**Causa:** servidor travou por esgotamento de RAM (OOM — Out of Memory).

**O que aconteceu:** dois scans de biblioteca do Jellyfin foram disparados simultaneamente (Filmes + Animes). O Jellyfin abre um processo `ffprobe` por arquivo durante o scan — com dezenas de arquivos sendo analisados ao mesmo tempo, combinado com os processos `node` dos containers Docker e o `rclone` rodando em paralelo, os 8GB de RAM + 3.7GB de swap foram esgotados.

**Linha do tempo:**
- `01:52` — systemd-journald começa a reportar "Under memory pressure"
- `01:54` — OOM Killer ativado pelo rclone; kernel mata processos (`systemd` de usuário, `sd-pam`)
- `02:06` — container node (Docker) morto com 22GB de memória virtual alocada
- `02:09` — sistema trava completamente; desligamento forçado necessário

**Lição aprendida:** o Jellyfin não enfileira scans simultâneos — cada scan abre processos em paralelo. Não disparar mais de um scan de biblioteca ao mesmo tempo em servidores com pouca RAM.

---

## [1.1.0] — 2026-05-28

### Adicionado
- Apache Tika (OCR e indexação de texto completo para o Nextcloud)
- Tika integrado à rede interna do Nextcloud (`nextcloud_network`)

### Alterado
- **Migração dos dados do Nextcloud:** movidos de `/DATA/AppData/` (disco do OS) para `/mnt/Se0/60-Serviços/nextcloud/data/` (disco de 2TB dedicado)
- Hardware documentado corretamente: CPU é Xeon E5-2650 v4 (anterior: E5-2630); placa-mãe é Intel X99-P4 (anterior: ZSUS)
- Compose files refatorados para usar variáveis de ambiente (sem credenciais hardcoded)

### Corrigido
- Disco OS estava em risco de esgotamento com dados do Nextcloud crescendo — resolvido com a migração

---

## [1.0.0] — 2026-05-27

### Adicionado
- Nextcloud (nuvem privada) com PostgreSQL + Redis
- Jellyfin (servidor de mídia)
- Syncthing (sincronização de arquivos entre dispositivos)
- n8n (automação de workflows)
- qBittorrent (cliente BitTorrent)
- Scrutiny (monitoramento S.M.A.R.T. dos discos)
- MySpeed (histórico de velocidade de internet)
- CasaOS como painel de controle
- Acesso remoto via Tailscale VPN
