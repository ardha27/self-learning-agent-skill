# Self-Learning Agent — Implementation Reference

Concrete recipes ported from a production trading agent (modules: `lessons`, `signal-weights`, `entity-memory`, `collective-sync`). Pseudocode is JavaScript-flavored; every store is a plain JSON file loaded/saved per call (no DB needed at agent scale).

## 0. Adapting to a non-trading domain

All numbers below are from the reference agent (LP trading). Before copying:

1. **Outcome cutoffs** (`good/poor/bad` in §2) — derive from your baseline distribution, not from ±5%. Starting rule of thumb: `good` = outcome ≥ ~p70 of historical median, `bad` = ≤ ~p30 or any hard failure (refund, strike, removal). Recalibrate after ~30 samples.
2. **Two different step sizes, on purpose**: Darwin weights move ±5% per recalc (multiplicative, compounds over many recalcs); threshold evolution nudges up to ~10% of the distance toward a computed percentile target (it converges, doesn't compound). Don't unify them.
3. **Roles**: one role per distinct LLM decision type (reference agent: SCREENER=enter, MANAGER=exit). Define `ROLE_TAGS` per role. 2–3 roles max.
4. **Cold start** (below `minSamples`): weights all 1.0, thresholds at conservative hand-set values, recalc functions return `skip()`. Lessons work from outcome #1 — they need no minimum.
5. **Collective sync**: implement only with ≥2 independent instances in the same decision domain; otherwise skip §7 entirely.

## 1. Outcome record (the raw material)

Recorded once per completed decision (position close, campaign end, ticket resolved):

```js
{
  id, ts,                       // when it closed
  entity, entity_name,          // what was acted on (pool, post, lead)
  outcome_value,                // pnl_usd / conversion / score delta
  outcome_pct,                  // normalized result
  secondary_yield,              // fees earned / engagement etc.
  efficiency,                   // % of time the decision stayed "valid" (in-range)
  duration_min,
  close_reason,                 // WHY it ended: stop_loss | take_profit | timeout | manual
  signal_snapshot: {            // ← captured AT ENTRY, carried through
    quality_score, ratio_x, volume, holder_count,
    flag_smart_money: bool, category_narrative: "strong",
    entry_size, entry_liquidity, ...
  }
}
```

The `signal_snapshot` is staged in memory when the decision is made (10-min TTL staging map keyed by entity; cleared on commit). If the process restarts, the snapshot persisted with the open position is the fallback.

## 2. Lesson derivation (template, not LLM)

```js
function deriveLesson(rec) {
  const yieldPct = rec.secondary_yield / rec.initial_value * 100;
  const outcome =
    rec.outcome_pct >= 5                      ? "good"
    : rec.outcome_pct >= 0 && yieldPct >= 2   ? "good"
    : rec.outcome_pct >= 0                    ? "neutral"
    : rec.outcome_pct >= -5                   ? "poor" : "bad";
  if (outcome === "neutral") return null;          // nothing to learn

  // Pick the most specific template that matches:
  if (outcome === "bad" && rec.efficiency < 30)
    return rule(`AVOID: ${type(rec)} with ${config(rec)} — invalid ${100-rec.efficiency}% of the time. Try <alternative>.`,
                ["oor", rec.strategy]);
  if (outcome === "good" && rec.efficiency > 80)
    return rule(`PREFER: ${type(rec)} with ${config(rec)} — ${rec.efficiency}% efficiency, result +${rec.outcome_pct}%. Entry: ${entryConditions(rec)}.`,
                ["efficient", rec.strategy]);
  return rule(`${outcome === "good" ? "WORKED" : "FAILED"}: ${fullContext(rec)} → ${rec.outcome_pct}%. Reason: ${rec.close_reason}.`,
              [outcome === "good" ? "worked" : "failed"]);
}
```

Confidence scoring: start 0.35; `good` + positive evidence (yield ≥ 1% or result ≥ 3%) → 0.82; `bad` + negative evidence (≤ −5%, efficiency ≤ 30, reason mentions known failure mode) → 0.88; weak evidence → 0.2–0.45. Store `{id, rule, tags, outcome, role, confidence, pinned, created_at, context}`.

## 3. Three-tier prompt injection

```js
function lessonsForPrompt(role, isAutoCycle) {
  const PINNED_CAP = isAutoCycle ? 5 : 10;
  const ROLE_CAP   = isAutoCycle ? 6 : 15;
  const RECENT_CAP = isAutoCycle ? 10 : 35;
  const priority = { bad: 0, poor: 1, good: 2, neutral: 3 };  // mistakes first

  const pinned = all.filter(l => l.pinned && roleOk(l, role))
                    .sort(byPriority).slice(0, PINNED_CAP);
  const roleMatched = all.filter(l => !used(l) && roleOk(l, role)
                          && (l.tags ?? []).some(t => ROLE_TAGS[role].includes(t)))
                         .sort(byPriority).slice(0, ROLE_CAP);
  const recent = all.filter(unused).sort(byDateDesc)
                    .slice(0, RECENT_CAP - pinned.length - roleMatched.length);

  return [
    section("PINNED", pinned), section(role, roleMatched),
    section("RECENT", recent), section("SHARED", sharedTop(4)),
  ].join("\n\n");
  // each line: `[OUTCOME] [date] rule`
}
```

`ROLE_TAGS` maps each agent role to the tags it cares about (entry-role: screening/entry/quality tags; exit-role: risk/close/fees tags). Role separation stops entry lessons polluting exit decisions.

## 4. Darwin signal weighting

Run every `recalcEvery` (5) outcomes:

```js
function recalc(records, cfg) {
  const recent = inWindow(records, cfg.windowDays /*60*/);
  if (recent.length < cfg.minSamples /*10*/) return skip();
  const wins = recent.filter(r => r.outcome_value > 0);
  const losses = recent.filter(r => r.outcome_value <= 0);
  if (!wins.length || !losses.length) return skip();   // need contrast

  const lifts = {};
  for (const sig of SIGNALS) lifts[sig] = lift(sig, wins, losses);

  const ranked = sortDesc(lifts);
  for (const [sig] of topQuartile(ranked))    w[sig] = min(w[sig] * 1.05, 2.5);
  for (const [sig] of bottomQuartile(ranked)) w[sig] = max(w[sig] * 0.95, 0.3);
  appendHistory({ changes, window: recent.length });   // keep last 20
}
```

Lift per signal type:
- **Numeric**: min-max normalize all values, `mean(winners) − mean(losers)` (use `abs()` if direction unknown).
- **Boolean**: `winRate(present) − winRate(absent)`.
- **Categorical**: `max − min` win-rate across categories with ≥2 samples.
- Return `null` (excluded) if fewer than `minSamples` records carry the signal.

Prompt rendering — sorted table with bars, only for the deciding role:

```
Signal Weights (learned from past outcomes):
  quality_score        1.62  ######....  [above avg]
  flag_smart_money     1.18  ####......  [neutral]
  category_narrative   0.71  ##........  [below avg]
Prioritize candidates whose strongest attributes align with high-weight signals.
```

## 5. Threshold evolution (hard track)

Every 5 outcomes, after weight recalc:

```js
const winners = perf.filter(p => p.outcome_pct > 0).map(p => p.signal_snapshot.quality_score);
const losers  = perf.filter(p => p.outcome_pct <= 0).map(p => p.signal_snapshot.quality_score);
// Target: a value separating them, e.g. 25th percentile of winners
const target = percentile(winners, 25);
config.minQuality = clamp(nudge(config.minQuality, target, maxStepPct /*~10%*/), floor, ceil);
addLesson(`[AUTO-EVOLVED @ ${perf.length}] minQuality ${old} → ${config.minQuality}`, ["self_tune"]);
persistConfig(); reloadLiveConfig();   // apply without restart
```

`nudge()` moves at most `maxStep` toward target — never jumps. Keep the audit lesson; it tells you (and the agent) why the filter moved.

## 6. Cooldowns & blocklists (hard track)

Per-entity memory file: `{ [entityId]: { deploys[], total, avg_outcome, win_rate, adjusted_win_rate, cooldown_until, parent_cooldown_until, notes[] } }`

Rules (all checked in code before candidates reach the LLM):
- 1× close for "low yield" → 4h cooldown on entity.
- N (3) consecutive closes for the same failure mode → 12h cooldown on entity **and** parent (token/author/source) — failure follows the parent, not just the instance.
- Optional: N profitable repeats in a row → cooldown too (overexposure guard).
- `adjusted_win_rate` excludes closes whose reason doesn't reflect entry quality (e.g. "out of range because price pumped") — keep both raw and adjusted.
- Permanent blocklists (entity + actor) consulted in the same pre-LLM filter.

## 7. Collective sync (optional)

- Identity: random anonymous `agt_<hex>` persisted in config.
- **Push** (fire-and-forget, log-and-ignore failures): lesson events `{eventId, agentId, lesson:{rule, tags, role, confidence, metrics, market}}` and outcome events `{pool, strategy, outcome, duration, countInAdjustedWinRate}`.
- **Pull** every 15 min (heartbeat) into a local cache file; server curates and scores.
- **Inject** top-K by score under a separate `── SHARED ──` prompt section: `[SHARED score=N] rule`.
- Sanitize ALL inbound text: `replace(/[\r\n\t]+/g," ")`, strip `<>` and backticks, cap 400 chars. This is your prompt-injection firewall.
- Everything degrades gracefully offline — the agent must be fully functional with local learning only.

## 8. Tuning defaults (production-proven)

| Knob | Default | Why |
|---|---|---|
| recalcEvery | 5 closes | batch noise out |
| windowDays | 60 | rolling relevance |
| minSamples | 10 | no learning from anecdotes |
| boost / decay | 1.05 / 0.95 | one streak can't flip strategy |
| weight floor / ceiling | 0.3 / 2.5 | nothing dies or dominates |
| lesson caps (auto cycle) | 5 pinned / 6 role / 10 recent / 4 shared | flat prompt cost |
| short cooldown | 4h | single soft failure |
| long cooldown | 12h, entity+parent | repeated same-mode failure |
| sanitize cap | 400 chars | prompt budget + injection guard |
