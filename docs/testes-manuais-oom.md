# Testes Manuais — Proteções OOM

Testes que requerem interação física ou humana. Execute após qualquer
mudança significativa de infraestrutura ou antes de declarar uma versão estável.

O script automatizado cobre a configuração estática. Estes testes cobrem
o comportamento real em runtime.

---

## Teste 1 — Desligamento forçado e boot limpo

**O que valida:** a regra udev (`UDISKS_IGNORE=1`) e o `se0-recovery.service`
funcionam corretamente após um shutdown não-gracioso.

**Passos:**
1. Com o servidor ligado e todos os serviços rodando normalmente, pressione
   o botão de power por ~5 segundos (simulando uma queda de energia)
2. Aguarde o servidor reiniciar automaticamente
3. Acesse o Jellyfin: `http://192.168.15.11:8097`
   - ✅ Esperado: interface carrega e a biblioteca (Filmes/Animes/Séries) aparece
   - ❌ Falha: "Nenhuma mídia encontrada" ou erro de conexão
4. Acesse o Nextcloud: `http://192.168.15.11:7580`
   - ✅ Esperado: tela de login aparece (HTTP 302 → login)
   - ❌ Falha: erro 503 ou página em branco
5. No servidor, execute o script automatizado para confirmar tudo:
   ```bash
   sudo bash ~/homelab/system/test-oom-protections.sh
   ```

**Se falhar:** execute manualmente:
```bash
sudo mount /mnt/Se0
docker restart jellyfin nextcloud
```
E investigue os logs: `journalctl -b 0 | grep -E "Se0|sdb1|fsck|se0-recovery"`

---

## Teste 2 — Scan de biblioteca único (monitorado)

**O que valida:** o limite de concorrência do scan (`LibraryScanFanoutConcurrency=2`)
está funcionando e não haverá explosão de processos `ffprobe`.

**Passos:**
1. Abra **dois terminais** no servidor
2. No terminal 1, monitore os processos ffprobe em tempo real:
   ```bash
   watch -n 1 'pgrep -c ffprobe 2>/dev/null || echo 0'
   ```
3. No terminal 2, monitore a RAM:
   ```bash
   watch -n 2 free -h
   ```
4. No Jellyfin (dashboard admin): inicie o scan de **apenas uma** biblioteca
   (ex: Filmes) — **não** clique em "Scan All Libraries"
5. Observe o terminal 1 durante o scan:
   - ✅ Esperado: número de processos `ffprobe` permanece ≤ 5
   - ❌ Falha: número sobe para dezenas (10+)
6. Observe o terminal 2:
   - ✅ Esperado: RAM sobe moderadamente, nunca passa de ~6GB
   - ❌ Falha: RAM vai a 100% e sistema começa a usar swap excessivamente

**Tempo estimado:** 5–15 min dependendo do tamanho da biblioteca

---

## Teste 3 — Reprodução de vídeo (Jellyfin)

**O que valida:** os limites de RAM não quebraram a reprodução normal.

**Passos:**
1. Abra o Jellyfin em qualquer dispositivo (PC, TV ou tablet)
2. Reproduza um filme ou episódio por pelo menos **2 minutos**
3. No servidor, verifique o uso de RAM do container:
   ```bash
   docker stats jellyfin --no-stream
   ```
   - ✅ Esperado: RAM em uso bem abaixo de 4GB (tipicamente < 500MB em Direct Play)
   - ⚠️ Atenção: se o arquivo precisar de transcodificação (ffmpeg ativo),
     o uso pode subir — mas deve permanecer abaixo de 4GB

**Dica:** para ver se está transcodificando ou fazendo Direct Play,
veja no Jellyfin: ícone de usuário → Reproduções ativas.

---

## Teste 4 — Nextcloud funcional pós-reboot

**O que valida:** dados do Nextcloud (no Se0) acessíveis após boot normal.

**Passos:**
1. Faça um **desligamento gracioso**: `sudo shutdown -h now`
2. Ligue o servidor novamente
3. Acesse: `http://192.168.15.11:7580` — faça login com `werus`
4. Verifique que as pastas `10.Pessoal/`, `20.Estudos/` aparecem com conteúdo
5. Abra um documento qualquer para confirmar que os dados estão íntegros

---

## Teste 5 — Limites de RAM em stress leve (opcional)

**O que valida:** container realmente não ultrapassa o limite definido.

**Passos:**
1. Inicie um scan de biblioteca no Jellyfin E reproduza um vídeo ao mesmo tempo
2. Monitore com:
   ```bash
   docker stats --no-stream
   ```
3. - ✅ Esperado: jellyfin permanece abaixo de 4GB com as duas operações
   - ❌ Falha: container é morto pelo Docker (OOMKilled) — nesse caso,
     ajuste os limites para cima (o cap está muito apertado)

Para verificar se algum container foi morto por OOM:
```bash
docker inspect jellyfin --format '{{.State.OOMKilled}}'
```

---

## Checklist de aprovação

Marque cada item após executar e aprovar:

- [x] Teste 1 — Desligamento forçado: Se0 montou automaticamente, Jellyfin e Nextcloud ok *(2026-05-30)*
- [x] Teste 2 — Scan único monitorado: ≤ 5 processos ffprobe simultâneos *(2026-05-30)*
- [x] Teste 3 — Reprodução de vídeo: funciona normalmente, RAM abaixo de 4GB *(2026-05-30)*
- [x] Teste 4 — Nextcloud pós-reboot gracioso: dados acessíveis e íntegros *(2026-05-30)*
- [ ] Teste 5 — Stress leve (opcional): nenhum container morto por OOM

**v1.1.4 aprovada e estável** — todos os testes obrigatórios (1–4) concluídos em 2026-05-30.
