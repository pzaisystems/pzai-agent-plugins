#!/bin/bash
# yoda-session-watchdog.sh — v5
# v2 backup: /root/scripts/yoda-session-watchdog.sh.v2.bak
# v3 backup: /root/scripts/yoda-session-watchdog.sh.v3.bak
# v4 backup: /root/scripts/yoda-session-watchdog.sh.v4.bak
#
# v5 changes (2026-04-28 by Maximus, after pulse+rating-dialog jam):
#   - Check 3 now matches ANY queued ❯ prompt with text (not just
#     [Telegram]/[Slack] channel messages). Today's jam was 5 stacked
#     [STRATEGIC PULSE - ...] entries from a cron, missed by v4 regex.
#   - NEW Check 5: rating-dialog auto-dismiss. claude-cli's
#     "1: Bad  2: Fine  3: Good  0: Dismiss" rating modal blocks all input
#     until acknowledged; if visible >60s with no processing, send "0".
touch /root/scripts/yoda-watchdog-heartbeat
LOG=/root/scripts/yoda-session-watchdog.log
TOKEN=$(grep TOKEN ~/.claude/channels/telegram/.env | cut -d= -f2 | tr -d '"')
CHAT_ID=7123589252
STATE_FILE=/root/scripts/yoda-pending-state
SLACK_STATE_FILE=/root/scripts/yoda-slack-pending-state
PROMPT_STUCK_FILE=/root/scripts/yoda-prompt-stuck-state
RATING_STUCK_FILE=/root/scripts/yoda-rating-stuck-state
SLACK_JSONL=/root/website-pipeline/logs/slack-conversation.jsonl
STALL_THRESHOLD=300  # 5 minutes
STUCK_PROMPT_THRESHOLD=60  # 1 minute
RATING_DISMISS_THRESHOLD=60  # 1 minute

alert_mack() {
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" -d "text=$1" > /dev/null 2>&1
}

restart_yoda_with_verification() {
  tmux kill-session -t yoda 2>/dev/null
  sleep 2
  tmux new-session -d -s yoda
  tmux send-keys -t yoda "cd /root/website-pipeline && /root/.local/bin/claude --channels plugin:telegram@claude-plugins-official plugin:precontext@local --plugin-dir /root/pzai-agent-plugins/plugins/precontext-channel" Enter
  for i in $(seq 1 20); do
    sleep 1
    if tmux capture-pane -t yoda -p | grep -q "Listening for channel messages from:"; then
      echo "$(date) [watchdog] Restart verified — Telegram plugin active" >> $LOG
      return 0
    fi
  done
  echo "$(date) [watchdog] RESTART FAILED — Telegram plugin did NOT activate within 20s" >> $LOG
  alert_mack "Yoda watchdog: restart FAILED, Telegram plugin did not activate. SSH in and check."
  return 1
}

# Check 1: tmux alive
if ! tmux has-session -t yoda 2>/dev/null; then
  echo "$(date) [watchdog] tmux session dead — restarting" >> $LOG
  restart_yoda_with_verification
  rm -f $STATE_FILE $PROMPT_STUCK_FILE $RATING_STUCK_FILE
  exit 0
fi

PANE=$(tmux capture-pane -t yoda -p -S -50)

# Check 5 (NEW v5): rating-dialog auto-dismiss.
# claude-cli's "Was that response good?" modal blocks input until pressed.
# Auto-dismiss with "0" if visible for >RATING_DISMISS_THRESHOLD with no
# active processing.
if echo "$PANE" | grep -qE "1:\s*Bad\s+2:\s*Fine\s+3:\s*Good"; then
  if ! echo "$PANE" | grep -qE "✢|Sautéing|Choreographing|Thinking|running stop hooks|esc to interrupt"; then
    NOW=$(date +%s)
    if [ ! -f $RATING_STUCK_FILE ]; then
      echo "$NOW" > $RATING_STUCK_FILE
    else
      RATING_SINCE=$(cat $RATING_STUCK_FILE)
      RATING_DURATION=$((NOW - RATING_SINCE))
      if [ $RATING_DURATION -gt $RATING_DISMISS_THRESHOLD ]; then
        echo "$(date) [watchdog] RATING DIALOG stuck ${RATING_DURATION}s — sending 0 (Dismiss)" >> $LOG
        tmux send-keys -t yoda "0"
        rm -f $RATING_STUCK_FILE
      fi
    fi
  else
    rm -f $RATING_STUCK_FILE
  fi
else
  rm -f $RATING_STUCK_FILE
fi

