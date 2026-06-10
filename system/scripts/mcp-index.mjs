#!/usr/bin/env node
// MCP-first knowledge indexer — uses ruflo MCP stdio protocol for memory_store.
// Auto-embeddings, HNSW maintenance, and schema management handled by ruflo server.
//
// Prefer this over bulk-index.mjs (SQLite direct). Fall back to bulk-index.mjs when:
//   - ruflo is not installed/reachable
//   - USE_SQLITE=1 is set
//
// Usage:
//   node mcp-index.mjs                              # reads /tmp/knowledge-sections.jsonl
//   node mcp-index.mjs /path/to/sections.jsonl      # reads specified JSONL
//   node mcp-index.mjs --cleanup /path/to.jsonl     # also removes orphan entries
//   node mcp-index.mjs --dry-run /path/to.jsonl     # parse + report only, no MCP calls
//
// JSONL format (one per line):
//   {"key":"knowledge:dimension:doc:section","value":"...","tags":["source:brana-knowledge","type:dimension"]}
//   {"key":"pattern:feedback:slug","value":"...","namespace":"pattern","tags":["type:feedback"]}
// If namespace is omitted, defaults to "knowledge".

import { spawn, execSync } from 'node:child_process';
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';

// ── Arg parsing ────────────────────────────────────────────────
let jsonlPath = '/tmp/knowledge-sections.jsonl';
let orphanCleanup = false;
let dryRun = false;
const CONCURRENCY = 5;

for (const arg of process.argv.slice(2)) {
  if (arg === '--cleanup') {
    orphanCleanup = true;
  } else if (arg === '--dry-run') {
    dryRun = true;
  } else if (!arg.startsWith('-')) {
    jsonlPath = arg;
  }
}

// ── Resolve ruflo binary (mirrors bulk-index.mjs resolution logic) ─
function resolveRuflo() {
  // Try 1: npm global root
  try {
    const globalRoot = execSync('npm root -g', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim();
    const candidate = join(dirname(globalRoot), '.bin', 'ruflo');
    if (existsSync(candidate)) return candidate;
  } catch {}
  // Try 2: node prefix (works with nvm, volta, fnm)
  try {
    const nodeDir = dirname(dirname(process.execPath));
    const candidate = join(nodeDir, 'bin', 'ruflo');
    if (existsSync(candidate)) return candidate;
  } catch {}
  // Try 3: PATH
  try {
    const found = execSync('which ruflo', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim();
    if (found) return found;
  } catch {}
  return null;
}

const RUFLO = process.env.RUFLO_BIN || resolveRuflo();
if (!RUFLO) {
  console.error('ERROR: ruflo not found. Install with: npm install -g ruflo');
  process.exit(1);
}

// ruflo npm tarballs (≤3.10.40) ship bin/ruflo.js with a CRLF shebang and the
// installed file can lose its exec bit — executing the bin directly fails with
// EACCES or `env: 'node\r': No such file or directory`. Resolve to the
// underlying .js and run it with the node interpreter instead.
function rufloCommand(args) {
  let target = RUFLO;
  try { target = realpathSync(RUFLO); } catch {}
  if (/\.(js|mjs|cjs)$/.test(target)) {
    return [process.execPath, [target, ...args]];
  }
  return [RUFLO, args];
}

// ── MCP JSON-RPC stdio client ───────────────────────────────────
class McpClient {
  constructor(proc) {
    this.proc = proc;
    this.id = 1;
    this.pending = new Map();
    this.buffer = '';

    this.proc.stdout.on('data', (data) => {
      this.buffer += data.toString();
      let newlineIdx;
      while ((newlineIdx = this.buffer.indexOf('\n')) !== -1) {
        const line = this.buffer.slice(0, newlineIdx).trim();
        this.buffer = this.buffer.slice(newlineIdx + 1);
        if (!line) continue;
        try {
          const msg = JSON.parse(line);
          if (msg.id !== undefined && this.pending.has(msg.id)) {
            const { resolve } = this.pending.get(msg.id);
            this.pending.delete(msg.id);
            resolve(msg);
          }
        } catch { /* skip non-JSON lines */ }
      }
    });

    this.proc.stderr.on('data', (data) => {
      const line = data.toString().trim();
      // Suppress noisy INFO lines, surface real errors
      if (line && !line.includes('[INFO]') && !line.includes('info:')) {
        process.stderr.write(`[ruflo] ${line}\n`);
      }
    });
  }

  send(method, params) {
    return new Promise((resolve, reject) => {
      const id = this.id++;
      this.pending.set(id, { resolve, reject });
      const msg = JSON.stringify({ jsonrpc: '2.0', id, method, params });
      this.proc.stdin.write(msg + '\n');

      // 15s timeout per call (embeddings can be slow on first run)
      const timer = setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`Timeout on request id=${id} method=${method}`));
        }
      }, 15000);
      // Allow process to exit even if timer is pending
      timer.unref();
    });
  }

  async initialize() {
    const resp = await this.send('initialize', {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: { name: 'mcp-index', version: '1.0.0' }
    });
    this.proc.stdin.write(
      JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n'
    );
    return resp;
  }

  async callTool(name, args) {
    return this.send('tools/call', { name, arguments: args });
  }

  close() {
    this.proc.stdin.end();
    // Give the server a moment to flush before killing
    setTimeout(() => this.proc.kill(), 500);
  }
}

