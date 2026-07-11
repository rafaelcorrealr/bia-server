# HomeLab — Infraestrutura Self-Hosted

> **Nota:** toda a configuração, documentação e evolução deste HomeLab está sendo conduzida com o auxílio do [Claude](https://claude.ai) (Anthropic), utilizando majoritariamente o modelo **Claude Sonnet 4.7** via Claude Code. Os commits, decisões de arquitetura, scripts e documentação são resultado de uma colaboração direta entre o dono do servidor e a IA.

Servidor doméstico rodando sobre Ubuntu Server 24.04, gerenciado com Docker Compose e CasaOS. O objetivo é ter controle total sobre dados pessoais e experimentar automação e serviços open-source.

## Stack de serviços

| Serviço | Função | Porta |
|---|---|---|
| [Nextcloud](compose/nextcloud/) | Nuvem privada (arquivos, calendário, contatos) | 7580 |
| [Jellyfin](compose/jellyfin/) | Servidor de mídia (filmes, séries, música) | 8097 |
| [Syncthing](compose/syncthing/) | Sincronização P2P de arquivos entre dispositivos | 8384 |
| [n8n](compose/n8n/) | Automação de workflows (no-code/low-code) | 5678 |
| [qBittorrent](compose/qbittorrent/) | Cliente BitTorrent com WebUI | 8181 |
| [Scrutiny](compose/scrutiny/) | Monitoramento S.M.A.R.T. dos discos rígidos | 38080 |
| [MySpeed](compose/myspeed/) | Histórico de velocidade de internet | 5216 |
| [Apache Tika](compose/nextcloud/) | OCR e indexação de texto completo (integrado ao Nextcloud) | 9998 |
| [Aria2 + AriaNg](compose/aria2/) | Downloads DDL com WebUI | 6800 / 6880 |
| ConFin | Controle financeiro + bot NFC-e no Telegram ([repo próprio](https://github.com/rafaelcorrealr/confin)) | 8765 |

## Hardware

- **CPU:** Intel Xeon E5-2650 v4 (12 cores / 24 threads)
- **RAM:** 8 GB DDR4 ECC
- **OS Disk:** 109 GB (sistema + AppData dos containers)
- **Disco de dados:** 2× 2TB (mídias, downloads, Nextcloud, arquivo)
- **Rede:** LAN + Tailscale VPN para acesso remoto seguro

> Detalhes completos em [docs/architecture.md](docs/architecture.md)

## Como usar

### Pré-requisitos
- Docker e Docker Compose instalados
- [CasaOS](https://casaos.io) (opcional, para o painel de controle)

### Configuração

1. Clone o repositório:
   ```bash
   git clone https://github.com/rafaelcorrealr/homelab.git
   cd homelab
   ```

2. Copie o arquivo de variáveis e preencha com seus valores:
   ```bash
   cp .env.example .env
   nano .env
   ```

3. Suba o serviço desejado:
   ```bash
   docker compose -f compose/nextcloud/docker-compose.yml up -d
   ```

### Ordem recomendada para primeiro deploy

1. `nextcloud` (inclui PostgreSQL, Redis e Tika)
2. `jellyfin`
3. `syncthing`
4. `n8n`
5. `qbittorrent`
6. `scrutiny`
7. `myspeed`

## Segurança

- Nenhuma porta exposta diretamente para a internet — acesso externo feito via **Tailscale VPN**
- Credenciais gerenciadas via arquivo `.env` (nunca commitado)
- Dados do Nextcloud em disco separado do OS

## Histórico de versões

Ver [CHANGELOG.md](CHANGELOG.md)
