#!/bin/bash
# precontext-reply.sh — log Yoda's outbound reply to precontext-chat.jsonl
# so the PreContext Talk-to-Yoda tab can render the bidirectional thread.
#
# AUDIO-ON-EVERY-POST RULE (Mack 2026-05-07 7:18 PM EDT — "Audios should be
# part of the post. It should never not be included."): every PreContext post
# generates audio synchronously and writes ONE combined entry with content +
# audio_url. The previous 5+ sentence floor + YODA_SUPPRESS_AUDIO opt-out
# were both removed because Yoda kept drifting back to short text-only acks.
#
# ONLY EXCEPTION: copy-paste prompts for Perplexity/Portia/agents — TTS
# reading code/URLs/imperative-step-lists is unhelpful noise. Set
# YODA_PROMPT_PASTE=1 explicitly when posting that kind of content.
#
# Usage: bash /root/scripts/precontext-reply.sh "your reply text"
# Skip audio for copy-paste prompt: YODA_PROMPT_PASTE=1 bash precontext-reply.sh "..."

set -u

MESSAGE="${1:-}"
if [ -z "$MESSAGE" ]; then
  echo "Usage: $0 \"reply text\"" >&2
  exit 1
fi

LOG=/root/website-pipeline/logs/precontext-chat.jsonl
mkdir -p "$(dirname "$LOG")"

# BATCH MODE — Mack 2026-05-10 3:20 PM EDT: "all your agents have to be doing
# batches." When PRECONTEXT_BATCH_MODE=1 is set (typically by yoda-heartbeat-
# pulse.sh when spawning agents), posts queue to agent-post-queue.jsonl instead
# of firing immediately. yoda-agent-digest.sh runs 2x/day (10 AM + 6 PM EDT)
# and emits ONE combined post per fire. Mack-direct posts (Yoda's main thread
# reply, not from cron) leave PRECONTEXT_BATCH_MODE unset and post normally.
if [ "${PRECONTEXT_BATCH_MODE:-0}" = "1" ]; then
  QUEUE=/root/website-pipeline/logs/agent-post-queue.jsonl
  mkdir -p "$(dirname "$QUEUE")" 2>/dev/null || true
  MESSAGE="$MESSAGE" AUTHOR="${YODA_AUTHOR:-yoda}" python3 -c '
import os, json, datetime
row = {
    "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "type": "agent_post",
    "author": os.environ.get("AUTHOR", "yoda").lower(),
    "content": os.environ["MESSAGE"],
}
with open("/root/website-pipeline/logs/agent-post-queue.jsonl", "a") as f:
    f.write(json.dumps(row) + "\n")
print(f"[batch-mode] queued as {row[\"author\"]} for next digest")
'
  exit 0
fi

# YODA_SUPPRESS_AUDIO is now IGNORED (deliberately) so Yoda cannot drift back
# to text-only short replies. Audio fires unless the caller explicitly marks
# the post as a copy-paste prompt via YODA_PROMPT_PASTE=1. Log a warning so
# any drift attempt is visible in the script log.
if [ "${YODA_SUPPRESS_AUDIO:-0}" = "1" ] && [ "${YODA_PROMPT_PASTE:-0}" != "1" ]; then
  echo "[precontext-reply.sh] YODA_SUPPRESS_AUDIO=1 ignored — audio is mandatory on every post per Mack 2026-05-07. Use YODA_PROMPT_PASTE=1 only for copy-paste prompts." >&2
fi

# AUDIO PATH: every post unless YODA_PROMPT_PASTE=1 → single combined entry.
# Audio script writes the JSONL itself (with content + audio_url). On any
# audio failure, fall through to text-only path below.
if [ "${YODA_PROMPT_PASTE:-0}" != "1" ]; then
  if YODA_AUTHOR="${YODA_AUTHOR:-yoda}" bash /root/scripts/precontext-reply-audio.sh "$MESSAGE"; then
    exit 0
  fi
  echo "Audio path failed — falling back to text-only entry" >&2
fi

# TEXT-ONLY PATH: short replies, suppressed audio, or audio failure fallback.
# Optional PCX_CHOICES_JSON env var attaches a tappable-button array to the
# message entry (Mack 2026-05-05 1:10 PM EDT). Format: [{"label":"A","desc":"...","send":"..."}]
MESSAGE="$MESSAGE" AUTHOR="${YODA_AUTHOR:-yoda}" PCX_CHOICES_JSON="${PCX_CHOICES_JSON:-}" python3 -c '
import os, json, datetime
author = os.environ.get("AUTHOR", "yoda").lower()
entry = {
    "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "direction": "out",
    "author_name": author,
    "content": os.environ["MESSAGE"],
}
choices_json = os.environ.get("PCX_CHOICES_JSON", "").strip()
if choices_json:
    try:
        entry["choices"] = json.loads(choices_json)
    except Exception as e:
        print("WARN: PCX_CHOICES_JSON parse failed: " + str(e))
log = "/root/website-pipeline/logs/precontext-chat.jsonl"
with open(log, "a") as f:
    f.write(json.dumps(entry) + "\n")
print("Logged to PreContext chat (author=" + author + ").")
'
