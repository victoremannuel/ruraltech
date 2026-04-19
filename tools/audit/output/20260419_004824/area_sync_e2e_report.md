# Relatório E2E — Area Sync

**Data/hora:** 2026-04-19T03:58:28.905390+00:00

**Conclusão:** `INCONCLUSIVO`

## Configuração

| Campo | Valor |
|---|---|
| areaId | `kQSjWOVdkqTNDM9WBggT` |
| propertyId | `T0xeG8WQHwJRI6H3t7vr` |
| commandId | `AUTO_AREA_FENCE:kQSjWOVdkqTNDM9WBggT:7685085E8B9186D1:23A00185B336A70A` |
| linkedDeviceIds | `['3222380545']` |
| matrixSerialPort | `/dev/tty.usbserial-59470049741` |
| collarSerialPort | `/dev/tty.usbserial-1420` |

## Delta do polígono

- Vértice 0 original: `[-16.67473048753214, -49.48371635164385]`
- Vértice 0 alterado: `[-16.67472048753214, -49.48371635164385]`
- Delta: `+1e-05` lat (~1m norte)

## Falhas detectadas

- Timeout: fluxo não alcançou estado terminal em 10 min

## Timeline

- `2026-04-19T03:48:24.492830+00:00  Buscando área existente...`
- `2026-04-19T03:48:24.973829+00:00  Área: id=kQSjWOVdkqTNDM9WBggT property=T0xeG8WQHwJRI6H3t7vr devices=['3222380545'] points=6`
- `2026-04-19T03:48:24.973875+00:00  Polígono alterado: vértice 0 [-16.67473048753214, -49.48371635164385] → [-16.67472048753214, -49.48371635164385]`
- `2026-04-19T03:48:25.984619+00:00  Atualizando área kQSjWOVdkqTNDM9WBggT no Supabase...`
- `2026-04-19T03:48:26.345290+00:00  Área atualizada com sucesso no Supabase.`
- `2026-04-19T03:48:28.354190+00:00  Aguardando resultado ponta a ponta (max ~10 min)...`
- `2026-04-19T03:58:28.610093+00:00  commandId resolvido para o relatório: AUTO_AREA_FENCE:kQSjWOVdkqTNDM9WBggT:7685085E8B9186D1:23A00185B336A70A`
- `2026-04-19T03:58:28.612267+00:00  Restaurando polígono original...`
- `2026-04-19T03:58:28.905310+00:00  Polígono original restaurado.`

## Próximos passos

- Investigar falhas listadas acima.
- Verificar serial monitor e tabelas Supabase.
- Arquivo de logs: `/Users/victoremannuel/Documents/dev/ruraltech/tools/audit/output/20260419_004824`
