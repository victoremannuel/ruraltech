/**
 * Supabase service-role client for migration import.
 * Uses SERVICE_ROLE_KEY (bypasses RLS).
 */
import { createRequire } from 'module';
import { readFileSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

function loadDotEnv() {
  const envPath = join(__dirname, '..', '.env');
  if (!existsSync(envPath)) return;
  const lines = readFileSync(envPath, 'utf8').split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx < 0) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    const val = trimmed.slice(eqIdx + 1).trim().replace(/^["']|["']$/g, '');
    if (key && !process.env[key]) process.env[key] = val;
  }
}

loadDotEnv();

const require = createRequire(import.meta.url);

let _client;

export function getSupabaseAdmin() {
  if (!_client) {
    const url = process.env.SUPABASE_URL;
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!url || !key) {
      throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required');
    }
    const { createClient } = require('@supabase/supabase-js');
    _client = createClient(url, key, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return _client;
}

/**
 * Upsert rows in batches. Throws on error.
 * @param {string} table - Supabase table name
 * @param {Array} rows - data rows
 * @param {object} opts - { onConflict?: string, batchSize?: number }
 */
export async function batchUpsert(table, rows, opts = {}) {
  if (!rows || rows.length === 0) return { count: 0 };
  const client = getSupabaseAdmin();
  const batchSize = opts.batchSize || 500;
  let total = 0;
  for (let i = 0; i < rows.length; i += batchSize) {
    const batch = rows.slice(i, i + batchSize);
    const query = client.from(table).upsert(batch, {
      onConflict: opts.onConflict,
      ignoreDuplicates: false,
    });
    const { error } = await query;
    if (error) {
      throw new Error(`batchUpsert(${table}) batch ${i / batchSize}: ${error.message}`);
    }
    total += batch.length;
  }
  return { count: total };
}

/**
 * Insert rows in batches (no conflict handling — use for tables with no natural key).
 */
export async function batchInsert(table, rows, opts = {}) {
  if (!rows || rows.length === 0) return { count: 0 };
  const client = getSupabaseAdmin();
  const batchSize = opts.batchSize || 500;
  let total = 0;
  for (let i = 0; i < rows.length; i += batchSize) {
    const batch = rows.slice(i, i + batchSize);
    const { error } = await client.from(table).insert(batch);
    if (error) {
      throw new Error(`batchInsert(${table}) batch ${i / batchSize}: ${error.message}`);
    }
    total += batch.length;
  }
  return { count: total };
}

/**
 * Count rows in a Supabase table.
 * @returns {Promise<number>}
 */
export async function countTable(table) {
  const client = getSupabaseAdmin();
  const { count, error } = await client.from(table).select('*', { count: 'exact', head: true });
  if (error) throw new Error(`countTable(${table}): ${error.message}`);
  return count ?? 0;
}

/**
 * Fetch all rows from a table (all pages).
 * Only use for validation/small tables.
 */
export async function fetchAll(table, columns = '*') {
  const client = getSupabaseAdmin();
  const pageSize = 1000;
  const rows = [];
  let from = 0;
  while (true) {
    const { data, error } = await client.from(table).select(columns).range(from, from + pageSize - 1);
    if (error) throw new Error(`fetchAll(${table}): ${error.message}`);
    if (!data || data.length === 0) break;
    rows.push(...data);
    if (data.length < pageSize) break;
    from += pageSize;
  }
  return rows;
}

/**
 * Create a Supabase Auth user via Admin API.
 * @returns {{ id: string }} auth user record
 */
export async function createAuthUser({ email, password, userMetadata }) {
  const client = getSupabaseAdmin();
  const { data, error } = await client.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: userMetadata,
  });
  if (error) throw new Error(`createAuthUser(${email}): ${error.message}`);
  return data.user;
}

/**
 * Generate a recovery/password-reset link for a user.
 * @returns {string} action link URL
 */
export async function generateRecoveryLink(email) {
  const client = getSupabaseAdmin();
  const { data, error } = await client.auth.admin.generateLink({
    type: 'recovery',
    email,
  });
  if (error) throw new Error(`generateRecoveryLink(${email}): ${error.message}`);
  return data.properties?.action_link ?? '';
}
