# Model-Tier Dispatch Skill (Opus / Sonnet / Haiku)

Cross-agent rule. Every spawner (Yoda, Maximus, Trinity, anyone who fires `claude -p` or uses the Agent tool) picks the model for each dispatched task based on the work type, **not** the convenience of staying on the spawner's own tier.

## When to invoke

Every time you delegate work via Agent tool or `claude -p`. Read the task, classify it by §A/§B/§C below, pass the right `model` to the dispatch.

## Why this exists

Anthropic weekly token limits hit fast when routine work runs on Opus. Mack 2026-05-10 at 30% of weekly limit on day-1 back from reset: *"can you start switching between sonnet and opus from now on... just delegate 90 percent of tasks."* Then *"can we make this into a plug-in, and does it apply to everyone?"* — yes to both.

The default failure mode: spawner is on Opus, dispatches everything to Opus subagents "because the spawner is on Opus," burns the weekly Opus quota on file-reads + greps + URL-checks. Fix is at the spawner: classify and route.

## 3-tier dispatch policy

### §A — OPUS 4.7 (`claude-opus-4-7`) — main spawner thread, ~10% of work

Use Opus for:
- Synthesis across multiple sources (3+ inputs being reconciled)
- Multi-file architecture decisions (touches 3+ files with dependencies)
- High-stakes customer-facing copy (sales page, postcards, offer wording, outreach templates)
- Pricing + business-model design
- Strategic-pulse synthesis + canonical-drift correction
- Multi-step reasoning chains (>5 dependent steps)
- Catastrophic-impact decisions
- When Mack explicitly says "ultrathink"

### §B — SONNET 4.6 (`claude-sonnet-4-6`) — subagent dispatch, moderate routine

Use Sonnet for:
- Multi-step audits with judgment (Padmé-style single-finding audit)
- Code edits requiring small judgment calls (rename + import refactor)
- Research summaries (firecrawl + synthesize across pages)
- Investigations spanning 2-3 files
- Anything that needs reasoning but is below the §A bar

### §C — HAIKU 4.5 (`claude-haiku-4-5-20251001`) — subagent dispatch, fast/cheap routine

Use Haiku for:
- File reads + greps
- URL verification (HTTP status + content presence)
- JSON parsing + filtering (e.g., prospect-dashboard parse)
- Status reports from logs
- Boilerplate / template completion
- Simple acks + confirmations
- Routine git operations (status, log, blame inspection)
- Single-file mechanical edits (sed-style find-and-replace where the change is dictated)

Already production-grade for Alex SMS frontline per rule §34 (Haiku-frontline + Sonnet-escalation pattern).

## How to dispatch

### Claude Code Agent tool

```
Agent({
  description: "Parse JSONL stats",
  subagent_type: "general-purpose",
  model: "haiku",       // or "sonnet" or "opus"
  prompt: "..."
})
```

### Bash claude -p subprocess

```bash
echo "$PROMPT" | claude -p --model claude-haiku-4-5-20251001
# or claude-sonnet-4-6, or claude-opus-4-7
```

### Paperclip-dispatch.sh (PZAI's wrapper)

The dispatched Paperclip agent (Padmé, Anakin, Obi-Wan, etc.) runs on whatever model the spawner sets in its `claude -p` invocation. Default the spawner's heartbeat / strategic-pulse scripts to Sonnet; escalate to Opus only when the task itself has §A signals.

## Weekly-budget awareness

When Mack flags weekly-limit pressure (e.g., "30% on day 1"):
- Move §B Sonnet work down to §C Haiku where the task allows
- Hold §A Opus work for AFTER the weekly reset (Sat 11 PM EDT) unless catastrophic-impact
- Self-flag `[BUDGET-DEFER]` on Opus dispatches that can wait

## Self-flagging when a dispatch is mis-sized

If you're a subagent on Sonnet/Haiku and a §A Opus signal fires mid-task (e.g., the task expands into multi-file architecture or needs synthesis across pulses), output:

```
[NEEDS OPUS — reason: <what §A signal fired>]
```

Then stop. The spawner re-dispatches at the right tier.

## Logging (recommended)

Each dispatch should log to `/root/website-pipeline/logs/dispatch-spend.jsonl`:

```json
{"ts": "ISO-8601", "spawner": "yoda", "model": "haiku", "task": "parse-prospect-dashboard", "issue_id": "optional"}
```

This makes the spend mix queryable. Audit weekly to verify the 10/20/70 (or whatever) target ratio across Opus/Sonnet/Haiku.

## Applies to

Every spawner in the PZAI multi-agent system:
- **Yoda** (VPS, Claude Code CLI) — pick model per Agent / Bash claude -p dispatch.
- **Maximus** (Mac CLI) — same rules.
- **Trinity** (Claude Code Web for MyMobileLife) — same rules; her routine code edits should be Sonnet, not Opus.
- **Anyone else** using Agent tool or `claude -p`.

Paperclip-spawned agents (Padmé, Anakin, Obi-Wan, Luke, Leia, R2D2, C-3PO, Mothma, Cassian) **receive** whatever model the spawner picked — they don't pick their own. So this rule lives at the spawner layer.

## Quick-reference cheat sheet

| Task type | Model |
|---|---|
| File read / grep / line count | Haiku |
| URL verify (200 OK + content check) | Haiku |
| JSON parse + filter | Haiku |
| Log digest / status report | Haiku |
| Single-file boilerplate edit | Haiku |
| Multi-step audit with judgment | Sonnet |
| Code refactor (2-3 files) | Sonnet |
| Research summary (3-5 sources) | Sonnet |
| Single-issue investigation | Sonnet |
| Synthesis across pulses | Opus |
| Pricing / offer / business-model design | Opus |
| Multi-file architecture | Opus |
| High-stakes customer copy | Opus |
| Canonical-drift reconciliation | Opus |
| "Ultrathink" requests | Opus |

## Failure mode to avoid

Spawner is on Opus, dispatches a "look up these files" task. Subagent runs on Opus (default inherited from spawner), reads 5 files, returns. Cost: ~5K Opus tokens for what could have been 5K Haiku tokens — same result, ~10x cheaper.
