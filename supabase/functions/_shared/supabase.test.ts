import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

import { COMMAND_TTL_MS, commandExpiryMs } from "./supabase.ts";

Deno.test("commandExpiryMs — SET_FENCE usa TTL estendido para bancada", () => {
  const createdAtMs = 1_700_000_000_000;
  assertEquals(COMMAND_TTL_MS.SET_FENCE, 30 * 60 * 1000);
  assertEquals(
    commandExpiryMs("SET_FENCE", createdAtMs),
    createdAtMs + (30 * 60 * 1000),
  );
});

Deno.test("commandExpiryMs — fallback mantém 10 minutos para comando desconhecido", () => {
  const createdAtMs = 1_700_000_000_000;
  assertEquals(
    commandExpiryMs("UNKNOWN_COMMAND", createdAtMs),
    createdAtMs + (10 * 60 * 1000),
  );
});
