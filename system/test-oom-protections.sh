#!/bin/bash
# Testa todas as proteções contra OOM implementadas nas versões v1.1.2–v1.1.4
# Uso: sudo bash system/test-oom-protections.sh

PASS=0
FAIL=0
WARN=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; WARN=$((WARN + 1)); }
header() { echo -e "\n=== $1 ==="; }

# ---------------------------------------------------------------------------
header "SWAP"

SWAP_GB=$(awk '/^\/swap/ {printf "%.0f", $3/1024/1024}' /proc/swaps 2>/dev/null || echo 0)
if [ "$SWAP_GB" -ge 7 ]; then
    pass "Swap: ${SWAP_GB}GB (esperado ≥ 7GB)"
else
    fail "Swap: ${SWAP_GB}GB — esperado 8GB"
fi

# ---------------------------------------------------------------------------
header "DISCO Se0"

if mountpoint -q /mnt/Se0; then
    pass "Se0 montado em /mnt/Se0"
else
    fail "Se0 NÃO está montado — execute: sudo mount /mnt/Se0"
fi

for dir in "Animes" "Filmes" "Séries"; do
    if [ -d "/mnt/Se0/10-Mídias(Jellyfin)/$dir" ]; then
        pass "Biblioteca Jellyfin acessível: $dir"
    else
        fail "Pasta não encontrada: /mnt/Se0/10-Mídias(Jellyfin)/$dir"
    fi
done

# ---------------------------------------------------------------------------
header "PROTEÇÃO UDISKS (Se0)"

UDISKS_IGNORE=$(udevadm info /dev/sdb1 2>/dev/null | grep "UDISKS_IGNORE" | awk -F= '{print $2}')
if [ "$UDISKS_IGNORE" = "1" ]; then
    pass "UDISKS_IGNORE=1 ativo no sdb1"
else
    fail "UDISKS_IGNORE não está ativo — verifique /etc/udev/rules.d/99-se0-internal.rules"
fi

# ---------------------------------------------------------------------------
header "SERVIÇO DE RECUPERAÇÃO Se0"

if systemctl is-enabled se0-recovery.service &>/dev/null; then
    pass "se0-recovery.service habilitado"
else
    fail "se0-recovery.service NÃO habilitado"
fi

if [ -x /usr/local/bin/se0-recovery.sh ]; then
    pass "Script se0-recovery.sh existe e é executável"
else
    fail "Script /usr/local/bin/se0-recovery.sh não encontrado"
fi

# ---------------------------------------------------------------------------
header "JELLYFIN — CONFIGURAÇÃO DE CONCORRÊNCIA"

JELLYFIN_XML="/DATA/AppData/jellyfin/config/system.xml"

SCAN_VAL=$(grep -oP '(?<=<LibraryScanFanoutConcurrency>)\d+' "$JELLYFIN_XML" 2>/dev/null || echo "X")
if [ "$SCAN_VAL" = "2" ]; then
    pass "LibraryScanFanoutConcurrency = 2"
else
    fail "LibraryScanFanoutConcurrency = '$SCAN_VAL' (esperado: 2)"
fi

META_VAL=$(grep -oP '(?<=<LibraryMetadataRefreshConcurrency>)\d+' "$JELLYFIN_XML" 2>/dev/null || echo "X")
if [ "$META_VAL" = "2" ]; then
    pass "LibraryMetadataRefreshConcurrency = 2"
else
    fail "LibraryMetadataRefreshConcurrency = '$META_VAL' (esperado: 2)"
fi

# ---------------------------------------------------------------------------
header "LIMITES DE MEMÓRIA DOS CONTAINERS"

check_mem() {
    local container="$1" expected="$2"
    local actual
    actual=$(docker inspect "$container" --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "ERR")
    local label_mb=$(( expected / 1024 / 1024 ))
    if [ "$actual" = "$expected" ]; then
        pass "Limite $container: ${label_mb}MB"
    elif [ "$actual" = "ERR" ]; then
        fail "Container '$container' não encontrado"
    else
        local actual_mb=$(( actual / 1024 / 1024 ))
        fail "Limite $container: ${actual_mb}MB (esperado: ${label_mb}MB)"
    fi
}

check_mem "jellyfin"                  4294967296
check_mem "n8n"                       1073741824
check_mem "tika"                      1073741824
check_mem "nextcloud"                 1073741824
check_mem "big-bear-scrutiny"          536870912
check_mem "big-bear-syncthing"         536870912
check_mem "db-nextcloud"               536870912
check_mem "qbittorrent"                536870912
check_mem "myspeed"                    268435456
check_mem "redis-nextcloud"            268435456
check_mem "big-bear-nextcloud-cron-1"  268435456

# ---------------------------------------------------------------------------
header "SAÚDE DOS SERVIÇOS"

check_http() {
    local name="$1" url="$2" expected="$3"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [ "$code" = "$expected" ]; then
        pass "$name responde: HTTP $code"
    else
        fail "$name: HTTP $code (esperado: $expected)"
    fi
}

check_http "Jellyfin" "http://localhost:8097/health" "200"
check_http "Nextcloud" "http://localhost:7580/" "302"

WATCHING=$(docker logs jellyfin 2>&1 | grep "Watching directory" | grep "/Media/" | wc -l)
if [ "$WATCHING" -ge 1 ]; then
    pass "Jellyfin monitorando biblioteca de mídia ($WATCHING diretórios)"
else
    warn "Jellyfin pode não estar monitorando a biblioteca — Se0 estava montado ao iniciar?"
fi

# ---------------------------------------------------------------------------
header "RESUMO"
echo ""
echo -e "  ${GREEN}PASS: $PASS${NC}  |  ${RED}FAIL: $FAIL${NC}  |  ${YELLOW}WARN: $WARN${NC}"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "❌ Alguns testes falharam. Corrija os itens [FAIL] acima."
    exit 1
else
    echo "✅ Todas as proteções verificadas com sucesso."
    exit 0
fi
