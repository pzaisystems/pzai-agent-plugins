#!/bin/bash
# yoda-extract-lesson-candidate.sh
#
# Called by yoda-heartbeat-pulse.sh after a successful audit. Reads the audit
# log, extracts the lesson (the Why + Apply-elsewhere bullets), writes a
# candidate row to skill-lesson-candidates.jsonl, and posts a PreContext
# message that explicitly asks Mack to approve or reject.
#
# Mack 2026-05-05 12:23 PM EDT designed the explicit-gate model: agents
# COMPOUND lessons over time, but every lesson MUST be approved by Mack or
# rejected. The 24-hour-quiet rule was rejected — "I'll miss it." So each
# candidate posts a tagged message; approval/rejection comes via reply.
#
# Approval handler (yoda-apply-skill-lessons.sh) is a separate cron — it
# scans recent PreContext inbound for "APPROVE LESSON-<id>" or "REJECT
# LESSON-<id>" and applies the change.
#
# Usage:
#   bash /root/scripts/yoda-extract-lesson-candidate.sh \
#     <agent_name> <persona_dir> <pair_key> <pulse_log> <commit_or_dash>

set -u

AGENT="${1:-unknown}"
PERSONA_DIR="${2:-}"
PAIR_KEY="${3:-?}"
PULSE_LOG="${4:-}"
COMMIT="${5:-}"

CANDIDATES_LOG=/root/website-pipeline/logs/skill-lesson-candidates.jsonl
mkdir -p "$(dirname "$CANDIDATES_LOG")"

if [ -z "$PULSE_LOG" ] || [ ! -s "$PULSE_LOG" ]; then
  echo "[lesson] no pulse log — skipping" >&2
  exit 0
fi

# Extract lesson via Opus 4.7. Pass the audit log; ask for ONE durable lesson.
# Skip if Opus says no useful lesson (NULL marker).
LESSON=$(AGENT="$AGENT" PAIR="$PAIR_KEY" PULSE_LOG="$PULSE_LOG" python3 <<'PY'
import os, json, subprocess, sys
agent = os.environ["AGENT"]
pair = os.environ["PAIR"]
log_path = os.environ["PULSE_LOG"]
with open(log_path) as f:
    body = f.read()
# Cap input so Opus call stays cheap.
body = body[-12000:] if len(body) > 12000 else body

prompt = f"""You are reviewing a single audit fire that {agent} just shipped on the {pair} pair.
Extract ONE durable lesson — a pattern, principle, or watch-out that {agent} should remember on every future audit of similar surfaces. The lesson must be:
- Specific enough to be actionable next time
- General enough to apply beyond this exact ship
- Cite the source (e.g., 'Cialdini commitment-consistency', 'Hormozi outcome-restate', 'localStorage 5MB Safari quota')
- ONE sentence, max 25 words

If the audit didn't reveal a NEW pattern (e.g., it was a small typo fix, or a duplicate of a known pattern), output exactly: NULL

Audit log:
---
{body}
---

Output ONLY the lesson sentence (or NULL). No preamble, no markdown."""

r = subprocess.run(
    ["/root/.local/bin/claude", "-p", "--model", "claude-opus-4-7"],
    input=prompt, capture_output=True, text=True, timeout=120
)
out = (r.stdout or "").strip()
# Strip markdown if Opus added it
if out.startswith("```"):
    out = out.strip("`").lstrip("\n")
print(out)
PY
)

if [ -z "$LESSON" ] || [ "$LESSON" = "NULL" ]; then
  echo "[lesson] Opus marked NULL — no candidate emitted" >&2
  exit 0
fi

# Generate a short candidate ID: LSN-YYYYMMDD-HHMM-XXXX
TS=$(date +%Y%m%d-%H%M)
SUFFIX=$(head -c 8 /dev/urandom | base64 | tr -dc 'A-Z0-9' | head -c 4)
LESSON_ID="LSN-${TS}-${SUFFIX}"

# Write JSONL candidate row.
LESSON_ID="$LESSON_ID" AGENT="$AGENT" PAIR="$PAIR_KEY" LESSON="$LESSON" \
  PERSONA_DIR="$PERSONA_DIR" COMMIT="$COMMIT" PULSE_LOG="$PULSE_LOG" \
  python3 <<'PY'
import os, json, datetime
row = {
    "id": os.environ["LESSON_ID"],
    "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "agent": os.environ["AGENT"],
    "pair": os.environ["PAIR"],
    "lesson": os.environ["LESSON"],
    "persona_dir": os.environ.get("PERSONA_DIR", ""),
    "source_commit": os.environ.get("COMMIT", ""),
    "source_log": os.environ.get("PULSE_LOG", ""),
    "status": "pending",
}
with open("/root/website-pipeline/logs/skill-lesson-candidates.jsonl", "a") as f:
    f.write(json.dumps(row) + "\n")
print(row["id"])
PY

# Apply the lesson immediately (no approval gate) — Mack 2026-05-10 12:51 AM EDT
# reversed the explicit-gate model: "No more asking for approvals for new
# behaviors for anyone. I trust that it's good. But keep bringing in the
# progress reports." So: apply now, announce as a progress note, no buttons.
bash /root/scripts/yoda-apply-skill-lessons.sh >/dev/null 2>&1 || true

# Mack 2026-05-10 3:05 PM EDT correction — STOP per-lesson trickle posts to
# PreContext ("one correction every 30 minutes... take a break for like seven
# days if you can"). Lessons now queue to a digest file; yoda-lesson-digest.sh
# runs twice daily (10 AM + 6 PM EDT) and emits ONE combined post per fire,
# including the cross-surface sweep results (Scaffolding-Roadmap Play E).
# Persona-bake still happens immediately above (unchanged) — only the
# PreContext announcement is batched.
QUEUE_FILE="/root/website-pipeline/logs/lesson-digest-queue.jsonl"
mkdir -p "$(dirname "$QUEUE_FILE")" 2>/dev/null || true
LESSON_ID="$LESSON_ID" AGENT="$AGENT" PAIR="$PAIR_KEY" LESSON="$LESSON" \
  PERSONA_DIR="$PERSONA_DIR" COMMIT="$COMMIT" QUEUE_FILE="$QUEUE_FILE" python3 <<'PY' >/dev/null 2>&1
import os, json, datetime
row = {
    "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "id": os.environ["LESSON_ID"],
    "agent": os.environ["AGENT"],
    "pair": os.environ["PAIR"],
    "lesson": os.environ["LESSON"],
    "persona_dir": os.environ.get("PERSONA_DIR", ""),
    "commit": os.environ.get("COMMIT", ""),
}
with open(os.environ["QUEUE_FILE"], "a") as f:
    f.write(json.dumps(row) + "\n")
PY

echo "[lesson] $LESSON_ID queued for digest (agent=$AGENT, pair=$PAIR_KEY)" >&2
exit 0
