#!/usr/bin/env bun
/**
 * PreContext channel plugin for Claude Code.
 *
 * Polls a precontext-chat.jsonl log for new inbound messages and pushes them
 * into Claude as MCP channel events. Exposes a precontext_reply tool that
 * calls a configurable reply script.
 *
 * Configuration (env vars or hardcode below):
 *   PRECONTEXT_CHAT_LOG   — path to precontext-chat.jsonl
 *   PRECONTEXT_REPLY_SCRIPT — path to reply shell script
 *
 * Start: bun server.ts
 * Claude Code: claude --channels plugin:precontext@local --plugin-dir /path/to/precontext-channel
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from '@modelcontextprotocol/sdk/types.js'
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs'
import { homedir } from 'os'
import { join } from 'path'
import { spawnSync } from 'child_process'

const CHAT_LOG = process.env.PRECONTEXT_CHAT_LOG ?? '/root/website-pipeline/logs/precontext-chat.jsonl'
const REPLY_SCRIPT = process.env.PRECONTEXT_REPLY_SCRIPT ?? '/root/scripts/precontext-reply.sh'
const STATE_DIR = join(homedir(), '.claude', 'channels', 'precontext')
const STATE_FILE = join(STATE_DIR, 'state.json')
const POLL_MS = 3000

try { mkdirSync(STATE_DIR, { recursive: true }) } catch {}

function loadState(): { lastTs: string } {
  try {
    return JSON.parse(readFileSync(STATE_FILE, 'utf8'))
  } catch {
    return { lastTs: new Date(0).toISOString() }
  }
}

function saveState(state: { lastTs: string }) {
  writeFileSync(STATE_FILE, JSON.stringify(state), 'utf8')
}

function getNewMessages(lastTs: string): Array<{ ts: string; content: string; user: string }> {
  if (!existsSync(CHAT_LOG)) return []
  const lines = readFileSync(CHAT_LOG, 'utf8').split('\n').filter(Boolean)
  const results: Array<{ ts: string; content: string; user: string }> = []

  for (const line of lines) {
    try {
      const entry = JSON.parse(line)
      const dir = entry.direction ?? entry.dir ?? ''
      if (!dir.startsWith('in')) continue
      const ts = entry.timestamp ?? entry.ts ?? ''
      if (!ts || ts <= lastTs) continue
      const content = entry.content ?? entry.message ?? entry.text ?? ''
      if (!content) continue
      results.push({ ts, content, user: 'mack' })
    } catch {}
  }

  return results.sort((a, b) => a.ts.localeCompare(b.ts))
}

const mcp = new Server(
  { name: 'precontext-channel', version: '0.2.0' },
  { capabilities: { tools: {}, 'claude/channel': {} } }
)

mcp.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'precontext_reply',
      description:
        'Send a reply to Mack via PreContext. Always use this — never call the reply script directly. Audio is generated automatically.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          message: { type: 'string', description: 'Reply text to send.' },
          prompt_paste: {
            type: 'boolean',
            description: 'Set true for copy-paste prompts to skip audio.',
            default: false,
          },
        },
        required: ['message'],
      },
    },
  ],
}))

mcp.setRequestHandler(CallToolRequestSchema, async (req) => {
  if (req.params.name !== 'precontext_reply') {
    return { content: [{ type: 'text', text: `Unknown tool: ${req.params.name}` }], isError: true }
  }

  const { message, prompt_paste } = req.params.arguments as { message: string; prompt_paste?: boolean }
  const env = { ...process.env }
  if (prompt_paste) env.YODA_PROMPT_PASTE = '1'

  const result = spawnSync('bash', [REPLY_SCRIPT, message], { env, encoding: 'utf8', timeout: 30000 })

  if (result.status !== 0) {
    const err = result.stderr ?? result.error?.message ?? 'unknown error'
    return { content: [{ type: 'text', text: `precontext_reply failed: ${err}` }], isError: true }
  }

  return { content: [{ type: 'text', text: 'Sent.' }] }
})

const transport = new StdioServerTransport()
await mcp.connect(transport)

mcp.notification({
  method: 'notifications/claude/channel/permission',
  params: {
    instructions:
      'Messages from Mack arrive via PreContext as <channel source="precontext" user="mack" ts="...">MESSAGE</channel>. ' +
      'Respond using the precontext_reply tool. Never call precontext-reply.sh directly. ' +
      'Audio is generated automatically. Set prompt_paste: true for code/URL-heavy replies.',
  },
}).catch(() => {})

let state = loadState()

async function poll() {
  const msgs = getNewMessages(state.lastTs)
  for (const msg of msgs) {
    try {
      await mcp.notification({
        method: 'notifications/claude/channel',
        params: { content: msg.content, meta: { user: msg.user, ts: msg.ts, source: 'precontext' } },
      })
      state.lastTs = msg.ts
      saveState(state)
    } catch (err) {
      process.stderr.write(`precontext channel: failed to deliver message: ${err}\n`)
    }
  }
}

setInterval(() => { void poll() }, POLL_MS)
void poll()

process.stderr.write('precontext channel: listening\n')
