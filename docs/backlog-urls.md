# Backlog URLs — AI Systems & Claude Code Enhancement

> **Superseded.** All 69 items migrated to `.claude/tasks.json` (stream: `research`, IDs t-091 through t-159). Use `/brana:tasks next --stream research` or `/brana:tasks status` to browse. This file is kept for reference only.
>
> Pre-scanned 2026-02-20 (batch 1), 2026-03-02 (batch 2). Sources: LinkedIn, GitHub, blogs, X.
> Status: `new` | `reviewed` | `applied` | `skipped`
> Cross-ref: [doc 30](30-backlog.md) Links section (#473–#506 = batch 2)

---

## HIGH — Directly actionable for thebrana / Claude Code

| # | URL | Topic | Author | Summary | Tags | Status |
|---|-----|-------|--------|---------|------|--------|
| 5 | [Claude Code Docs: Plugins](https://code.claude.com/docs/en/discover-plugins#code-intelligence) | Code Intelligence & Plugin Discovery | Anthropic | Official docs on LSP integration, plugin discovery, code intelligence features in Claude Code | `claude-code-enhancement` | `reviewed` — Install pyright-lsp for palco. Skip marketplace conversion (deploy.sh sufficient for single user). |
| 7 | [PAIML MCP Agent Toolkit](https://github.com/paiml/paiml-mcp-agent-toolkit) | MCP Server Infrastructure | Pragmatic AI Labs | Production MCP server: deterministic agent infra, code quality analysis, 17+ languages, explicit Claude Code integration | `mcp-tooling`, `ai-agent-systems` | `reviewed` — Use CLI on-demand, not as MCP server (22 tools = 11-44K token tax). Run dead code detection on palco V3. |
| 9 | [The LLM Harness Problem](https://mkweb.dev/blog/llm-harness-problem) | Edit Format Performance | mkweb.dev | str_replace vs diff format swings LLM coding performance 20-40%; infrastructure wrapper matters as much as model weights | `claude-code-enhancement`, `ai-agent-systems` | `reviewed` — Applied: wide Edit context + Write<50LOC in context-budget.md, test assertion discipline in universal-quality.md. |
| 12 | [GitHub Agentic Workflows](https://www.linkedin.com/posts/eddie-aftandilian-772b267_we-launched-github-agentic-workflows-today-share-7428234738760323073-xAzO) | Agentic CI/CD | Eddie Aftandilian (GitHub) | CI/CD evolving into repository-level autonomous agent behaviors; continuous AI instead of continuous integration | `claude-code-enhancement`, `ai-agent-systems` | `new` |
| 13 | [FastMCP 3.0](https://www.linkedin.com/posts/daniel-avila-arias_el-skill-de-fastmcp-30-ya-est%C3%A1-disponible-ugcPost-7428477350339629056-kBp0) | FastMCP 3.0 GA | Daniel Avila Arias | FastMCP 3.0 context applications for rich adaptive agent systems; direct MCP tooling upgrade | `mcp-tooling`, `claude-code-enhancement` | `reviewed` — FastMCP 3.0 is for building MCP servers, not using them. Relevant when a portfolio project needs a custom server. No action now. |
| 14 | [AI Agent Coding Workflow](https://www.linkedin.com/posts/anurag-bhagsain_my-coding-workflow-with-ai-agents-total-share-7428668544512499712-cpLp) | Multi-Agent Workflow | Anurag Bhagsain | $300/mo workflow: Claude Opus for planning/research, Codex for review; agents manage parallel tasks via worktrees | `claude-code-enhancement`, `ai-agent-systems` | `new` |
| 16 | [Delegate](https://github.com/nikhilgarg28/delegate) | Multi-Agent Orchestration | Nikhil Garg | Persistent multi-agent orchestration: plan, staff, coordinate, and merge code autonomously on your machine | `ai-agent-systems` | `reviewed` — Extracted 2 patterns: worktree cleanup in /brana:tasks done, actionable nudges in delegation-routing. Persistent agent memory skipped (existing debrief/retrospective sufficient). |
| 19 | [Learn Claude Guide](https://sara-kukovec.github.io/Learn-Claude/) | Claude Learning Resource | Sara Kukovec | Comprehensive guide: Claude, Claude Code, Projects, file handling, structured courses with official Anthropic resources | `claude-code-enhancement` | `new` |
| 22 | [GraphRAG](https://www.linkedin.com/posts/rag-graphrag-genai-share-7429126855745585152-XDWA) | Knowledge Graphs for Agents | RAG/GraphRAG community | GraphRAG: structured knowledge graphs reduce hallucinations, enable semantic agent reasoning beyond vector-only retrieval | `knowledge-graphs`, `ai-agent-systems` | `new` |
| 24 | [Engineering Transformation](https://www.linkedin.com/posts/robertrita_this-changes-what-engineering-means-share-7429321401486098432-CBnq) | AI-Driven Development | Robert Rita | Transformational change to engineering practice via AI-driven development and Claude Code adoption | `claude-code-enhancement` | `new` |
| 27 | [Claude Code Productivity](https://www.linkedin.com/posts/robin-lorenz-54055412a_aiengineering-claudecode-developerproductivity-share-7428128377552875520-_7j-) | Developer Productivity | Robin Lorenz | AI engineering practices, Claude Code tooling, and developer productivity improvements | `claude-code-enhancement` | `new` |
| 28 | [AI + PM + Claude Code](https://www.linkedin.com/posts/vstakhovsky_ai-productmanagement-claudecode-share-7429311443616907264-q-Vw) | Product Management + AI | Vstakhovsky | PM perspective on Claude Code integration for product development workflows | `claude-code-enhancement` | `new` |
| 29 | [ClawWork](https://www.linkedin.com/posts/chao-huang-208993177_introducing-clawwork-transform-your-openclaw-share-7429075091826659328-jh_T) | Agent Accountability | Chao Huang | OpenClaw → AI coworker with economic-accountability patterns; $10K earned in 7h across 44+ industries | `ai-agent-systems` | `new` |
| 30 | [Claude Code Dev Tools](https://www.linkedin.com/posts/miguelmirandadias_claudecode-ai-developertools-share-7429445478326554624-mIvS) | Claude Code Tooling | Miguel Miranda | Claude Code as AI developer tool; 79% automation vs 21% augmentation in 500K+ interactions | `claude-code-enhancement` | `new` |
| 34 | [YaVendio/OLIVE Protocol](https://www.linkedin.com/posts/cruz-melo_github-yavendioolive-transform-python-share-7430082392440287233-P__5) | MCP Alternative Protocol | Cruz Melo (YaVendio CTO) | OLIVE: HTTP-based alternative to MCP; transforms Python functions into remote tools for AI agents | `mcp-tooling`, `ai-agent-systems` | `new` |
| 36 | [Custom AI Orchestration CLI](https://www.linkedin.com/posts/michael-a-tomcal-2186486a_i-built-a-custom-orchestration-cli-for-ai-share-7432079783460745217-qN7W) | AI Agent Orchestration | Michael Tomcal | Built custom orchestration CLI for AI agents — orchestration patterns, multi-agent coordination | `ai-agent-systems` | `new` |
| 43 | [Open-Source OS for AI](https://www.linkedin.com/posts/osama-jaber-osama2001_we-open-sourced-an-operating-system-for-ai-share-7432586733197856768-6LQ7) | AI Operating System | Osama Jaber | Open-sourced operating system for AI agents — runtime, scheduling, resource management | `ai-agent-systems` | `new` |
| 44 | [CLAUDE.md at 400 Lines](https://www.linkedin.com/posts/alejandro-gomez-cerezo_mi-claude-md-tiene-400-l%C3%ADneas-y-acaba-de-share-7432346651350114305-01aO) | CLAUDE.md Engineering | Alejandro Gomez Cerezo | CLAUDE.md at 400 lines — large-scale prompt engineering, structure at scale | `claude-code-enhancement` | `new` |
| 45 | [Claude Code + Codex Together](https://www.linkedin.com/posts/richard-rizk-a09a70213_we-just-made-claude-code-and-codex-work-together-ugcPost-7432103995143311360-4JeU) | Multi-Agent Collaboration | Richard Rizk | Made Claude Code and Codex work together — dual-agent workflow, complementary strengths | `claude-code-enhancement`, `ai-agent-systems` | `new` |
| 46 | [Theo: Delete Your CLAUDE.md](https://www.linkedin.com/posts/dileep-krishna_theo-says-delete-your-claudemd-half-the-share-7432685118689021952-6qbX) | CLAUDE.md Debate | Dileep Krishna (citing Theo) | Theo argues for deleting CLAUDE.md — contrarian view on prompt file engineering | `claude-code-enhancement` | `new` |
| 48 | [GitHub Spec Kit](https://github.com/github/spec-kit) | Spec-Driven Development | GitHub | Official GitHub spec-kit — spec-driven development toolkit, structured specifications | `claude-code-enhancement`, `ai-agent-systems` | `new` |
| 49 | [Claude Code Tips That Changed How I Work](https://medium.com/@ianodad/some-claude-code-tips-that-actually-changed-how-i-work-b34f35b3dc73) | Claude Code Workflow | Ian Odad | Practical Claude Code tips that materially changed workflow | `claude-code-enhancement` | `new` |
| 50 | [Shared Memory for Claude Code](https://www.linkedin.com/posts/steve-phelps-203270_a-shared-memory-for-claude-code-share-7432414226435956736-HihS) | Persistent Memory | Steve Phelps | Obsidian wiki-links as shared knowledge graph + auditor skill for contradiction detection + shared tag taxonomy | `claude-code-enhancement` | `reviewed` — No action. Brana already solves this differently: semantic embeddings (580+ entries, 384-dim) + doc hierarchy + cross-references + /brana:reconcile. The "auditor traverses graph for contradictions" pattern could enhance /brana:memory review someday but low priority — brana's reflection DAG prevents most contradictions structurally. |
| 59 | [Ruflo v3.50 (formerly claude-flow)](https://www.linkedin.com/posts/reuvencohen_so-long-claude-flow-hello-ruflo-v350-ugcPost-7433292476595003393-bpqi) | claude-flow Rebrand | Reuven Cohen | claude-flow renamed to Ruflo v3.50 — direct upstream impact on brana memory stack | `ai-agent-systems`, `mcp-tooling` | `reviewed` — No immediate action. Legacy `claude-flow` npm alias works (both at 3.5.2 as of 2026-03-02). Brana on v3.5.1. 92 refs across 33 system files need eventual rename. Embedding dimension risk: ruflo defaults 768-dim WASM, our embeddings.json forces 384-dim (safe). Upgrade to ruflo@3.5.2 when next maintenance cycle. **RECHECK: verify `claude-flow` and `ruflo` npm versions still match — if they diverge, alias is being abandoned and migration is urgent.** |
| 62 | [AI Web Agent Backbone](https://www.linkedin.com/posts/digcreator_the-ultimate-backbone-for-ai-web-agents-just-share-7433607645422485505-3LHz) | Web Agent Infrastructure | DigCreator | Ultimate backbone for AI web agents — infrastructure layer for browser-based agents | `ai-agent-systems` | `new` |
| 65 | [Open Source MCP Server](https://www.linkedin.com/posts/krajewski-ptr_an-open-source-mcp-server-just-came-out-that-share-7433883947069218816-rODp) | MCP Server | Krajewski | New open source MCP server — evaluate for brana MCP ecosystem | `mcp-tooling` | `new` |
| 67 | [Agent Orchestrator](https://www.linkedin.com/posts/prateekkarnal_agent-orchestrator-lets-one-person-manage-share-7434120370519015424-dw50) | Agent Orchestration | Prateek Karnal | Agent orchestrator for one-person management of multiple agents | `ai-agent-systems` | `new` |
| 61 | [The Coding Agent Harness](https://x.com/juliandeangeIis/status/2027888587975569534) | Agent Harness / Context Engineering | Julian DeAngelis (MercadoLibre) | Context engineering at scale: 4 levers (custom rules, MCPs, skills, SDD) + feedback loops. Rolling out across 20K devs. Context rot at ~60% window. Modular rules <500 lines, on-demand skill loading, spec-driven development, Stop hook gates. | `claude-code-enhancement`, `ai-agent-systems` | `reviewed` — Applied: trimmed git-discipline 142→51 lines, added 55% context rot yellow zone, few-shot examples in sdd-tdd + task-convention. Deferred: test/lint feedback hook (t-043), PR review agent (t-044), script-bundled skills (t-045). |

## MEDIUM — Relevant context, not immediately actionable

| # | URL | Topic | Author | Summary | Tags | Status |
|---|-----|-------|--------|---------|------|--------|
| 1 | [Claude Code Creator Keynote](https://www.linkedin.com/posts/basiakubicka_the-guy-who-created-claude-code-just-gave-share-7426304877305311232-HNyI) | Claude Code Origins | Basia Kubicka (poster) | Keynote by Claude Code creator — content inaccessible but likely high relevance | `claude-code-enhancement` | `new` |
| 4 | [Self-Taught AI Career](https://www.linkedin.com/posts/shivanivirdi_i-taught-myself-ai-from-scratch-got-promoted-share-7426849470778208257-Wybd) | AI Learning Path | Shivani Virdi | Self-taught AI journey from scratch to career growth | `general-ai-learning` | `new` |
| 6 | [Opus 4.6 Discussion](https://www.linkedin.com/posts/marcosheidemann_while-everyone-was-talking-about-opus-46-share-7428029536497364992-Qsqp) | Model Capabilities | Marcos Heidemann | Discussion of Opus 4.6 features while broader community focused elsewhere | `general-ai-learning` | `new` |
| 8 | [UGC Mega Prompt](https://www.linkedin.com/posts/harshiltomar_steal-this-mega-prompt-to-generate-high-quality-ugcPost-7425131572258947072-EYx4) | Prompt Template | Harshil Tomar | High-quality UGC generation prompt template | `prompt-engineering` | `new` |
| 10 | [AI Automation & Agent Swarms](https://www.linkedin.com/posts/pedro-sequeira-martins_ai-softwareengineering-automation-share-7427682468666859521-1015) | Agent Swarms | Pedro Sequeira Martins | AI automation, RPA, and autonomous agent swarms for business transformation | `ai-agent-systems` | `new` |
| 15 | [Code Review Agents Tested](https://www.linkedin.com/posts/daniel-avila-arias_he-probado-varios-agentes-de-revisi%C3%B3n-de-ugcPost-7428876869841715200-CM6t) | Code Review Agents | Daniel Avila Arias | Comparison of multiple code review agent implementations | `ai-agent-systems` | `new` |
| 18 | [Claude Code Workflows](https://www.linkedin.com/posts/varunzxzx_ai-softwareengineering-claudecode-share-7428343713225146369-M0bk) | Claude Code Workflows | Varun | Claude Code workflows for software engineering | `claude-code-enhancement` | `new` |
| 20 | [OpenClaw Agents](https://www.linkedin.com/posts/vinothgovindarajan_openclaw-agents-ai-share-7429409471778471938-mjqN) | Agent Framework | Vinoth Govindarajan | OpenClaw: open-source autonomous agent system | `ai-agent-systems` | `new` |
| 21 | [BigQuery Semantic Graph](https://www.linkedin.com/posts/axel-thevenot_a-new-bigquerys-native-semantic-layer-using-share-7429576816618713088-uAMs) | Semantic Data Layer | Axel Thevenot | BigQuery native semantic graph layer; graphs as instruction manuals for bounded agent traversal | `knowledge-graphs` | `new` |
| 23 | [Web API for AI Agents](https://www.linkedin.com/posts/zachary-boland_the-web-just-got-an-api-for-ai-agents-and-share-7427842401345654786-D4v3) | Agent Web APIs | Zachary Boland | New web APIs enabling AI agent interaction with the web | `ai-agent-systems` | `new` |
| 25 | [AI Tooling Solution](https://www.linkedin.com/posts/hrishioa_six-months-ago-we-badly-needed-something-share-7429573370880581632-M7L_) | AI Tooling | Hrishioa | Solution built for previously unmet need in AI tooling — topic unclear | `ai-agent-systems` | `new` |
| 26 | [Fine-Tuning Accessible](https://www.linkedin.com/posts/alejandro-ao_you-dont-need-to-be-an-expert-to-fine-tune-share-7429479134050938880-ms1h) | LLM Fine-Tuning | Alejandro AO | Democratizing LLM fine-tuning without deep expertise | `prompt-engineering` | `new` |
| 31 | [GitHub Projects Classic Sunset](https://github.blog/changelog/2024-05-23-sunset-notice-projects-classic/) | GitHub Deprecation | GitHub | Projects Classic sunset (Aug 2024); API sunset Nov 2024. DevOps awareness. | `devops-ci` | `new` |
| 32 | [OpenCode Permission Security](https://www.linkedin.com/posts/iv%C3%A1n-s%C3%A1nchez-b87649396_opencodes-permission-system-is-not-security-share-7428582778096742400-jHEn) | Agent Security | Ivan Sanchez | AI agent permissions: file modification controls, default-allow patterns, Docker/VM isolation | `ai-agent-systems` | `new` |
| 33 | [8 Rules for OpenClaw](https://www.linkedin.com/posts/olga-s-2a7822165_8-rules-without-them-working-with-openclaw-share-7429974204667772928-qz33) | Agent Best Practices | Olga S. | OpenClaw 8 core Layer 1 tools: file access, command execution, web access | `ai-agent-systems` | `new` |
| 35 | [CLAUDE.md Tips](https://www.linkedin.com/posts/yauhen-klishevich_this-one-%F0%9D%97%96%F0%9D%97%9F%F0%9D%97%94%F0%9D%97%A8%F0%9D%97%97%F0%9D%97%98%F0%9D%97%BA%F0%9D%97%B1-file-might-be-share-7430352145373331457-LPLx) | CLAUDE.md Engineering | Yauhen Klishevich | Tips on CLAUDE.md file structure and prompt engineering for Claude Code | `claude-code-enhancement`, `prompt-engineering` | `new` |
| 37 | [SaaS Payment Gateway Bypass](https://www.linkedin.com/posts/askjohngeorge_bypassed-a-saas-payment-gateway-in-under-share-7432147819970330624-qlyv) | Security Testing | John George | Bypassed a SaaS payment gateway — agent security implications | `security` | `new` |
| 38 | [Infrastructure Shift](https://www.linkedin.com/posts/thewinstonbrown_theres-a-real-infrastructure-shift-happening-share-7432525372778291202-XdLz) | Infrastructure Trends | Winston Brown | Real infrastructure shift happening — AI-era infra patterns | `devops-ci` | `new` |
| 39 | [Runway FlightPaths](https://www.runway.team/blog/introducing-flightpaths-by-runway) | CI/CD Planning | Runway | Introducing FlightPaths — release planning and CI/CD orchestration | `devops-ci` | `new` |
| 40 | [MLOps / K8s / Docker](https://www.linkedin.com/posts/roshan-erukulla-79b12a178_mlops-kubernetes-docker-share-7431511968093732864-Qe_b) | MLOps Infrastructure | Roshan Erukulla | MLOps, Kubernetes, Docker patterns and practices | `devops-ci` | `new` |
| 41 | [Self-Hostable Data Warehouse](https://www.artmann.co/articles/build-a-lightweight-self-hostable-data-warehouse) | Data Infrastructure | Artmann | Build a lightweight self-hostable data warehouse — DuckDB/Parquet patterns | `devops-ci` | `new` |
| 47 | [Claude Code AI Engineering](https://www.linkedin.com/posts/innovativemonk_claudecode-aiengineering-devtools-share-7431229766130794496-4gmn) | Claude Code DevTools | InnovativeMonk | Claude Code AI engineering and developer tools patterns | `claude-code-enhancement` | `new` |
| 51 | [OpenClaw Agent Problems](https://www.linkedin.com/posts/julio-andres-olivares_un-gran-problema-con-openclaw-y-agentes-share-7432898145749127168-LLZr) | Agent Challenges | Julio Olivares | Major problem with OpenClaw and agent orchestration | `ai-agent-systems` | `new` |
| 52 | [Agentic AI / OpenClaw](https://www.linkedin.com/posts/imaxxs_agenticai-aiagents-openclaw-ugcPost-7432613287302746112-qVXX) | Agent Ecosystem | Imaxxs | Agentic AI, agents, OpenClaw ecosystem discussion | `ai-agent-systems` | `new` |
| 53 | [Development Flow Needs](https://www.linkedin.com/posts/duncankmckinnon_what-do-development-flows-need-to-be-more-share-7432894534344323072-HuoK) | Dev Workflow | Duncan McKinnon | What development flows need to be more effective — workflow patterns | `ai-agent-systems` | `new` |
| 54 | [Boris Cherny Interview](https://www.linkedin.com/posts/zihong-chen_chatting-with-boris-cherny-the-guy-who-share-7431418512260284416-jlwd) | Creator Interview | Zihong Chen | Interview with Boris Cherny — likely Claude Code or TypeScript related | `claude-code-enhancement` | `new` |
| 55 | [Claude + Codex Self-Improvement](https://www.linkedin.com/posts/suraj-kumar-86217a20a_claude-added-codex-and-codex-made-itself-share-7433492783962918912-n4mv) | AI Evolution | Suraj Kumar | Claude added Codex, Codex made itself — self-improving agent patterns | `claude-code-enhancement`, `ai-agent-systems` | `new` |
| 56 | [Claude Code Dev Tools](https://www.linkedin.com/posts/tamzid-ahmed-fahim_claudecode-ai-developertools-share-7433097099807961089-HcHi) | Developer Tools | Tamzid Ahmed Fahim | Claude Code AI developer tools and productivity | `claude-code-enhancement` | `new` |
| 57 | [Claude Code AI Engineering](https://www.linkedin.com/posts/robinlorenz-ai_claudecode-aiengineering-developertools-share-7433102275214016513-iyrU) | AI Engineering | Robin Lorenz | Claude Code AI engineering and developer tools best practices | `claude-code-enhancement` | `new` |
| 58 | [Claude Code Productivity](https://www.linkedin.com/posts/larryfang_claudecode-aiengineering-developerproductivity-share-7433018516984975361--Cfk) | Developer Productivity | Larry Fang | Claude Code engineering and developer productivity patterns | `claude-code-enhancement` | `new` |
| 63 | [BrainWire](https://www.linkedin.com/posts/hoenig-clemens-09456b98_brainwire-ugcPost-7433661030351708160-EYXj) | Agent Memory System | Clemens Hoenig | BrainWire — agent memory and knowledge wiring system | `ai-agent-systems` | `new` |
| 64 | [BrainWire DeepBrain DeepNote](https://www.linkedin.com/posts/hoenig-clemens-09456b98_brainwiredeepbraindeepnote-activity-7433988368239198208-6fAB) | Agent Cognition | Clemens Hoenig | BrainWire DeepBrain DeepNote — deeper agent cognition patterns | `ai-agent-systems` | `new` |
| 68 | [Cloning Slack with Claude Code](https://www.linkedin.com/posts/nathancavaglione_day-314-cloning-slack-with-claude-code-share-7433958640103026689-hdKo) | Claude Code Project | Nathan Cavaglione | Day 314: Building Slack clone with Claude Code — large project patterns | `claude-code-enhancement` | `new` |
| 69 | [Multi-Agent Systems](https://www.linkedin.com/posts/alan-helouani_aiengineering-agenticai-multiagentsystems-ugcPost-7427344045565210624-yaHC) | Multi-Agent Architecture | Alan Helouani | AI engineering, agentic AI, multi-agent system patterns | `ai-agent-systems` | `new` |

## LOW — Not relevant to Claude Code / AI systems

| # | URL | Topic | Author | Summary | Tags | Status |
|---|-----|-------|--------|---------|------|--------|
| 2 | [Open Source Growth](https://www.linkedin.com/posts/gavrielco_my-open-source-project-is-growing-faster-activity-7427659960504795136-Di1I) | OSS Growth | Gavriel Chesterton | Growing open source projects faster | `not-relevant` | `new` |
| 3 | [RLM Reimplementation](https://www.linkedin.com/posts/andrew-hinh_i-reimplemented-rlm-minimal-httpslnkdin-share-7428003615186874368-qPPt) | RLM Minimal | Andrew Hinh | Reimplementing RLM minimal | `not-relevant` | `new` |
| 11 | [Kafka Tutorial](https://www.linkedin.com/posts/nk-systemdesign-one_give-me-2-mins-and-ill-teach-you-how-kafka-share-7428424730640158720-_gsJ) | System Design | NK SystemDesign | Kafka messaging architecture in 2 minutes | `devops-ci` | `new` |
| 17 | [Neo4j Ontology](https://www.linkedin.com/posts/akash-g-7a5224246_knowledgegraphs-neo4j-ontology-share-7427272928578269185-FOks) | Knowledge Graphs | Akash G. | Knowledge graph architecture with Neo4j — no AI agent focus | `knowledge-graphs` | `new` |
| 42 | [LinkedIn Activity Post](https://www.linkedin.com/posts/activity-7432762547293798400-uNt1) | Unknown | Unknown | LinkedIn activity post — content unclear from URL | `unknown` | `new` |
| 60 | [X Post](https://x.com/i/status/2027123051477815797) | Unknown | Unknown | X/Twitter post — content not accessible from URL slug | `unknown` | `new` |
| 66 | [Gastown Hall AI](https://gastownhall.ai) | AI Platform | Gastown Hall | AI community or product — needs review | `unknown` | `new` |

---

## Tag Index

| Tag | Count | HIGH | MED | LOW |
|-----|-------|------|-----|-----|
| `claude-code-enhancement` | 29 | 17 | 12 | 0 |
| `ai-agent-systems` | 29 | 12 | 17 | 0 |
| `mcp-tooling` | 6 | 6 | 0 | 0 |
| `devops-ci` | 6 | 0 | 5 | 1 |
| `prompt-engineering` | 3 | 0 | 3 | 0 |
| `knowledge-graphs` | 3 | 1 | 1 | 1 |
| `general-ai-learning` | 2 | 0 | 2 | 0 |
| `security` | 1 | 0 | 1 | 0 |
| `unknown` | 4 | 0 | 0 | 4 |
| `not-relevant` | 2 | 0 | 0 | 2 |

## Picked Item Workflow

When a backlog item is picked to work on (beyond review/research), use `/build-feature`:

1. **Orient** — research the item, understand the landscape
2. **Discover** — brainstorm approaches, evaluate trade-offs
3. **Shape** — write an ADR (`/decide`) capturing the decision
4. **Design** — spec-driven development (SDD): write the spec before code
5. **Plan** — break into tasks, write tests first (TDD)
6. **Build** — implement, test, verify
7. **Close** — debrief, back-propagate to specs

This ensures every backlog item gets the same rigor thebrana was built with: ADRs, SDD, TDD, challenger review on significant decisions.

---

## Priority Queue (next actions)

1. ~~**#9** — Study harness problem~~ `reviewed` — 3 lines to 2 rules files
2. ~~**#5** — Read official Claude Code plugin docs~~ `reviewed` — install pyright-lsp
3. ~~**#13** — Review FastMCP 3.0~~ `reviewed` — no action, knowledge only
4. ~~**#7** — Evaluate PAIML MCP toolkit~~ `reviewed` — CLI on-demand, dead code palco
5. ~~**#16** — Study Delegate orchestration~~ `reviewed` — worktree cleanup + actionable nudges
6. **#34** — Assess OLIVE protocol as MCP alternative
7. **#14** — Extract workflow patterns (worktree + multi-agent)
8. **#12** — Study GitHub agentic workflows for CI/CD evolution
9. **#22** — Evaluate GraphRAG for knowledge system enhancement
10. **#29** — Study ClawWork accountability patterns
11. ~~**#59** — Evaluate Ruflo v3.50 rebrand~~ `reviewed` — no immediate action, alias works, 92 refs to rename eventually
12. ~~**#50** — Study shared memory for Claude Code~~ `reviewed` — Obsidian wiki-links + auditor skill. Brana already covers this via semantic search + doc hierarchy
13. **#48** — Evaluate GitHub spec-kit for spec-driven development
14. **#45** — Study Claude Code + Codex dual-agent workflow
15. **#65** — Evaluate new open source MCP server
16. **#36** — Study custom AI orchestration CLI patterns
17. **#67** — Evaluate Agent Orchestrator (Prateek Karnal / Composio)
18. **#49** — Extract Claude Code workflow tips (Ian Odad)
19. **#44** — Compare 400-line CLAUDE.md approach vs brana's split architecture
20. **#46** — Study "delete your CLAUDE.md" contrarian argument