# Check 3 (broadened in v5): stuck-prompt auto-Enter.
# If ANY text is queued at the ❯ prompt with no processing indicator,
# send Enter after STUCK_PROMPT_THRESHOLD. v4 only matched [Telegram]/[Slack]
# channel messages and missed cron-fired pulse text.
if echo "$PANE" | grep -qE "❯.+[A-Za-z]"; then
  if ! echo "$PANE" | grep -qE "✢|Sautéing|Choreographing|Thinking|running stop hooks|esc to interrupt"; then
    NOW=$(date +%s)
    if [ ! -f $PROMPT_STUCK_FILE ]; then
      echo "$NOW" > $PROMPT_STUCK_FILE
    else
      STUCK_SINCE=$(cat $PROMPT_STUCK_FILE)
      STUCK_DURATION=$((NOW - STUCK_SINCE))
      if [ $STUCK_DURATION -gt $STUCK_PROMPT_THRESHOLD ]; then
        echo "$(date) [watchdog] STUCK PROMPT for ${STUCK_DURATION}s — sending Enter" >> $LOG
        tmux send-keys -t yoda Enter
        rm -f $PROMPT_STUCK_FILE
      fi
    fi
  else
    rm -f $PROMPT_STUCK_FILE
  fi
else
  rm -f $PROMPT_STUCK_FILE
fi

# Check 2: Telegram stall detection
PENDING=$(curl -s "https://api.telegram.org/bot${TOKEN}/getWebhookInfo" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['pending_update_count'])" 2>/dev/null)

if [ -z "$PENDING" ] || [ "$PENDING" = "0" ]; then
  rm -f $STATE_FILE
  exit 0
fi

NOW=$(date +%s)
if [ ! -f $STATE_FILE ]; then
  echo "$NOW $PENDING" > $STATE_FILE
  exit 0
fi

read FIRST_SEEN FIRST_PENDING < $STATE_FILE
STALL_DURATION=$((NOW - FIRST_SEEN))

if [ $STALL_DURATION -gt $STALL_THRESHOLD ]; then
  echo "$(date) [watchdog] STALL: $PENDING pending Telegram updates for ${STALL_DURATION}s — restarting" >> $LOG
  alert_mack "Yoda unresponsive for ${STALL_DURATION}s with $PENDING pending Telegram messages — restarting."
  restart_yoda_with_verification
  rm -f $STATE_FILE $PROMPT_STUCK_FILE $RATING_STUCK_FILE
fi

