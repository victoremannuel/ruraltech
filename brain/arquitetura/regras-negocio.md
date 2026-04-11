# Architecture: Regras de Negócio — RuralTech

## Overview

Regras que governam o comportamento do sistema, independentes de implementação.

## Components

### Comandos LoRa

| Regra | Detalhes |
|---|---|
| IDs LoRa numéricos > 0 | `deviceId` deve ser inteiro positivo |
| SET_FENCE: 3–32 pontos | Polígono de cerca mínimo 3, máximo 32 vértices |
| SET_HERDING_PLAN: 1–8 fases | Cada fase com 3–32 pontos |
| Payload LoRa ≤ 128 bytes | Fragmentação automática para payloads maiores |
| SET_PARAMS com wifi_ota_enabled=false | Exige `requested_by_role=adm|admin` ou `requested_by_admin=true` |
| Coleira vinculada a propriedade | Só recebe comandos LoRa se estiver associada a uma `property_id` |

### Geofence

- A cerca que governa violações **na coleira** é a cerca persistida em NVS do firmware
- A cerca no cloud (Supabase `fences`) é a **intenção** — só vira realidade após `polygon_apply_result` confirmado
- Quando `ruralProperties.points` muda, o backend cria automaticamente `SET_FENCE` para todas as coleiras da propriedade
- Quando `areas.perimeter` ou `areas.linkedDeviceIds` muda, o backend cria `SET_FENCE` **seletivo** apenas para as coleiras vinculadas

### Piquetes (Areas)

- `areas.linkedDeviceIds` é a **fonte de verdade** do vínculo piquete ↔ coleira
- `collars.activeAreaId` é espelho operacional/auditoria (não define o vínculo)
- Alterações com `source=herding_operation` são ignoradas na sincronização automática de fence
- Promoção do piquete a área permanente é opcional (`area_promotion_requested`)

### Condução de Rebanho (Herding)

- Uma operação de herding cria um `SET_HERDING_PLAN` para cada coleira selecionada
- Operação pode opcionalmente criar uma `area` permanente (`created_area_id`)
- Notificações enviadas a `notify_user_ids` ao completar/falhar
- Operação anterior é marcada como `superseded` quando nova operação é criada para o mesmo dispositivo

### Controle de Modo Operacional

- `wifi_ota_enabled=true` (padrão): coleira aceita comandos via Wi-Fi + LoRa
- `wifi_ota_enabled=false` (modo LoRa-only): bloqueio Wi-Fi, apenas LoRa
- Alteração para `false` é **ação administrativa** — exige role `adm` ou `admin`
- Alteração pode ser feita via `SET_PARAMS` com marcador de admin

### Segurança

- Escrita anônima nas Edge Functions Supabase só com `matrixId + writerKey` válidos
- RLS no Supabase controla acesso por `owner_uid`, `user_uids`, ou role `admin`
- Sensores e coordenadas devem ser validados antes de persistir
- Não logar dados sensíveis (senhas, writer keys, tokens)

### Auditoria

- Todo comando tem `cmd_id` determinístico para deduplicação
- `origin_doc_type` + `origin_doc_id` permitem rastrear qual objeto de origem gerou o comando
- Sucesso de gravação: confirmação prioritária via `polygon_apply_result` da coleira
- Falhas precoces (antes da coleira): registradas em `propertyCommandEvents`
- Log no app combina `propertyEvents` + `propertyCommandEvents`

### Integridade de Dados

- Telemetria deve manter **coordenadas válidas** (lat -90..90, lon -180..180) e timestamps coerentes (`receivedAt`/`receivedAtMs`)
- Fixtures JSON em `contracts/messages/` são **baseline de regressão** — nunca quebrar sem atualizar testes simultâneos
- Policies RLS do Supabase devem permanecer alinhadas com papéis (`adm` vs `user`) e ownership

### Auditoria de Feature (E2E)

- Toda implementação ou alteração deve rodar auditoria das funcionalidades impactadas para garantir **sucesso E2E no requisito de negócio**
- Não entregar feature sem validar o fluxo completo: app → Edge Function → RTDB → matriz → coleira → confirmação

## Flow

1. App define intenção (salva polígono/plano/parâmetro)
2. Backend valida e enfileira comando
3. Matriz despacha via LoRa
4. Coleira aplica e confirma
5. Auditoria registrada; app exibe resultado

## Technologies

- Dart (Flutter) — validação no app
- C++ (firmware/shared) — validação no firmware
- Postgres RLS — controle de acesso no banco
- Edge Functions (Deno) — validação e enfileiramento na cloud

## Related

[[requisitos]]
[[fluxos-comunicacao-ponta-a-ponta]]
[[modelagem-dados-supabase]]

#arquitetura #ruraltech 