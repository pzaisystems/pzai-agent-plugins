#!/bin/bash
# PZAI Weekly Report — fires every Sunday 8am
# Collects: Yoda health, PreContext activity, Trinity builds, outreach pipeline
# Posts to PreContext so Mack gets it on his phone.

REPORT_DATE=$(TZ=America/New_York date '+%A %b %d, %Y')
CHAT_LOG="/root/website-pipeline/logs/precontext-chat.jsonl"
REPLY_SCRIPT="/root/scripts/precontext-reply.sh"

# -- Yoda Health --
YODA_UP="unknown"
if tmux has-session -t yoda 2>/dev/null; then
    YODA_UP="running"
else
    YODA_UP="DOWN"
fi
YODA_UPTIME=$(uptime -p 2>/dev/null || echo "unknown")

# -- PreContext activity (last 7 days) --
PRECONTEXT_MSGS=0
PRECONTEXT_OUTBOUND=0
if [ -f "$CHAT_LOG" ]; then
    WEEK_AGO=$(date -d '7 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-7d '+%Y-%m-%d' 2>/dev/null)
    PRECONTEXT_MSGS=$(python3 -c "
import json, sys
count = 0
with open('$CHAT_LOG') as f:
    for line in f:
        try:
            d = json.loads(line)
            ts = d.get('timestamp', d.get('ts',''))
            if ts >= '$WEEK_AGO':
                count += 1
        except: pass
print(count)
" 2>/dev/null || echo "?")
    PRECONTEXT_OUTBOUND=$(python3 -c "
import json
count = 0
with open('$CHAT_LOG') as f:
    for line in f:
        try:
            d = json.loads(line)
            ts = d.get('timestamp', d.get('ts',''))
            dir_ = d.get('direction', d.get('dir',''))
            if ts >= '$WEEK_AGO' and dir_.startswith('out'):
                count += 1
        except: pass
print(count)
" 2>/dev/null || echo "?")
fi

# -- Trinity builds (git log on MyCarLife-iOS) --
TRINITY_BRANCHES=0
cd /root/MyCarLife-iOS 2>/dev/null && {
    git fetch --all -q 2>/dev/null
    TRINITY_BRANCHES=$(git branch -r 2>/dev/null | grep 'origin/claude/' | wc -l | tr -d ' ')
    LAST_COMMIT=$(git log origin/main --oneline -1 2>/dev/null || echo "unknown")
}

# -- Outreach pipeline status --
PIPELINE_STATUS="not checked"
if [ -f "/root/website-pipeline/logs/pipeline.log" ]; then
    PIPELINE_STATUS=$(tail -3 /root/website-pipeline/logs/pipeline.log 2>/dev/null | tr '\n' ' ')
fi

# -- A2P / Twilio reminder --
A2P_NOTE="Check Twilio for A2P approval status"

# -- Compose report --
REPORT="PZAI Weekly Report — $REPORT_DATE

Yoda: $YODA_UP | VPS uptime: $YODA_UPTIME

PreContext (last 7 days): $PRECONTEXT_MSGS total messages, $PRECONTEXT_OUTBOUND outbound replies

Trinity: $TRINITY_BRANCHES active claude/* branches | Latest main: $LAST_COMMIT

Pipeline: $PIPELINE_STATUS

Reminder: $A2P_NOTE"

# -- Send --
bash "$REPLY_SCRIPT" "$REPORT"
