#!/usr/bin/env node
/**
 * Fase 5.4 — Import transformed data into Supabase.
 *
 * Import order (respects FK dependencies):
 *   1. auth.users (via Auth Admin API) + profiles
 *   2. rural_properties
 *   3. gateways (FK → rural_properties optional)
 *   4. collars (FK → rural_properties, gateways optional)
 *   5. areas (FK → rural_properties)
 *   6. fences (FK → collars.id)
 *   7. herding_plans (FK → collars.id)
 *   8. herding_operations (FK → rural_properties)
 *   9. events
 *  10. matrix_bindings, matrix_queue_keys, matrix_command_queues, matrix_command_results
 *  11. property_telemetry_latest, property_telemetry_history
 *  12. property_health_latest, property_health_history
 *  13. property_events
 *  14. property_commands, property_command_events
 *
 * Skips: user_push_tokens (recreated by app at runtime)
 *
 * Input:  temp/migration/transformed/*.jsonl + uid_map.json
 * Output: temp/migration/import.log + temp/migration/reset_links.csv
 *
 * Usage:
 *   node scripts/migration/03_import_supabase.mjs
 */

import { readFileSync, writeFileSync, createWriteStream, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { randomBytes } from 'crypto';

import {
  getSupabaseAdmin,
  batchUpsert,
  batchInsert,
  createAuthUser,
  generateRecoveryLink,
} from './lib/supabase_client.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const TRANSFORMED_DIR = join(__dirname, '..', '..', 'temp', 'migration', 'transformed');
const LOG_DIR = join(__dirname, '..', '..', 'temp', 'migration');

mkdirSync(LOG_DIR, { recursive: true });

const logStream = createWriteStream(join(LOG_DIR, 'import.log'), { flags: 'a' });

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  logStream.write(line + '\n');
}

function readJsonl(filename) {
  const path = join(TRANSFORMED_DIR, filename);
  if (!existsSync(path)) {
    log(`  WARN: ${filename} not found, skipping`);
    return [];
  }
  const content = readFileSync(path, 'utf8').trim();
  if (!content) return [];
  return content.split('\n').filter(Boolean).map(line => JSON.parse(line));
}

function readJsonFile(filename) {
  const path = join(TRANSFORMED_DIR, filename);
  if (!existsSync(path)) return null;
  return JSON.parse(readFileSync(path, 'utf8'));
}

function randomPassword() {
  return randomBytes(16).toString('hex');
}

// ─── Step 1: Create Auth users + profiles ────────────────────────────────────

async function importAuthAndProfiles() {
  log('Step 1: Creating Supabase Auth users + profiles...');

  const profileRows = readJsonl('profiles.jsonl');
  const uidMap = readJsonFile('uid_map.json') ?? {};

  // Pre-load all existing Supabase Auth users to handle "already exists" case
  const client = getSupabaseAdmin();
  const existingByEmail = new Map();
  let page = 1;
  while (true) {
    const { data, error } = await client.auth.admin.listUsers({ page, perPage: 1000 });
    if (error || !data?.users?.length) break;
    for (const u of data.users) {
      if (u.email) existingByEmail.set(u.email.toLowerCase(), u);
    }
    if (data.users.length < 1000) break;
    page++;
  }
  log(`  Found ${existingByEmail.size} existing Supabase Auth users`);

  const resetLinks = [['email', 'legacy_uid', 'reset_link']];
  const profilesWithAuthId = [];

  for (const row of profileRows) {
    const fbUid = row.legacy_uid;
    const email = row.email;

    if (!email) {
      log(`  WARN: skip ${fbUid} — no email`);
      continue;
    }

    const emailLower = email.toLowerCase();
    let supabaseUuid;

    if (existingByEmail.has(emailLower)) {
      // User already exists — use their existing UUID
      supabaseUuid = existingByEmail.get(emailLower).id;
      log(`  Reuse existing: ${email} (${fbUid} → ${supabaseUuid})`);
    } else {
      try {
        const authUser = await createAuthUser({
          email,
          password: randomPassword(),
          userMetadata: { legacy_uid: fbUid },
        });
        supabaseUuid = authUser.id;
        log(`  Created: ${email} (${fbUid} → ${supabaseUuid})`);

        try {
          const link = await generateRecoveryLink(email);
          resetLinks.push([email, fbUid, link]);
        } catch (linkErr) {
          log(`  WARN: recovery link for ${email}: ${linkErr.message}`);
          resetLinks.push([email, fbUid, 'FAILED']);
        }
      } catch (err) {
        log(`  ERROR: ${email}: ${err.message}`);
        continue;
      }
    }

    if (uidMap[fbUid]) uidMap[fbUid].supabaseUuid = supabaseUuid;
    profilesWithAuthId.push({
      auth_user_id: supabaseUuid,
      legacy_uid: fbUid,
      email,
      role: row.role ?? 'user',
    });
  }

  // Upsert profiles
  if (profilesWithAuthId.length > 0) {
    const { count } = await batchUpsert('profiles', profilesWithAuthId, { onConflict: 'auth_user_id' });
    log(`  profiles upserted: ${count}`);
  }

  // Save reset links CSV
  const csvPath = join(LOG_DIR, 'reset_links.csv');
  writeFileSync(csvPath, resetLinks.map(r => r.join(',')).join('\n'));
  log(`  reset_links.csv saved: ${resetLinks.length - 1} new users`);

  // Save updated uid_map
  writeFileSync(join(TRANSFORMED_DIR, 'uid_map.json'), JSON.stringify(uidMap, null, 2));
}

