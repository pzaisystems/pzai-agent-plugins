#!/bin/bash
# Send a message to Maximus's live session via the inbox server.
# Usage: maximus-reply.sh "your message here"
# Maximus gets it as a channel event within ~3 seconds if his session is running.

source /root/.pzai-env 2>/dev/null
source /root/.env 2>/dev/null

MESSAGE="$1"
if [ -z "$MESSAGE" ]; then
    echo "Usage: maximus-reply.sh <message>" >&2
    exit 1
fi

TOKEN="${MAXIMUS_INBOX_TOKEN}"
if [ -z "$TOKEN" ]; then
    echo "MAXIMUS_INBOX_TOKEN not set" >&2
    exit 1
fi

RESPONSE=$(curl -s -w '\n%{http_code}' -X POST http://localhost:8765/message \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"message\": $(echo "$MESSAGE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))'), \"from\": \"yoda\"}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
if [ "$HTTP_CODE" = "200" ]; then
    echo "Sent to Maximus."
else
    # Fallback: write to Yoda-Request.md if server is down
    echo "🚨 LIVE-PIPE OFFLINE — inbox server returned $HTTP_CODE. Message: $MESSAGE" >> /root/MyCarLife-iOS/02-AGENTS/Maximus/Yoda-Request.md
    echo "Fell back to Yoda-Request.md (inbox server down)"
fi
