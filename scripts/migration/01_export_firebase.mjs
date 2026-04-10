#!/usr/bin/env node
/**
 * Fase 5.2 — Export Firebase data to temp/migration/
 *
 * Exports:
 *   - Firebase Auth (all users)
 *   - Firestore collections: ruralProperties, areas, gateways, collars,
 *     fences, herdingPlans, herdingOperations, events, loraCommands, loraCommandEvents
 *   - RTDB: telemetryLatest, telemetryHistory (30 days), healthLatest,
 *     healthHistory (30 days), propertyEvents (30 days), propertyCommands,
 *     propertyCommandEvents (30 days), matrixBindings, matrixQueueKeys,
 *     matrixCommandQueues, matrixCommandResults
 *
 * Output: temp/migration/*.json + export.log
 *
 * Usage:
 *   node scripts/migration/01_export_firebase.mjs
 *
 * Requires scripts/migration/.env with:
 *   FB_SERVICE_ACCOUNT_PATH=/path/to/service-account.json
 *   FB_PROJECT_ID=ruraltech10
 *   FB_RTDB_URL=https://ruraltech10-default-rtdb.firebaseio.com
 */

import { mkdirSync, writeFileSync, createWriteStream } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

import {
  listAllAuthUsers,
  exportCollection,
  exportRTDBPath,
  listRTDBChildren,
  exportRTDBChild,
} from './lib/firebase_client.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, '..', '..', 'temp', 'migration');

mkdirSync(OUT_DIR, { recursive: true });

const logStream = createWriteStream(join(OUT_DIR, 'export.log'), { flags: 'a' });
function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  logStream.write(line + '\n');
}

function saveJson(filename, data) {
  const path = join(OUT_DIR, filename);
  writeFileSync(path, JSON.stringify(data, null, 2));
  log(`  Saved ${filename} (${Array.isArray(data) ? data.length + ' records' : 'object'})`);
}

// Last N day keys (YYYYMMDD format) for RTDB windowed exports
function lastNDayKeys(n) {
  const keys = [];
  const now = new Date();
  for (let i = 0; i < n; i++) {
    const d = new Date(now);
    d.setDate(d.getDate() - i);
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    keys.push(`${y}${m}${day}`);
  }
  return keys;
}

async function exportFirestoreCollections() {
  const collections = [
    'ruralProperties',
    'areas',
    'gateways',
    'collars',
    'fences',
    'herdingPlans',
    'herdingOperations',
    'events',
    'loraCommands',
    'loraCommandEvents',
  ];

  for (const col of collections) {
    log(`Exporting Firestore collection: ${col}...`);
    try {
      const docs = await exportCollection(col);
      saveJson(`firestore_${col}.json`, docs);
    } catch (err) {
      log(`  ERROR exporting ${col}: ${err.message}`);
    }
  }
}

async function exportRTDBLatest(subtree, filename) {
  log(`Exporting RTDB ${subtree}...`);
  try {
    const data = await exportRTDBPath(subtree);
    saveJson(filename, data ?? {});
  } catch (err) {
    log(`  ERROR exporting RTDB ${subtree}: ${err.message}`);
  }
}

async function exportRTDBWindowed(subtree, filename, dayKeys) {
  log(`Exporting RTDB ${subtree} (${dayKeys.length} day keys)...`);
  const result = {};
  for (const dayKey of dayKeys) {
    try {
      const data = await exportRTDBChild(subtree, dayKey);
      if (data) result[dayKey] = data;
    } catch (err) {
      log(`  WARN: ${subtree}/${dayKey}: ${err.message}`);
    }
  }
  saveJson(filename, result);
  log(`  ${Object.keys(result).length} day keys with data`);
}

