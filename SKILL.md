---
name: self-learning-agent
description: Use when building an LLM agent that makes repeated decisions with measurable outcomes (trading, deploys, content picks, lead scoring, moderation) and should improve from its own results — especially when the agent repeats past mistakes, ignores what worked before, or its prompt grows unbounded with history.
---

# Self-Learning Agent Architecture

Battle-tested pattern extracted from a production autonomous trading agent (on-chain LP market-making). The agent gets smarter over time **without fine-tuning and without the LLM writing its own memory**.

## Core Principle

**The LLM is the reader, never the author, of what was learned.** All learning is computed by plain deterministic code from outcome data. The LLM only consumes the results — either as text in its prompt (soft) or as filters that prune its options before it ever sees them (hard).

Two tracks, always both:

| Track | Mechanism | Binding | Examples |
|---|---|---|---|
| **Soft** | inject learned text into system prompt | LLM may weigh it | episodic lessons, signal weights, shared lessons, recent-decision log |
| **Hard** | code mutates filters/blocklists directly | LLM never sees pruned options | threshold evolution, cooldowns, blacklists, deterministic exit rules |

If everything is soft, the agent "knows" but still misbehaves. If everything is hard, it can't reason about edge cases. Use both.

## The Five Components

1. **Episodic lessons** — after each outcome, a *template* (not the LLM) classifies it (good/neutral/poor/bad) and renders a rule string: `PREFER: <conditions> — <evidence>` / `AVOID: ...` / `WORKED:` / `FAILED:`. Neutral outcomes are discarded — nothing to learn. Each lesson gets tags, a role, and a confidence score from evidence strength.
2. **Signal weighting ("Darwin")** — snapshot all decision signals *at decision time*; on close, compute each signal's predictive lift (winners vs losers), boost the top quartile ×1.05, decay the bottom ×0.95, clamp to [0.3, 2.5]. (Weight steps are ±5% — distinct from the threshold-evolution step below.) Render as a table in the prompt: "prioritize candidates whose strongest attributes align with high-weight signals."
3. **Threshold evolution** — every N outcomes, recompute hard filter values (e.g. minimum quality score) from percentiles of winning vs losing entries, nudge config toward the target by at most ~10% per step (its own knob, larger than the weight step because thresholds chase a computed target rather than compounding), write an `[AUTO-EVOLVED]` lesson as the audit trail.
4. **Cooldowns & blocklists** — mechanical avoidance with expiry: one bad-yield close → 4h cooldown on that entity; 3 consecutive same-failure closes → 12h cooldown on entity *and* its parent. Permanent blocklists for known-bad actors. Checked in code before candidates reach the LLM.
5. **Collective sync (optional)** — push lessons + outcome events to a shared server fire-and-forget; pull score-curated lessons from other agents into a local cache, inject top-K under a separate prompt section. **Only worth it when ≥2 independent instances run the same decision domain** (or a community server exists); a solo agent gains nothing and adds an attack surface. **Sanitize every inbound string** (length cap, strip newlines and `<>` backticks) — shared text enters your prompt, so treat it as prompt-injection surface.

## Mapping to Your Domain

The pattern is domain-agnostic; rename the fields. Anchor examples:

| Concept | LP/Trading (reference) | Content publishing | Lead scoring |
|---|---|---|---|
| entity / parent | pool / base token | video / topic cluster | lead / company |
| outcome_value | PnL USD | views vs baseline | conversion |
| secondary_yield | fees earned | engagement rate | reply rate |
| efficiency | % time in range | watch-time % | funnel progress |
| close_reason | stop_loss, OOR, low_yield | 48h window, removed | won, lost, ghosted |
| excluded from win-rate | "pumped out of range" | platform-removed videos | lead went out of business |

**Calibrate outcome cutoffs per domain** — the reference agent's `good ≥ +5%` is a trading number. Derive yours from baseline percentiles (e.g. good = top ~30% vs your historical median, bad = bottom ~30% or any hard failure) and revisit after ~30 samples.

**Roles** = one per distinct decision type the LLM makes (enter vs exit; select vs schedule). Keep it to 2–3; more roles than decision types just fragments the lesson pool.

## Prompt Injection Budget (critical)

Never dump all memory into the prompt. Three capped tiers per cycle:
**PINNED** (always, ~5) → **ROLE-MATCHED** (tag-filtered per agent role, ~6) → **RECENT** (fill, ~10), plus **SHARED** (~4). Sort bad outcomes first — avoiding repeat mistakes beats repeating wins.

## Safeguards That Make It Work

- **Cold start**: below `minSamples`, weights stay at 1.0 and thresholds stay at conservative hand-set values — only the lesson log accumulates (it's useful from outcome #1). Learning systems activate themselves once data exists; don't special-case.
- Require **both wins and losses** (and a minimum sample count in a rolling window) before recomputing weights/thresholds — otherwise skip.
- Evolve **slowly** (±5% per step, hard floor/ceiling) so one lucky streak can't flip the strategy.
- Snapshot signals **at entry**, not at close — else you learn from exit conditions.
- Exclude outcome categories that don't reflect signal quality from win-rate stats (e.g. "price pumped out of range" is not a bad entry).
- Every store that echoes into the prompt gets sanitized on write.
- All learning state in plain JSON files — inspectable, diffable, deletable.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Letting the LLM write its own lessons | Template-derive from outcome data; LLM-authored memory drifts and self-reinforces |
| Unbounded lesson injection | 3-tier caps; prompt cost stays flat as history grows |
| Recalc on every outcome | Batch every N closes with min-sample gate; reduces noise |
| Only soft learning | Add hard gates; "the model knows" ≠ "the model complies" |
| Trusting shared/external lessons | Sanitize + cap + separate prompt section |

Detailed data shapes, algorithms, and pseudocode: see [reference.md](reference.md).
