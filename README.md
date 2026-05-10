# PZAI Agent Plugins

Reusable hooks, skills, scripts, and plugins for the PZAI multi-agent system (Yoda, Maximus, Trinity).

This is the single source of truth for agent infrastructure. When a hook breaks or a skill is updated, fix it here and pull on every agent — no more manual SCP.

## Structure

```
plugins/
  precontext-channel/   MCP channel plugin — bridges Claude Code to PreContext
hooks/
  proactive-improvements-check.sh   Stop hook — forces automation gap analysis each session
  auto-capture-skill.sh             Stop hook — captures non-obvious solutions as skills
  swift-trap-scanner.sh             PreToolUse hook — blocks Swift commits with known bad patterns
scripts/
  claude-or             OpenRouter wrapper for claude -p cron scripts (cheaper model routing)
  weekly-report.sh      Sunday 8am PZAI status report → PreContext
  precontext-reply.sh   Send a message to Mack via PreContext (with audio)
skills/
  yoda-revive-skill.md              Step-by-step Yoda revival for every failure mode
  proactive-improvements-check-skill.md   The 4-question improvement check
  model-tier-dispatch-skill.md      Opus/Sonnet/Haiku 3-tier dispatch policy for every spawner (Yoda/Maximus/Trinity)
```

## Installing on a new agent

```bash
# Clone on the agent machine
git clone https://github.com/pzaisystems/pzai-agent-plugins /root/pzai-agent-plugins

# Hooks (global, applies to all Claude Code sessions on this machine)
cp /root/pzai-agent-plugins/hooks/*.sh /root/.claude/hooks/
chmod +x /root/.claude/hooks/*.sh

# Scripts
cp /root/pzai-agent-plugins/scripts/* /root/scripts/
chmod +x /root/scripts/claude-or /root/scripts/weekly-report.sh

# Wire hooks into ~/.claude/settings.json Stop and PreToolUse arrays
# (see each hook file header for the exact settings.json snippet)
```

## Updating

```bash
cd /root/pzai-agent-plugins && git pull
# Re-copy any updated hooks/scripts to their deployed paths
```

## Adding a new plugin/hook/skill

1. Add the file to the right folder in this repo
2. Commit and push
3. Pull on each agent that needs it
4. Update this README
