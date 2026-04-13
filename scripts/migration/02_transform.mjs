#!/usr/bin/env node
/**
 * Fase 5.3 — Transform Firebase exports → Supabase-ready JSONL files.
 *
 * Input:  temp/migration/firestore_*.json + rtdb_*.json + auth_users.json
 * Output: temp/migration/transformed/*.jsonl  (one row per line, ready for import)
 *         temp/migration/uid_map.json          (firebase_uid → supabase_auth_uuid placeholder)
 *
 * Usage:
 *   node scripts/migration/02_transform.mjs
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync, unlinkSync } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { createHash } from 'crypto';

import {
  transformRuralProperty,
  transformArea,
  transformGateway,
  transformCollar,
  transformFence,
  transformHerdingPlan,
  transformHerdingOperation,
  transformEvent,
  transformPropertyCommand,
  transformPropertyCommandEvent,
  transformTelemetryLatest,
  transformTelemetryHistory,
  transformHealthLatest,
  transformHealthHistory,
  transformPropertyEvent,
  transformMatrixBinding,
  transformMatrixQueueKey,
  transformMatrixCommandQueue,
  transformMatrixCommandResult,
  normalizeId,
  normalizeText,
  computePropertyScopeId,
  fbTimestampToIso,
  fbTimestampToMs,
} from './lib/transformers.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const IN_DIR = join(__dirname, '..', '..', 'temp', 'migration');
const OUT_DIR = join(IN_DIR, 'transformed');

mkdirSync(OUT_DIR, { recursive: true });

function log(msg) {
  console.log(`[${new Date().toISOString()}] ${msg}`);
}

function readJson(filename) {
  const path = join(IN_DIR, filename);
  if (!existsSync(path)) {
    log(`  WARN: ${filename} not found, skipping`);
    return null;
  }
  return JSON.parse(readFileSync(path, 'utf8'));
}

function writeJsonl(filename, rows) {
  const path = join(OUT_DIR, filename);
  const content = rows.map(r => JSON.stringify(r)).join('\n') + (rows.length ? '\n' : '');
  writeFileSync(path, content);
  log(`  -> ${filename}: ${rows.length} rows`);
}

function writeJsonFile(filename, data) {
  writeFileSync(join(OUT_DIR, filename), JSON.stringify(data, null, 2));
}

// ─── Auth users ──────────────────────────────────────────────────────────────

function transformAuthUsers(authUsers) {
  log('Transforming auth_users...');
  // uid_map: firebase_uid → { email, role, willBeCreated: true }
  // Actual Supabase UUID is assigned during import; we store a placeholder here.
  const uidMap = {};
  const profileRows = [];

  for (const u of authUsers) {
    const fbUid = u.uid;
    const email = u.email ?? null;
    const role = u.customClaims?.role ?? 'user';
    uidMap[fbUid] = { email, role, firebaseUid: fbUid, supabaseUuid: null };
    profileRows.push({
      legacy_uid: fbUid,
      email,
      role,
      // auth_user_id will be filled during import
    });
  }

  writeJsonl('profiles.jsonl', profileRows);
  return uidMap;
}

// ─── Firestore collections ────────────────────────────────────────────────────

function transformCollection(filename, transformer, outputName) {
  const docs = readJson(filename);
  if (!docs) return [];
  log(`Transforming ${filename}...`);
  const rows = [];
  for (const doc of docs) {
    try {
      rows.push(transformer(doc));
    } catch (err) {
      log(`  WARN: skip doc ${doc.id}: ${err.message}`);
    }
  }
  writeJsonl(outputName, rows);
  return rows;
}

// ─── RTDB transforms ─────────────────────────────────────────────────────────

function transformRTDBTelemetryLatest() {
  const data = readJson('rtdb_telemetryLatest.json');
  if (!data) return;
  log('Transforming rtdb_telemetryLatest...');
  const rows = [];
  for (const [propertyId, devices] of Object.entries(data)) {
    if (!devices || typeof devices !== 'object') continue;
    for (const [deviceId, entry] of Object.entries(devices)) {
      if (!entry || typeof entry !== 'object') continue;
      rows.push(transformTelemetryLatest({ propertyId, deviceId, data: entry }));
    }
  }
  writeJsonl('property_telemetry_latest.jsonl', rows);
}

function transformRTDBTelemetryHistory() {
  const data = readJson('rtdb_telemetryHistory.json');
  if (!data) return;
  log('Transforming rtdb_telemetryHistory...');
  const rows = [];
  for (const [dayKey, byProperty] of Object.entries(data)) {
    if (!byProperty || typeof byProperty !== 'object') continue;
    for (const [propertyId, byDevice] of Object.entries(byProperty)) {
      if (!byDevice || typeof byDevice !== 'object') continue;
      for (const [deviceId, byHistory] of Object.entries(byDevice)) {
        if (!byHistory || typeof byHistory !== 'object') continue;
        for (const [historyId, entry] of Object.entries(byHistory)) {
          if (!entry || typeof entry !== 'object') continue;
          rows.push(transformTelemetryHistory({ propertyId, deviceId, dayKey, historyId, data: entry }));
        }
      }
    }
  }
  writeJsonl('property_telemetry_history.jsonl', rows);
}

function transformRTDBHealthLatest() {
  const data = readJson('rtdb_healthLatest.json');
  if (!data) return;
  log('Transforming rtdb_healthLatest...');
  const rows = [];
  for (const [propertyId, devices] of Object.entries(data)) {
    if (!devices || typeof devices !== 'object') continue;
    for (const [deviceId, entry] of Object.entries(devices)) {
      if (!entry || typeof entry !== 'object') continue;
      rows.push(transformHealthLatest({ propertyId, deviceId, data: entry }));
    }
  }
  writeJsonl('property_health_latest.jsonl', rows);
}

function transformRTDBHealthHistory() {
  const data = readJson('rtdb_healthHistory.json');
  if (!data) return;
  log('Transforming rtdb_healthHistory...');
  const rows = [];
  for (const [dayKey, byProperty] of Object.entries(data)) {
    if (!byProperty || typeof byProperty !== 'object') continue;
    for (const [propertyId, byDevice] of Object.entries(byProperty)) {
      if (!byDevice || typeof byDevice !== 'object') continue;
      for (const [deviceId, byHistory] of Object.entries(byDevice)) {
        if (!byHistory || typeof byHistory !== 'object') continue;
        for (const [historyId, entry] of Object.entries(byHistory)) {
          if (!entry || typeof entry !== 'object') continue;
          rows.push(transformHealthHistory({ propertyId, deviceId, dayKey, historyId, data: entry }));
        }
      }
    }
  }
  writeJsonl('property_health_history.jsonl', rows);
}

function transformRTDBPropertyEvents() {
  const data = readJson('rtdb_propertyEvents.json');
  if (!data) return;
  log('Transforming rtdb_propertyEvents...');
  const rows = [];
  for (const [propertyId, byDay] of Object.entries(data)) {
    if (!byDay || typeof byDay !== 'object') continue;
    for (const [dayKey, events] of Object.entries(byDay)) {
      if (!events || typeof events !== 'object') continue;
      for (const [eventId, entry] of Object.entries(events)) {
        if (!entry || typeof entry !== 'object') continue;
        rows.push(transformPropertyEvent({ propertyId, dayKey, eventId, data: entry }));
      }
    }
  }
  writeJsonl('property_events.jsonl', rows);
}

function transformRTDBPropertyCommands() {
  const data = readJson('rtdb_propertyCommands.json');
  if (!data) return;
  log('Transforming rtdb_propertyCommands...');
  const rows = [];
  for (const [propertyId, commands] of Object.entries(data)) {
    if (!commands || typeof commands !== 'object') continue;
    for (const [commandId, entry] of Object.entries(commands)) {
      if (!entry || typeof entry !== 'object') continue;
      rows.push(transformPropertyCommand({
        id: commandId,
        data: { ...entry, propertyId, commandId },
      }));
    }
  }
  writeJsonl('property_commands_rtdb.jsonl', rows);
}

function transformRTDBPropertyCommandEvents() {
  const data = readJson('rtdb_propertyCommandEvents.json');
  if (!data) return;
  log('Transforming rtdb_propertyCommandEvents...');
  const rows = [];
  for (const [propertyId, byDay] of Object.entries(data)) {
    if (!byDay || typeof byDay !== 'object') continue;
    for (const [dayKey, byCommand] of Object.entries(byDay)) {
      if (!byCommand || typeof byCommand !== 'object') continue;
      for (const [commandId, events] of Object.entries(byCommand)) {
        if (!events || typeof events !== 'object') continue;
        for (const [eventId, entry] of Object.entries(events)) {
          if (!entry || typeof entry !== 'object') continue;
          rows.push(transformPropertyCommandEvent({
            id: eventId,
            data: { ...entry, commandId },
            propertyId,
            dayKey,
          }));
        }
      }
    }
  }
  writeJsonl('property_command_events_rtdb.jsonl', rows);
}

function transformRTDBMatrixBindings() {
  const data = readJson('rtdb_matrixBindings.json');
  if (!data) return;
  log('Transforming rtdb_matrixBindings...');
  const rows = [];
  for (const [runtimeId, entry] of Object.entries(data)) {
    if (!entry || typeof entry !== 'object') continue;
    rows.push(transformMatrixBinding({ runtimeId, data: entry }));
  }
  writeJsonl('matrix_bindings.jsonl', rows);
}

function transformRTDBMatrixQueueKeys() {
  const data = readJson('rtdb_matrixQueueKeys.json');
  if (!data) return;
  log('Transforming rtdb_matrixQueueKeys...');
  const rows = [];
  for (const [runtimeId, entry] of Object.entries(data)) {
    if (!entry || typeof entry !== 'object') continue;
    rows.push(transformMatrixQueueKey({ runtimeId, data: entry }));
  }
  writeJsonl('matrix_queue_keys.jsonl', rows);
}

function transformRTDBMatrixCommandQueues() {
  const data = readJson('rtdb_matrixCommandQueues.json');
  if (!data) return;
  log('Transforming rtdb_matrixCommandQueues...');
  const rows = [];
  for (const [runtimeId, byQueueKey] of Object.entries(data)) {
    if (!byQueueKey || typeof byQueueKey !== 'object') continue;
    for (const [queueKey, byCommand] of Object.entries(byQueueKey)) {
      if (!byCommand || typeof byCommand !== 'object') continue;
      for (const [commandId, entry] of Object.entries(byCommand)) {
        if (!entry || typeof entry !== 'object') continue;
        rows.push(transformMatrixCommandQueue({ runtimeId, queueKey, commandId, data: entry }));
      }
    }
  }
  writeJsonl('matrix_command_queues.jsonl', rows);
}

function transformRTDBMatrixCommandResults() {
  const data = readJson('rtdb_matrixCommandResults.json');
  if (!data) return;
  log('Transforming rtdb_matrixCommandResults...');
  const rows = [];
  for (const [runtimeId, byCommand] of Object.entries(data)) {
    if (!byCommand || typeof byCommand !== 'object') continue;
    for (const [commandId, entry] of Object.entries(byCommand)) {
      if (!entry || typeof entry !== 'object') continue;
      rows.push(transformMatrixCommandResult({ runtimeId, commandId, data: entry }));
    }
  }
  writeJsonl('matrix_command_results.jsonl', rows);
}

/**
 * Merge property_commands from Firestore and RTDB, deduplicating by (property_id, command_id).
 * RTDB wins on conflict (more recent status).
 */
