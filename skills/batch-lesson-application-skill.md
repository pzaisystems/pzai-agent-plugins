# Batch Lesson Application Skill

Cross-agent rule. When your strategic-pulse / heartbeat / audit extracts a durable lesson, **batch-apply it to every matching surface in one Sonnet call**, then emit ONE consolidated digest post. Never trickle per-lesson posts to PreContext.

## When to invoke

Every time `yoda-extract-lesson-candidate.sh` (or equivalent) returns a non-NULL lesson at the end of an audit fire. The mechanism: persona-bake the lesson into your CLAUDE.md (already wired), then sweep all surfaces with the same pair-tag, then queue the digest entry.

## Why this exists

Locked 2026-05-10 by Mack after his agents (mainly Padmé via the heartbeat-pulse cron firing every 30 min) were posting one correction every 30 minutes for 7+ days. *"Stop posting like one correction every 30 minutes. It should be one correction, and just take a break for like seven days if you can."* And: *"Do a lesson, learn something, and then apply it to every single surface. I don't know why we have to wait."*

The default failure mode: heartbeat extracts a lesson, posts "lesson auto-applied to my persona — future audits will follow," and the existing 13 surfaces that already violate the lesson stay broken. Customer-facing copy drift compounds.

## The pattern

1. **Lesson extracted** by `yoda-extract-lesson-candidate.sh` — pair-tagged (e.g., `Outreach / Marketing|Psychology`), durable, one-sentence.
2. **Persona-baked** by `yoda-apply-skill-lessons.sh` — appended to the agent's CLAUDE.md `## Skill Lessons (auto-appended)` section. Every future audit by that agent inherits the lesson.
3. **Cross-surface sweep** (Scaffolding-Roadmap Play E — pending build at time of skill creation): one Sonnet call ingests the lesson + all surfaces tagged with the same pair-key, outputs a JSON `{surface_path: deterministic_edit_or_null}` for each. Deterministic edits applied via find-and-replace (per rule §34 Build C invariant — AI proposes structured JSON, deterministic write applies). One commit, all surfaces touched.
4. **Queue, don't post.** The lesson + per-surface delta queue to `/root/website-pipeline/logs/lesson-digest-queue.jsonl` and `/root/website-pipeline/logs/agent-post-queue.jsonl`. `yoda-lesson-digest.sh` (cron 10 AM + 6 PM + 10 PM EDT) flushes both queues into ONE combined PreContext post — at most 3 lesson-posts/day regardless of how many lessons extract.

## Token economics (Mack's intuition: yes, batching saves real tokens)

13 separate per-surface fires: each loads agent context (~3K tokens) + analyzes one feature (~2K) + outputs one fix (~500) = 13 × 5.5K = ~71K tokens.

One batch fire with shared context: ~3K context + 13 features (~13K) + 13 fixes (~6.5K) = ~22K tokens.

~70% saved, plus 12 fewer agent-spawn overheads and a single prompt-cache hit instead of 13 cold starts.

## Cool-down

Per-lesson PreContext posts are SUPPRESSED at extraction time. They queue. Mack sees the digest 2-3x/day, not every 30 minutes. Even if 5 agents each extract a lesson in the same hour, Mack sees ONE combined digest at the next 10 AM / 6 PM / 10 PM EDT cron.

## How each agent participates

| Layer | What the agent does |
|---|---|
| **Spawner** (Yoda, Maximus, Trinity) | Sets `PRECONTEXT_BATCH_MODE=1` on the `claude -p` invocation. Subagents inherit. |
| **Paperclip agents** (Padmé, Anakin, Obi-Wan, Luke, Leia, R2D2, C-3PO, Mothma, Cassian) | Inherit the env var. Their `bash precontext-reply.sh "..."` calls automatically queue instead of fire. |
| **`precontext-reply.sh`** | Checks `$PRECONTEXT_BATCH_MODE`. If set, appends to `agent-post-queue.jsonl`. Otherwise posts immediately. Mack-direct replies (main thread) skip batch mode. |
| **`yoda-lesson-digest.sh`** | Cron 10 AM / 6 PM / 10 PM EDT. Reads both queues, emits ONE combined post per fire, archives the queue. |

## Required reading mandate (rule §10 SHARED-BASE companion)

Every audit post must include a 🔗 Links block:
- **Live**: customer-facing https URL if the change touched a customer surface (e.g., `https://web.pzai.systems/postcard-restaurant-v7-back.html`)
- **Commit**: full GitHub commit URL `https://github.com/pzaisystems/REPO/commit/SHA`
- **File**: GitHub blob URL with line range `https://github.com/pzaisystems/REPO/blob/main/PATH#LSTART-LEND`

Use `n/a` if a category genuinely doesn't apply (e.g., no customer-facing live URL for an internal config file). Never omit the line. Mack reads on his phone — raw paths and bare commit SHAs aren't tappable.

## Applies to

Every agent that extracts lessons — Padmé, Anakin, Obi-Wan, Luke, Leia, R2D2, C-3PO, Mon Mothma, Cassian, Yoda, Alex. Trinity follows the same pattern when she ships substantive MyMobileLife work.

## Failure mode to avoid

A lesson extracts. Agent posts "🧠 Lesson auto-applied — Padmé (Outreach / Marketing|Psychology) ... ID: LSN-...". 30 minutes later, another lesson extracts, another post. By end of day, Mack has 32 posts. He pings: *"stop trickling, batch."* You re-read this skill and remember: queue, don't post.
