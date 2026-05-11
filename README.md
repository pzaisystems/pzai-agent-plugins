# PZAI Agent Plugins

Reusable hooks, skills, scripts, and plugins for the PZAI multi-agent system (Yoda, Maximus, Trinity).

This is the single source of truth for agent infrastructure. When a hook breaks or a skill is updated, fix it here and pull on every agent — no more manual SCP.

## Structure

```
plugins/
  precontext-channel/   MCP channel plugin — bridges Claude Code to PreContext (Mack's inbound messages → Yoda)
  yoda-inbox-channel/   MCP channel plugin — RECEIVE-ONLY inbox; polls yoda-inbox.jsonl and delivers agent findings to Yoda in real time
hooks/
  proactive-improvements-check.sh         Stop hook — forces automation gap analysis each session
  auto-capture-skill.sh                   Stop hook — captures non-obvious solutions as skills
  swift-trap-scanner.sh                   PreToolUse hook — blocks Swift commits with known bad patterns
  yoda-stop-hook-agent-memory-reminder.sh Stop hook — blocks session-end until Yoda signs an Agent-Memory.md entry for substantive work in the last 30 min
scripts/
  claude-or                          OpenRouter wrapper for claude -p cron scripts (cheaper model routing)
  weekly-report.sh                   Sunday 8am PZAI status report → PreContext
  precontext-reply.sh                Send a message to Mack via PreContext (with audio). Honors PRECONTEXT_BATCH_MODE=1 to queue instead of fire.
  paperclip-dispatch.sh              Paperclip CLI wrapper + Agent-Memory.md signed-entry validation in `complete` (observer mode through 2026-05-17, escalates to blocking if signing-discipline lapses)
  yoda-heartbeat-pulse.sh            Audit-heartbeat cron (every 30 min). Sets PRECONTEXT_BATCH_MODE=1 on claude -p so audit posts queue instead of trickle. LAB-NOTEBOOK format with mandatory 🔗 Live/Commit/File links.
  yoda-extract-lesson-candidate.sh   Called by heartbeat-pulse after a successful audit; extracts ONE durable lesson via Opus, queues to lesson-digest-queue.jsonl (post is batched, not fired per-lesson)
  yoda-apply-skill-lessons.sh        Cron (every 15 min) — auto-approves pending lesson candidates + appends to the agent's persona CLAUDE.md `## Skill Lessons (auto-appended)` section
  yoda-lesson-digest.sh              Cron (10 AM + 6 PM + 10 PM EDT) — flushes BOTH lesson queue + agent-post queue, emits ONE combined PreContext digest per fire, archives queues
  yoda-session-watchdog.sh           Cron-based liveness watchdog — revives Yoda's tmux session if it dies, handles 401/OAuth/rate-limit recovery paths
skills/
  yoda-revive-skill.md                    Step-by-step Yoda revival for every failure mode
  proactive-improvements-check-skill.md   The 4-question improvement check
  model-tier-dispatch-skill.md            Opus/Sonnet/Haiku 3-tier dispatch policy for every spawner (Yoda/Maximus/Trinity)
  batch-lesson-application-skill.md       Cross-agent rule — extracted lessons batch-apply to all matching surfaces; one digest post 2-3x/day, never trickle
  agent-memory-signing-skill.md           Cross-agent rule — every substantive ship ends with a signed entry appended at BOTTOM of Agent-Memory.md (newest-at-top stacking breaks the Stop hook)
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
