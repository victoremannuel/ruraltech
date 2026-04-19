# Task: Auditoria Home mapa cinza pos-login 2026-04-11

## Context

Nova auditoria focada na regressão em que a Home abre, o mapa aparece por instantes e em seguida some, ficando cinza. A correção anterior não eliminou o problema em device real. Esta nota registra o plano específico, o checklist de implementação e o histórico desta rodada.

## Action

- [x] revisar o fluxo assíncrono que muda a Home logo após o login
- [x] endurecer parsing de coordenadas para propriedades, áreas e gateways
- [x] parar a reconciliação/admin bootstrap automática na abertura da Home
- [x] parar o recenter automático por geolocalização ao abrir a Home
- [x] manter a correção do parse de `poll-notifications`
- [x] validar com análise estática dos arquivos alterados
- [x] validar com testes focados da Home e do mapa
- [ ] validar no app real se o mapa deixa de sumir após login
- [ ] capturar novo diagnóstico caso o problema persista em device real

## Status

Em andamento.

## Next step

- publicar/testar a nova build no device real
- se persistir, instrumentar a Home para identificar qual atualização assíncrona está derrubando o mapa em runtime real

## History

### 2026-04-11

- hipótese principal desta rodada:
  - o mapa estava sendo desestabilizado por efeitos automáticos logo após o primeiro frame autenticado
  - os candidatos mais fortes eram a reconciliação automática de estado cloud para admin e o recenter automático após geolocalização
- correções aplicadas:
  - remoção da reconciliação automática `backfillLegacyAccessForAreasAndGateways()` na abertura da Home
  - remoção do recenter automático por geolocalização ao abrir a Home
  - manutenção do parsing defensivo de coordenadas para evitar quebra na árvore do mapa
- validação local:
  - `dart analyze`: PASS
  - `flutter test`: PASS

## Related

[[ruraltech]]
[[visao-geral]]
[[requisitos]]
[[regras-negocio]]
[[auditoria-total-solucao-2026-04-11]]
[[auditoria-app-mapa-gateway]]
[[uiux-telas]]
[[fluxos-comunicacao-ponta-a-ponta]]
