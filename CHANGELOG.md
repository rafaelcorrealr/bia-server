# Changelog

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
