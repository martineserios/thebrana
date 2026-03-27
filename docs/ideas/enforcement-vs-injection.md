# Enforcement vs Injection — The Harness Architecture Fork

> Brainstormed 2026-03-26. Status: draft. Source: t-651 (SuperClaude investigation).

## Hook

"Your AI coding assistant has 30 commands and 20 agents. It also consumes 32% of your context window before you type a single character."

## Core Thesis

The Claude Code harness ecosystem has forked into two architectural philosophies:

1. **Prompt injection** — load behavioral instructions into context as markdown. The model "should" follow them.
2. **Enforcement-first** — use hooks to gate actions. The model "cannot" violate them.

SuperClaude (22K stars, v4.3) represents the injection approach. Brana represents enforcement-first. The difference isn't cosmetic — it creates fundamentally different failure modes.

## The Three Contrasts

### 1. Context Budget: Front-loaded vs Lazy

**Injection:** All commands, agents, modes, and rules loaded at session start. SuperClaude's Issue #299 documents 32% context consumed before the user types anything. Their own architecture docs acknowledge ~60K tokens of overhead.

**Enforcement:** Skills loaded on invocation. Rules are 1-2 line files. Hooks are shell scripts that fire on events, not context entries. Base footprint: ~2-3% of context.

**Why it matters:** Context is the scarcest resource in agentic coding. A harness that consumes a third of it is solving one problem (structure) while creating another (capacity).

### 2. Compliance: "Should" vs "Must"

**Injection:** Advisory prompts ("follow these rules", "use this format"). The model can and does ignore them under pressure — especially as context fills and instructions get compacted away.

**Enforcement:** PreToolUse deny hooks that block execution. The model literally cannot write to an implementation file before a test exists. No prompt can override a hook gate.

**Why it matters:** The value of structure is proportional to its reliability. Advisory structure works most of the time. Enforced structure works all of the time. In production agent workflows, "most of the time" isn't good enough.

### 3. Memory: Keyword Matching vs Semantic Search

**Injection:** Per-project JSONL files with 50% keyword overlap threshold. No cross-project memory. No embeddings.

**Enforcement:** Semantic embeddings indexed from 33 knowledge documents (315+ sections). Cross-client pattern transfer with confidence tiers. Patterns that resolve real issues get promoted; misleading patterns get demoted.

**Why it matters:** An agent that can't learn across projects repeats the same mistakes in every repo. Memory architecture determines whether your harness gets smarter over time or stays static.

## Five More Contrasts (Feature-Level)

### 4. Quality Gates: Self-Assessment vs External Review

**Injection:** "Four Questions" self-check protocol. The agent fills in a dict: `tests_passed: True`, `requirements_met: [...]`. Nobody verifies. The agent grades its own homework.

**Enforcement:** Challenger agent (separate context, calibrated rubric with few-shot examples) provides external adversarial review. PreToolUse hooks block implementation without specs. The agent cannot self-certify.

**One-liner:** *"A self-check that depends on the agent honestly reporting its own results is a self-review, not validation."*

### 5. Confidence Scoring: Keywords vs Reasoning

**Injection:** Confidence score via Python keyword matching. `"fix" in task.lower()` → +0.2 score. `"investigate" in task.lower()` → -0.15. Starting score: 0.5. This is regex pretending to be reasoning.

**Enforcement:** Challenger agent stress-tests plans with adversarial scenarios. Confidence comes from surviving the challenge, not from counting keywords.

**One-liner:** *"Confidence scoring that counts keywords is theater. Real confidence comes from adversarial review — can your plan survive a challenger trying to break it?"*

### 6. Token Efficiency: Emoji Abbreviations vs Transport-Layer Filtering

**Injection:** Symbol systems (arrows, abbreviations), "targeting 30-50% reduction." Token budget manager with 3 hardcoded tiers (200/1000/2500 tokens) that doesn't actually measure tokens.

**Enforcement:** RTK (Rust Token Killer) — CLI proxy that rewrites tool output at the transport layer. 34 TOML filters, 60-90% measured savings. The context window never sees the noise.

**One-liner:** *"A token budget that doesn't measure tokens is a spreadsheet, not a system."*

### 7. Error Learning: Word Overlap vs Semantic Embeddings

**Injection:** ReflexionMemory stores errors in JSONL. Retrieval: split words, compare overlap, 70% threshold. "authentication module import failure" won't match "auth module crash" — zero word overlap despite identical meaning.

**Enforcement:** 384-dim ONNX embeddings (all-MiniLM-L6-v2) in ruflo. Semantic similarity catches meaning, not just words. Cross-client: a mistake in one project teaches every project.

**One-liner:** *"Error learning through word overlap is 2015-era information retrieval."*

### 8. Research: Flat Files vs Indexed Knowledge

**Injection:** Research output saved to `claudedocs/research_*.md`. Flat markdown files. No semantic search, no cross-session retrieval. Each session starts from zero.

**Enforcement:** Findings indexed into ruflo with semantic embeddings. Cross-session, cross-client. Intermediate findings get 30-day TTL; promoted findings persist. Each research round makes the next one smarter.

**One-liner:** *"Research that produces a markdown file is a dead end. Research that indexes into a semantic knowledge base compounds across sessions."*

## The Master Thesis

*"The difference between a framework that asks Claude to be better and a system that makes it impossible to be worse."*

## The Positioning Angle

SuperClaude validates the market — 22K stars in 9 months proves people want structured Claude Code. But their architectural weaknesses (context bloat, no enforcement, primitive memory) are exactly the problems that enforcement-first harnesses solve.

The question for practitioners isn't "do I need a harness?" — it's "do I want one that suggests good behavior or one that enforces it?"

## Content Formats

- **LinkedIn post (short):** Hook + 3 contrasts as bullet points + master thesis as closer
- **LinkedIn article (long):** All 8 contrasts with Issue #299 evidence, code examples from SuperClaude's actual Python (keyword matching exposed)
- **Thread/carousel:** One contrast per slide, visual comparison tables. 8 slides + hook + closer = 10 slides
- **Hot take post:** Just the master thesis + 1-2 contrasts. Controversial enough to drive engagement.
- **Educational post:** "5 questions to evaluate any AI coding harness" — derived from the contrasts as evaluation criteria

## Tags

#harness-engineering #claude-code #context-engineering #enforcement
