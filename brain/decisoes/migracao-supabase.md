# Decision: Migração Firebase → Supabase

Date: 2026

## Context

O projeto usava Firebase (Auth, Firestore, RTDB, Functions) como backend principal.
A RTDB continua sendo o barramento de comandos cloud em tempo real.

## Options

1. Manter Firebase completo
2. Migrar tudo para Supabase
3. Migração gradual: Supabase como camada de comando/API, Firebase como barramento RT

## Decision

Migração gradual para Supabase, mantendo RTDB como barramento de comandos LoRa.
Branch `audit/remove-firebase-complete` consolidou a remoção do Firebase do app.

## Reason

- Supabase oferece Postgres com Row Level Security e Edge Functions mais flexíveis
- Firebase Realtime Database ainda é superior para stream de eventos em tempo real (comandos LoRa)
- Custo e vendor lock-in

## Impact

- `supabase/` tem Edge Functions: `queue-lora-command`, `matrix-cloud`, `admin-repair-cloud-state`, `poll-notifications`, `send-push`
- App Flutter usa apenas Supabase; o backhaul de despacho ainda depende de `matrixId + writerKey` e fila RT
- A reconciliação de escopo/binding roda via `admin-repair-cloud-state`

## Related

[[ruraltech]]
[[visao-geral]]

#decisões #ruraltech 
