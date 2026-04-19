# Relatório E2E — Area Sync

**Data/hora:** 2026-04-19T03:35:05.591067+00:00

**Conclusão:** `INCONCLUSIVO`

## Configuração

| Campo | Valor |
|---|---|
| areaId | `kQSjWOVdkqTNDM9WBggT` |
| propertyId | `T0xeG8WQHwJRI6H3t7vr` |
| commandId | `AUTO_AREA_FENCE:kQSjWOVdkqTNDM9WBggT:B222C54D07E35367:23A00185B336A70A` |
| linkedDeviceIds | `['3222380545']` |
| matrixSerialPort | `/dev/tty.usbserial-59470049741` |
| collarSerialPort | `/dev/tty.usbserial-1420` |

## Delta do polígono

- Vértice 0 original: `[-16.67474048753214, -49.48371635164385]`
- Vértice 0 alterado: `[-16.67473048753214, -49.48371635164385]`
- Delta: `+1e-05` lat (~1m norte)

## Falhas detectadas

- Timeout: fluxo não alcançou estado terminal em 10 min

## Timeline

- `2026-04-19T03:25:01.473775+00:00  Buscando área existente...`
- `2026-04-19T03:25:01.985831+00:00  Área: id=kQSjWOVdkqTNDM9WBggT property=T0xeG8WQHwJRI6H3t7vr devices=['3222380545'] points=6`
- `2026-04-19T03:25:01.985895+00:00  Polígono alterado: vértice 0 [-16.67474048753214, -49.48371635164385] → [-16.67473048753214, -49.48371635164385]`
- `2026-04-19T03:25:03.010889+00:00  Atualizando área kQSjWOVdkqTNDM9WBggT no Supabase...`
- `2026-04-19T03:25:03.417866+00:00  Área atualizada com sucesso no Supabase.`
- `2026-04-19T03:25:05.425458+00:00  Aguardando resultado ponta a ponta (max ~10 min)...`
- `2026-04-19T03:35:05.590431+00:00  commandId resolvido para o relatório: AUTO_AREA_FENCE:kQSjWOVdkqTNDM9WBggT:B222C54D07E35367:23A00185B336A70A`

## Próximos passos

- Investigar falhas listadas acima.
- Verificar serial monitor e tabelas Supabase.
- Arquivo de logs: `/Users/victoremannuel/Documents/dev/ruraltech/tools/audit/output/20260419_002501`
