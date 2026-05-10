#!/bin/bash
# yoda-lesson-digest.sh — batched lesson-application digest.
#
# Reads /root/website-pipeline/logs/lesson-digest-queue.jsonl (populated by
# yoda-extract-lesson-candidate.sh each time an agent's pulse extracts a
# lesson), emits ONE combined PreContext post per fire covering all queued
# lessons, then truncates the queue.
#
# Cron: 0 10,18 * * * /root/scripts/yoda-lesson-digest.sh
#
# Mack 2026-05-10 3:05 PM EDT directive: stop the 30-min trickle of per-lesson
# PreContext posts. "One correction, take a break for like seven days if you
# can." So lessons accumulate in the queue and ship as a digest at 10 AM and
# 6 PM EDT — at most 2 posts per day, regardless of how many lessons extract.
#
# Cross-surface sweep (Scaffolding-Roadmap Play E) — when the per-pair
# surface-inventory + Sonnet batch-apply mechanism lands, this script will
# also include "Surfaces edited: N" + per-surface diff bullets. Until then
# the digest signals the sweep is queued.

set -u

QUEUE_FILE="/root/website-pipeline/logs/lesson-digest-queue.jsonl"
AGENT_POST_QUEUE="/root/website-pipeline/logs/agent-post-queue.jsonl"
LOG="/root/website-pipeline/logs/lesson-digest.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

ts_now() { date '+%Y-%m-%d %H:%M:%S %Z'; }

# Mack 2026-05-10 3:20 PM EDT extension: this digest now flushes BOTH the
# lesson queue (from yoda-extract-lesson-candidate.sh) AND the generic
# agent-post queue (from precontext-reply.sh's PRECONTEXT_BATCH_MODE path —
# captures Padmé/Obi-Wan/etc. audit posts that fired every 30 min before).
# Skip if BOTH are empty.
if [ ! -s "$QUEUE_FILE" ] && [ ! -s "$AGENT_POST_QUEUE" ]; then
  echo "[$(ts_now)] both queues empty — no digest emitted" >> "$LOG"
  exit 0
fi

# Build the digest post body from BOTH queues — lessons + agent posts.
# Group by agent. Mack 2026-05-10 3:20 PM EDT: "all your agents have to be
# doing batches." Audit + lesson posts from heartbeat-pulse (every 30 min)
# now flow through this digest.
MSG_FILE=$(mktemp)
QUEUE_FILE="$QUEUE_FILE" AGENT_POST_QUEUE="$AGENT_POST_QUEUE" MSG_FILE="$MSG_FILE" python3 <<'PY' >> "$LOG" 2>&1
import os, json, collections, datetime

lesson_path = os.environ["QUEUE_FILE"]
post_path = os.environ["AGENT_POST_QUEUE"]
out_path = os.environ["MSG_FILE"]

def load_jsonl(p):
    out = []
    if not os.path.exists(p):
        return out
    with open(p) as f:
        for line in f:
            try:
                out.append(json.loads(line))
            except Exception:
                pass
    return out

lessons = load_jsonl(lesson_path)
posts = load_jsonl(post_path)

if not lessons and not posts:
    open(out_path, "w").close()
    print("[digest] no parseable rows in either queue — nothing to emit")
    raise SystemExit(0)

# Group agent posts by author. Lessons stay separate (different shape).
posts_by_author = collections.defaultdict(list)
for r in posts:
    posts_by_author[r.get("author", "unknown")].append(r)

lessons_by_agent = collections.defaultdict(list)
for r in lessons:
    lessons_by_agent[r.get("agent", "unknown")].append(r)

total = len(lessons) + len(posts)
agents_seen = set(posts_by_author.keys()) | set(lessons_by_agent.keys())

lines = []
lines.append(f"🧠 Agent digest — {total} item(s) batched across {len(agents_seen)} agent(s) since last fire")
lines.append("")

# Agent-posts section — first because these are the heartbeat audits Mack
# specifically called out as trickle.
for author, items in sorted(posts_by_author.items()):
    lines.append(f"**{author}** — {len(items)} update{'s' if len(items)>1 else ''}:")
    for r in items:
        content = r.get("content", "").strip()
        # Take the first line as the headline; full body is in the queue
        # archive for debugging. Keep digest tight.
        head = content.split("\n", 1)[0][:200]
        lines.append(f"• {head}")
    lines.append("")

# Lessons section
if lessons_by_agent:
    lines.append(f"🧠 Lessons baked into personas ({len(lessons)} total):")
    for agent, items in sorted(lessons_by_agent.items()):
        for r in items:
            pair = r.get("pair", "?")
            lesson = r.get("lesson", "")
            lid = r.get("id", "?")
            lines.append(f"• {agent} [{pair}] \"{lesson}\" — ID: {lid}")
    lines.append("")
    lines.append("Each lesson is baked into the agent's persona (CLAUDE.md). Cross-surface sweep status: queued as Scaffolding-Roadmap Play E.")

with open(out_path, "w") as f:
    f.write("\n".join(lines))
print(f"[digest] composed {len(posts)} agent-posts + {len(lessons)} lessons across {len(agents_seen)} agents")
PY

if [ ! -s "$MSG_FILE" ]; then
  echo "[$(ts_now)] message body empty — skipping post" >> "$LOG"
  rm -f "$MSG_FILE"
  exit 0
fi

# Post once.
MSG=$(cat "$MSG_FILE")
# Unset PRECONTEXT_BATCH_MODE so the digest post itself doesn't get queued
# back into the same queue (infinite loop). The digest goes out as Yoda
# directly to Mack.
PRECONTEXT_BATCH_MODE=0 YODA_AUTHOR="yoda" bash /root/scripts/precontext-reply.sh "$MSG" >> "$LOG" 2>&1 || {
  echo "[$(ts_now)] precontext-reply failed" >> "$LOG"
  rm -f "$MSG_FILE"
  exit 1
}

# Archive both queues — don't just delete; keep history for debugging the
# digest output if anything looks off.
ARCHIVE_DIR="/root/website-pipeline/logs/lesson-digest-archive"
mkdir -p "$ARCHIVE_DIR" 2>/dev/null || true
TS=$(date +%Y%m%d-%H%M%S)
if [ -s "$QUEUE_FILE" ]; then
  mv "$QUEUE_FILE" "$ARCHIVE_DIR/lesson-queue-$TS.jsonl" 2>/dev/null || true
  touch "$QUEUE_FILE"
fi
if [ -s "$AGENT_POST_QUEUE" ]; then
  mv "$AGENT_POST_QUEUE" "$ARCHIVE_DIR/agent-post-queue-$TS.jsonl" 2>/dev/null || true
  touch "$AGENT_POST_QUEUE"
fi

rm -f "$MSG_FILE"
echo "[$(ts_now)] digest emitted and both queues archived" >> "$LOG"
exit 0
