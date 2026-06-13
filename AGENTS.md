# AGENTS.md — Self-Learning Agent

This repository packages a reusable **agent architecture skill**, not an application. It is written to be consumed by any coding/agentic assistant that reads an `AGENTS.md`, `SKILL.md`, `GEMINI.md`, or `CLAUDE.md` context file (Claude Code, OpenAI Codex, Cursor, Zed, Aider, Gemini CLI, GitHub Copilot CLI, and similar).

## When this applies

Load and follow this skill whenever you are helping build or improve an **LLM agent that makes repeated decisions with measurable outcomes** (trading, deploys, content selection, lead scoring, moderation, routing) and that should improve from its own results — especially when the agent repeats past mistakes, ignores what worked before, or its prompt grows without bound as history accumulates.

## What to read

1. **[`SKILL.md`](SKILL.md)** — the architecture: the core principle, the two learning tracks, the five components, domain mapping, the prompt-injection budget, safeguards, and common mistakes.
2. **[`reference.md`](reference.md)** — implementation recipes: data shapes, lesson derivation, signal weighting, threshold evolution, cooldowns/blocklists, collective sync, and tuning defaults.

Read both before writing any code for a self-learning agent. The numbers in the reference come from one production domain (LP trading); recalibrate them for the target domain as the files instruct.

## Core principle (so you have it even without opening the files)

**The LLM is the reader, never the author, of what was learned.** All learning is computed by plain deterministic code from outcome data. The LLM only consumes the result — either as text injected into its prompt (the *soft* track) or as filters that prune its options before it ever sees them (the *hard* track). Use both tracks; soft-only "knows but misbehaves," hard-only "can't reason about edge cases."

The five components are: (1) template-derived episodic lessons, (2) deterministic signal weighting, (3) threshold evolution, (4) cooldowns & blocklists, (5) optional collective sync across instances. Caps on prompt injection keep cost flat as history grows. Sanitize any text that originates outside the agent before it reaches the prompt.

## Tool mapping for non–Claude-Code agents

This skill contains no tool-specific calls — it is plain architecture guidance, so it ports as-is. The `SKILL.md` frontmatter (`name`, `description`) is the Anthropic Agent Skills convention; agents that do not parse frontmatter can ignore it and read the body directly.
