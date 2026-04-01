#!/usr/bin/env node
/**
 * ruflo-batch-store.mjs — Fast batch memory_store via MCP stdio protocol.
 *
 * Reads JSON entries from stdin, stores each via a single ruflo MCP process.
 * ~30ms per entry vs ~15s per CLI call.
 *
 * Input format (JSON array on stdin):
 *   [{"key":"k","value":"v","namespace":"ns","tags":["t1"],"upsert":true}, ...]
 *
 * Usage:
 *   cat entries.json | node ruflo-batch-store.mjs
 *   generate-entries.sh | node ruflo-batch-store.mjs
 */
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';

const RUFLO = process.env.RUFLO_BIN || 'ruflo';

// Read all stdin into a string
async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf-8');
}

// MCP JSON-RPC stdio client
class McpClient {
  constructor(proc) {
    this.proc = proc;
    this.id = 1;
    this.pending = new Map();
    this.ready = false;
    this.buffer = '';

    // Parse newline-delimited JSON responses
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
  }

  send(method, params) {
    return new Promise((resolve, reject) => {
      const id = this.id++;
      this.pending.set(id, { resolve, reject });
      const msg = JSON.stringify({ jsonrpc: '2.0', id, method, params });
      this.proc.stdin.write(msg + '\n');

      // Timeout after 10s
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`Timeout on request ${id}`));
        }
      }, 10000);
    });
  }

  async initialize() {
    const resp = await this.send('initialize', {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: { name: 'ruflo-batch-store', version: '1.0.0' }
    });
    // Send initialized notification
    this.proc.stdin.write(JSON.stringify({
      jsonrpc: '2.0',
      method: 'notifications/initialized'
    }) + '\n');
    return resp;
  }

  async callTool(name, args) {
    return this.send('tools/call', { name, arguments: args });
  }

  close() {
    this.proc.stdin.end();
    this.proc.kill();
  }
}

async function main() {
  // Read entries from stdin
  const input = await readStdin();
  let entries;
  try {
    entries = JSON.parse(input);
  } catch (e) {
    console.error(`Error parsing stdin JSON: ${e.message}`);
    process.exit(1);
  }

  if (!Array.isArray(entries) || entries.length === 0) {
    console.error('No entries to store (expected JSON array on stdin)');
    process.exit(0);
  }

  console.error(`[batch-store] ${entries.length} entries to store`);

  // Spawn ruflo MCP server
  const proc = spawn(RUFLO, ['mcp', 'start'], {
    stdio: ['pipe', 'pipe', 'pipe'],
    cwd: process.env.HOME,
    env: { ...process.env }
  });

  // Log stderr for debugging
  proc.stderr.on('data', (data) => {
    const line = data.toString().trim();
    if (line && !line.includes('[INFO]')) {
      console.error(`[ruflo] ${line}`);
    }
  });

  const client = new McpClient(proc);

  try {
    // Wait for server to start, then initialize MCP protocol
    await new Promise(resolve => setTimeout(resolve, 2000));
    await client.initialize();
    console.error('[batch-store] MCP protocol initialized');

    // Initialize memory DB schema (equivalent to `ruflo memory init`)
    try {
      const initResp = await client.callTool('memory_store', {
        key: '__init__', value: '__init__', namespace: 'default', upsert: true
      });
      // If init succeeded, delete the temp entry
      await client.callTool('memory_delete', { key: '__init__', namespace: 'default' });
    } catch (e) {
      // Schema might already exist or init might use a different mechanism
      console.error(`[batch-store] DB init probe: ${e.message}`);
    }

    let stored = 0;
    let errors = 0;
    const startTime = Date.now();

    for (const entry of entries) {
      try {
        const args = {
          key: entry.key,
          value: entry.value || entry.content,
          namespace: entry.namespace || 'default',
          upsert: entry.upsert !== false
        };
        if (entry.tags) {
          args.tags = Array.isArray(entry.tags) ? entry.tags : [entry.tags];
        }

        const resp = await client.callTool('memory_store', args);
        const result = resp?.result;

        if (result?.content?.[0]?.text) {
          const parsed = JSON.parse(result.content[0].text);
          if (parsed.success) {
            stored++;
          } else {
            errors++;
            console.error(`  WARN: ${entry.key}: ${parsed.error || 'unknown error'}`);
          }
        } else {
          stored++; // Assume success if no error
        }
      } catch (e) {
        errors++;
        console.error(`  ERROR: ${entry.key}: ${e.message}`);
      }
    }

    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
    const rate = (stored / (elapsed || 1)).toFixed(0);

    console.log(JSON.stringify({
      total: entries.length,
      stored,
      errors,
      elapsed_seconds: parseFloat(elapsed),
      entries_per_second: parseFloat(rate)
    }));

    console.error(`[batch-store] Done: ${stored} stored, ${errors} errors in ${elapsed}s (${rate}/s)`);
  } catch (e) {
    console.error(`[batch-store] Fatal: ${e.message}`);
    process.exit(1);
  } finally {
    client.close();
  }
}

main();
