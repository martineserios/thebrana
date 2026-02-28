/**
 * ControllerRegistry Shim
 *
 * Bridges the gap between memory-bridge.js (expects ControllerRegistry)
 * and AgentDB v3 (provides getController + database + embedder).
 *
 * memory-bridge.js calls:
 *   const { ControllerRegistry } = await import('@claude-flow/memory');
 *   registry.initialize({ dbPath, dimension, controllers })
 *   registry.get('tieredCache')  -> controller or null
 *   registry.getAgentDB()        -> { database: db, embedder }
 *
 * This shim wraps AgentDB v3's native API to satisfy that interface.
 * Deployed by deploy.sh into @claude-flow/memory's dist/.
 */
import { AgentDB } from 'agentdb';

export class ControllerRegistry {
  #agentdb = null;
  #initialized = false;

  async initialize(config = {}) {
    if (this.#initialized) return;

    this.#agentdb = new AgentDB({
      dbPath: config.dbPath || undefined,
      dimension: config.dimension || 384,
      maxElements: 10000,
    });

    await this.#agentdb.initialize();
    this.#initialized = true;
  }

  /**
   * Proxy for controller access.
   * Returns null for controllers that don't exist instead of throwing.
   */
  get(name) {
    if (!this.#agentdb || !this.#initialized) return null;

    // Map bridge names to AgentDB controller names
    const nameMap = {
      'tieredCache': null,           // Not in AgentDB v3
      'mutationGuard': 'mutationGuard',
      'attestationLog': 'attestationLog',
      'reasoningBank': 'reasoningBank',
      'reflexion': 'reflexion',
      'skills': 'skills',
      'causalGraph': 'causalGraph',
      'causalRecall': 'causalRecall',
      'learningSystem': 'learningSystem',
      'explainableRecall': 'explainableRecall',
      'nightlyLearner': 'nightlyLearner',
      'hierarchicalMemory': null,    // Not in AgentDB v3
      'memoryConsolidation': null,   // Not in AgentDB v3
      'batchOperations': null,       // Not in AgentDB v3
      'contextSynthesizer': null,    // Not in AgentDB v3
      'semanticRouter': null,        // Not in AgentDB v3
    };

    const mapped = nameMap[name];
    if (mapped === null || mapped === undefined) return null;

    try {
      return this.#agentdb.getController(mapped);
    } catch {
      return null;
    }
  }

  /**
   * Returns the AgentDB instance in the shape the bridge expects.
   */
  getAgentDB() {
    if (!this.#agentdb) return null;
    return {
      database: this.#agentdb.database,
      embedder: this.#agentdb.embedder,
    };
  }
}
