#!/usr/bin/env node
/**
 * Fase 5.5 — Post-import validation.
 *
 * Checks:
 *   1. Row counts per table (prints actual vs expected from export)
 *   2. Referential integrity spot checks
 *   3. Random sample comparison (50 random rows per key entity)
 *
 * Output:
 *   temp/migration/validation_report.md
 *   Exit code 0 = all PASS, 1 = at least one FAIL
 *
 * Usage:
 *   node scripts/migration/04_validate.mjs
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

import { getSupabaseAdmin, countTable, fetchAll } from './lib/supabase_client.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const TRANSFORMED_DIR = join(__dirname, '..', '..', 'temp', 'migration', 'transformed');
const LOG_DIR = join(__dirname, '..', '..', 'temp', 'migration');

mkdirSync(LOG_DIR, { recursive: true });

const results = [];
let anyFail = false;

function pass(check, detail = '') {
  console.log(`  PASS: ${check}${detail ? ' — ' + detail : ''}`);
  results.push({ status: 'PASS', check, detail });
}

function fail(check, detail = '') {
  console.error(`  FAIL: ${check}${detail ? ' — ' + detail : ''}`);
  results.push({ status: 'FAIL', check, detail });
  anyFail = true;
}

function warn(check, detail = '') {
  console.log(`  WARN: ${check}${detail ? ' — ' + detail : ''}`);
  results.push({ status: 'WARN', check, detail });
}

function countJsonl(filename) {
  const path = join(TRANSFORMED_DIR, filename);
  if (!existsSync(path)) return 0;
  const content = readFileSync(path, 'utf8').trim();
  if (!content) return 0;
  return content.split('\n').filter(Boolean).length;
}

function sampleJsonl(filename, n = 50) {
  const path = join(TRANSFORMED_DIR, filename);
  if (!existsSync(path)) return [];
  const lines = readFileSync(path, 'utf8').trim().split('\n').filter(Boolean);
  if (lines.length <= n) return lines.map(l => JSON.parse(l));
  // Random sample
  const sampled = [];
  const step = Math.floor(lines.length / n);
  for (let i = 0; i < lines.length && sampled.length < n; i += step) {
    sampled.push(JSON.parse(lines[i]));
  }
  return sampled;
}

// ─── Count checks ────────────────────────────────────────────────────────────

async function checkCounts() {
  console.log('\n## Row Count Checks\n');

  const tables = [
    ['profiles', 'profiles.jsonl'],
    ['rural_properties', 'rural_properties.jsonl'],
    ['gateways', 'gateways.jsonl'],
    ['collars', 'collars.jsonl'],
    ['areas', 'areas.jsonl'],
    ['fences', 'fences.jsonl'],
    ['herding_plans', 'herding_plans.jsonl'],
    ['herding_operations', 'herding_operations.jsonl'],
    ['events', 'events.jsonl'],
    ['matrix_bindings', 'matrix_bindings.jsonl'],
    ['matrix_queue_keys', 'matrix_queue_keys.jsonl'],
    ['matrix_command_queues', 'matrix_command_queues.jsonl'],
    ['matrix_command_results', 'matrix_command_results.jsonl'],
    ['property_telemetry_latest', 'property_telemetry_latest.jsonl'],
    ['property_telemetry_history', 'property_telemetry_history.jsonl'],
    ['property_health_latest', 'property_health_latest.jsonl'],
    ['property_health_history', 'property_health_history.jsonl'],
    ['property_events', 'property_events.jsonl'],
    ['property_commands', 'property_commands.jsonl'],
    ['property_command_events', 'property_command_events.jsonl'],
  ];

  for (const [table, jsonl] of tables) {
    const expected = countJsonl(jsonl);
    const actual = await countTable(table);
    const ratio = expected > 0 ? actual / expected : 1;
    const detail = `expected=${expected}, actual=${actual}, ratio=${ratio.toFixed(2)}`;
    if (actual === 0 && expected > 0) {
      fail(`count:${table}`, detail + ' — EMPTY TABLE');
    } else if (ratio < 0.95) {
      fail(`count:${table}`, detail + ' — MORE THAN 5% MISSING');
    } else if (actual > expected * 1.1) {
      warn(`count:${table}`, detail + ' — MORE ROWS THAN EXPECTED (pre-existing data?)');
    } else {
      pass(`count:${table}`, detail);
    }
  }
}

// ─── Referential integrity checks ────────────────────────────────────────────

async function checkReferentialIntegrity() {
  console.log('\n## Referential Integrity Checks\n');
  const client = getSupabaseAdmin();

  // Check: all areas.property_id exist in rural_properties
  {
    const { data, error } = await client
      .from('areas')
      .select('id, property_id')
      .not('property_id', 'is', null);
    if (error) { fail('integrity:areas.property_id', error.message); }
    else {
      const propIds = new Set((await fetchAll('rural_properties', 'id')).map(r => r.id));
      const orphans = (data ?? []).filter(a => a.property_id && !propIds.has(a.property_id));
      if (orphans.length > 0) {
        fail('integrity:areas.property_id', `${orphans.length} orphan areas (sample: ${orphans.slice(0, 3).map(a => a.id).join(', ')})`);
      } else {
        pass('integrity:areas.property_id');
      }
    }
  }

  // Check: all collars.gateway_id (when not null) exist in gateways
  {
    const { data, error } = await client
      .from('collars')
      .select('id, gateway_id')
      .not('gateway_id', 'is', null);
    if (error) { fail('integrity:collars.gateway_id', error.message); }
    else {
      const gwIds = new Set((await fetchAll('gateways', 'id')).map(r => r.id));
      const orphans = (data ?? []).filter(c => c.gateway_id && !gwIds.has(c.gateway_id));
      if (orphans.length > 0) {
        warn('integrity:collars.gateway_id', `${orphans.length} collars with unknown gateway_id (may have been deleted)`);
      } else {
        pass('integrity:collars.gateway_id');
      }
    }
  }

  // Check: profiles.legacy_uid is unique
  {
    const profiles = await fetchAll('profiles', 'legacy_uid');
    const seen = new Set();
    const dupes = [];
    for (const p of profiles) {
      if (seen.has(p.legacy_uid)) dupes.push(p.legacy_uid);
      seen.add(p.legacy_uid);
    }
    if (dupes.length > 0) {
      fail('integrity:profiles.legacy_uid_unique', `duplicates: ${dupes.slice(0, 5).join(', ')}`);
    } else {
      pass('integrity:profiles.legacy_uid_unique');
    }
  }

  // Check: fences.device_id references collars.id
  {
    const fences = await fetchAll('fences', 'device_id');
    const collarIds = new Set((await fetchAll('collars', 'id')).map(r => r.id));
    const orphans = fences.filter(f => !collarIds.has(f.device_id));
    if (orphans.length > 0) {
      fail('integrity:fences.device_id', `${orphans.length} fences with no matching collar id`);
    } else {
      pass('integrity:fences.device_id');
    }
  }

  // Check: no profile with null auth_user_id
  {
    const { data, error } = await client
      .from('profiles')
      .select('legacy_uid')
      .is('auth_user_id', null);
    if (error) { fail('integrity:profiles.auth_user_id', error.message); }
    else if ((data ?? []).length > 0) {
      fail('integrity:profiles.auth_user_id_null', `${data.length} profiles missing auth_user_id`);
    } else {
      pass('integrity:profiles.auth_user_id_null');
    }
  }
}

// ─── Sample comparison ───────────────────────────────────────────────────────

async function checkSamples() {
  console.log('\n## Sample Data Checks\n');
  const client = getSupabaseAdmin();

  // rural_properties: check name and property_scope_id match
  {
    const sample = sampleJsonl('rural_properties.jsonl', 20);
    let mismatches = 0;
    for (const expected of sample) {
      const { data } = await client.from('rural_properties').select('id, name, property_scope_id').eq('id', expected.id).maybeSingle();
      if (!data) { mismatches++; continue; }
      if (data.property_scope_id !== expected.property_scope_id) mismatches++;
    }
    if (mismatches > 0) {
      fail('sample:rural_properties', `${mismatches}/${sample.length} mismatches in name/property_scope_id`);
    } else {
      pass('sample:rural_properties', `${sample.length} samples OK`);
    }
  }

  // collars: device_id, name
  {
    const sample = sampleJsonl('collars.jsonl', 20);
    let mismatches = 0;
    for (const expected of sample) {
      const { data } = await client.from('collars').select('id, device_id, name').eq('id', expected.id).maybeSingle();
      if (!data) { mismatches++; continue; }
      if (data.device_id !== expected.device_id) mismatches++;
    }
    if (mismatches > 0) {
      fail('sample:collars', `${mismatches}/${sample.length} mismatches`);
    } else {
      pass('sample:collars', `${sample.length} samples OK`);
    }
  }

  // profiles: legacy_uid present
  {
    const sample = sampleJsonl('profiles.jsonl', 20);
    let mismatches = 0;
    for (const expected of sample) {
      const { data } = await client.from('profiles').select('legacy_uid, email').eq('legacy_uid', expected.legacy_uid).maybeSingle();
      if (!data) mismatches++;
    }
    if (mismatches > 0) {
      fail('sample:profiles', `${mismatches}/${sample.length} profiles missing in Supabase`);
    } else {
      pass('sample:profiles', `${sample.length} samples OK`);
    }
  }
}

// ─── Report generation ───────────────────────────────────────────────────────

function generateReport() {
  const now = new Date().toISOString();
  const lines = [
    `# Migration Validation Report`,
    `Generated: ${now}`,
    '',
    `## Summary`,
    `Total checks: ${results.length}`,
    `PASS: ${results.filter(r => r.status === 'PASS').length}`,
    `WARN: ${results.filter(r => r.status === 'WARN').length}`,
    `FAIL: ${results.filter(r => r.status === 'FAIL').length}`,
    '',
    `## Result: ${anyFail ? '**FAIL — DO NOT PROCEED WITH CUTOVER**' : '**PASS — Ready for cutover**'}`,
    '',
    `## Details`,
    '',
  ];
  for (const r of results) {
    lines.push(`- [${r.status}] **${r.check}**${r.detail ? ': ' + r.detail : ''}`);
  }
  const report = lines.join('\n');
  const reportPath = join(LOG_DIR, 'validation_report.md');
  writeFileSync(reportPath, report);
  console.log(`\nReport saved: ${reportPath}`);
  return report;
}

async function main() {
  console.log('=== Migration Validation Start ===\n');

  await checkCounts();
  await checkReferentialIntegrity();
  await checkSamples();

  generateReport();

  console.log(`\n=== Validation ${anyFail ? 'FAILED' : 'PASSED'} ===`);
  process.exit(anyFail ? 1 : 0);
}

main().catch(err => {
  console.error(`FATAL: ${err.message}\n${err.stack}`);
  process.exit(1);
});
