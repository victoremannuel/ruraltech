# Task: Auditoria total da solução e correções 2026-04-11

#ruraltech
#tarefas

## Context

Nova rodada de auditoria/correção da solução RuralTech após regressão reportada no app: login como `adm`, mapa visível por cerca de 1 segundo e depois área principal do mapa ficando cinza. O objetivo desta nota é registrar o histórico do trabalho corrente sem misturar com a auditoria pós-migração anterior.

## Action

- estabilizar `login -> Home -> mapa`
- auditar streams da Home, auth/profile refresh e bootstrap admin
- ampliar cobertura de backend/RLS para tabelas lidas na Home
- validar contratos e testes host-side do firmware
- registrar baseline, correções aplicadas e pendências restantes

## Status

Em andamento.

## Checklist

- [x] corrigir o fluxo `login -> Home -> mapa` para não desmontar a tela após login
- [x] remover recriação volátil do `FlutterMap`
- [x] transformar falhas de carga da Home em overlay não destrutivo
- [x] dar estado explícito ao bootstrap admin de reconciliação legado
- [x] adicionar teste de regressão do estado de sessão/Home
- [x] corrigir o parse do retorno de `poll-notifications` no worker Android
- [x] alinhar notas do brain com as Edge Functions ativas e o estado real do backhaul
- [x] endurecer a renderização do mapa contra coordenadas inválidas
- [x] ampliar cobertura RLS para `gateways`
- [x] ampliar cobertura RLS para `collars`
- [x] ampliar cobertura RLS para `pending_notifications`
- [x] rodar `flutter analyze`
- [x] rodar `flutter test`
- [x] rodar `firmware/tests/command_contract_test.cpp`
- [x] rodar `firmware/tests/queue_stream_support_test.cpp`
- [x] rodar `supabase test db --local`
- [x] compilar `coleira` com `PartitionScheme=min_spiffs`
- [x] compilar `gateway` com `PartitionScheme=min_spiffs`
- [x] compilar `gateway-matriz` com `PartitionScheme=min_spiffs`
- [x] validar orçamento de flash dos três firmwares
- [ ] validar o fluxo real no app com login `adm`
- [ ] auditar Edge Functions críticas (`queue-lora-command`, `matrix-cloud`, `poll-notifications`, `admin-repair-cloud-state`, `send-push`)
- [ ] classificar/remover deriva residual de Firebase/RTDB no runtime e na documentação
- [ ] fechar checklist E2E com hardware real

## Next step

- validar no app real se o mapa permanece estável após login `adm`
- ampliar pgTAP para `gateways`, `collars` e `pending_notifications`
- rodar `supabase test db --local` com Docker ativo
- seguir para compile completo dos três firmwares e validação de flash

## History

### 2026-04-11

- baseline confirmado:
  - `flutter analyze`: PASS
  - `flutter test`: PASS
  - `firmware/tests/command_contract_test.cpp`: PASS
  - `firmware/tests/queue_stream_support_test.cpp`: PASS
  - `supabase test db --local`: PASS
- correções aplicadas no app:
  - Home deixou de bloquear a tela inteira em refresh tardio de perfil após a primeira sessão autenticada
  - mapa deixou de depender de `key` volátil baseada em contagens/posição
  - falhas de `properties/areas/devices/gateways` passaram a aparecer em overlay não-destrutivo
  - bootstrap admin de reconciliação legado passou a ter estado explícito e erro visível
- cobertura adicionada:
  - `app/test/home_session_state_test.dart`
  - `app/test/pending_notifications_test.dart`
- correções adicionais:
  - `callbackDispatcher` do Android passou a aceitar o formato real retornado por `poll-notifications`
  - notas `brain/decisoes/migracao-supabase.md` e `brain/projetos/ruraltech.md` foram alinhadas com as Edge Functions atuais e com o backhaul RT ainda ativo na matriz
  - a Home passou a ignorar coordenadas inválidas em propriedades, áreas e gateways, em vez de deixar a renderização do mapa quebrar
- cobertura adicionada nesta rodada:
  - `app/test/map_coordinates_test.dart`
- validações de firmware já concluídas:
  - `coleira`: 1145389 bytes (58%), RAM 66000 bytes (20%)
  - `gateway`: 1916199 bytes (97%), RAM 75332 bytes (22%)
  - `gateway-matriz`: 1347515 bytes (68%), RAM 72724 bytes (22%)
  - alerta: `gateway` permaneceu dentro do limite, mas com margem de flash curta

## Related

[[ruraltech]]
[[visao-geral]]
[[requisitos]]
[[regras-negocio]]
[[fluxos-comunicacao-ponta-a-ponta]]
[[modelagem-dados-supabase]]
[[uiux-telas]]
