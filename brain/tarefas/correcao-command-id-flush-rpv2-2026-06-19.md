# Task: Correção de Command ID e Flush RPv2 2026-06-19

#ruraltech
#tarefas

## Context

Implementar na `main` o plano `ruraltech_rpv2_command_id_flush_fix_plan.md`, corrigindo truncamento de command IDs longos e o hot loop do flush de status RPv2 diferidos sem alterar o formato binário LoRa nem o schema Supabase.

Continua [[estabilizacao-transporte-rpv2-2026-06-19]] e segue [[protocolo-rpv2]].

## Action

- [x] Confirmar `main`, baseline RPv2 e alterações preexistentes
- [x] Carregar Graphify, brain e plano completo
- [x] Inventariar buffers e cópias de command ID
- [x] Adicionar política compartilhada de tamanho e cópia segura
- [x] Preservar command ID completo na matriz e coleira
- [x] Estabilizar fila e flush diferido com consumo, backoff e logs
- [x] Reter comando ativo até publicação terminal confirmada
- [x] Corrigir buffers de status truncados
- [x] Adicionar ou ampliar testes host-side
- [x] Executar validações estáticas e testes
- [x] Compilar matriz e coleira
- [x] Atualizar Graphify e documentação do brain

## Status

Implementação concluída na `main`; pendem apenas gravação e validação física/cloud.

Validações concluídas:
- `git diff --check`
- testes host-side de contrato, stream, anti-replay e política RPv2
- compilação Arduino da matriz: 73% flash, 29% RAM global
- compilação Arduino da coleira: 60% flash, 21% RAM global
- Graphify atualizado para 4.090 nós e 6.101 arestas

Decisão de persistência:
- command ID de auditoria passou a 128 bytes;
- fila EEPROM passou de 10 para 8 slots para não colidir com a área do último GPS válido;
- layout incrementado para v3, limpando registros antigos incompatíveis.

## Next step

Gravar ambos os firmwares, executar a bancada de seis pontos e validar no Supabase que o command ID completo sai de `queued` sem criar linha truncada.

## Related

[[fluxo-comandos]]
