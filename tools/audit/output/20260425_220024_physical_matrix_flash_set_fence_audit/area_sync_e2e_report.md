# Relatório E2E — Area Sync

**Data/hora:** 2026-04-26T01:19:46.280098+00:00

**Conclusão:** `FALHA`

## Configuração

| Campo | Valor |
|---|---|
| areaId | `kQSjWOVdkqTNDM9WBggT` |
| propertyId | `T0xeG8WQHwJRI6H3t7vr` |
| commandId | `AUTO_AREA_FENCE:kQSjWOVdkqTNDM9WBggT:FE7FD5ECA20D7089:23A00185B336A70A` |
| linkedDeviceIds | `['3222380545']` |
| matrixSerialPort | `/dev/tty.usbserial-59470049741` |
| collarSerialPort | `N/A` |

## Delta do polígono

- Vértice 0 original: `[-16.674919067537086, -49.48423817286258]`
- Vértice 0 alterado: `[-16.674909067537087, -49.48423817286258]`
- Delta: `+1e-05` lat (~1m norte)

## Falhas detectadas

- Status terminal negativo: failed

## Timeline

- `2026-04-26T01:19:37.159349+00:00  Buscando área existente...`
- `2026-04-26T01:19:37.976123+00:00  Área: id=kQSjWOVdkqTNDM9WBggT property=T0xeG8WQHwJRI6H3t7vr devices=['3222380545'] points=6`
- `2026-04-26T01:19:37.976156+00:00  Polígono alterado: vértice 0 [-16.674919067537086, -49.48423817286258] → [-16.674909067537087, -49.48423817286258]`
- `2026-04-26T01:19:38.983794+00:00  Atualizando área kQSjWOVdkqTNDM9WBggT no Supabase...`
- `2026-04-26T01:19:39.268331+00:00  Área atualizada com sucesso no Supabase.`
- `2026-04-26T01:19:41.275145+00:00  Aguardando resultado ponta a ponta (max ~10 min)...`
- `2026-04-26T01:19:46.279660+00:00  Status terminal negativo: failed`
- `2026-04-26T01:19:46.279959+00:00  commandId resolvido para o relatório: AUTO_AREA_FENCE:kQSjWOVdkqTNDM9WBggT:FE7FD5ECA20D7089:23A00185B336A70A`

## Próximos passos

- Investigar falhas listadas acima.
- Verificar serial monitor e tabelas Supabase.
- Arquivo de logs: `tools/audit/output/20260425_220024_physical_matrix_flash_set_fence_audit`
