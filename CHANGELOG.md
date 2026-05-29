# Changelog

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
