# Yoda Inbox Channel Plugin

Claude Code MCP channel plugin — RECEIVE-ONLY inbox that delivers cron-spawned agent findings to Yoda's live session in real time.

## What it does

- Polls `yoda-inbox.jsonl` every 3 seconds for new `agent_finding` entries
- Pushes each entry into Yoda's Claude Code session as a channel event
- Formats events as `[INBOX @HH:MM UTC] agent: first-200-chars...` so Yoda sees agent name + preview instantly
- RECEIVE-ONLY: no reply tool — Yoda governs by reading findings and posting curated summaries to Mack via `precontext-reply.sh`

## Context

Added 2026-05-10 when govern-mode architecture flipped: cron agents (Padme, Obi-Wan, Anakin, Luke, Leia, R2D2, C-3PO, Mothma, Cassian, heartbeat-pulse, lesson-extract) now route their posts to `yoda-inbox.jsonl` instead of Mack's PreContext chat. Yoda is the governor — reads all findings, evaluates research quality, watches cron health, curates executive summaries for Mack.

## Setup

```bash
# On Yoda's VPS:
cd /root/pzai-agent-plugins && git pull

# Start Claude Code with BOTH channel plugins:
/root/.local/bin/claude \
  --channels plugin:telegram@claude-plugins-official \
  --channels plugin:precontext@local \
  --channels plugin:yoda-inbox@local \
  --plugin-dir /root/pzai-agent-plugins/plugins/precontext-channel \
  --plugin-dir /root/pzai-agent-plugins/plugins/yoda-inbox-channel
```

## Config (env vars)

| Var | Default | Description |
|-----|---------|-------------|
| `YODA_INBOX_LOG` | `/root/website-pipeline/logs/yoda-inbox.jsonl` | Path to agent inbox log |

## State file

`~/.claude/channels/yoda-inbox/state.json` — tracks the last-seen timestamp so only NEW entries are surfaced after restart.
