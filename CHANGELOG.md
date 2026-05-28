# Changelog

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
