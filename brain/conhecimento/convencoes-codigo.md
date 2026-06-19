# Conhecimento: Convenções Obrigatórias de Código — RuralTech

#ruraltech
#conhecimento

## Context

Regras de codificação que todos os contribuidores (e agentes) devem seguir no monorepo.

## Description

Convenções de estilo, tipagem, erros, imports e organização de artefatos que garantem consistência e manutenibilidade do projeto.

## Details

### Tipagem e Estilo

- **Tipagem explícita** e validações defensivas em todo payload de comando e coordenadas
- **Proibido** `dynamic` ou `Map` sem validação de schema no app Flutter
- **Firmware**: usar tipos de largura fixa (`uint8_t`, `uint16_t`, `int32_t`, etc.)
- Funções com **responsabilidade única** e nomes semânticos
- **Constantes de limite centralizadas**: `maxLoraPayloadBytes`, `maxPolygonPoints`, etc.
- Regras de negócio devem retornar `reason` claro quando houver rejeição

### Imports (Dart)

- Preferir imports de pacote (`package:ruraltech_app/...`) fora do mesmo módulo
- Evitar acoplamento por imports profundos e referências cruzadas desnecessárias
- **Firmware**: headers locais por módulo (`*.h`) + contrato compartilhado via `firmware/shared`

### Erros e Retorno

- **Proibidas falhas silenciosas** para regras de negócio
- Comandos app/firmware: sempre produzir retorno estruturado — `ok` + `reason` via `command_result` / `ACK` / `NACK`
- Mensagens de erro devem indicar **causa acionável**: ex. `invalid_device_id`, `admin_required_for_lora_only`
- Exceções cloud: usar `CloudException` / `CloudAuthException` — nunca expor detalhes internos

### Artefatos Temporários

- **Todo artefato temporário local** (compilação, logs, dumps, relatórios intermediários, saídas de testes) deve ir para `temp/`
- **Proibido** criar artefatos em `app/`, `firmware/`, raiz do repo ou outras pastas, salvo quando ferramenta exige caminho fixo

### O que NÃO fazer

- Não alterar contratos públicos de mensagem (`contracts/messages/`) sem atualizar fixtures e testes
- Não introduzir novas dependências de firmware sem avaliar impacto de flash/memória (CRÍTICO: firmware não pode estourar a flash do ESP32)
- Não mudar RLS policies do Supabase sem incluir teste de regressão em `supabase/tests/`
- Não commitar arquivos locais de segredos (`manual_settings.local.h`, chaves de produção, tokens)
- Não bypassar validações de segurança/admin para comandos críticos
- Não desativar gates de CI (`flutter analyze`, `flutter test`, regras tests, firmware compile)
- Não criar artefatos temporários fora de `temp/` sem necessidade técnica
- Não narrar o processo de trabalho (outputs devem ser diretos e factuais)
- Não dar resumos longos — frases objetivas e diretas ao final

### O que DEVE fazer

- Ao final de qualquer trabalho: colocar **resumo curto** com frases objetivas e diretas
- Toda feature/alteração deve rodar auditoria das funcionalidades impactadas para garantir sucesso E2E

## Related

[[ruraltech]]
[[stack-tecnologico]]
[[padroes-implementacao]]
[[regras-negocio]]
[[visao-geral]]
