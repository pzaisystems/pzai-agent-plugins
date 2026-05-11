#!/usr/bin/env bun
/**
 * Yoda Inbox channel plugin for Claude Code.
 *
 * Polls yoda-inbox.jsonl for new agent_finding entries and pushes them
 * into Yoda's Claude session as MCP channel events. RECEIVE-ONLY — no
 * reply tool. Yoda reads findings, governs, then posts to Mack via
 * the normal precontext-reply.sh.
 *
 * Configuration (env vars or hardcode below):
 *   YODA_INBOX_LOG — path to yoda-inbox.jsonl
 *
 * Start: bun server.ts
 * Claude Code: claude --channels plugin:yoda-inbox@local --plugin-dir /path/to/yoda-inbox-channel
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

const INBOX_LOG = process.env.YODA_INBOX_LOG ?? '/root/website-pipeline/logs/yoda-inbox.jsonl'
const STATE_DIR = join(homedir(), '.claude', 'channels', 'yoda-inbox')
const STATE_FILE = join(STATE_DIR, 'state.json')
const POLL_MS = 3000
const PREVIEW_CHARS = 200

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

function getNewFindings(lastTs: string): Array<{ ts: string; agent: string; content: string; type: string }> {
  if (!existsSync(INBOX_LOG)) return []
  const lines = readFileSync(INBOX_LOG, 'utf8').split('\n').filter(Boolean)
  const results: Array<{ ts: string; agent: string; content: string; type: string }> = []

  for (const line of lines) {
    try {
      const entry = JSON.parse(line)
      const ts = entry.ts ?? entry.timestamp ?? ''
      if (!ts || ts <= lastTs) continue
      const type = entry.type ?? 'agent_finding'
      const agent = entry.agent ?? 'unknown'
      const content = entry.content ?? entry.message ?? entry.text ?? ''
      if (!content) continue
      results.push({ ts, agent, content, type })
    } catch {}
  }

  return results.sort((a, b) => a.ts.localeCompare(b.ts))
}

function formatEvent(finding: { ts: string; agent: string; content: string; type: string }): string {
  const preview = finding.content.length > PREVIEW_CHARS
    ? finding.content.slice(0, PREVIEW_CHARS) + '...'
    : finding.content
  // Compact timestamp: "2026-05-10T23:04:07.123+00:00" → "23:04 UTC"
  const shortTs = finding.ts.replace(/T(\d{2}:\d{2}):\d{2}.*/, '$1 UTC')
  return `[INBOX @${shortTs}] ${finding.agent}: ${preview}`
}

const mcp = new Server(
  { name: 'yoda-inbox-channel', version: '0.1.0' },
  { capabilities: { tools: {}, 'claude/channel': {} } }
)

// Receive-only — no tools exposed, but ListTools must be handled to satisfy the SDK
mcp.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: [] }))

mcp.setRequestHandler(CallToolRequestSchema, async (req) => {
  return { content: [{ type: 'text', text: `Unknown tool: ${req.params.name}` }], isError: true }
})

const transport = new StdioServerTransport()
await mcp.connect(transport)

mcp.notification({
  method: 'notifications/claude/channel/permission',
  params: {
    instructions:
      'Agent findings arrive as <channel source="yoda-inbox" agent="..." ts="...">PREVIEW</channel>. ' +
      'This channel is RECEIVE-ONLY — do not reply here. ' +
      'Read findings, govern the agent stack, then post a curated summary to Mack via precontext_reply (precontext-channel tool) or bash /root/scripts/precontext-reply.sh. ' +
      'Each event is truncated to 200 chars — read the full entry in /root/website-pipeline/logs/yoda-inbox.jsonl if needed.',
  },
}).catch(() => {})

let state = loadState()

async function poll() {
  const findings = getNewFindings(state.lastTs)
  for (const finding of findings) {
    try {
      await mcp.notification({
        method: 'notifications/claude/channel',
        params: {
          content: formatEvent(finding),
          meta: {
            agent: finding.agent,
            ts: finding.ts,
            type: finding.type,
            source: 'yoda-inbox',
          },
        },
      })
      state.lastTs = finding.ts
      saveState(state)
    } catch (err) {
      process.stderr.write(`yoda-inbox channel: failed to deliver finding: ${err}\n`)
    }
  }
}

setInterval(() => { void poll() }, POLL_MS)
void poll()

process.stderr.write('yoda-inbox channel: listening\n')
