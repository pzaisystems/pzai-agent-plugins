#!/usr/bin/env bash
# paperclip-dispatch.sh — wrap Paperclip issue lifecycle so Yoda's subagent
# dispatches appear on the agents.pzai.systems dashboard.
#
# Usage:
#   paperclip-dispatch.sh start   <agent-name> "<title>" ["description"]
#       → creates issue + assigns to agent, prints ISSUE_ID on stdout
#   paperclip-dispatch.sh comment <issue-id>  "<body>"
#       → appends a comment (progress notes mid-run)
#   paperclip-dispatch.sh complete <issue-id> ["<final note>"]
#       → comments final note, sets status=done, releases agent
#
# Agent names accepted: Alex | Obi-Wan | Padme | Yoda  (Anakin still accepted as legacy alias)
#
# Regenerate agent IDs if they ever change:
#   sudo -u paperclip bash -lc 'cd /home/paperclip/paperclip-sandbox && \
#     pnpm -s paperclipai agent list --company-id e730d78e-7459-4051-8e70-31b90f192079'

set -euo pipefail

COMPANY_ID="e730d78e-7459-4051-8e70-31b90f192079"

agent_id_for() {
  case "$1" in
    Alex|alex)   echo "b0ab967c-2e67-478d-b623-9007c11646dc" ;;
    Anakin)      echo "b0ab967c-2e67-478d-b623-9007c11646dc" ;;  # legacy alias — use Alex
    Obi-Wan)     echo "1d234481-47ff-49a8-9fd9-1c887a58e60e" ;;
    Padme|Padmé) echo "d0b0793a-6a9e-48e8-b262-95841a9b007e" ;;
    Yoda)        echo "ddda21b7-5a4d-436c-b070-d244beb10876" ;;
    Luke)        echo "36d60651-6a61-4016-80fb-ef679af1f1f5" ;;  # Retention & Renewal — added 2026-05-03 2:25 PM EDT
    Leia)        echo "94c688ee-df4e-49cf-abdb-f21ca80aba71" ;;  # Onboarding & Setup — added 2026-05-03 2:25 PM EDT
    R2D2|r2d2)   echo "f1f4b52b-c6d3-4f81-a605-4b5534f8fe68" ;;  # Capital Stewardship / Growth lens — spawned 2026-05-04 1:30 AM EDT
    C-3PO|c3po|threepio) echo "80f5f341-fd6e-4a10-9bb6-c83c4ee4408d" ;;  # Capital Stewardship / Conservation lens — spawned 2026-05-04 9:27 AM EDT
    Mon-Mothma|Mon\ Mothma|mon-mothma|mothma) echo "4e473326-edea-4804-93e4-22dccb9e7548" ;;  # Governance / chief-of-staff layer — Hermes surface — added 2026-05-10
    Cassian|cassian) echo "0b76b84f-32b9-4346-9b82-fce7bde2085c" ;;  # Codex execution lane — added 2026-05-10
    *) return 1 ;;
  esac
}

