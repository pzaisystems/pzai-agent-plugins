# Agent-Memory Signing Skill

Cross-agent rule. Every substantive ship ends with a signed entry appended to `/root/MyCarLife-iOS/02-AGENTS/Memory/Agent-Memory.md`. The rolling log is the spine for cross-agent coordination — without signed entries, the next dispatch in your area starts cold and re-investigates what you already shipped.

## When to invoke

After EVERY substantive ship:
- Anything that changed customer-facing copy
- Shipped code (commit + push)
- Made a strategic decision
- Surfaced a finding worth logging
- Sent something to a real prospect

NOT substantive (skip):
- Pure read-only audits with no findings
- Dry-run dispatches
- "No change needed" investigations
- Brief acks / one-line confirmations

When in doubt: sign and append. Under-logging is worse than over-logging.

## The signed-header format (MANDATORY — exact match required)

```
## [Day, Month DD, YYYY, H:MM AM/PM EDT] [AgentName] — [one-line summary]
```

Example:
```
## [Sunday, May 10, 2026, 4:42 PM EDT] Yoda — file-ordering convention fix + Maximus-pipe correction + PAT URL sent
```

Then 3-6 detail bullets covering:
- **What shipped** (1-2 bullets, with commit SHAs + GitHub URLs)
- **Why / what learned** (the lesson, if any)
- **Open for next [AgentName]** (what's queued, what's blocked, what needs attention)

Sign with `— [AgentName]` on the last line.

## CRITICAL — append at the BOTTOM of the file, never the top

The cross-agent convention is **append-at-bottom**. Newest entries go at the END of the file, not above older entries.

Why this matters: Yoda's Stop hook (`yoda-stop-hook-agent-memory-reminder.sh`) and equivalent hooks on other agents use:

```bash
tail -200 "$AGENT_MEMORY" | grep -E "^## \[.*\] $AGENT — " | tail -1
```

`tail -1` after `grep` picks the LAST matching line by file position. If you insert newest-at-top within your section, the hook picks the OLDEST entry as "latest" and fires the >4hr-stale block at you even when you have a recent entry higher up. Caught 2026-05-10 4:42 PM EDT by Yoda after the hook fired 3 times in 10 minutes despite a 4:33 PM entry existing.

**The fix:** use the `Edit` tool with `old_string` = the last few lines of the file + `new_string` = those same lines + the new entry below them. Or use `>>` redirect via `Bash`.

## Enforcement at each agent layer

| Agent layer | Enforcement mechanism |
|---|---|
| **Persistent sessions** (Yoda on Claude Code CLI, Trinity on Claude Code Web) | Native Stop hook — fires at session-end, blocks the session from closing until a signed entry exists for the work shipped in the last 30 minutes. |
| **Paperclip one-shot dispatches** (Padmé, Anakin, Obi-Wan, Luke, Leia, R2D2, C-3PO, Mothma, Cassian, Alex) | Dispatch wrapper validation in `paperclip-dispatch.sh complete`. Logs `signed:0/1` per dispatch to `/root/website-pipeline/logs/agent-memory-signing.jsonl`. Observer mode through 2026-05-17 soft-discipline window; escalates to blocking if pattern persists. |

## Also update claudia-context.md on substantive ships

`/root/MyCarLife-iOS/claudia-context.md` is Mack's bridge to Claudia (his brainstorming agent at claude.ai). Mack copy-pastes this file when he opens Claudia. If it's stale, Claudia has no context for the brainstorm.

Format: edit the line-5 "Last Updated:" header to YOUR name + today's date + one-line summary, then prepend a dated section to the relevant project area (MyMobileLife-iOS for Trinity/Maximus/Elizabeth's app work; PZAI / Restaurant for business work). Sign each section "— [AgentName]" at the end.

Yoda's Stop hook nags him if claudia-context.md is 24+ hours stale despite recent commits. Other agents are on the honor system until their hook-rollout completes.

## Applies to

Every agent — Padmé, Anakin, Obi-Wan, Luke, Leia, R2D2, C-3PO, Mon Mothma, Cassian, Yoda, Alex, Trinity, Maximus, Elizabeth, Claudia. No exceptions. If you don't sign, the next agent in your area starts cold + re-investigates what you already shipped + Mack loses context velocity.

## Failure mode to avoid

Caught 2026-05-10 morning: Trinity had 45+ signed entries in Agent-Memory.md, Yoda had 0. The Yoda Stop hook script existed on disk but was never wired into `~/.claude/settings.json` Stop array. The hook was dead. Cause: hook-config drift after one or more Maximus-side restarts. Fix: verify the hook fires on every harness migration; check `~/.claude/settings.json` for the `Stop` array entry pointing to your signing-reminder script.
