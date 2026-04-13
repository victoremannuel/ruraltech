# Supabase Database Webhooks — Auto-sync de Polígonos

Este documento descreve os **Database Webhooks** necessários para ativar o
auto-sync de cerca ponta a ponta no RuralTech. Sem esses webhooks configurados,
a gravação no banco acontece normalmente, mas as edge functions
`auto-sync-property-fence` e `auto-sync-area-fence` **não são acionadas** e o
comando LoRa não é gerado automaticamente.

---

## Pré-requisitos

- Supabase projeto ID: `nhoewnfuyjbtpklrotbf`
- Edge functions já deployadas:
  - `auto-sync-property-fence`
  - `auto-sync-area-fence`
- Service Role Key disponível (usada pelo webhook para autenticar a chamada)

---

## Webhook 1 — rural\_properties → auto-sync-property-fence

### Onde configurar

Supabase Dashboard → **Database** → **Webhooks** → **Create a new hook**

### Configuração

| Campo | Valor |
|---|---|
| Nome | `on_property_points_changed` |
| Tabela | `public.rural_properties` |
| Eventos | `INSERT`, `UPDATE` |
| Tipo | **HTTP Request** |
| URL | `https://nhoewnfuyjbtpklrotbf.supabase.co/functions/v1/auto-sync-property-fence` |
| Método HTTP | `POST` |

### Headers obrigatórios

```
Content-Type: application/json
Authorization: Bearer <SERVICE_ROLE_KEY>
```

> Substitua `<SERVICE_ROLE_KEY>` pela chave de serviço do projeto.
> No Dashboard ela está em **Settings → API → service_role**.

### Payload enviado pelo Supabase (automático)

O Supabase envia automaticamente:

```json
{
  "type": "UPDATE",
  "table": "rural_properties",
  "schema": "public",
  "record": { ...novo estado da linha... },
  "old_record": { ...estado anterior da linha... }
}
```

A edge function usa `record.id`, `record.points`, `old_record.points` e
`record.property_scope_id`.

### Filtro recomendado (opcional)

Se o Supabase permitir filtro por coluna no webhook:

- Coluna: `points`
- Condição: `points IS DISTINCT FROM OLD.points`

Mesmo sem filtro, a edge function faz a comparação interna e retorna
`{ skipped: true, reason: "polygon_unchanged" }` quando não há mudança real.

### Rollback

Para desativar sem apagar: suspender o webhook no Dashboard.
Para reativar: reativar no Dashboard ou recadastrar com os mesmos parâmetros.

---

## Webhook 2 — areas → auto-sync-area-fence

### Onde configurar

Supabase Dashboard → **Database** → **Webhooks** → **Create a new hook**

### Configuração

| Campo | Valor |
|---|---|
| Nome | `on_area_fence_changed` |
| Tabela | `public.areas` |
| Eventos | `INSERT`, `UPDATE` |
| Tipo | **HTTP Request** |
| URL | `https://nhoewnfuyjbtpklrotbf.supabase.co/functions/v1/auto-sync-area-fence` |
| Método HTTP | `POST` |

### Headers obrigatórios

```
Content-Type: application/json
Authorization: Bearer <SERVICE_ROLE_KEY>
```

### Payload enviado pelo Supabase (automático)

```json
{
  "type": "UPDATE",
  "table": "areas",
  "schema": "public",
  "record": { ...novo estado da linha... },
  "old_record": { ...estado anterior da linha... }
}
```

A edge function usa `record.id`, `record.property_id`, `record.perimeter`,
`record.linked_device_ids`, `record.source`, `old_record.perimeter` e
`old_record.linked_device_ids`.

### Bypass de herding_operation

Se `record.source === "herding_operation"`, a edge function retorna
`{ skipped: true, reason: "bypass_herding_source" }` sem gerar comando.
Isso evita conflito com o fluxo de condução/arrebanhamento ativo.

### Rollback

Mesma instrução do Webhook 1.

---

## Alternativa: via Supabase CLI

Se preferir configurar por código (infraestrutura declarativa):

```bash
# Listar webhooks existentes
supabase db webhooks list --project-ref nhoewnfuyjbtpklrotbf

# Criar webhook para rural_properties
supabase db webhooks create \
  --project-ref nhoewnfuyjbtpklrotbf \
  --name on_property_points_changed \
  --table rural_properties \
  --events INSERT,UPDATE \
  --url https://nhoewnfuyjbtpklrotbf.supabase.co/functions/v1/auto-sync-property-fence \
  --http-method POST \
  --header "Authorization=Bearer <SERVICE_ROLE_KEY>"

# Criar webhook para areas
supabase db webhooks create \
  --project-ref nhoewnfuyjbtpklrotbf \
  --name on_area_fence_changed \
  --table areas \
  --events INSERT,UPDATE \
  --url https://nhoewnfuyjbtpklrotbf.supabase.co/functions/v1/auto-sync-area-fence \
  --http-method POST \
  --header "Authorization=Bearer <SERVICE_ROLE_KEY>"
```

---

## Verificação pós-configuração

1. Editar o polígono de uma fazenda no app
2. Verificar no Supabase Dashboard → **Logs** → **Edge Functions** → `auto-sync-property-fence`
3. Verificar em **Table Editor** → `property_commands`: linha com `origin_doc_type = ruralProperty`
4. Verificar em **Table Editor** → `matrix_command_queues`: payload com `points` em formato `[[lat,lon],...]`

Repetir para `areas` → `auto-sync-area-fence`.

---

## Diagnóstico de falhas comuns

| Sintoma | Causa provável | Ação |
|---|---|---|
| Webhook não dispara | Evento não configurado | Verificar `INSERT`/`UPDATE` no cadastro |
| Edge function retorna 401 | Header `Authorization` ausente ou incorreto | Verificar Service Role Key |
| `skipped: polygon_unchanged` | Polígono não mudou de fato | Normal — idempotência intencional |
| `no_matrix_for_property` | Propriedade sem gateway matriz vinculado e pronto | Verificar `gateways.is_matrix`, `binding_ready`, `supports_scoped_lora` |
| `missing_matrix_queue_key` | Matriz sem `queue_key` em `matrix_queue_keys` | Gateway precisa registrar a queue_key ao iniciar |
| `no_ready_collars` | Nenhuma coleira com `binding_ready = true` | Verificar estado das coleiras vinculadas à propriedade |
| `command_already_exists` | Mesmo polígono + targets já enfileirado | Idempotência intencional — comandId determinístico |
