#!/usr/bin/env bun
/**
 * Maximus Inbox channel plugin for Claude Code.
 *
 * Polls Yoda's inbox server every 3s for new messages and pushes them
 * into Maximus's live session as channel events.
 *
 * Start: bun server.ts
 * Claude Code: claude --channels plugin:maximus-inbox@local --plugin-dir /path/to/maximus-inbox
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js'
import { readFileSync, writeFileSync, mkdirSync } from 'fs'
import { homedir } from 'os'
import { join } from 'path'

const INBOX_URL = process.env.MAXIMUS_INBOX_URL ?? 'http://187.124.157.74:8765'
const TOKEN = process.env.MAXIMUS_INBOX_TOKEN ?? ''
const POLL_MS = 3000
const STATE_DIR = join(homedir(), '.claude', 'channels', 'maximus-inbox')
const STATE_FILE = join(STATE_DIR, 'state.json')

try { mkdirSync(STATE_DIR, { recursive: true }) } catch {}

function loadState(): { lastTs: string } {
  try { return JSON.parse(readFileSync(STATE_FILE, 'utf8')) }
  catch { return { lastTs: '' } }
}
function saveState(state: { lastTs: string }) {
  writeFileSync(STATE_FILE, JSON.stringify(state), 'utf8')
}

const mcp = new Server(
  { name: 'maximus-inbox', version: '0.1.0' },
  { capabilities: { tools: {}, 'claude/channel': {} } }
)

mcp.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: [] }))

const transport = new StdioServerTransport()
await mcp.connect(transport)

mcp.notification({
  method: 'notifications/claude/channel/permission',
  params: {
    instructions:
      'Messages from Yoda arrive as <channel source="maximus-inbox" user="yoda" ts="...">MESSAGE</channel>. ' +
      'These are direct agent-to-agent messages — act on them immediately. ' +
      'Resolve any requests, then notify Yoda via tmux: ssh root@187.124.157.74 "tmux send-keys -t yoda \'...\' Enter"',
  },
}).catch(() => {})

let state = loadState()

async function poll() {
  if (!TOKEN) return
  try {
    const url = `${INBOX_URL}/messages${state.lastTs ? `?since=${encodeURIComponent(state.lastTs)}` : ''}`
    const res = await fetch(url, { headers: { Authorization: `Bearer ${TOKEN}` } })
    if (!res.ok) return
    const messages: Array<{ ts: string; from: string; message: string }> = await res.json()
    for (const msg of messages) {
      await mcp.notification({
        method: 'notifications/claude/channel',
        params: { content: msg.message, meta: { user: msg.from, ts: msg.ts, source: 'maximus-inbox' } },
      })
      state.lastTs = msg.ts
      saveState(state)
    }
  } catch {}
}

setInterval(() => { void poll() }, POLL_MS)
void poll()

process.stderr.write('maximus-inbox channel: listening\n')
