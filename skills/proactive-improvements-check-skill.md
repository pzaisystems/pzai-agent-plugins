# Proactive Improvements Check Skill

Use this at any time (or it fires automatically at session end via Stop hook) to surface automation opportunities before they go unnoticed.

## When to invoke
- Manually: /proactive-check anytime during a session
- Automatically: fires as Stop hook at every session end

## The 4 Questions

Answer all 4 before the session ends:

**1. REPEATED MANUAL STEPS**
Did Mack do anything manually more than once this session — OAuth login, restarting Yoda, copy-pasting, checking a status? If yes: what is the permanent fix and why did you not suggest it mid-session?

**2. AUTOMATION GAPS**
Is there a shell script, manual process, or recurring pain point you touched this session that a hook, cron, plugin, or architectural change could own permanently? Name it specifically.

**3. PLUGIN/TOOL OPPORTUNITY**
Did you see Mack bridging two systems manually that a Claude Code plugin or MCP tool could own natively? (Example: Yoda down → OAuth dance → could be auto-rotation plugin.)

**4. WHAT YOU SHOULD HAVE SAID SOONER**
What improvement did you notice but did not proactively surface? Be honest. If nothing — say "nothing flagged this session" explicitly.

## Response format

If findings exist: state them clearly, then ask Mack if he wants you to build the fix now or file it to Mack-Tasks.md.

Do NOT say "I will do better next time." Either build it or file it.

If nothing found: say "Nothing flagged this session" and stop.

## Wiring as a Stop hook

Copy `hooks/proactive-improvements-check.sh` to the agent's hooks directory and add to settings.json Stop array.
