# Backlog URLs — AI Systems & Claude Code Enhancement

> Pre-scanned 2026-02-20. Sources: LinkedIn, GitHub, blogs.
> Status: `new` | `reviewed` | `applied` | `skipped`

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
| 16 | [Delegate](https://github.com/nikhilgarg28/delegate) | Multi-Agent Orchestration | Nikhil Garg | Persistent multi-agent orchestration: plan, staff, coordinate, and merge code autonomously on your machine | `ai-agent-systems` | `reviewed` — Extracted 2 patterns: worktree cleanup in /tasks done, actionable nudges in delegation-routing. Persistent agent memory skipped (existing debrief/retrospective sufficient). |
| 19 | [Learn Claude Guide](https://sara-kukovec.github.io/Learn-Claude/) | Claude Learning Resource | Sara Kukovec | Comprehensive guide: Claude, Claude Code, Projects, file handling, structured courses with official Anthropic resources | `claude-code-enhancement` | `new` |
| 22 | [GraphRAG](https://www.linkedin.com/posts/rag-graphrag-genai-share-7429126855745585152-XDWA) | Knowledge Graphs for Agents | RAG/GraphRAG community | GraphRAG: structured knowledge graphs reduce hallucinations, enable semantic agent reasoning beyond vector-only retrieval | `knowledge-graphs`, `ai-agent-systems` | `new` |
| 24 | [Engineering Transformation](https://www.linkedin.com/posts/robertrita_this-changes-what-engineering-means-share-7429321401486098432-CBnq) | AI-Driven Development | Robert Rita | Transformational change to engineering practice via AI-driven development and Claude Code adoption | `claude-code-enhancement` | `new` |
| 27 | [Claude Code Productivity](https://www.linkedin.com/posts/robin-lorenz-54055412a_aiengineering-claudecode-developerproductivity-share-7428128377552875520-_7j-) | Developer Productivity | Robin Lorenz | AI engineering practices, Claude Code tooling, and developer productivity improvements | `claude-code-enhancement` | `new` |
| 28 | [AI + PM + Claude Code](https://www.linkedin.com/posts/vstakhovsky_ai-productmanagement-claudecode-share-7429311443616907264-q-Vw) | Product Management + AI | Vstakhovsky | PM perspective on Claude Code integration for product development workflows | `claude-code-enhancement` | `new` |
| 29 | [ClawWork](https://www.linkedin.com/posts/chao-huang-208993177_introducing-clawwork-transform-your-openclaw-share-7429075091826659328-jh_T) | Agent Accountability | Chao Huang | OpenClaw → AI coworker with economic-accountability patterns; $10K earned in 7h across 44+ industries | `ai-agent-systems` | `new` |
| 30 | [Claude Code Dev Tools](https://www.linkedin.com/posts/miguelmirandadias_claudecode-ai-developertools-share-7429445478326554624-mIvS) | Claude Code Tooling | Miguel Miranda | Claude Code as AI developer tool; 79% automation vs 21% augmentation in 500K+ interactions | `claude-code-enhancement` | `new` |
| 34 | [YaVendio/OLIVE Protocol](https://www.linkedin.com/posts/cruz-melo_github-yavendioolive-transform-python-share-7430082392440287233-P__5) | MCP Alternative Protocol | Cruz Melo (YaVendio CTO) | OLIVE: HTTP-based alternative to MCP; transforms Python functions into remote tools for AI agents | `mcp-tooling`, `ai-agent-systems` | `new` |

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

## LOW — Not relevant to Claude Code / AI systems

| # | URL | Topic | Author | Summary | Tags | Status |
|---|-----|-------|--------|---------|------|--------|
| 2 | [Open Source Growth](https://www.linkedin.com/posts/gavrielco_my-open-source-project-is-growing-faster-activity-7427659960504795136-Di1I) | OSS Growth | Gavriel Chesterton | Growing open source projects faster | `not-relevant` | `new` |
| 3 | [RLM Reimplementation](https://www.linkedin.com/posts/andrew-hinh_i-reimplemented-rlm-minimal-httpslnkdin-share-7428003615186874368-qPPt) | RLM Minimal | Andrew Hinh | Reimplementing RLM minimal | `not-relevant` | `new` |
| 11 | [Kafka Tutorial](https://www.linkedin.com/posts/nk-systemdesign-one_give-me-2-mins-and-ill-teach-you-how-kafka-share-7428424730640158720-_gsJ) | System Design | NK SystemDesign | Kafka messaging architecture in 2 minutes | `devops-ci` | `new` |
| 17 | [Neo4j Ontology](https://www.linkedin.com/posts/akash-g-7a5224246_knowledgegraphs-neo4j-ontology-share-7427272928578269185-FOks) | Knowledge Graphs | Akash G. | Knowledge graph architecture with Neo4j — no AI agent focus | `knowledge-graphs` | `new` |

---

## Tag Index

| Tag | Count | HIGH | MED | LOW |
|-----|-------|------|-----|-----|
| `claude-code-enhancement` | 16 | 11 | 5 | 0 |
| `ai-agent-systems` | 15 | 6 | 9 | 0 |
| `mcp-tooling` | 4 | 4 | 0 | 0 |
| `prompt-engineering` | 3 | 0 | 3 | 0 |
| `knowledge-graphs` | 3 | 1 | 2 | 0 |
| `general-ai-learning` | 2 | 0 | 2 | 0 |
| `devops-ci` | 2 | 0 | 1 | 1 |
| `not-relevant` | 2 | 0 | 0 | 2 |

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