function mergePropertyCommands() {
  log('Merging property_commands (Firestore + RTDB)...');
  const fsPath = join(OUT_DIR, 'property_commands_fs.jsonl');
  const rtdbPath = join(OUT_DIR, 'property_commands_rtdb.jsonl');
  const merged = new Map();

  function loadJsonlSync(path) {
    if (!existsSync(path)) return [];
    return readFileSync(path, 'utf8').trim().split('\n').filter(Boolean).map(l => JSON.parse(l));
  }

  for (const row of loadJsonlSync(fsPath)) {
    const key = `${row.property_id}::${row.command_id}`;
    merged.set(key, row);
  }
  for (const row of loadJsonlSync(rtdbPath)) {
    const key = `${row.property_id}::${row.command_id}`;
    merged.set(key, row); // RTDB overwrites Firestore
  }
  const rows = [...merged.values()];
  writeJsonl('property_commands.jsonl', rows);

  try { if (existsSync(fsPath)) unlinkSync(fsPath); } catch (_) {}
  try { if (existsSync(rtdbPath)) unlinkSync(rtdbPath); } catch (_) {}
}

function main() {
  log('=== Transform Start ===');

  // Auth
  const authUsers = readJson('auth_users.json');
  const uidMap = authUsers ? transformAuthUsers(authUsers) : {};
  writeJsonFile('uid_map.json', uidMap);
  log(`uid_map: ${Object.keys(uidMap).length} users`);

  // Firestore
  transformCollection('firestore_ruralProperties.json', transformRuralProperty, 'rural_properties.jsonl');
  transformCollection('firestore_areas.json', transformArea, 'areas.jsonl');
  transformCollection('firestore_gateways.json', transformGateway, 'gateways.jsonl');
  transformCollection('firestore_collars.json', transformCollar, 'collars.jsonl');
  transformCollection('firestore_fences.json', transformFence, 'fences.jsonl');
  transformCollection('firestore_herdingPlans.json', transformHerdingPlan, 'herding_plans.jsonl');
  transformCollection('firestore_herdingOperations.json', transformHerdingOperation, 'herding_operations.jsonl');
  transformCollection('firestore_events.json', transformEvent, 'events.jsonl');

  // Firestore loraCommands → property_commands_fs.jsonl (intermediate)
  const loraCommandDocs = readJson('firestore_loraCommands.json');
  if (loraCommandDocs) {
    const rows = loraCommandDocs.map(doc => transformPropertyCommand(doc));
    writeJsonl('property_commands_fs.jsonl', rows);
  }

  // Firestore loraCommandEvents → merge into property_command_events_fs.jsonl
  const loraCommandEventDocs = readJson('firestore_loraCommandEvents.json');
  if (loraCommandEventDocs) {
    // These are top-level events without a property context — put in a generic day_key
    const rows = loraCommandEventDocs.map(doc => {
      const propertyId = normalizeId(doc.data?.propertyId ?? doc.data?.property_id ?? '');
      const dayKey = String(doc.data?.dayKey ?? doc.data?.day_key ?? '00000000');
      return transformPropertyCommandEvent({
        id: doc.id,
        data: doc.data,
        propertyId,
        dayKey,
      });
    }).filter(r => r.property_id);
    writeJsonl('property_command_events_fs.jsonl', rows);
  }

  // RTDB
  transformRTDBTelemetryLatest();
  transformRTDBTelemetryHistory();
  transformRTDBHealthLatest();
  transformRTDBHealthHistory();
  transformRTDBPropertyEvents();
  transformRTDBPropertyCommands();
  transformRTDBPropertyCommandEvents();
  transformRTDBMatrixBindings();
  transformRTDBMatrixQueueKeys();
  transformRTDBMatrixCommandQueues();
  transformRTDBMatrixCommandResults();

  // Merge property_commands
  mergePropertyCommands();

  // Merge property_command_events from FS + RTDB
  log('Merging property_command_events (Firestore + RTDB)...');
  function loadJsonlSync(path) {
    if (!existsSync(path)) return [];
    return readFileSync(path, 'utf8').trim().split('\n').filter(Boolean).map(l => JSON.parse(l));
  }
  const fsEvtPath = join(OUT_DIR, 'property_command_events_fs.jsonl');
  const rtdbEvtPath = join(OUT_DIR, 'property_command_events_rtdb.jsonl');
  const allEvts = new Map();
  for (const r of loadJsonlSync(fsEvtPath)) {
    allEvts.set(`${r.property_id}::${r.day_key}::${r.event_id}`, r);
  }
  for (const r of loadJsonlSync(rtdbEvtPath)) {
    allEvts.set(`${r.property_id}::${r.day_key}::${r.event_id}`, r);
  }
  writeJsonl('property_command_events.jsonl', [...allEvts.values()]);
  try { if (existsSync(fsEvtPath)) unlinkSync(fsEvtPath); } catch (_) {}
  try { if (existsSync(rtdbEvtPath)) unlinkSync(rtdbEvtPath); } catch (_) {}

  log('=== Transform Complete ===');
  log(`Output directory: ${OUT_DIR}`);
}

try {
  main();
} catch (err) {
  console.error(`FATAL: ${err.message}\n${err.stack}`);
  process.exit(1);
}