async function exportRTDBPropertyWindowed(subtree, filename, dayKeys) {
  // subtree/{property}/{dayKey}/{...}
  log(`Exporting RTDB ${subtree} per-property (${dayKeys.length} day keys)...`);
  const propertyKeys = await listRTDBChildren(subtree);
  log(`  Found ${propertyKeys.length} properties`);
  const result = {};
  for (const propKey of propertyKeys) {
    result[propKey] = {};
    for (const dayKey of dayKeys) {
      try {
        const data = await exportRTDBChild(`${subtree}/${propKey}`, dayKey);
        if (data) result[propKey][dayKey] = data;
      } catch (err) {
        log(`  WARN: ${subtree}/${propKey}/${dayKey}: ${err.message}`);
      }
    }
  }
  saveJson(filename, result);
}

async function exportRTDBPropertyAll(subtree, filename) {
  // subtree/{property}/{...} — export all (not windowed)
  log(`Exporting RTDB ${subtree} (all)...`);
  try {
    const data = await exportRTDBPath(subtree);
    saveJson(filename, data ?? {});
  } catch (err) {
    log(`  ERROR: ${err.message}`);
  }
}

async function main() {
  log('=== Firebase Export Start ===');

  // 1. Firebase Auth
  log('Exporting Firebase Auth users...');
  try {
    const users = await listAllAuthUsers();
    const mapped = users.map(u => ({
      uid: u.uid,
      email: u.email ?? null,
      emailVerified: u.emailVerified,
      displayName: u.displayName ?? null,
      disabled: u.disabled,
      providerData: u.providerData,
      customClaims: u.customClaims ?? null,
      metadata: {
        creationTime: u.metadata.creationTime,
        lastSignInTime: u.metadata.lastSignInTime,
      },
    }));
    saveJson('auth_users.json', mapped);
    log(`Auth: ${mapped.length} users exported`);
  } catch (err) {
    log(`ERROR exporting Auth: ${err.message}`);
  }

  // 2. Firestore collections
  await exportFirestoreCollections();

  // 3. RTDB exports
  const dayKeys = lastNDayKeys(30);

  // telemetryLatest/{property}/{device}
  await exportRTDBLatest('telemetryLatest', 'rtdb_telemetryLatest.json');

  // telemetryHistory/{dayKey}/{property}/{device}/{historyId}
  await exportRTDBWindowed('telemetryHistory', 'rtdb_telemetryHistory.json', dayKeys);

  // healthLatest/{property}/{device}
  await exportRTDBLatest('healthLatest', 'rtdb_healthLatest.json');

  // healthHistory/{dayKey}/{property}/{device}/{historyId}
  await exportRTDBWindowed('healthHistory', 'rtdb_healthHistory.json', dayKeys);

  // propertyEvents/{property}/{dayKey}/{eventId}
  await exportRTDBPropertyWindowed('propertyEvents', 'rtdb_propertyEvents.json', dayKeys);

  // propertyCommands/{property}/{commandId}
  await exportRTDBPropertyAll('propertyCommands', 'rtdb_propertyCommands.json');

  // propertyCommandEvents/{property}/{dayKey}/{commandId}/{eventId}
  await exportRTDBPropertyWindowed('propertyCommandEvents', 'rtdb_propertyCommandEvents.json', dayKeys);

  // matrixBindings/{runtimeId}
  await exportRTDBLatest('matrixBindings', 'rtdb_matrixBindings.json');

  // matrixQueueKeys/{runtimeId}
  await exportRTDBLatest('matrixQueueKeys', 'rtdb_matrixQueueKeys.json');

  // matrixCommandQueues/{runtimeId}/{queueKey}/{commandId}
  await exportRTDBLatest('matrixCommandQueues', 'rtdb_matrixCommandQueues.json');

  // matrixCommandResults/{runtimeId}/{commandId}
  await exportRTDBLatest('matrixCommandResults', 'rtdb_matrixCommandResults.json');

  log('=== Firebase Export Complete ===');
  logStream.end();
}

main().catch(err => {
  log(`FATAL: ${err.message}\n${err.stack}`);
  logStream.end();
  process.exit(1);
});