// ── Helpers ─────────────────────────────────────────────────────

// Run up to CONCURRENCY tasks at a time
async function pool(tasks, concurrency, fn) {
  const results = [];
  let idx = 0;
  async function worker() {
    while (idx < tasks.length) {
      const i = idx++;
      results[i] = await fn(tasks[i], i);
    }
  }
  const workers = Array.from({ length: Math.min(concurrency, tasks.length) }, worker);
  await Promise.all(workers);
  return results;
}

// ── Main ────────────────────────────────────────────────────────
async function main() {
  if (!existsSync(jsonlPath)) {
    console.error(`ERROR: JSONL file not found: ${jsonlPath}`);
    process.exit(1);
  }

  // Read + parse JSONL
  const lines = readFileSync(jsonlPath, 'utf8').trim().split('\n').filter(Boolean);
  const sections = lines.map((l, i) => {
    try {
      return JSON.parse(l);
    } catch (e) {
      console.error(`WARN: Skipping line ${i + 1} (JSON parse error): ${e.message}`);
      return null;
    }
  }).filter(Boolean);

  console.log(`=== MCP Index ===`);
  console.log(`JSONL:     ${jsonlPath}`);
  console.log(`Sections:  ${sections.length}`);
  console.log(`Mode:      ${dryRun ? 'dry-run' : 'live'}`);
  console.log(`Cleanup:   ${orphanCleanup && !dryRun ? 'yes' : 'no'}`);
  console.log(`Ruflo:     ${RUFLO}`);
  console.log('');

  if (sections.length === 0) {
    console.log('No sections to index.');
    process.exit(0);
  }

  // Dry-run: report namespaces + sample keys, then exit
  if (dryRun) {
    const namespaces = {};
    for (const s of sections) {
      const ns = s.namespace || 'knowledge';
      namespaces[ns] = (namespaces[ns] || 0) + 1;
    }
    console.log('Would index:');
    for (const [ns, count] of Object.entries(namespaces)) {
      console.log(`  ${ns}: ${count} entries`);
    }
    console.log('\nSample keys (first 5):');
    for (const s of sections.slice(0, 5)) {
      console.log(`  ${s.key}  [ns: ${s.namespace || 'knowledge'}]`);
    }
    if (sections.length > 5) {
      console.log(`  ... and ${sections.length - 5} more`);
    }
    console.log('\nDry-run complete. No changes made.');
    process.exit(0);
  }

  // Spawn ruflo MCP server (via node interpreter — see rufloCommand)
  const [rufloCmd, rufloArgs] = rufloCommand(['mcp', 'start']);
  const proc = spawn(rufloCmd, rufloArgs, {
    stdio: ['pipe', 'pipe', 'pipe'],
    cwd: homedir(),
    env: { ...process.env }
  });

  proc.on('error', (err) => {
    console.error(`ERROR: Failed to spawn ruflo: ${err.message}`);
    process.exit(1);
  });

  const client = new McpClient(proc);

  let stored = 0;
  let errors = 0;
  const startTime = Date.now();
  const storedKeys = new Set();

  try {
    // Wait for MCP server startup before handshake
    await new Promise(resolve => setTimeout(resolve, 2000));
    await client.initialize();

    // Warm up: probe DB init (idempotent — delete the sentinel right after)
    try {
      await client.callTool('memory_store', {
        key: '__mcp_index_init__', value: '__init__', namespace: 'default', upsert: true
      });
      await client.callTool('memory_delete', { key: '__mcp_index_init__', namespace: 'default' });
    } catch (e) {
      // Schema may already exist; non-fatal
      process.stderr.write(`[mcp-index] DB init probe: ${e.message}\n`);
    }

    // Index with 5-way concurrency
    await pool(sections, CONCURRENCY, async (s, i) => {
      try {
        const args = {
          key: s.key,
          value: s.value || s.content,
          namespace: s.namespace || 'knowledge',
          upsert: true
        };
        if (s.tags) {
          // memory_store accepts tags as comma-separated string or array; use array
          args.tags = Array.isArray(s.tags) ? s.tags : [s.tags];
        }

        const resp = await client.callTool('memory_store', args);
        const result = resp?.result;

        // Determine success: some ruflo versions return {success:true}, others just text
        let success = true;
        if (result?.content?.[0]?.text) {
          try {
            const parsed = JSON.parse(result.content[0].text);
            if (parsed.success === false) {
              success = false;
              process.stderr.write(`  WARN: ${s.key}: ${parsed.error || 'store returned success:false'}\n`);
            }
          } catch {
            // Non-JSON text response — treat as success
          }
        } else if (resp?.error) {
          success = false;
          process.stderr.write(`  WARN: ${s.key}: ${resp.error.message || JSON.stringify(resp.error)}\n`);
        }

        if (success) {
          stored++;
          storedKeys.add(s.key);
        } else {
          errors++;
        }
      } catch (e) {
        errors++;
        process.stderr.write(`  ERROR: ${s.key}: ${e.message}\n`);
      }

      // Progress line (overwrite in place)
      const pct = (((stored + errors) / sections.length) * 100).toFixed(0);
      const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
      const rate = (stored / Math.max(0.1, elapsed)).toFixed(0);
      process.stdout.write(`\r  ${pct}% (${stored + errors}/${sections.length}) — ${rate}/s — ${elapsed}s elapsed  `);
    });

    process.stdout.write('\n\n');

    // Orphan cleanup — list existing entries per namespace, delete any not in this run
    let orphansRemoved = 0;
    if (orphanCleanup && storedKeys.size > 0) {
      const indexedNamespaces = new Set(sections.map(s => s.namespace || 'knowledge'));
      console.log(`Checking orphans in: ${[...indexedNamespaces].join(', ')}...`);

      for (const ns of indexedNamespaces) {
        let cursor = null;
        const existingKeys = new Set();

        // Paginate through all entries in namespace
        do {
          try {
            const resp = await client.callTool('memory_list', {
              namespace: ns,
              limit: 200,
              ...(cursor ? { cursor } : {})
            });
            const result = resp?.result?.content?.[0]?.text;
            if (!result) break;
            const parsed = JSON.parse(result);
            const entries = parsed.entries || parsed.results || parsed || [];
            if (!Array.isArray(entries) || entries.length === 0) break;
            for (const e of entries) {
              if (e.key) existingKeys.add(e.key);
            }
            cursor = parsed.cursor || parsed.next_cursor || null;
          } catch (e) {
            process.stderr.write(`  WARN: memory_list for namespace '${ns}' failed: ${e.message}\n`);
            break;
          }
        } while (cursor);

        // Delete orphans
        const orphans = [...existingKeys].filter(k => !storedKeys.has(k));
        console.log(`  ${ns}: ${existingKeys.size} existing, ${storedKeys.size} indexed, ${orphans.length} orphans`);

        for (const key of orphans) {
          try {
            await client.callTool('memory_delete', { key, namespace: ns });
            orphansRemoved++;
          } catch (e) {
            process.stderr.write(`  WARN: Failed to delete orphan ${key}: ${e.message}\n`);
          }
        }
      }
      console.log(`Orphans removed: ${orphansRemoved}`);
    }

    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
    const rate = (stored / Math.max(0.1, elapsed)).toFixed(0);

    console.log(`=== MCP Index Complete ===`);
    console.log(`Stored:   ${stored}`);
    console.log(`Errors:   ${errors}`);
    console.log(`Orphans:  ${orphansRemoved}`);
    console.log(`Time:     ${elapsed}s`);
    console.log(`Rate:     ${rate} entries/sec`);

    // Exit non-zero if error rate exceeds 5%
    if (sections.length > 0) {
      const errorPct = (errors * 100) / sections.length;
      if (errorPct >= 5) {
        console.error(`Error rate ${errorPct.toFixed(0)}% exceeds 5% threshold`);
        client.close();
        process.exit(1);
      }
    }
  } catch (e) {
    console.error(`FATAL: ${e.message}`);
    client.close();
    process.exit(1);
  }

  client.close();

  // Signal the session's ruflo MCP to reload DB (SIGHUP → wrapper restarts with fresh data).
  // mcp-index.mjs spawns its own ruflo process which writes to disk, but the session MCP
  // still has a stale in-memory copy (t-988).
  const pidFile = join(homedir(), '.swarm/ruflo-mcp.pid');
  if (existsSync(pidFile)) {
    const pid = parseInt(readFileSync(pidFile, 'utf8').trim(), 10);
    if (pid > 0) {
      try {
        process.kill(pid, 'SIGHUP');
        console.log(`Sent SIGHUP to session ruflo MCP (pid ${pid}) — DB will reload.`);
      } catch (e) {
        console.log(`Could not signal session ruflo MCP (pid ${pid}): ${e.message}`);
      }
    }
  }
}

main();
