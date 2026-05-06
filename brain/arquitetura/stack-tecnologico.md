# Architecture: Stack Tecnológico — RuralTech

#ruraltech
#arquitetura

## Overview

Stack completo do monorepo, por camada, com ferramentas de CI/CD e qualidade.

## Components

### App (`app/`)

| Item | Detalhe |
|---|---|
| Linguagem | Dart 3.3+ |
| Framework | Flutter [[uiux-telas]] (Material 3) |
| Banco | Supabase Postgres [[modelagem-dados-supabase]] (RLS, Realtime, Edge Functions) |
| Cliente | `supabase-dart` (sem ORM) |
| Testes | `flutter_test` (unit/widget/fixtures) |
| Linter | `flutter_lints` + `flutter analyze` + `dart format` |
| CI jobs | `Flutter Analyze + Test` · `Flutter Regression` |

### Firmwares (`coleira/`, `gateway/`, `gateway-matriz/`)

| Item | Detalhe |
|---|---|
| Linguagem | C++ (Arduino) |
| Framework | Arduino Core ESP32 |
| Persistência | NVS/EEPROM (coleira) · SD card com logs (gateway) |
| Rádio | RadioLib (LoRa SX127x) |
| Atualizações | OTA Wi-Fi |
| Testes | Contrato C++ compilado com `g++` em `firmware/tests/` |
| Linter | Compilação com `-Wall -Wextra -pedantic` |
| CI jobs | `arduino-cli compile` para coleira, gateway, gateway-matriz |

### Supabase (`supabase/`)

| Item | Detalhe |
|---|---|
| Banco | Postgres 15+ com RLS em todas as tabelas |
| Auth | Supabase Auth [[migracao-supabase]] (JWT) |
| Realtime | CDC WebSocket em 13 tabelas |
| Edge Functions | Deno [[fluxo-comandos]] (TypeScript) |
| Testes | pgTAP via `supabase test db --local` |

### Regras/Testes Legados (`app/rules-tests/`)

| Item | Detalhe |
|---|---|
| Linguagem | Node.js (ESM) |
| Framework | Node test runner + `@firebase/rules-unit-testing` |
| Status | **Legado** — substituído por pgTAP em `supabase/tests/` |

## Flow

### CI/CD — GitHub Actions

| Workflow | Arquivo | Trigger |
|---|---|---|
| PR Quality | `.github/workflows/pr-quality.yml` | Pull Request |
| Nightly Regression | `.github/workflows/nightly-regression.yml` | Agendado (noturno) |

**Gates obrigatórios por PR:**
1. `flutter analyze` — zero warnings/errors
2. `flutter test` — todos os testes passando
3. `supabase test db --local` — pgTAP RLS
4. `g++` compile `command_contract_test.cpp`
5. `arduino-cli compile` — coleira, gateway, gateway-matriz

Desativar qualquer gate de CI é **proibido**.

## Technologies

- ESP32 Dev Module (Arduino IDF)
- LoRa SX127x (payload máx 128 bytes)
- Flutter/Dart 3.3+
- Supabase (Postgres, Auth, Realtime, Edge Functions Deno)
- GitHub Actions

## Related

[[ruraltech]]
[[visao-geral]]
[[design-system-v2]]
[[convencoes-codigo]]
[[padroes-implementacao]]
[[requisitos]]
[[modelagem-dados-supabase]]
[[migracao-supabase]]
[[uiux-telas]]
[[fluxo-comandos]]
