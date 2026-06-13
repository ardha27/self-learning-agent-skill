# Self-Learning Agent

A skill that teaches an LLM agent to improve from its own results — no fine-tuning, and without letting the model write its own memory.

It started as the learning layer of a production autonomous trading agent. I pulled it out into a pattern that doesn't care about the domain. The same structure works for deploy bots, content pickers, lead scorers, moderation queues — anything that makes the same kind of decision over and over and can measure how it turned out.

## The idea in one line

The LLM reads what was learned; it never writes it. Plain deterministic code turns past outcomes into lessons and filters. The model only consumes them — as text in its prompt, or as filters that remove bad options before it ever sees them.

That split matters. If all the learning is text the model "knows about," it will still ignore it under pressure. If all of it is hard filters, the model can't reason about the edge cases. You need both tracks.

## What's inside

| File | What it is |
|---|---|
| [`SKILL.md`](SKILL.md) | The architecture: core principle, the two tracks, the five components, how to map it to your domain, the prompt-budget rules, and the mistakes that sink most attempts. |
| [`reference.md`](reference.md) | The implementation: data shapes, lesson templates, signal weighting, threshold evolution, cooldowns and blocklists, optional cross-instance sync, and tuning defaults. |
| [`AGENTS.md`](AGENTS.md) | The cross-agent entry point. |
| [`install.sh`](install.sh) | Drops the files where your agent looks for them. |

The numbers in the reference come from one domain (LP trading). Recalibrate them for yours — both files say where and how.

## Install

Clone it, then run the installer for your agent:

```bash
git clone https://github.com/ardha27/self-learning-agent-skill.git
cd self-learning-agent-skill
```

**Claude Code** (and Claude apps):

```bash
./install.sh claude        # -> ~/.claude/skills/self-learning-agent/
```

**GitHub Copilot CLI:**

```bash
./install.sh copilot       # -> ~/.copilot/skills/self-learning-agent/
```

**Codex, Cursor, Zed, Aider, Gemini CLI, or any agent that reads `AGENTS.md`:**

```bash
./install.sh project ./your-project   # copies the skill + AGENTS.md into the project
```

Then point your agent's root context file (`AGENTS.md`, `GEMINI.md`, `CLAUDE.md`) at `self-learning-agent/AGENTS.md`, or paste its "When this applies" line in.

No installer? Just copy `SKILL.md` and `reference.md` into wherever your agent reads skills, or drop `AGENTS.md` at the root of your repo. The content is plain markdown with no tool-specific calls, so it ports as-is.

## Why it works across agents

The skill is architecture guidance, not tool-calling code. There's nothing to translate between platforms. `SKILL.md` carries the Anthropic Agent Skills frontmatter (`name`, `description`) for agents that use it; anything that doesn't parse frontmatter can read the body directly.

## License

MIT — see [LICENSE](LICENSE).
