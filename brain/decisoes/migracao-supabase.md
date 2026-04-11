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
Branch `audit/remove-firebase-complete` indica que a remoção do Firebase está sendo completada.

## Reason

- Supabase oferece Postgres com Row Level Security e Edge Functions mais flexíveis
- Firebase Realtime Database ainda é superior para stream de eventos em tempo real (comandos LoRa)
- Custo e vendor lock-in

## Impact

- `supabase/` tem Edge Functions: `queue-lora-command`, `matrix-cloud`, `repair-firebase-mirrors`
- App Flutter usa ambos os SDKs durante a transição
- Mirrors Firebase são reparados via Edge Function para manter compatibilidade

## Related

[[ruraltech]]
[[visao-geral]]

#decisões #ruraltech 