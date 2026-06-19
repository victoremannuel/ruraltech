# Task: CRC Canônico RPv2 e Timeout Wake 2026-06-19

#ruraltech
#tarefas

## Context

Implementar na `main` o plano `ruraltech_rpv2_canonical_crc_implementation_plan.md` após a bancada confirmar que `SET_FENCE` chega ao `FENCE_COMMIT`, mas falha deterministicamente com `crc_mismatch`. Continua [[pump-unificado-rpv2-timing-rtr-2026-06-19]] e segue [[protocolo-rpv2]].

## Action

- [x] Inventariar representação e cálculos CRC existentes
- [x] Criar contrato canônico compartilhado de CRC para pontos E7
- [x] Integrar o helper na matriz e na coleira
- [x] Adicionar logs opcionais do vetor CRC
- [x] Encerrar imediatamente a sessão após CRC mismatch terminal
- [x] Elevar e proteger contra overflow o timeout de espera de uplink
- [x] Adicionar testes host-side e integrar ao CI
- [x] Compilar matriz e coleira
- [x] Executar validações estáticas e testes automatizados
- [x] Atualizar arquitetura, histórico e pendências de bancada

Update context: implementação concluída na `main`; 28 testes host-side passaram e ambos os firmwares compilaram.

## Status

Implementação concluída na `main`; bancada física pendente.

Evidências:
- coleira: 60% flash, 21% RAM
- gateway-matriz: 73% flash, 29% RAM
- `git diff --check` aprovado
- todos os 28 testes em `firmware/tests` aprovados

## Next step

Gravar matriz e coleira com o mesmo build e executar bancadas de 6 e 7 pontos, comparando `RPV2_CRC_VECTOR_END` e confirmando `RPV2_CRC_OK`, `RPV2_SESSION_COMPLETE` e Supabase `applied`.

## Related

[[estabilizacao-transporte-rpv2-2026-06-19]]
[[protocolo-rpv2]]
