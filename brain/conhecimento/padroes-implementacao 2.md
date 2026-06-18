# Conhecimento: Padrões de Implementação — RuralTech

#ruraltech
#conhecimento

## Context

Padrões que devem ser seguidos ao implementar novos endpoints, comandos, acesso ao banco e testes.

## Description

Guia de referência para desenvolvimento consistente no monorepo RuralTech.

## Details

### Novos Endpoints e Comandos (Gateway + App)

1. **Validar payload antes de qualquer IO ou chamada de rede**
2. Manter compatibilidade com contratos em `contracts/messages/`
3. Para comandos acima de **128 bytes**: usar fragmentação (`chunked`) seguindo padrão atual
4. Publicar resultado no WebSocket com formato `command_result`
5. Para alterações de modo operacional (`wifi_ota_enabled=false`): **exigir marcador administrativo** (`requested_by_role=adm|admin` ou `requested_by_admin=true`)

### Acesso ao Banco (Supabase no App)

- **Somente `CloudService`** concentra acesso ao Supabase Postgres no app
- `screens/` e `widgets/` **não devem importar ou acessar Supabase diretamente**
- Operações múltiplas devem usar transação/batch via **RPC** quando necessário
- **Sempre normalizar IDs** (path string, uid bruto, DocumentReference legado) antes de persistir
- IDs LoRa de coleira devem ser **numéricos e maiores que zero**

### Padrões de Teste

- Priorizar testes de **comportamento observável** (entrada/saída) — não testar detalhes internos
- **Mocks apenas para dependências externas**: WebSocket, HTTP, clock, Supabase client
- Não mockar banco de dados local — usar o real quando possível

**Suíte mínima por área impactada:**

| Área | Comando |
|---|---|
| App Flutter | `flutter analyze` + `flutter test` em `app/` |
| Regras Supabase | `supabase test db --local` (pgTAP em `supabase/tests/`) |
| Contrato firmware | Compilar + executar `firmware/tests/command_contract_test.cpp` com g++ |
| Firmware | `arduino-cli compile` para coleira, gateway, gateway-matriz |

**Exemplo de padrão (Dart):**
```dart
group('GatewayService business rules', () {
  test('blocks LoRa-only SET_PARAMS without admin marker', () {})
})
```

### Segurança

- **Nunca commitar** segredos: `manual_settings.local.h`, chaves, credenciais de produção
- **Não logar** dados sensíveis (senhas, writer keys, tokens)
- Validar autenticação/autorização pelas **RLS policies do Supabase** (testadas via pgTAP)
- Sanitizar inputs de coordenadas, IDs e payload JSON
- **Princípio de menor privilégio:**
  - `wifi_ota_enabled=false` requer origem administrativa
  - Escrita anônima nas Edge Functions Supabase só com `matrixId + writerKey` válidos

### Performance (Referência Rápida)

- Respeitar limite LoRa de **128 bytes** por frame (fragmentação automática para maiores)
- Evitar **N+1 no Supabase** — preferir queries consolidadas e merge por chave
- Usar **batch** em operações de escrita em massa
- Em descoberta de rede local: manter processamento em lotes (`batch probing`)
- Em listagens do gateway (`/devices`, `/logs`): manter limite (`?limit=<n>`)

### Integridade de Contrato

- Fixtures JSON em `contracts/messages/` são **baseline de regressão**
- **Proibido** quebrar um contrato existente sem atualizar simultaneamente os testes
- Policies RLS do Supabase devem permanecer alinhadas com papéis (`adm` vs `user`) e ownership

## Related

[[convencoes-codigo]]
[[regras-negocio]]
[[stack-tecnologico]]
[[modelagem-dados-supabase]]
