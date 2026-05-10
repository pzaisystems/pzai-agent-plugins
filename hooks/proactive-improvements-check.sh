#!/bin/bash
# Stop Hook: PROACTIVE IMPROVEMENTS CHECK
# Forces agent to surface automation opportunities before every session ends.
# Mack shouldn't have to ask — this makes it automatic.
#
# Install on any agent:
#   cp hooks/proactive-improvements-check.sh ~/.claude/hooks/  (global)
#   cp hooks/proactive-improvements-check.sh .claude/hooks/    (project)
#   chmod +x <destination>/proactive-improvements-check.sh
#   Add to settings.json Stop hooks array.

PROMPT='PROACTIVE IMPROVEMENTS CHECK — answer all 4 before this session ends:

1. REPEATED MANUAL STEPS: Did Mack do anything manually more than once this session (OAuth login, restarting Yoda, copy-pasting, checking a status)? If yes — what is the permanent fix and why did you not suggest it mid-session?

2. AUTOMATION GAPS: Is there a shell script, manual process, or recurring pain point you touched this session that a hook, cron, plugin, or architectural change could own permanently? Name it specifically.

3. PLUGIN/TOOL OPPORTUNITY: Did you see Mack bridging two systems manually that a Claude Code plugin or MCP tool could own natively? (Example: Yoda down → OAuth dance → could be auto-rotation plugin.)

4. WHAT YOU SHOULD HAVE SAID SOONER: What improvement did you notice but not proactively surface? Be honest. If nothing — say "nothing flagged this session" explicitly.

If findings exist: state them, then ask Mack if he wants you to build the fix now or file it to Mack-Tasks.md. Do NOT just say "I will do better next time." Either build it or file it.'

echo "{\"systemMessage\": $(printf '%s' "$PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}"
exit 0
