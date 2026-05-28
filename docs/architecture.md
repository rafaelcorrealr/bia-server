# Arquitetura do HomeLab

## Hardware

| Componente | Especificação |
|---|---|
| CPU | Intel Xeon E5-2650 v4 (12 cores / 24 threads) |
| Placa-mãe | Intel X99-P4 |
| RAM | 8 GB DDR4 ECC |
| GPU | NVIDIA GTX 550 Ti |
| OS | Ubuntu Server 24.04.1 LTS |
| Kernel | 6.8.0 |

## Discos

| Dispositivo | Ponto de montagem | Uso |
|---|---|---|
| `/dev/sda2` | `/` (109 GB) | Sistema operacional |
| `/dev/sdb1` | `/mnt/Se0` (2 TB) | Mídias, downloads, dados do Nextcloud |
| `/dev/sdc1` | `/mnt/Hi0` (2 TB) | Arquivo e dados legados |

> **Decisão de design:** Os dados do Nextcloud foram migrados do disco do OS para `/mnt/Se0` para evitar esgotamento do disco de sistema e aproveitar a capacidade do disco de mídias.

## Diagrama de serviços

```
                    ┌─────────────────────────────────────────┐
                    │              Ubuntu Server               │
                    │                                          │
  Internet/LAN ───► │  CasaOS (painel de controle :80)        │
  Tailscale VPN      │                                          │
                    │  ┌──────────┐  ┌──────────┐             │
                    │  │Nextcloud │  │ Jellyfin │             │
                    │  │  :7580   │  │  :8097   │             │
                    │  └────┬─────┘  └──────────┘             │
                    │       │                                  │
                    │  ┌────▼──────────────────────────────┐  │
                    │  │  nextcloud_network (bridge)        │  │
                    │  │  ┌──────────┐  ┌───────────────┐  │  │
                    │  │  │PostgreSQL│  │     Redis     │  │  │
                    │  │  │  :5432   │  │    :6379      │  │  │
                    │  │  └──────────┘  └───────────────┘  │  │
                    │  │  ┌──────────────────────────────┐  │  │
                    │  │  │  Apache Tika (OCR/indexing)  │  │  │
                    │  │  │          :9998               │  │  │
                    │  │  └──────────────────────────────┘  │  │
                    │  └───────────────────────────────────┘  │
                    │                                          │
                    │  ┌──────────┐  ┌──────────┐             │
                    │  │    n8n   │  │Syncthing │             │
                    │  │  :5678   │  │  :8384   │             │
                    │  └──────────┘  └──────────┘             │
                    │                                          │
                    │  ┌──────────┐  ┌──────────┐             │
                    │  │qBittorr. │  │ Scrutiny │             │
                    │  │  :8181   │  │  :38080  │             │
                    │  └──────────┘  └──────────┘             │
                    │                                          │
                    │  ┌──────────┐                           │
                    │  │ MySpeed  │                           │
                    │  │  :5216   │                           │
                    │  └──────────┘                           │
                    └─────────────────────────────────────────┘
```

## Rede

- **LAN:** `192.168.x.0/24`
- **Tailscale VPN:** acesso remoto seguro a todos os serviços sem expor portas para a internet

## Decisões técnicas relevantes

### Nextcloud com Tika para busca em texto completo
O Apache Tika é integrado ao Nextcloud para habilitar indexação e busca dentro de arquivos (PDFs, documentos Office). Os dois containers compartilham a mesma rede Docker interna, evitando exposição desnecessária de porta.

### Separação de dados por disco
O disco `/mnt/Se0` (Seagate 2TB) concentra todos os dados de usuário (mídias, downloads, Nextcloud). O disco `/mnt/Hi0` (Hitachi 2TB) é usado para automação (n8n) e dados de arquivo. Isso facilita backups seletivos e evita que o OS disk fique cheio.

### CasaOS como painel de controle
Gerencia os containers Docker via interface web, facilitando monitoramento e atualizações sem necessidade de SSH para tarefas rotineiras.
