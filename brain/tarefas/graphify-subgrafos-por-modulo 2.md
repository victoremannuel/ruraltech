# Task: Graphify por Módulo

#ruraltech
#tarefas

## Context

O corpus raiz do monorepo excedeu o limite operacional do fluxo de `graphify` em uma única passada. Foi necessário particionar a indexação por subdomínio para gerar grafos úteis sem depender do backend `kimi|claude` do CLI instalado.

## Action

- [x] Detectar volume separado de `app`, `brain`, `coleira`, `gateway-matriz` e `gateway`
- [x] Extrair AST estrutural para os cinco subdiretórios
- [x] Complementar a camada semântica manualmente com Codex
- [x] Gerar `graph.json`, `graph.html` e `GRAPH_REPORT.md` em cada módulo

## Status

Concluído em 2026-05-06. A extração foi feita com helper local `scripts/graphify_manual_multi.py`, usando o pacote `graphify` para build/cluster/export e o próprio Codex para a semântica.

## Next step

Revisar, se necessário, as comunidades mais ruidosas do grafo de `app/` e adicionar arestas semânticas extras para reduzir o peso de imports genéricos (`package:flutter/material.dart`) nas perguntas sugeridas.

## Related

[[ruraltech]]
[[visao-geral]]
[[fluxos-comunicacao-ponta-a-ponta]]
