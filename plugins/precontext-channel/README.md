# PreContext Channel Plugin

Claude Code MCP channel plugin that bridges Yoda (or any Claude Code agent) to the PreContext messaging platform.

## What it does

- Polls `precontext-chat.jsonl` every 3 seconds for new inbound messages
- Pushes them into Claude as channel events
- Exposes a `precontext_reply` tool for sending replies (with auto-audio)

## Setup

```bash
# On the agent's VPS/machine:
git clone https://github.com/pzaisystems/pzai-agent-plugins
cd pzai-agent-plugins/plugins/precontext-channel
bun install

# Start Claude Code with this plugin:
claude --channels plugin:precontext@local --plugin-dir /path/to/precontext-channel
```

## Config (env vars)

| Var | Default | Description |
|-----|---------|-------------|
| `PRECONTEXT_CHAT_LOG` | `/root/website-pipeline/logs/precontext-chat.jsonl` | Path to chat log |
| `PRECONTEXT_REPLY_SCRIPT` | `/root/scripts/precontext-reply.sh` | Path to reply script |
