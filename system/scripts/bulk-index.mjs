#!/usr/bin/env node
// Bulk knowledge indexer — uses ruflo's own deps (better-sqlite3 + @xenova/transformers)
// to write directly to memory_entries with proper embeddings.

import { createRequire } from 'module';
import { readFileSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

// Use ruflo's installed modules
const rufloBase = join(homedir(), '.nvm/versions/node/v20.19.0/lib/node_modules/ruflo/node_modules');
const require = createRequire(rufloBase + '/');

const Database = require('better-sqlite3');
const { pipeline, env } = await import(join(rufloBase, '@xenova/transformers/src/transformers.js'));

// Use cached models, don't download
env.cacheDir = join(rufloBase, '@xenova/transformers/.cache');
env.allowRemoteModels = false;

const DB_PATH = join(homedir(), '.swarm/memory.db');
const JSONL_PATH = '/tmp/knowledge-sections.jsonl';

// Load embedding model (same as ruflo uses)
console.log('Loading embedding model...');
const embedder = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
console.log('Model loaded.');

// Open DB
const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');
db.pragma('synchronous = NORMAL');

// Read sections
const lines = readFileSync(JSONL_PATH, 'utf8').trim().split('\n');
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
        // Extract embedding array from tensor
        const dims = results[j].dims || [384];
        const embeddingArray = Array.from(results[j].data).slice(0, 384);

        insert.run({
          id: genId(),
          key: s.key,
          namespace: 'knowledge',
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
console.log(`=== Bulk Index Complete ===`);
console.log(`Stored:  ${stored}`);
console.log(`Errors:  ${errors}`);
console.log(`Time:    ${((Date.now() - startTime) / 1000).toFixed(1)}s`);

db.close();
