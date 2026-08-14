# Multi-Agent LLM Judge Panels: Research Findings 2024-2026

## Executive Summary

Diverse LLM judge panels outperform single judges and show 43-118% improvement gains (F1 +43.67%, recall +118.83%), but diminishing returns plateau at n=5-10 runs; the critical factors are model diversity (not ensemble size), blind ranking to prevent bias propagation, and recognizing that disagreement—not unanimous agreement—is the most diagnostic signal. Correlated errors remain the primary failure mode when models share training or architectural bias, and best-practice panels combine vendor diversity with structured consensus rules (3-of-5) and specialized agent briefs (one job per agent).

---

## Key Findings

### Panel Diversity & Effectiveness
- **[Nine Judges, Two Effective Votes](https://arxiv.org/pdf/2605.29800)** — Correlated errors severely undermine LLM evaluation panels; unanimous agreement is far less diagnostic than it appears; marginal value of additional judges approaches zero when models share common biases.
- **[Replacing Judges with Juries (2404.18796)](https://arxiv.org/abs/2404.18796)** — Panel diversity strategy beats single strong judges; credible applications use vendor-diverse panels (not identical-replica ensembles) with 3-of-5 consensus rule and Fleiss' κ reliability statistics + bootstrap CI.
- **[SE-Jury: LLM-as-Ensemble-Judge for Software Engineering (ASE 2025)](https://conf.researchr.org/details/ase-2025/ase-2025-papers/222/SE-Jury-An-LLM-as-Ensemble-Judge-Metric-for-Narrowing-the-Gap-with-Human-Evaluation-)** — First ensemble-judge metric for code correctness; five distinct evaluation strategies with dynamic team selection identifies most appropriate subset of judges; outperforms single-judge approaches.

### Practical Multi-Agent Code Review
- **[Multi-Model AI Code Review (Zylos Research, 2026-03-01)](https://zylos.ai/research/2026-03-01-multi-model-ai-code-review-convergence/)** — Multiple independent LLM review passes aggregated via synthesis LLM; using Gemini-2.5-Flash at n=10 runs achieved F1 of 21.91% (43.67% improvement over single-pass), recall +118.83%; plateau observed at n=5-10 runs, genuine diminishing returns beyond.
- **[Multi-Agent LLM Code Review Pipeline (HackenProof)](https://hackenproof.com/blog/build-a-multi-agent-ai-code-review-pipeline)** — AI Code Reviewer orchestrates multiple LLMs with specialized agents (security, performance, code quality); disagreement between agents is often the most valuable signal.
- **[Cubic.dev Micro-Agent Architecture](https://github.com/calimero-network/ai-code-reviewer)** — One job per agent (Planner, Security, Duplication, Editorial); narrower briefs produce sharper reads and less room to argue out of findings.

### Bias and Error Propagation
- **[Contagion Networks (2606.20493)](https://arxiv.org/html/2606.20493)** — Evaluator biases consistently propagate between agents, even within same model family; formal framework for measuring bias contagion in multi-agent systems.
- **[PARIKSHA: Human-LLM Evaluator Agreement (2406.15053)](https://arxiv.org/pdf/2406.15053)** — Position bias favors earlier responses; length bias prefers longer outputs regardless of quality; agreeableness bias over-accepts without critical evaluation; error rates exceed 50%.
- **[Multi-Agent LLM Bias Mitigation (MindStudio)](https://www.mindstudio.ai/blog/how-to-build-llm-council-ensemble-agents)** — Blind ranking prevents models from deferring to prestige models or anchoring to first answer; scores reflect actual quality rather than position or model reputation.

### Cost-Accuracy Tradeoffs & Optimal Panel Size
- **[On Cost-Effective LLM-as-a-Judge (2604.13717)](https://arxiv.org/html/2604.13717)** — Criteria injection and ensembling dominate cost-accuracy tradeoff; heterogeneous panels (specialized judges for different criteria) reach 85.8% accuracy (+13.5 pp over baseline) at 1.3× cost; outperform monolithic judges.
- **[Tuning Judge Design for 1/1000 Cost (2501.17178)](https://arxiv.org/pdf/2501.17178)** — Vendor-diverse panel + specialized judge design dramatically reduces cost while preserving accuracy; intra-model bias arises when judges favor outputs from own architecture.
- **[Robust Adaptive Routing (2605.10805)](https://arxiv.org/pdf/2605.10805)** — Cost-efficient routing for LLM-as-judge; tradeoff depends on criticality of accuracy for application; expert annotation panels of 3 senior reviewers sufficient for rigorous specialized-domain evaluation.

---

## Failure Modes

1. **Correlated Errors** — When all panel members share training data, architecture, or alignment approach, ensemble aggregation provides no benefit; diversity across multiple dimensions critical.
2. **Position Bias** — Earlier-presented responses favored; models anchor to first answer and defer to "prestige" models; cascades across ensemble.
3. **Length Bias** — Longer outputs scored higher regardless of quality.
4. **Agreeableness Bias** — Over-acceptance without critical evaluation; models reluctant to be negative.
5. **Intra-Model Bias** — Judges favor outputs from similar architecture or training.
6. **Self-Preference Bias** — Models prefer outputs from same model family.
7. **Unanimous Agreement False Confidence** — Unanimous votes no more diagnostic than split votes when all judges share common bias.
8. **Diminishing Returns Beyond n=5-10** — Additional judges add noise and cost without signal gain; plateau observed empirically.
9. **Bias Propagation/Contagion** — Evaluator biases leak between agents, even within same model family; creates false consensus.
10. **Majority-Vote Weakness** — Simple majority vote can hide distributed disagreement signals; consensus threshold rules (3-of-5) more robust.

---

## Best-Practice Recommendations

### Panel Composition
- **Use vendor diversity, not ensemble size.** Different training, architecture, alignment — not more of the same. Small diverse panel (3-5) beats large homogeneous panel (9+).
- **Implement blind ranking.** Remove model labels, position order, and metadata that create anchoring. Score actual response quality in isolation.
- **Specialize agent briefs.** One job per agent (security, performance, style, logic); narrow briefs produce sharper reads and defensible finds.

### Consensus & Aggregation
- **Use 3-of-5 consensus rule, not majority vote.** More robust to distributed errors than simple quorum.
- **Include reliability statistics.** Report Fleiss' κ with non-parametric bootstrap confidence intervals; quantify actual agreement beyond binary "pass/fail."
- **Harvest disagreement.** Flag cases where judges split; disagreement is often the most actionable signal. Synthesize divergent finds, don't suppress them.

### Cost & Operations
- **Optimal panel size: n=5-10 runs.** F1 and recall plateau there; beyond that is waste. For multi-agent code review, 5 independent passes + aggregation achieves 43% improvement at sustainable cost.
- **Use heterogeneous judges for different criteria.** Security specialist, performance specialist, style specialist; combine scores; outperforms single monolithic judge.
- **Run independent passes and aggregate.** Don't use cascading judges (A→B→C); use parallel runs (A, B, C all see same input); prevents bias contagion.

### Validation
- **Pilot with 3 senior domain experts as ground truth.** Establish what high-quality judgment looks like for your domain before trusting ensemble.
- **Compare single-judge vs. panel on same cases.** Measure signal gain (recall, precision) not just agreement; some disagreement is healthy and diagnostic.
- **Monitor for correlated failures.** Track cases where entire panel misses a finding; signals shared blind spot in model diversity.

---

## Sources
- [Nine Judges, Two Effective Votes (2605.29800)](https://arxiv.org/pdf/2605.29800)
- [SE-Jury: LLM-as-Ensemble-Judge for Software Engineering (ASE 2025)](https://conf.researchr.org/details/ase-2025/ase-2025-papers/222/SE-Jury-An-LLM-as-Ensemble-Judge-Metric-for-Narrowing-the-Gap-with-Human-Evaluation-)
- [Replacing Judges with Juries (2404.18796)](https://arxiv.org/abs/2404.18796)
- [Multi-Model AI Code Review: Convergence Loops (Zylos Research)](https://zylos.ai/research/2026-03-01-multi-model-ai-code-review-convergence/)
- [Multi-Agent LLM Code Review Pipeline (HackenProof)](https://hackenproof.com/blog/build-a-multi-agent-ai-code-review-pipeline)
- [Contagion Networks: Evaluator Bias Propagation (2606.20493)](https://arxiv.org/html/2606.20493)
- [PARIKSHA: Human-LLM Evaluator Agreement (2406.15053)](https://arxiv.org/pdf/2406.15053)
- [On Cost-Effective LLM-as-a-Judge (2604.13717)](https://arxiv.org/html/2604.13717)
- [Tuning LLM Judge Design for 1/1000 Cost (2501.17178)](https://arxiv.org/pdf/2501.17178)
- [Reasoning Is Not Free: Robust Adaptive Routing (2605.10805)](https://arxiv.org/pdf/2605.10805)
- [AI Code Reviewer Multi-Agent System (GitHub)](https://github.com/calimero-network/ai-code-reviewer)
- [Exploring LLM-as-a-Judge (Weights & Biases)](https://wandb.ai/site/articles/exploring-llm-as-a-judge/)
