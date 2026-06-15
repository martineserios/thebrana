---
name: jobs-to-be-done
description: "Map what job the user/customer is actually hiring the product to do — functional, emotional, and social dimensions. Clayton Christensen + Tony Ulwick. Use when reframing product decisions around motivations rather than features, or when 'what should we build?' is unclear."
group: thinking
keywords: [jtbd, jobs-to-be-done, user-motivation, product, christensen, ulwick, customer-job, outcome, feature-framing]
allowed-tools:
  - AskUserQuestion
  - Read
  - Glob
  - Grep
status: acquired
source: "https://github.com/owl-listener/designer-skills"
acquired: "2026-06-15"
---

# Jobs-to-Be-Done (JTBD)

> People don't buy products — they hire them to get a job done. Focus on the job, not the product. — Clayton Christensen

## The Core Idea

A "job" is a goal or objective a person is trying to achieve in a specific circumstance. The same product can be hired for different jobs by different people. Understanding the job — not the demographic or the feature request — is what drives durable product decisions.

## Three Dimensions of Every Job

| Dimension | Question | Example (project management tool) |
|-----------|----------|-----------------------------------|
| **Functional** | What practical task are they trying to do? | "Track who owns what by when" |
| **Emotional** | How do they want to feel? | "Feel in control, not anxious about deadlines" |
| **Social** | How do they want to be perceived? | "Look organized and reliable to their boss" |

Features address functional jobs. Emotional and social jobs are why people actually switch products.

## Job Statement Format

> **When** [situation], **I want to** [motivation], **so I can** [expected outcome].

Example:
- "When my team grows past 5 people, I want to know who's working on what without asking, so I can stop being the bottleneck for status updates."

## Steps

### 1. Identify the core job
What is the person fundamentally trying to accomplish? State it in job-statement format. Avoid feature language — "I want a dashboard" is not a job. "I want to know what's happening without asking" is.

### 2. Map the three dimensions
For this job:
- **Functional:** the specific task or outcome
- **Emotional:** the feeling they seek or want to avoid
- **Social:** how they want to be seen

### 3. Define job stages (full lifecycle)
Map the complete job:

| Stage | What the person does |
|-------|---------------------|
| Define | Realizes they have the job to do |
| Locate | Finds what they need to do the job |
| Prepare | Sets up to execute |
| Confirm | Verifies they're doing the right thing |
| Execute | Does the job |
| Monitor | Checks progress |
| Modify | Adjusts as needed |
| Conclude | Finishes + evaluates |

Where does the current product support this lifecycle? Where are the gaps?

### 4. Map current "hired" solutions
How do people do this job today? What are they *already* hiring?
- Products, tools, workarounds, manual processes
- What triggers the hire? What causes firing (switching)?

### 5. Find underserved outcomes
For each job stage: what does success look like? Where are current solutions falling short?

Ulwick's outcome format: "Minimize the time it takes to [functional outcome] when [context]."

### 6. Design implications
What would a product optimized for this job look like — not this feature set?

## Output Format

```
JTBD Analysis: [Product/Feature/Decision]

Core job: When [situation], I want to [motivation], so I can [outcome].

Job dimensions:
- Functional: [specific task]
- Emotional: [desired feeling / avoided feeling]
- Social: [how they want to be perceived]

Job lifecycle gaps:
- [Stage]: currently [how done] — gap: [what's underserved]

Current solutions hired for this job:
- [Solution]: hired because [why], fired when [trigger to switch]

Underserved outcomes:
- Minimize time to [X] when [context]
- Increase likelihood of [Y] when [context]

Design implication:
- Instead of building [feature], build [job-focused alternative]
- The real competitor is [what they currently hire, not the obvious one]
```
