# Task: Hardening do Planner RPv2 para 32 Pontos 2026-06-19

#ruraltech
#tarefas

## Context

Implementar na `main` o plano `ruraltech_rpv2_32_point_planner_implementation_plan.md` para suportar cercas de 3 a 32 pontos sem abortar a medição antes do particionamento. Continua [[crc-canonico-rpv2-timeout-wake-2026-06-19]] e preserva [[estabilizacao-transporte-rpv2-2026-06-19]].

## Action

- [x] Carregar Graphify, brain, plano e baseline da `main`
- [x] Limitar a primeira medição de cada fragmento ao máximo seguro de 5 pontos
- [x] Reduzir falhas de medição multiponto antes de falhar terminalmente
- [x] Preservar falha terminal para fragmento unitário impossível
- [x] Garantir publicação estruturada de falhas do planner por alvo
- [x] Cobrir planos de 3, 4, 5, 6, 7, 8, 12, 20 e 32 pontos
- [x] Cobrir entradas inválidas, falha unitária e capacidade insuficiente
- [x] Integrar e executar testes host-side
- [x] Verificar suporte a 7 fragmentos no transporte existente
- [x] Executar validações estáticas e compilação aplicável
- [x] Atualizar histórico, pendências e checkpoint no brain

## Status

Implementação concluída na `main`; compilação Arduino e bancada física permanecem pendentes.

Update context: planner bounded-first, redução segura de falha multiponto, publicação estruturada e CI implementados em 2026-06-19.

Concluído:
- `32` pontos planejam `5+5+5+5+5+5+2`, sem tentativa inicial de 32.
- `20` pontos planejam `5+5+5+5`.
- falha multiponto de codec/medição reduz até encontrar um candidato válido.
- falha unitária termina como `single_point_encode_failed`.
- fallback imediato de falha inclui `reason`, `reasonCode` quando conhecido e `deviceResults` por alvo.
- 27 testes host-side passaram.
- `git diff --check` passou.

Blocker:
- compilações de `gateway-matriz` e `coleira` foram interrompidas após mais de 60 segundos sem saída, repetindo o hang silencioso conhecido deste host.

## Next step

Compilar em host Arduino estável, gravar ambos os firmwares e executar bancadas de 6, 12, 20 e 32 pontos, incluindo repetição de 32 pontos após deep sleep.

## Related

[[protocolo-rpv2]]
[[reaproveitamento-area-sync-queue-downlink-cloud-2026-04-18]]
