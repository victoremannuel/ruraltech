# Migration Pipeline: Firebase → Supabase

Pipeline ETL para migrar dados do Firebase (`ruraltech10`) para o Supabase.

## Pré-requisitos

### Dependências Node.js

```bash
cd scripts/migration
npm init -y
npm install firebase-admin @supabase/supabase-js
```

### Arquivo de configuração

Crie `scripts/migration/.env` (não commitado):

```env
# Firebase
FB_SERVICE_ACCOUNT_PATH=/caminho/para/ruraltech10-service-account.json
FB_PROJECT_ID=ruraltech10
FB_RTDB_URL=https://ruraltech10-default-rtdb.firebaseio.com

# Supabase (usar service role key — bypassa RLS)
SUPABASE_URL=https://nhoewnfuyjbtpklrotbf.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...
```

O service account JSON do Firebase pode ser obtido em:
**Firebase Console → Project Settings → Service Accounts → Generate new private key**

## Sequência de execução

### 1. Export do Firebase

```bash
node scripts/migration/01_export_firebase.mjs
```

Exporta para `temp/migration/`:
- `auth_users.json` — usuários Firebase Auth
- `firestore_*.json` — collections Firestore
- `rtdb_*.json` — dados do RTDB (últimos 30 dias para dados históricos)

Log em `temp/migration/export.log`.

### 2. Transformação

```bash
node scripts/migration/02_transform.mjs
```

Converte para o schema Supabase. Output em `temp/migration/transformed/*.jsonl`.

Também gera `uid_map.json` (firebase_uid → metadados) para uso no import.

### 3. Import

```bash
node scripts/migration/03_import_supabase.mjs
```

Importa em ordem de dependência de FK. Cria usuários no Supabase Auth com senha aleatória e gera links de recuperação de senha em `temp/migration/reset_links.csv`.

Log em `temp/migration/import.log`.

### 4. Validação

```bash
node scripts/migration/04_validate.mjs
```

Verifica contagens, integridade referencial e amostras aleatórias. Gera relatório em `temp/migration/validation_report.md`.

- Exit code `0` = PASS (pronto para corte)
- Exit code `1` = FAIL (não prosseguir)

## Rollback

Apenas antes de reabrir escritas para os usuários:

```bash
SUPABASE_DB_URL=postgres://postgres:senha@db.xxx.supabase.co:5432/postgres \
  bash scripts/migration/99_rollback.sh
```

## Arquivos de saída

| Arquivo | Descrição |
|---|---|
| `temp/migration/export.log` | Log do passo 1 |
| `temp/migration/import.log` | Log do passo 3 |
| `temp/migration/reset_links.csv` | Links de recuperação de senha por email |
| `temp/migration/validation_report.md` | Relatório de validação |
| `temp/migration/transformed/uid_map.json` | Mapeamento firebase_uid → supabase_uuid |

## Ordem de importação (FKs)

```
auth.users → profiles
           → rural_properties → gateways → collars → areas
                                                    → fences
                                                    → herding_plans
                              → herding_operations
                              → events
                              → property_commands → property_command_events
                              → property_events
                              → property_telemetry_latest/history
                              → property_health_latest/history
matrix_bindings / matrix_queue_keys / matrix_command_queues / matrix_command_results
```

## Notas

- `user_push_tokens` é pulado — será recriado pelo app ao fazer login.
- `property_scope_id` é recomputado via SHA-256 do `id` (nunca copiado do Firebase).
- Usuários migrados recebem senha temporária aleatória; use `reset_links.csv` para notificá-los.
- Execute a pipeline completa pelo menos 2x em staging antes do corte real.
