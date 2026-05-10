#!/bin/bash
# Stop Hook: AUTO-CAPTURE SKILL
# When you reasoned through something non-obvious this session (3+ turns,
# back-and-forth debugging, architecture decisions), capture it as a skill
# so the next agent does not have to rediscover it from scratch.
#
# Install on any agent:
#   cp hooks/auto-capture-skill.sh ~/.claude/hooks/  (global)
#   chmod +x ~/.claude/hooks/auto-capture-skill.sh
#   Add to settings.json Stop hooks array.

PROMPT='AUTO-CAPTURE SKILL CHECK — scan this session before it closes:

Think about what you worked through this session that was NON-OBVIOUS. Specifically:

- Did you debug something that required 3+ tool calls or rounds of reasoning to solve?
- Did you discover a non-obvious pattern, workaround, or architectural fact about this codebase, Yoda, or the agent system?
- Did you figure out the correct sequence for something that would have failed if done wrong (OAuth dance, hook format, VPS restart order, etc.)?

IF YES — write a skill file RIGHT NOW. Use this format:
- File path: .claude/skills/<kebab-case-problem-name>-skill.md
- Start with: what the problem is, when to use this skill
- Then: the exact steps or code that worked
- End with: what NOT to do (the wrong turns you took before finding the solution)

Use the Write tool or Bash/python3 to save it to .claude/skills/.

IF NOTHING NON-OBVIOUS was figured out this session — say "No new skills captured" and stop. Do not create a skill file just to create one. Only real hard-won knowledge earns a skill file.'

echo "{\"systemMessage\": $(printf '%s' "$PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}"
exit 0
