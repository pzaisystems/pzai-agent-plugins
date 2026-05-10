#!/bin/bash
# Yoda Stop hook — agent-memory + claudia-context signing reminder.
#
# Fires when Yoda finishes a turn. Two checks:
#  (1) substantive session AND no Yoda-signed entry in Agent-Memory.md in
#      the last 4 hours → block + instruct to append signed entry.
#  (2) substantive session AND claudia-context.md not updated by Yoda in
#      the last 24 hours → block + instruct to update claudia-context.md
#      (the second-brain bridge file Mack copy-pastes to claude.ai).
#
# Mack 2026-05-10 12:48 PM EDT — claudia-context.md audit showed Trinity 88
# updates / Yoda 1 ever / everyone else 0. The bridge file is critical
# because Claudia is Mack's brainstormer — stale claudia-context = stale
# Claudia = bad brainstorming.
#
# This is the auto-discipline mechanism that mirrors Trinity's pattern
# (45 signed entries vs Yoda's 0 prior to 2026-05-10). Wired into
# /root/.claude/settings.json under hooks.Stop.
#
# Override (one-shot, brief replies that don't warrant an entry):
#   touch /tmp/yoda-skip-memory-log

set -u

OVERRIDE_FILE="/tmp/yoda-skip-memory-log"
if [ -f "$OVERRIDE_FILE" ]; then
  rm -f "$OVERRIDE_FILE"
  exit 0
fi

VAULT=/root/MyCarLife-iOS
MEM=$VAULT/02-AGENTS/Memory/Agent-Memory.md
PIPELINE=/root/website-pipeline
WEBSITE=/root/pzai-systems-official-website

# Was this session substantive? Check commit count in the last 30 min across
# the three repos Yoda authors in.
SUBSTANTIVE=0
for r in "$VAULT" "$PIPELINE" "$WEBSITE"; do
  [ -d "$r/.git" ] || continue
  recent=$(git -C "$r" log --since="30 minutes ago" --oneline 2>/dev/null | wc -l)
  if [ "$recent" -gt 0 ]; then
    SUBSTANTIVE=1
    break
  fi
done

# If nothing substantive happened, nothing to log — silent exit.
if [ "$SUBSTANTIVE" -eq 0 ]; then
  exit 0
fi

# Has Yoda already written a signed entry recently? Look at the last 50 lines
# of Agent-Memory.md and check for a Yoda header within the last 4 hours.
NOW_EPOCH=$(date +%s)
FOUR_HOURS_AGO=$(( NOW_EPOCH - 14400 ))

LATEST_YODA_TS=$(tail -200 "$MEM" 2>/dev/null \
  | grep -E "^## \[.*\] Yoda — " \
  | tail -1 \
  | sed -E 's/^## \[([^]]+)\].*/\1/')

if [ -n "$LATEST_YODA_TS" ]; then
  # Header format is "Sunday, May 10, 2026, 12:32 PM EDT" — the comma between
  # year and time breaks GNU `date -d`. Strip it before parsing.
  TS_CLEAN=$(echo "$LATEST_YODA_TS" | sed -E 's/(, [0-9]{4}), /\1 /')
  LATEST_EPOCH=$(date -d "$TS_CLEAN" +%s 2>/dev/null || echo 0)
  if [ "$LATEST_EPOCH" -le "$FOUR_HOURS_AGO" ]; then
    cat <<'BLOCK'
{
  "decision": "block",
  "reason": "Append a signed entry to /root/MyCarLife-iOS/02-AGENTS/Memory/Agent-Memory.md before ending this session. You shipped substantive work in the last 30 minutes (commits made) but haven't logged a signed entry in Agent-Memory.md in the last 4 hours. Format: '## [Day, Month DD, YYYY, H:MM AM/PM EDT] Yoda — one-line summary' followed by 3-6 detail bullets covering what shipped, what's open, and what's queued for the next Yoda. Sign with '— Yoda' on the last line. After appending, commit + push the vault, then exit cleanly. To skip this turn (one-shot, brief replies): touch /tmp/yoda-skip-memory-log."
}
BLOCK
    exit 0
  fi
fi

# Check (2): claudia-context.md staleness.
# The file's "Last Updated:" line on line 5 is the canonical update marker.
# If Yoda hasn't touched it in 24 hours despite substantive commits, prompt.
TWENTYFOUR_AGO=$(( NOW_EPOCH - 86400 ))
CLAUDIA_FILE=/root/MyCarLife-iOS/claudia-context.md
if [ -f "$CLAUDIA_FILE" ]; then
  CLAUDIA_LAST_LINE=$(sed -n '5p' "$CLAUDIA_FILE" 2>/dev/null)
  # Only prompt if the last update was BY YODA (avoid prompting Yoda to
  # overwrite Trinity's MyMobileLife-side update with PZAI-side content
  # within minutes of her commit).
  if echo "$CLAUDIA_LAST_LINE" | grep -q "by Yoda"; then
    CLAUDIA_TS=$(echo "$CLAUDIA_LAST_LINE" | sed -E 's/^\*\*Last Updated:\*\* ([^,]+, [^,]+, [0-9]{4}), ([0-9]{1,2}:[0-9]{2} [AP]M [A-Z]+).*/\1 \2/')
    CLAUDIA_EPOCH=$(date -d "$CLAUDIA_TS" +%s 2>/dev/null || echo 0)
    if [ "$CLAUDIA_EPOCH" -gt 0 ] && [ "$CLAUDIA_EPOCH" -le "$TWENTYFOUR_AGO" ]; then
      cat <<'BLOCK'
{
  "decision": "block",
  "reason": "Update /root/MyCarLife-iOS/claudia-context.md before ending this session. You shipped substantive work in the last 30 minutes but the last Yoda update to claudia-context.md was 24+ hours ago. This file is Mack's bridge to Claudia (his brainstormer at claude.ai). Stale claudia-context = stale Claudia = bad brainstorming. Edit line 5 ('Last Updated:' header) to today's date + your one-line summary, then prepend a new dated section under the existing 'PZAI / Restaurant Launch — Current State' section covering what shipped + what's open. After editing, commit + push the vault, then exit cleanly. To skip this turn (rare): touch /tmp/yoda-skip-memory-log."
}
BLOCK
      exit 0
    fi
  fi
fi
exit 0

# Substantive work happened + no recent Yoda entry → block session close,
# instruct Yoda to append a signed entry. Per Claude Code hook spec, the
# Stop hook can return JSON with decision="block" to require the agent to
# act before stopping.

cat <<EOF
{
  "decision": "block",
  "reason": "Append a signed entry to /root/MyCarLife-iOS/02-AGENTS/Memory/Agent-Memory.md before ending this session. You shipped substantive work in the last 30 minutes (commits made) but haven't logged a signed entry in Agent-Memory.md in the last 4 hours. Format: '## [Day, Month DD, YYYY, H:MM AM/PM EDT] Yoda — one-line summary' followed by 3-6 detail bullets covering what shipped, what's open, and what's queued for the next Yoda. Sign with '— Yoda' on the last line. After appending, commit + push the vault, then exit cleanly. To skip this turn (one-shot, brief replies): touch /tmp/yoda-skip-memory-log."
}
EOF
exit 0
