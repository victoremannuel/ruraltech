/**
 * Firebase Admin SDK wrapper for migration export.
 * Reads credentials from environment variables or scripts/migration/.env
 */
import { createRequire } from 'module';
import { readFileSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Load .env from scripts/migration/.env if it exists
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

let _admin;
let _db;
let _auth;
let _rtdb;

function getAdmin() {
  if (!_admin) {
    _admin = require('firebase-admin');
    const serviceAccountPath = process.env.FB_SERVICE_ACCOUNT_PATH;
    if (!serviceAccountPath) {
      throw new Error('FB_SERVICE_ACCOUNT_PATH is required in environment or scripts/migration/.env');
    }
    if (!existsSync(serviceAccountPath)) {
      throw new Error(`Service account file not found: ${serviceAccountPath}`);
    }
    const serviceAccount = JSON.parse(readFileSync(serviceAccountPath, 'utf8'));
    if (!_admin.apps.length) {
      _admin.initializeApp({
        credential: _admin.credential.cert(serviceAccount),
        databaseURL: process.env.FB_RTDB_URL || 'https://ruraltech10-default-rtdb.firebaseio.com',
      });
    }
  }
  return _admin;
}

export function getFirestore() {
  if (!_db) {
    _db = getAdmin().firestore();
  }
  return _db;
}

export function getFirebaseAuth() {
  if (!_auth) {
    _auth = getAdmin().auth();
  }
  return _auth;
}

export function getRTDB() {
  if (!_rtdb) {
    _rtdb = getAdmin().database();
  }
  return _rtdb;
}

/**
 * List all Firebase Auth users with pagination.
 * @returns {Promise<Array>} array of UserRecord objects
 */
export async function listAllAuthUsers() {
  const auth = getFirebaseAuth();
  const users = [];
  let pageToken;
  let pageCount = 0;
  do {
    const result = await auth.listUsers(1000, pageToken);
    users.push(...result.users);
    pageToken = result.pageToken;
    pageCount++;
    if (pageCount % 5 === 0) {
      process.stderr.write(`  Firebase Auth: fetched ${users.length} users so far...\n`);
    }
  } while (pageToken);
  return users;
}

/**
 * Export an entire Firestore collection (all documents, no limit).
 * Returns array of { id, data } objects.
 */
export async function exportCollection(collectionPath) {
  const db = getFirestore();
  const snapshot = await db.collection(collectionPath).get();
  return snapshot.docs.map(doc => ({ id: doc.id, data: doc.data() }));
}

/**
 * Export RTDB subtree. Returns raw JS object or null if missing.
 */
export async function exportRTDBPath(path) {
  const db = getRTDB();
  const snap = await db.ref(path).get();
  return snap.exists() ? snap.val() : null;
}

/**
 * Export RTDB subtree children keys only (for large trees).
 * @returns {Promise<string[]>}
 */
export async function listRTDBChildren(path) {
  const db = getRTDB();
  const snap = await db.ref(path).get();
  if (!snap.exists()) return [];
  const val = snap.val();
  return val && typeof val === 'object' ? Object.keys(val) : [];
}

/**
 * Export one RTDB child by key.
 */
export async function exportRTDBChild(parentPath, childKey) {
  return exportRTDBPath(`${parentPath}/${childKey}`);
}
