#!/usr/bin/env node
// Bulk knowledge indexer — uses ruflo's own deps (better-sqlite3 + @xenova/transformers)
// to write directly to memory_entries with proper embeddings.
//
// Usage:
//   node bulk-index.mjs                           # reads /tmp/knowledge-sections.jsonl
//   node bulk-index.mjs /path/to/sections.jsonl   # reads specified JSONL
//   node bulk-index.mjs --cleanup /path/to.jsonl  # also removes orphan entries
//
// JSONL format (one per line):
//   {"key":"knowledge:dimension:doc:section","value":"...","tags":["source:brana-knowledge","type:dimension"]}
//   {"key":"pattern:feedback:slug","value":"...","namespace":"pattern","tags":["type:feedback"]}
// If namespace is omitted, defaults to "knowledge".

import { createRequire } from 'module';
import { existsSync, readFileSync } from 'fs';
import { dirname, join } from 'path';
import { homedir } from 'os';
import { execSync } from 'child_process';

// Parse args
let jsonlPath = '/tmp/knowledge-sections.jsonl';
let orphanCleanup = false;

for (const arg of process.argv.slice(2)) {
  if (arg === '--cleanup') {
    orphanCleanup = true;
  } else if (!arg.startsWith('-')) {
    jsonlPath = arg;
  }
}

// Dynamically resolve ruflo's node_modules (no hardcoded nvm paths)
function resolveRufloBase() {
  // Try 1: npm global root + ruflo
  try {
    const globalRoot = execSync('npm root -g', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim();
    const candidate = join(globalRoot, 'ruflo', 'node_modules');
    if (existsSync(candidate)) return candidate;
  } catch {}
  // Try 2: resolve from node's own prefix (works with nvm, volta, fnm)
  try {
    const nodeDir = dirname(dirname(process.execPath));
    const candidate = join(nodeDir, 'lib', 'node_modules', 'ruflo', 'node_modules');
    if (existsSync(candidate)) return candidate;
  } catch {}
  // Try 3: which ruflo → follow symlink to package dir
  try {
    const rufloPath = execSync('which ruflo', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim();
    const realPath = execSync(`readlink -f "${rufloPath}"`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim();
    const candidate = join(dirname(dirname(realPath)), 'node_modules');
    if (existsSync(candidate)) return candidate;
  } catch {}
  console.error('ERROR: Cannot find ruflo installation. Install with: npm install -g ruflo');
  process.exit(1);
}

const rufloBase = resolveRufloBase();
const require = createRequire(rufloBase + '/');

const Database = require('better-sqlite3');
const { pipeline, env } = await import(join(rufloBase, '@xenova/transformers/src/transformers.js'));

// Use cached models, don't download
env.cacheDir = join(rufloBase, '@xenova/transformers/.cache');
env.allowRemoteModels = false;

const DB_PATH = join(homedir(), '.swarm/memory.db');

// Load embedding model (same as ruflo uses)
console.log('Loading embedding model...');
const embedder = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
console.log('Model loaded.');

// Open DB
const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');
db.pragma('synchronous = NORMAL');

// Read sections
const lines = readFileSync(jsonlPath, 'utf8').trim().split('\n');
const sections = lines.map(l => JSON.parse(l));
console.log(`Sections to index: ${sections.length}`);

// Prepare insert statement
const insert = db.prepare(`
  INSERT OR REPLACE INTO memory_entries
    (id, key, namespace, content, type, embedding, embedding_model, embedding_dimensions, tags, metadata, status)
  VALUES
    (@id, @key, @namespace, @content, @type, @embedding, @embedding_model, @embedding_dimensions, @tags, @metadata, @status)
`);

// Generate unique ID matching ruflo's format
function genId() {
  const ts = Date.now();
  const rand = Math.random().toString(36).substring(2, 8);
  return `entry_${ts}_${rand}`;
}

// Batch insert with embeddings
let stored = 0;
let errors = 0;
const BATCH_SIZE = 20;
const startTime = Date.now();
const storedKeys = new Set();

for (let i = 0; i < sections.length; i += BATCH_SIZE) {
  const batch = sections.slice(i, Math.min(i + BATCH_SIZE, sections.length));

  // Generate embeddings for the batch
  const texts = batch.map(s => s.value);
  const results = await embedder(texts, { pooling: 'mean', normalize: true });

  // Insert batch in a transaction
  const tx = db.transaction(() => {
    for (let j = 0; j < batch.length; j++) {
      const s = batch[j];
      try {
        const embeddingArray = Array.from(results[j].data).slice(0, 384);

        insert.run({
          id: genId(),
          key: s.key,
          namespace: s.namespace || 'knowledge',
          content: s.value,
          type: 'semantic',
          embedding: JSON.stringify(embeddingArray),
          embedding_model: 'local',
          embedding_dimensions: 384,
          tags: JSON.stringify(s.tags),
          metadata: '{}',
          status: 'active'
        });
        stored++;
        storedKeys.add(s.key);
      } catch (e) {
        errors++;
        console.error(`  ERR: ${s.key}: ${e.message}`);
      }
    }
  });
  tx();

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
  const pct = ((i + batch.length) / sections.length * 100).toFixed(0);
  process.stdout.write(`\r  ${pct}% (${stored}/${sections.length}) — ${elapsed}s`);
}

console.log('\n');

// Orphan cleanup — remove entries in indexed namespaces not in this run
let orphansRemoved = 0;
if (orphanCleanup && storedKeys.size > 0) {
  // Determine which namespaces were indexed in this run
  const indexedNamespaces = new Set(sections.map(s => s.namespace || 'knowledge'));
  console.log(`Checking for orphan entries in: ${[...indexedNamespaces].join(', ')}...`);

  for (const ns of indexedNamespaces) {
    const existing = db.prepare(
      `SELECT key FROM memory_entries WHERE namespace = ? AND status = 'active'`
    ).all(ns);

    const deleteStmt = db.prepare(
      `DELETE FROM memory_entries WHERE key = ? AND namespace = ?`
    );
    const cleanupTx = db.transaction(() => {
      for (const row of existing) {
        if (!storedKeys.has(row.key)) {
          deleteStmt.run(row.key, ns);
          orphansRemoved++;
        }
      }
    });
    cleanupTx();
  }
  console.log(`Orphans removed: ${orphansRemoved}`);
}

console.log(`=== Bulk Index Complete ===`);
console.log(`Stored:   ${stored}`);
console.log(`Errors:   ${errors}`);
console.log(`Orphans:  ${orphansRemoved}`);
console.log(`Time:     ${((Date.now() - startTime) / 1000).toFixed(1)}s`);

db.close();