# Invoke the paperclip CLI as the paperclip user with args preserved verbatim.
pc() {
  sudo -u paperclip -H bash -lc \
    'cd /home/paperclip/paperclip-sandbox && exec pnpm -s paperclipai "$@"' \
    -- "$@"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  start)
    agent="${1:-}"; title="${2:-}"; desc="${3:-}"
    if [[ -z "$agent" || -z "$title" ]]; then
      echo "usage: start <agent-name> \"<title>\" [description]" >&2; exit 2
    fi
    if ! agent_id=$(agent_id_for "$agent"); then
      echo "unknown agent: $agent (try Alex|Obi-Wan|Padme|Yoda|Luke|Leia|R2D2|C-3PO|Mon-Mothma|Cassian)" >&2; exit 2
    fi

    if [[ -n "$desc" ]]; then
      out=$(pc issue create --company-id "$COMPANY_ID" --title "$title" --description "$desc" --status in_progress --priority medium --assignee-agent-id "$agent_id" --json)
    else
      out=$(pc issue create --company-id "$COMPANY_ID" --title "$title" --status in_progress --priority medium --assignee-agent-id "$agent_id" --json)
    fi

    issue_id=$(printf '%s' "$out" | python3 -c "import sys,json
raw=sys.stdin.read().strip()
start=raw.find('{')
if start<0: sys.exit(0)
try:
  d=json.loads(raw[start:])
  print(d.get('id') or d.get('issue',{}).get('id',''))
except Exception:
  pass")

    if [[ -z "$issue_id" ]]; then
      echo "issue create failed. raw output:" >&2
      echo "$out" >&2
      exit 1
    fi
    echo "$issue_id"

    # Scaffolding-Roadmap Play A — log dispatch start so `complete` can verify
    # the agent appended a signed entry to Agent-Memory.md per SHARED-BASE §10.
    # Observer mode through 2026-05-17 (soft-discipline window, log-only).
    AGENT_MEMORY="/root/MyCarLife-iOS/02-AGENTS/Memory/Agent-Memory.md"
    STATE_FILE="/root/website-pipeline/logs/paperclip-dispatch-state.jsonl"
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
    start_lc=$(wc -l < "$AGENT_MEMORY" 2>/dev/null | tr -d ' ')
    printf '{"ts":"%s","event":"start","issue_id":"%s","agent":"%s","start_linecount":%s}\n' \
      "$(date -Iseconds)" "$issue_id" "$agent" "${start_lc:-0}" >> "$STATE_FILE" 2>/dev/null || true
    ;;

  comment)
    issue_id="${1:-}"; body="${2:-}"
    if [[ -z "$issue_id" || -z "$body" ]]; then
      echo "usage: comment <issue-id> \"<body>\"" >&2; exit 2
    fi
    pc issue comment "$issue_id" --body "$body" >/dev/null
    ;;

  complete)
    # Terminal state: keep the assignee on the finished issue so the dashboard
    # shows WHO completed it. DO NOT call `issue release` — that resets status
    # back to `todo` and clears the assignee.
    issue_id="${1:-}"; note="${2:-run complete}"
    if [[ -z "$issue_id" ]]; then
      echo "usage: complete <issue-id> [\"<final note>\"]" >&2; exit 2
    fi
    pc issue comment "$issue_id" --body "$note" >/dev/null || true

    # Scaffolding-Roadmap Play A — validate the agent appended a signed entry
    # to Agent-Memory.md before completion (SHARED-BASE §10). Observer mode
    # through 2026-05-17: log to JSONL only, no blocking, no PreContext spam
    # (digest cron posts daily summary). Flips to blocking mode after the
    # soft-discipline window if pattern persists.
    AGENT_MEMORY="/root/MyCarLife-iOS/02-AGENTS/Memory/Agent-Memory.md"
    STATE_FILE="/root/website-pipeline/logs/paperclip-dispatch-state.jsonl"
    NAG_LOG="/root/website-pipeline/logs/agent-memory-signing.jsonl"
    state_line=$(grep -F "\"issue_id\":\"$issue_id\"" "$STATE_FILE" 2>/dev/null | tail -1 || true)
    if [[ -n "$state_line" ]]; then
      state_agent=$(printf '%s' "$state_line" | python3 -c "import sys,json
try: print(json.loads(sys.stdin.read()).get('agent',''))
except Exception: print('')" 2>/dev/null || echo "")
      state_start_lc=$(printf '%s' "$state_line" | python3 -c "import sys,json
try: print(json.loads(sys.stdin.read()).get('start_linecount',0))
except Exception: print(0)" 2>/dev/null || echo 0)
      current_lc=$(wc -l < "$AGENT_MEMORY" 2>/dev/null | tr -d ' ')
      current_lc=${current_lc:-0}
      signed=0
      if [[ "$current_lc" -gt "${state_start_lc:-0}" ]]; then
        new_lines=$((current_lc - state_start_lc))
        if tail -n "$new_lines" "$AGENT_MEMORY" 2>/dev/null | grep -qE "^## \[.*\] $state_agent — "; then
          signed=1
        fi
      fi
      printf '{"ts":"%s","event":"complete","issue_id":"%s","agent":"%s","signed":%d,"start_lc":%s,"current_lc":%s}\n' \
        "$(date -Iseconds)" "$issue_id" "$state_agent" "$signed" "${state_start_lc:-0}" "$current_lc" >> "$NAG_LOG" 2>/dev/null || true
    fi

    pc issue update "$issue_id" --status done >/dev/null
    ;;

  *)
    cat >&2 <<USAGE
usage:
  $0 start    <agent-name> "<title>" [description]
  $0 comment  <issue-id>   "<body>"
  $0 complete <issue-id>   ["<final note>"]

agents: Alex | Obi-Wan | Padme | Yoda
company: PZAI ($COMPANY_ID)
dashboard: https://agents.pzai.systems
USAGE
    exit 2
    ;;
esac
