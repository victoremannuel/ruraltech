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
- Service Role Key disponível em: **Dashboard → Settings → API → service_role**

---

## Como acessar no Dashboard

O menu de webhooks fica em:

**Dashboard → Integrations → Webhooks**

URL direta:
```
https://supabase.com/dashboard/project/nhoewnfuyjbtpklrotbf/integrations/webhooks/overview
```

Clique em **"Create a new webhook"** (ou "Criar novo webhook").

---

## Opção A — Criar via Dashboard (recomendado)

### Webhook 1 — rural\_properties → auto-sync-property-fence

| Campo | Valor |
|---|---|
| Nome | `on_property_points_changed` |
| Tabela | `public.rural_properties` |
| Eventos | `INSERT`, `UPDATE` |
| Tipo | HTTP Request |
| URL | `https://nhoewnfuyjbtpklrotbf.supabase.co/functions/v1/auto-sync-property-fence` |
| Método HTTP | `POST` |

**Headers** (adicionar no campo de headers do formulário):

```json
{
  "Content-Type": "application/json",
  "Authorization": "Bearer <SERVICE_ROLE_KEY>"
}
```

> Substitua `<SERVICE_ROLE_KEY>` pela chave de serviço do projeto.
> Ela está em **Dashboard → Settings → API → service_role**.

**Observação:** o Supabase não suporta filtro por coluna nos webhooks de Dashboard.
A edge function faz a comparação internamente e retorna
`{ skipped: true, reason: "polygon_unchanged" }` quando não há mudança real em `points`.

---

### Webhook 2 — areas → auto-sync-area-fence

| Campo | Valor |
|---|---|
| Nome | `on_area_fence_changed` |
| Tabela | `public.areas` |
| Eventos | `INSERT`, `UPDATE` |
| Tipo | HTTP Request |
| URL | `https://nhoewnfuyjbtpklrotbf.supabase.co/functions/v1/auto-sync-area-fence` |
| Método HTTP | `POST` |

**Headers:**

```json
{
  "Content-Type": "application/json",
  "Authorization": "Bearer <SERVICE_ROLE_KEY>"
}
```

**Bypass de herding\_operation:** se `record.source === "herding_operation"`, a edge
function ignora automaticamente a chamada para evitar conflito com arrebanhamento ativo.

---

## Opção B — Criar via SQL (alternativa)

Se preferir não usar o Dashboard, crie os webhooks diretamente via SQL usando a
função nativa `supabase_functions.http_request`.

### Webhook 1 — rural\_properties

```sql
create trigger "on_property_points_changed"
after insert or update
on "public"."rural_properties"
for each row
execute function "supabase_functions"."http_request"(
  'https://nhoewnfuyjbtpklrotbf.supabase.co/functions/v1/auto-sync-property-fence',
  'POST',
  '{"Content-Type":"application/json","Authorization":"Bearer <SERVICE_ROLE_KEY>"}',
  '{}',
  '5000'
);
```

### Webhook 2 — areas

```sql
create trigger "on_area_fence_changed"
after insert or update
on "public"."areas"
for each row
execute function "supabase_functions"."http_request"(
  'https://nhoewnfuyjbtpklrotbf.supabase.co/functions/v1/auto-sync-area-fence',
  'POST',
  '{"Content-Type":"application/json","Authorization":"Bearer <SERVICE_ROLE_KEY>"}',
  '{}',
  '5000'
);
```

> Substitua `<SERVICE_ROLE_KEY>` pela chave real antes de executar.

**Parâmetros de `http_request` em ordem:**
1. URL de destino
2. Método HTTP
3. Headers em JSON (string)
4. Body adicional em JSON (string) — use `'{}'` para vazio
5. Timeout em milissegundos

Execute via **Dashboard → SQL Editor** ou pela Supabase CLI:

```bash
supabase db push --project-ref nhoewnfuyjbtpklrotbf
```

---

## Payload enviado pelo Supabase para as edge functions

O Supabase envia automaticamente o seguinte body em cada disparo:

**INSERT:**
```json
{
  "type": "INSERT",
  "table": "rural_properties",
  "schema": "public",
  "record": { "id": "...", "points": [...], "property_scope_id": "..." },
  "old_record": null
}
```

**UPDATE:**
```json
{
  "type": "UPDATE",
  "table": "rural_properties",
  "schema": "public",
  "record": { "id": "...", "points": [...], "property_scope_id": "..." },
  "old_record": { "id": "...", "points": [...] }
}
```

As edge functions usam os campos:
- `auto-sync-property-fence`: `record.id`, `record.points`, `record.property_scope_id`, `old_record.points`
- `auto-sync-area-fence`: `record.id`, `record.property_id`, `record.perimeter`, `record.linked_device_ids`, `record.source`, `old_record.perimeter`, `old_record.linked_device_ids`

---

## Verificação pós-configuração

1. Edite o polígono de uma fazenda no app
2. Acesse **Dashboard → Logs → Edge Functions → auto-sync-property-fence**
3. Confirme linha em **Table Editor → property\_commands** com `origin_doc_type = ruralProperty`
4. Confirme em **Table Editor → matrix\_command\_queues** que `payload.points` está no formato `[[lat, lon], ...]`

Repita para `areas → auto-sync-area-fence`.

---

## Diagnóstico de falhas comuns

| Sintoma | Causa provável | Ação |
|---|---|---|
| Webhook não dispara | Evento não configurado ou webhook desativado | Verificar `INSERT`/`UPDATE` em **Integrations → Webhooks** |
| Edge function retorna 401 | Header `Authorization` ausente ou Service Role Key incorreta | Verificar a chave em **Settings → API → service_role** |
| `skipped: polygon_unchanged` | Polígono não mudou de fato | Normal — idempotência intencional |
| `skipped: bypass_herding_source` | Área atualizada por operação de arrebanhamento | Normal — bypass intencional |
| `no_matrix_for_property` | Propriedade sem gateway matriz vinculado e pronto | Verificar `gateways.is_matrix`, `binding_ready`, `supports_scoped_lora` |
| `missing_matrix_queue_key` | Matriz sem `queue_key` em `matrix_queue_keys` | Gateway precisa registrar a queue_key ao inicializar |
| `no_ready_collars` | Nenhuma coleira com `binding_ready = true` na propriedade | Verificar estado das coleiras vinculadas |
| `command_already_exists` | Mesmo polígono + targets já enfileirado | Idempotência intencional — commandId determinístico |

---

## Rollback

- **Desativar sem apagar:** clicar em **Pause** no webhook em **Integrations → Webhooks**
- **Via SQL:** `drop trigger if exists "on_property_points_changed" on public.rural_properties;`
