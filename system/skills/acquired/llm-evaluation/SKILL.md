---
name: llm-evaluation
description: "LLM evaluation — automated metrics, human feedback, benchmarking. Use when testing performance, measuring AI quality, or establishing evaluation frameworks."
group: brana
keywords: [llm, evaluation, eval, testing, llm-judge, a-b-testing, benchmarking, bleu, rouge, bertscore, langsmith]
allowed-tools: [Read, Glob, Grep, AskUserQuestion]
status: experimental
source: "https://github.com/wshobson/agents @llm-evaluation"
acquired: "2026-04-30"
quarantine: true
---
> **QUARANTINE — Community tier.** Patterns here are unvalidated. Read-only tools only.
> Verify against official docs (Anthropic, LangSmith) before applying to production.

# LLM Evaluation

Master comprehensive evaluation strategies for LLM applications, from automated metrics to human evaluation and A/B testing.

## When to Use This Skill

- Measuring LLM application performance systematically
- Comparing different models or prompts
- Detecting performance regressions before deployment
- Validating improvements from prompt changes
- Building confidence in production systems
- Establishing baselines and tracking progress over time
- Debugging unexpected model behavior

## Core Evaluation Types

### 1. Automated Metrics

**Text Generation:**
- **BLEU**: N-gram overlap (translation)
- **ROUGE**: Recall-oriented (summarization)
- **METEOR**: Semantic similarity
- **BERTScore**: Embedding-based similarity
- **Perplexity**: Language model confidence

**Classification:**
- Accuracy, Precision/Recall/F1, Confusion Matrix, AUC-ROC

**Retrieval (RAG):**
- MRR, NDCG, Precision@K, Recall@K

### 2. LLM-as-Judge

Use stronger LLMs to evaluate weaker model outputs.

**Approaches:**
- **Pointwise**: Score individual responses
- **Pairwise**: Compare two responses (A/B)
- **Reference-based**: Compare to gold standard
- **Reference-free**: Judge without ground truth

```python
from anthropic import Anthropic
from pydantic import BaseModel, Field
import json

class QualityRating(BaseModel):
    accuracy: int = Field(ge=1, le=10)
    helpfulness: int = Field(ge=1, le=10)
    clarity: int = Field(ge=1, le=10)
    reasoning: str

async def llm_judge_quality(response: str, question: str, context: str = None) -> QualityRating:
    client = Anthropic()
    prompt = f"""Rate the following response:
Question: {question}
{f'Context: {context}' if context else ''}
Response: {response}

Provide ratings in JSON: {{"accuracy": <1-10>, "helpfulness": <1-10>, "clarity": <1-10>, "reasoning": "<explanation>"}}"""
    message = client.messages.create(
        model="claude-sonnet-4-6", max_tokens=500,
        system="You are an expert evaluator of AI responses.",
        messages=[{"role": "user", "content": prompt}]
    )
    return QualityRating(**json.loads(message.content[0].text))
```

### 3. A/B Testing with Statistical Significance

```python
from scipy import stats
import numpy as np

class ABTest:
    def __init__(self):
        self.variant_a_scores = []
        self.variant_b_scores = []

    def analyze(self, alpha: float = 0.05) -> dict:
        a, b = np.array(self.variant_a_scores), np.array(self.variant_b_scores)
        _, p_value = stats.ttest_ind(a, b)
        pooled_std = np.sqrt((np.std(a)**2 + np.std(b)**2) / 2)
        cohens_d = (np.mean(b) - np.mean(a)) / pooled_std
        return {
            "p_value": p_value,
            "statistically_significant": p_value < alpha,
            "cohens_d": cohens_d,
            "winner": "B" if np.mean(b) > np.mean(a) else "A"
        }
```

### 4. Regression Detection

```python
class RegressionDetector:
    def __init__(self, baseline_results: dict, threshold: float = 0.05):
        self.baseline = baseline_results
        self.threshold = threshold

    def check(self, new_results: dict) -> dict:
        regressions = []
        for metric, baseline_score in self.baseline.items():
            new_score = new_results.get(metric)
            if new_score and (new_score - baseline_score) / baseline_score < -self.threshold:
                regressions.append({"metric": metric, "baseline": baseline_score, "current": new_score})
        return {"has_regression": bool(regressions), "regressions": regressions}
```

## LangSmith Integration

```python
from langsmith import Client
from langsmith.evaluation import evaluate, LangChainStringEvaluator

client = Client()
dataset = client.create_dataset("qa_test_cases")
evaluators = [LangChainStringEvaluator("qa"), LangChainStringEvaluator("cot_qa")]

experiment_results = await evaluate(
    target_function,
    data=dataset.name,
    evaluators=evaluators,
    experiment_prefix="v1.0.0",
)
```

## Project-specific notes (proyecto_anita)

- Agent v4 eval strategy: replay-based shadow mode — captured real conversations from Kapso, not synthetic
- Eval set lives in `services/kapso-functions/eval/` and `config/kapso/platform/agents/*/eval-set.json`
- See `docs/agent-v4/plan.md` Phase 4b for eval integration tasks
- LLM-judge approach validated for Agent v4 output quality (t-447 CI wiring task)
