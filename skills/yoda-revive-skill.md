# Yoda Revival Skill

Use when Yoda is unresponsive, stuck, or erroring. Work through in order — stop at the first match.

## Step 1 — Is tmux session alive?

```bash
ssh root@187.124.157.74 "tmux ls 2>&1"
```

Expected: `yoda: 1 windows`. No session → Section A. Session exists → Step 2.

## Step 2 — What's on the pane?

```bash
ssh root@187.124.157.74 "tmux capture-pane -t yoda -p -S -80"
```

Match the last 20 lines to a state:

**401 / OAuth expired** — Signs: `401`, `invalid_api_key`, `Please log in` → Section B

**Hook error / minified JS** — Signs: `PreToolUse:Bash hook error`, `$.update(H,`, `/$bunfs/root/src/` → Section C

**Stuck at prompt** — Signs: `❯` visible but silent, PreContext/Telegram queued → Section D

**Process dead** — Signs: blank pane, no `❯` → Section A

**Rate limit** — Signs: `429`, `rate_limit_exceeded`, `overloaded` → Section E

## Section A — Cold Start

```bash
ssh root@187.124.157.74 "tmux kill-session -t yoda 2>/dev/null; sleep 1; tmux new-session -d -s yoda -x 220 -y 50 && tmux send-keys -t yoda '/root/.local/bin/claude --channels plugin:telegram@claude-plugins-official --plugin-dir /root/pzai-agent-plugins/plugins/precontext-channel' Enter"
sleep 12
ssh root@187.124.157.74 "tmux capture-pane -t yoda -p -S -20"
```

Trust dialog shows → send `1` then Enter. Login URL shows → Section B.

NOTE (v2.1.132+): `--dangerously-skip-permissions` is blocked as root. Drop it. settings.json `defaultMode:dontAsk` handles permissions.

## Section B — OAuth Re-login (~48hr cycle)

```bash
ssh root@187.124.157.74 "tmux send-keys -t yoda C-c && sleep 2 && tmux send-keys -t yoda '/root/.local/bin/claude --channels plugin:telegram@claude-plugins-official --plugin-dir /root/pzai-agent-plugins/plugins/precontext-channel' Enter"
sleep 8
ssh root@187.124.157.74 "tmux capture-pane -t yoda -p -S -15"
```

Copy the `https://claude.ai/...` URL → Padrick signs in → paste the code back:

```bash
ssh root@187.124.157.74 "tmux send-keys -t yoda 'CODE_HERE' Enter"
```

Watchdog Check 7 auto-detects 401s and attempts this automatically.

## Section C — Broken Hook (minified JS in pane)

Strip all hooks, restart. Investigate which hook was broken after Yoda is live.

```bash
ssh root@187.124.157.74 "cp /root/.claude/settings.json /root/.claude/settings.json.bak.$(date +%b%d) && python3 -c \"import json; s=json.load(open('/root/.claude/settings.json')); s.pop('hooks',None); json.dump(s,open('/root/.claude/settings.json','w'),indent=2); print('hooks stripped')\""
ssh root@187.124.157.74 "tmux kill-session -t yoda 2>/dev/null; sleep 1; tmux new-session -d -s yoda -x 220 -y 50 && tmux send-keys -t yoda '/root/.local/bin/claude --channels plugin:telegram@claude-plugins-official --plugin-dir /root/pzai-agent-plugins/plugins/precontext-channel' Enter"
sleep 12
ssh root@187.124.157.74 "tmux capture-pane -t yoda -p -S -15"
```

Restore hooks after fixing: `ssh root@187.124.157.74 "cp /root/.claude/settings.json.bak.DATE /root/.claude/settings.json"`

## Section D — Stuck Prompt

```bash
ssh root@187.124.157.74 "tmux send-keys -t yoda 'hello, respond?' Enter"
sleep 5
ssh root@187.124.157.74 "tmux capture-pane -t yoda -p -S -10"
```

Responds → listener broken, restart it. Silent → frozen, cold-start (Section A).

## Section E — Rate Limit

Wait 5-10 minutes. Watchdog Check 6 sends Telegram alert. Nothing to fix.

## Quick Commands

```bash
# Status check
ssh root@187.124.157.74 "tmux ls && tmux capture-pane -t yoda -p -S -20"

# Cold restart
ssh root@187.124.157.74 "tmux kill-session -t yoda 2>/dev/null; sleep 1; tmux new-session -d -s yoda -x 220 -y 50 && tmux send-keys -t yoda '/root/.local/bin/claude --channels plugin:telegram@claude-plugins-official --plugin-dir /root/pzai-agent-plugins/plugins/precontext-channel' Enter"

# Strip hooks (unblocks hook errors immediately)
ssh root@187.124.157.74 "python3 -c \"import json; s=json.load(open('/root/.claude/settings.json')); s.pop('hooks',None); json.dump(s,open('/root/.claude/settings.json','w'),indent=2)\""
```

## Outage History (pattern recognition)

- Apr 8 — Self-healing hook loop removed
- Apr 15 — Watchdog full-path fix
- Apr 16 — PreCompact hook broken → context maxed → stuck
- Apr 18 — VPS unreachable, recovered on its own
- Apr 28 — Wrong TELEGRAM_BOT_TOKEN env var name
- May 4 — OAuth 401 (~48hr cycle); Check 7 added to watchdog
- May 8 — v2.1.132 broke startup (root+dangerously-skip blocked, Telegram tag format changed); hook outputting minified JS → stripped hooks to unblock