# Check 4: Slack stall detection
if [ -f "$SLACK_JSONL" ]; then
  SLACK_LAST=$(tail -20 "$SLACK_JSONL" 2>/dev/null | python3 -c "
import json, sys, time
from datetime import datetime
last_in_ts = 0
last_out_ts = 0
for line in sys.stdin:
    try:
        d = json.loads(line)
        ts_raw = d.get('ts', '')
        direction = d.get('direction', '')
        if direction == 'in':
            try:
                t = float(ts_raw)
            except:
                continue
            if t > last_in_ts: last_in_ts = t
        elif direction == 'out':
            try:
                t = datetime.fromisoformat(ts_raw.replace('Z','+00:00')).timestamp()
            except:
                continue
            if t > last_out_ts: last_out_ts = t
    except: pass
if last_in_ts > last_out_ts and last_in_ts > 0:
    print(int(time.time() - last_in_ts))
else:
    print(0)
" 2>/dev/null)

  if [ -n "$SLACK_LAST" ] && [ "$SLACK_LAST" -gt "$STALL_THRESHOLD" ] 2>/dev/null; then
    if [ ! -f $SLACK_STATE_FILE ] || [ "$(cat $SLACK_STATE_FILE 2>/dev/null)" != "restarted" ]; then
      echo "$(date) [watchdog] SLACK STALL: last Slack 'in' unanswered for ${SLACK_LAST}s — restarting" >> $LOG
      alert_mack "Yoda knocked out — Slack message unanswered for ${SLACK_LAST}s. Restarting."
      restart_yoda_with_verification
      echo "restarted" > $SLACK_STATE_FILE
      rm -f $PROMPT_STUCK_FILE $RATING_STUCK_FILE
    fi
  else
    rm -f $SLACK_STATE_FILE
  fi
fi

# Check 6 (NEW v6, 2026-05-02 by Maximus): rate-limit detection.
# Detects 429 / rate_limit_error / "Rate limit exceeded" in the yoda pane.
# Does NOT restart (rate limit is OAuth-bucket-wide; restart shares same bucket
# and would 429 again immediately). Posts ONE alert to Discord on edge into
# rate-limit state, ONE alert on edge out. State file prevents alert spam.
#
# Why this exists: Padrick's Claude Max subscription is shared between Maximus
# (his interactive session) and Yoda (this VPS instance). When Maximus burns
# tokens fast, Yoda's API calls 429 too — Yoda goes silent until reset
# (typically 60s for input/output, 5h for daily). Without this check, Yoda
# appears dead and Padrick can't tell whether to wait or intervene.
RATE_LIMIT_STATE_FILE=/root/scripts/yoda-rate-limit-state
if echo "$PANE" | grep -qE "API Error: 429|rate_limit_error|Rate limit exceeded|rate_limit_exceeded"; then
  if [ ! -f $RATE_LIMIT_STATE_FILE ]; then
    NOW=$(date +%s)
    echo "$NOW" > $RATE_LIMIT_STATE_FILE
    echo "$(date) [watchdog] RATE-LIMIT detected — posting alert, no restart" >> $LOG
    bash /root/scripts/precontext-reply.sh "⚠️ Yoda rate-limited — Anthropic 429. Same OAuth bucket as Maximus. Waiting for reset, no action needed. (Auto-recovery alert when clear.)" > /dev/null 2>&1 || true
  fi
else
  if [ -f $RATE_LIMIT_STATE_FILE ]; then
    SINCE=$(cat $RATE_LIMIT_STATE_FILE 2>/dev/null)
    NOW=$(date +%s)
    DURATION=$((NOW - SINCE))
    echo "$(date) [watchdog] RATE-LIMIT cleared after ${DURATION}s — posting recovery" >> $LOG
    bash /root/scripts/precontext-reply.sh "🟢 Yoda back online — rate limit cleared after ${DURATION}s." > /dev/null 2>&1 || true
    rm -f $RATE_LIMIT_STATE_FILE
  fi
fi


# Check 7 (NEW v7, 2026-05-04 by Maximus): OAuth-rotation auto-restart.
# Detects the failure mode where Anthropic rotates the OAuth access token
# (Maximus refresh, iOS Claude refresh, Trinity routine fire), the new token
# lands in /root/.claude/.credentials.json on disk, but Yoda's already-running
# claude-cli session is still using the cached old token in memory and
# 401-ing on every API call. Pattern observed Sat 2026-05-02 + Mon 2026-05-04.
#
# All three conditions must hold to trigger auto-restart:
#   (a) Yoda's pane shows recent 401 / authentication_error text
#   (b) /root/.claude/.credentials.json was modified in the last 10 min
#       (a recent rotation by some other surface on Mack's account)
#   (c) we have NOT already auto-restarted in the last 10 min (backoff)
#
# If only (a): the token genuinely expired and needs /login — Check 1's
# existing auth-status logic + the watchdog's standard alerting handles
# that path. Don't restart blindly.
#
# State file: /root/scripts/yoda-last-token-restart (epoch seconds of last
# auto-restart). Posts a one-line PreContext alert on restart only.
TOKEN_RESTART_STATE_FILE=/root/scripts/yoda-last-token-restart
CREDS_FILE=/root/.claude/.credentials.json
TOKEN_RESTART_BACKOFF_SECONDS=600  # 10 min between auto-restarts
CREDS_RECENT_WINDOW_SECONDS=600    # creds modified in last 10 min counts as a recent rotation

if echo "$PANE" | grep -qE "API Error: 401|authentication_error|Invalid authentication"; then
  if [ -f "$CREDS_FILE" ]; then
    NOW=$(date +%s)
    CREDS_MTIME=$(stat -c %Y "$CREDS_FILE" 2>/dev/null || echo 0)
    CREDS_AGE=$((NOW - CREDS_MTIME))
    LAST_RESTART=$(cat "$TOKEN_RESTART_STATE_FILE" 2>/dev/null || echo 0)
    SINCE_LAST_RESTART=$((NOW - LAST_RESTART))

    if [ "$CREDS_AGE" -lt "$CREDS_RECENT_WINDOW_SECONDS" ] && \
       [ "$SINCE_LAST_RESTART" -gt "$TOKEN_RESTART_BACKOFF_SECONDS" ]; then
      echo "$(date) [watchdog] TOKEN-ROTATION detected — creds modified ${CREDS_AGE}s ago + 401 in pane — auto-restarting yoda" >> $LOG
      echo "$NOW" > "$TOKEN_RESTART_STATE_FILE"
      restart_yoda_with_verification
      bash /root/scripts/precontext-reply.sh "♻️ Yoda auto-restarted — picked up rotated OAuth token from disk. (Check 7 fired: 401 + credentials.json modified ${CREDS_AGE}s ago.)" > /dev/null 2>&1 || true
    fi
  fi
fi