// ─── Generic upsert steps ────────────────────────────────────────────────────

async function importTable(label, jsonlFile, table, conflictCol) {
  log(`Importing ${label}...`);
  const rows = readJsonl(jsonlFile);
  if (!rows.length) { log(`  no rows`); return; }
  const { count } = await batchUpsert(table, rows, { onConflict: conflictCol });
  log(`  ${table}: ${count} rows upserted`);
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
  log('=== Import Start ===');

  // 1. Auth + Profiles
  await importAuthAndProfiles();

  // 2. rural_properties
  await importTable('rural_properties', 'rural_properties.jsonl', 'rural_properties', 'id');

  // 3. gateways
  await importTable('gateways', 'gateways.jsonl', 'gateways', 'id');

  // 4. collars
  await importTable('collars', 'collars.jsonl', 'collars', 'id');

  // 5. areas
  await importTable('areas', 'areas.jsonl', 'areas', 'id');

  // 6. fences (device_id references collars.id)
  await importTable('fences', 'fences.jsonl', 'fences', 'device_id');

  // 7. herding_plans
  await importTable('herding_plans', 'herding_plans.jsonl', 'herding_plans', 'device_id');

  // 8. herding_operations
  await importTable('herding_operations', 'herding_operations.jsonl', 'herding_operations', 'id');

  // 9. events
  await importTable('events', 'events.jsonl', 'events', 'id');

  // 10. matrix_*
  await importTable('matrix_bindings', 'matrix_bindings.jsonl', 'matrix_bindings', 'runtime_id');
  await importTable('matrix_queue_keys', 'matrix_queue_keys.jsonl', 'matrix_queue_keys', 'runtime_id');

  // matrix_command_queues: composite PK (runtime_id, queue_key, command_id)
  {
    log('Importing matrix_command_queues...');
    const rows = readJsonl('matrix_command_queues.jsonl');
    if (rows.length) {
      const { count } = await batchUpsert('matrix_command_queues', rows, { onConflict: 'runtime_id,queue_key,command_id' });
      log(`  matrix_command_queues: ${count} rows upserted`);
    }
  }

  // matrix_command_results: composite PK (runtime_id, command_id)
  {
    log('Importing matrix_command_results...');
    const rows = readJsonl('matrix_command_results.jsonl');
    if (rows.length) {
      const { count } = await batchUpsert('matrix_command_results', rows, { onConflict: 'runtime_id,command_id' });
      log(`  matrix_command_results: ${count} rows upserted`);
    }
  }

  // 11. property_telemetry_latest / history
  {
    log('Importing property_telemetry_latest...');
    const rows = readJsonl('property_telemetry_latest.jsonl');
    if (rows.length) {
      const { count } = await batchUpsert('property_telemetry_latest', rows, { onConflict: 'property_id,device_id' });
      log(`  property_telemetry_latest: ${count} rows`);
    }
  }
  {
    log('Importing property_telemetry_history...');
    const rows = readJsonl('property_telemetry_history.jsonl');
    if (rows.length) {
      const { count } = await batchUpsert('property_telemetry_history', rows, { onConflict: 'property_id,device_id,history_id' });
      log(`  property_telemetry_history: ${count} rows`);
    }
  }

  // 12. property_health_latest / history
  {
    log('Importing property_health_latest...');
    const rows = readJsonl('property_health_latest.jsonl');
    if (rows.length) {
      const { count } = await batchUpsert('property_health_latest', rows, { onConflict: 'property_id,device_id' });
      log(`  property_health_latest: ${count} rows`);
    }
  }
  {
    log('Importing property_health_history...');
    const rows = readJsonl('property_health_history.jsonl');
    if (rows.length) {
      const { count } = await batchUpsert('property_health_history', rows, { onConflict: 'property_id,device_id,history_id' });
      log(`  property_health_history: ${count} rows`);
    }
  }

  // 13. property_events
  {
    log('Importing property_events...');
    const rows = readJsonl('property_events.jsonl');
    if (rows.length) {
      const { count } = await batchUpsert('property_events', rows, { onConflict: 'property_id,day_key,event_id' });
      log(`  property_events: ${count} rows`);
    }
  }

  // 14. property_commands + property_command_events
  {
    log('Importing property_commands...');
    const rows = readJsonl('property_commands.jsonl');
    if (rows.length) {
      const { count } = await batchUpsert('property_commands', rows, { onConflict: 'property_id,command_id' });
      log(`  property_commands: ${count} rows`);
    }
  }
  {
    log('Importing property_command_events...');
    const rows = readJsonl('property_command_events.jsonl');
    if (rows.length) {
      const { count } = await batchUpsert('property_command_events', rows, { onConflict: 'property_id,day_key,event_id' });
      log(`  property_command_events: ${count} rows`);
    }
  }

  log('=== Import Complete ===');
  logStream.end();
}

main().catch(err => {
  log(`FATAL: ${err.message}\n${err.stack}`);
  logStream.end();
  process.exit(1);
});
