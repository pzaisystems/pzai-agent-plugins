#!/bin/bash
# yoda-heartbeat-pulse.sh — AUDIT HEARTBEAT (v3 per Mack 2026-05-02 evening design).
#
# Replaces the task-executor version (backed up at .task-executor.bak) which
# violated Mack's 2026-05-02 redesign by saying "queue clear" when no Agent-
# Tasks items existed. The CEO heartbeat is NEVER done.
#
# Architecture: 6 DOMAINS × 6 LENSES = 36 (domain, lens) pairs.
# Each fire picks the most-overdue pair by composite score (Δchange + staleness
# + last-finding-severity + best-in-class-gap), audits the surface for that
# specific lens, finds ONE finding, ships if reversible OR pings Mack at
# severity ≤ 3 (1 = worst, 10 = trivial — flipped 2026-05-03 5:44 PM EDT).
#
# Mack's vision (locked 2026-05-02 ~10 PM EDT):
# > "I want a really self-improving system. You keep coming back. 'Hey Mac,
# >  I saw this one mistake we did with the text. It's not consistent.'
# >  Pricing isn't a checkbox — it's an area of purpose. Pricing consistency
# >  is just 3% of pricing purpose. You're not done after #8."
#
# Memory: project_audit_heartbeat_v3_design.md

set -uo pipefail

LOG=/root/website-pipeline/logs/yoda-heartbeat-pulse.log
RESEARCH=/root/website-pipeline/logs/heartbeat-research.md
FINDINGS=/root/website-pipeline/logs/heartbeat-findings.jsonl
SCOREBOARD=/root/website-pipeline/logs/heartbeat-scoreboard.json
BUILD_LOCK=/root/website-pipeline/logs/yoda-build-in-progress.lock
PULSE_OUTPUT_DIR=/root/website-pipeline/logs/heartbeat-pulses
mkdir -p "$PULSE_OUTPUT_DIR" "$(dirname "$LOG")"

CLAUDE_BIN=/root/.local/bin/claude
MODEL="claude-sonnet-4-6"  # Mack 2026-05-05 2:36 PM EDT — flipped back from Opus 4.7 to save weekly quota until Sat 11pm cutoff. Audit fires execute on Sonnet (proven adequate by 12 ships earlier today). Lesson extraction stays on Opus 4.7 (yoda-extract-lesson-candidate.sh — synthesis is the compounding layer worth the spend).
TIMEOUT_SECS=900

ts() { date "+%Y-%m-%d %H:%M:%S %Z"; }
log() { echo "[$(ts)] $*" >> "$LOG"; }

# Skip strategic-pulse fire minutes (07:00, 14:00, 21:00) — those minutes spawn
# 7-theme batches; let them have the API window to themselves.
HOUR=$(date +%H); MIN=$(date +%M)
if [ "$MIN" = "00" ] && { [ "$HOUR" = "07" ] || [ "$HOUR" = "14" ] || [ "$HOUR" = "21" ]; }; then
  log "skip — strategic-pulse batch window $HOUR:$MIN"
  exit 0
fi

if [ -f "$BUILD_LOCK" ]; then
  log "DEFERRED — build lock present"
  exit 0
fi

# OpenClaw 2026.4.29 `heartbeat.skipWhenBusy` pattern (adopted 2026-05-03 by
# OPENCLAW pulse). Defer this fire when a strategic-pulse batch is still
# in-flight — its 7 backgrounded subprocesses can run up to ~13 min after
# batch start (3min stagger + 10min timeout). Cron retries in 30 min, no
# schedule advance. OpenClaw note: "defer heartbeat turns while cron work
# is active or queued, retry busy skips without advancing the schedule."
BATCH_MARKER=/root/website-pipeline/logs/yoda-strategic-pulse-batch.marker
if [ -f "$BATCH_MARKER" ] && [ -n "$(find "$BATCH_MARKER" -mmin -13 2>/dev/null)" ]; then
  log "DEFERRED — strategic-pulse batch active (skipWhenBusy, OpenClaw 2026.4.29)"
  exit 0
fi

# ─── PICK (domain × lens) PAIR ──────────────────────────────────────────────
# Scoreboard tracks last-explored-at per pair. Initialize if missing.
# Pick the pair with the OLDEST last_explored_at (simple v1 — refine later
# with Δchange / severity / gap signals).
if [ ! -f "$SCOREBOARD" ]; then
  python3 - <<'PY' > "$SCOREBOARD"
import json
DOMAINS = [
    ("Pricing", "💲", "strategy, psychology, tier design, anchoring, trial length, competitive benchmarks"),
    ("Alex / Texting", "📱", "voice consistency, message structure, conversion psychology, response time, edge-case handling, SMS-marketing best-practice"),
    ("Restaurant Site", "🍽", "UX, trust signals, freshness, mobile, conversion friction, hero psychology, social proof"),
    ("Outreach / Marketing", "📮", "postcard design, text campaigns, email subject lines, channel mix, list quality, follow-up cadence"),
    ("Brand / Voice", "🎨", "tone consistency across surfaces, story, why-PZAI, anti-claims that build trust"),
    ("Onboarding / Setup", "🤝", "Brand Interview flow, first-week experience, expectation-setting, trust-building before launch"),
]
LENSES = [
    ("Consistency", "does this surface match all other surfaces?"),
    ("Best-in-class", "research what top competitors / Hormozi / Cialdini do, gap-check us"),
    ("Conversion", "designed to convert, or just exist?"),
    ("Psychology", "anchoring / scarcity / social proof / loss aversion working?"),
    ("Edge-case", "what breaks at the boundary?"),
    ("Friction", "every step that could lose someone"),
]
pairs = []
for d_name, d_emoji, d_scope in DOMAINS:
    for l_name, l_question in LENSES:
        pairs.append({
            "key": f"{d_name}|{l_name}",
            "domain": d_name,
            "domain_emoji": d_emoji,
            "domain_scope": d_scope,
            "lens": l_name,
            "lens_question": l_question,
            "last_explored_at": "1970-01-01T00:00:00Z",
            "last_finding_severity": 0,
        })
print(json.dumps({"pairs": pairs, "version": 1}, indent=2))
PY
  log "Initialized scoreboard with 36 pairs"
fi

# Schema guard — heal stray root-level keys before picking. Bug class
# observed 2026-05-03 (obs 1148) where audits wrote Pricing|Lens at root
# instead of updating .pairs[]. Karpathy: every failure → permanent fix.
if [ -x /root/scripts/yoda-scoreboard-validate.sh ]; then
  /root/scripts/yoda-scoreboard-validate.sh heal >/dev/null 2>&1 || true
fi

# Pick oldest pair — Pricing domain re-included after Mack locked $79/mo
# on 2026-05-04 6:57 PM EDT. Filter removed.
PICK=$(python3 - <<PY
import json
with open("$SCOREBOARD") as f:
    d = json.load(f)
pairs = sorted(d["pairs"], key=lambda p: p["last_explored_at"])
p = pairs[0]
print(json.dumps(p))
PY
)

DOMAIN=$(echo "$PICK" | python3 -c "import json,sys; print(json.load(sys.stdin)['domain'])")
DOMAIN_EMOJI=$(echo "$PICK" | python3 -c "import json,sys; print(json.load(sys.stdin)['domain_emoji'])")
DOMAIN_SCOPE=$(echo "$PICK" | python3 -c "import json,sys; print(json.load(sys.stdin)['domain_scope'])")
LENS=$(echo "$PICK" | python3 -c "import json,sys; print(json.load(sys.stdin)['lens'])")
LENS_Q=$(echo "$PICK" | python3 -c "import json,sys; print(json.load(sys.stdin)['lens_question'])")
PAIR_KEY=$(echo "$PICK" | python3 -c "import json,sys; print(json.load(sys.stdin)['key'])")

log "PICKED pair: $DOMAIN_EMOJI $DOMAIN × $LENS"

# Mack 2026-05-03 11:30 AM EDT: dispatch audits through Paperclip so each fire
# is attributed to the right specialist agent + visible on agents.pzai.systems.
# Yoda becomes orchestrator/CEO — Anakin/Obi-Wan/Padmé do the domain work.
case "$DOMAIN" in
  "Restaurant Site")            DISPATCH_AGENT="Anakin" ;;     # Magic Moment — frontend/templates
  # Mack 2026-05-03 3:09 PM EDT swap: Obi-Wan ↔ Padmé. Obi-Wan now owns Trust & Belief +
  # Continuous Improvement (the wise-mentor research role). Padmé owns Attraction +
  # Conversion (the senator/diplomat persuasion role). Names + personalities fit better.
  "Outreach / Marketing")       DISPATCH_AGENT="Padme" ;;       # Attraction — outreach copy
  "Pricing")                    DISPATCH_AGENT="Padme" ;;       # Conversion — pricing copy
  "Alex / Texting")             DISPATCH_AGENT="Padme" ;;       # Attraction — SMS drafting
  "Brand / Voice")              DISPATCH_AGENT="Obi-Wan" ;;    # Trust & Belief — voice consistency
  "Onboarding / Setup")         DISPATCH_AGENT="Luke" ;;        # Onboarding & Setup (swap 2026-05-03 3:12 PM EDT)
  # Retention & Renewal lens (when scoreboard adds it) → Leia (swap 2026-05-03 3:12 PM EDT)
  *)                            DISPATCH_AGENT="Yoda" ;;
esac
# Lowercase + dash-stripped form for YODA_AUTHOR env var (e.g. "Obi-Wan" → "obiwan")
DISPATCH_AGENT_LOWER=$(echo "$DISPATCH_AGENT" | tr '[:upper:]' '[:lower:]' | tr -d '-')
log "DISPATCH agent: $DISPATCH_AGENT (author=$DISPATCH_AGENT_LOWER)"

# Open Paperclip issue — dashboard at agents.pzai.systems gets the live activity.
ISSUE_ID=$(/root/scripts/paperclip-dispatch.sh start "$DISPATCH_AGENT" "Audit: $DOMAIN × $LENS" "Heartbeat fire — $LENS lens on $DOMAIN domain. See heartbeat-research.md after run." 2>>"$LOG" || echo "")
if [ -n "$ISSUE_ID" ]; then
  log "Paperclip issue: $ISSUE_ID assigned to $DISPATCH_AGENT"
fi

PROMPT='[AUDIT HEARTBEAT — domain × lens explorer, v3]

🚨 READ /root/.claude/projects/-root-website-pipeline/memory/AGENT_SCOPE_LOCKED.md FIRST. That file is the definitive in-scope / out-of-scope list (Mack 2026-05-04 9:24 PM EDT). Quick recap of what'\''s changed since v3:

CANONICAL SITES SCOPE (Mack 2026-05-04 9:24 PM EDT — narrowed: main pzai.systems index OUT, only customer-conversion surfaces IN):
✅ IN SCOPE — only audit/edit these:
  • https://pzai.systems/restaurant (THE squeeze page) → /root/pzai-systems-official-website/restaurant/
  • https://pzai.systems/interview-restaurants         → /root/pzai-systems-official-website/interview-restaurants/
  • https://pzai.systems/welcome (post-trial)          → /root/pzai-systems-official-website/welcome/
  • https://pzai.systems/keep-going (post-trial)       → /root/pzai-systems-official-website/keep-going/
  • Restaurant master template                          → /root/pzai-systems-official-website/templates/restaurant/
  • Postcard v7                                         → /root/pzai-systems-official-website/postcard-restaurant-v7*.html
  • A2P compliance pages                                → /root/pzai-systems-official-website/privacy-policy/, /terms-and-conditions/
  • Alex SMS handler (load-bearing for sms.pzai.systems demo flow) → /root/website-pipeline/services/prospects/web.py
  • Restaurant master template                       → /root/pzai-systems-official-website/templates/restaurant/

❌ OUT OF SCOPE — NEVER audit/edit:
  • 🚨 /root/pzai-systems-official-website/index.html (the main pzai.systems page) — Mack
    2026-05-04 9:24 PM EDT: "Why is Obi-Wan correcting something that'\''s irrelevant, like
    the free website? Can you please give them the website that we'\''re actually correcting,
    which is pzai.systems/restaurant?" The main page is NOT the customer-facing surface.
    The squeeze (/restaurant) is. Hands off the main index until Mack explicitly asks.
  • 🚨 ANYTHING under /root/website-pipeline/ EXCEPT services/prospects/web.py and
    outreach/templates/. Mack 2026-05-04 8:09 PM EDT (HARD STOP, after Padmé kept editing
    outreach/templates/ in pipeline): "Can you please stop Padme from going to a website
    pipeline? Just stop it; it'\''s not our website." NO EXCEPTIONS for customer demo sites,
    scripts, or sites/.
  • /root/pzai-systems-official-website/how-it-works/, /faq/, /why-templates/,
    /updates-vs-upgrades/, /restaurant-website-studio/ — educational/internal pages, not
    the conversion surface. Don'\''t touch unless Mack asks.
  • /root/pzai-systems-official-website/specs/alex-pro-system-prompt.md — Alex Pro is a
    separate \$49/mo add-on. Don'\''t drift its pricing.
  • Any *.vercel.app subdomain that is a customer demo (marigold-modern, customer-name-here, etc.)
  • sms.pzai.systems/demo/{CODE} per-prospect demos
  • mold.html (internal scratch — non-canonical)
  • All 9 NON-RESTAURANT niche pages (gyms, nail-salons, spas, coffee-shops, bakeries,
    barbershops, tattoo-shops, wedding-venues, real-estate) in canonical — these are
    HIDDEN via vercel.json 301 → /restaurant. Auditing them now is wasted tokens.

If your finding is on an out-of-scope surface, DROP IT and pick a different finding on a canonical surface. Do not edit non-canonical files.


Mack 2026-05-02 evening locked the heartbeat redesign:
> "I want a really self-improving system. You keep coming back. ''Hey Mac,
>  I saw this one mistake we did with the text. It''s not consistent.''
>  Pricing isn''t a checkbox — it''s an area of purpose. You''re not done
>  after #8. Pricing consistency is just 3% of pricing purpose."

This fire picks ONE (domain × lens) pair from the scoreboard and digs in.
NEVER say "queue clear" or "nothing actionable today" — those are banned
phrasings that violate Mack''s explicit design. If a check would be redundant,
research best-in-class for the domain instead. There is ALWAYS a deeper question.

YOUR PAIR THIS FIRE:
- DOMAIN: '"$DOMAIN_EMOJI $DOMAIN"' — '"$DOMAIN_SCOPE"'
- LENS: '"$LENS"' — '"$LENS_Q"'

PROCESS:
1. Identify the surface(s) for this domain. Examples per domain:
   - Pricing → main sales page, restaurant squeeze, customize page, niche pages, sample messages mentioning fees
   - Alex / Texting → Alex SMS handler config, sample message templates, text-templates dir, A2P submission text
   - Restaurant Site → /root/pzai-systems-official-website/restaurant/index.html + the master template
   - Outreach / Marketing → ⚠️ TEMPORARILY: only audit postcard-restaurant-v*.html in /root/pzai-systems-official-website/. Outreach templates have NOT YET been migrated from /root/website-pipeline/outreach/templates/ to canonical (Mack 2026-05-04 8:09 PM EDT — migration in progress). Until those are migrated, only audit canonical-side outreach. If you can'\''t find anything actionable in canonical for this domain, RESEARCH best-in-class for outreach instead of auditing.
   - Brand / Voice → CLAUDE.md voice rules, copy across all surfaces, naming
   - Onboarding / Setup → interview-restaurants/, restaurant-website-studio/, post-purchase email/SMS

2. Apply the lens "'"$LENS"'" — '"$LENS_Q"'

3. Find ONE specific finding. Output MUST follow this LAB-NOTEBOOK format (Mack 2026-05-03 2:38 PM EDT — he reads these to LEARN what we'\''re learning, not just track changes). All 6 fields required:

   🔬 Audit: '"$DOMAIN"' × '"$LENS"' — Severity N/10 — [PASS / SHIPPED / NEEDS-DECISION]
   📍 Surface: <file:line or URL>
   📋 Before: "<literal text/HTML being changed, ≤200 chars>"
   🔎 Finding: <one-sentence specific observation, NOT generic>
   ✏️ After (or PROPOSED): "<literal new text>"
   💡 Why (the learning): <best-in-class research or framework — Hormozi / Cialdini / competitor URL — that informed the choice. THIS is the value-add Mack reads to LEARN about his domain.>
   📦 Apply elsewhere: <list of OTHER surfaces with the same issue that should get the same fix>
   🔗 Links (MANDATORY — Mack 2026-05-10 3:30 PM EDT "put links up on all these updates"):
     - Live: <https URL of customer-facing page if applicable, e.g. https://web.pzai.systems/postcard-restaurant-v7-back.html>
     - Commit: <https://github.com/pzaisystems/REPO/commit/SHA>
     - File: <https://github.com/pzaisystems/REPO/blob/main/PATH#LSTART-LEND>
     If a link doesn't apply (e.g. no customer-facing live URL for an internal config file), write "n/a" — never omit the line. Mack reads on his phone; raw paths and bare commit SHAs aren't tappable.

SEVERITY SCALE (Mack 2026-05-03 5:44 PM EDT — flipped from "10=worst" to "1=worst" because P0/P1/CVSS convention is universal):
   1 = catastrophic / customer-blocking / brand-damaging
   2 = serious / actively losing leads or money
   3 = important / clear conversion gap
   4-6 = moderate / reversible polish, "should fix"
   7-9 = minor / cosmetic / nice-to-have
   10 = trivial / no real impact

4. ACTION (use the FLIPPED scale above — lower number = worse):
   - Severity ≥ 7: append the LAB-NOTEBOOK report to '"$RESEARCH"' under the appropriate domain heading. Do NOT ping Mack.
   - Severity 3-6 + reversible: ship the fix (commit + push). Post the FULL LAB-NOTEBOOK report to PreContext via `YODA_AUTHOR='"$DISPATCH_AGENT_LOWER"' bash /root/scripts/precontext-reply.sh "<message>"`. Include the commit URL in the Action field at the bottom. Mack 2026-05-05 10:10 AM EDT lifted the auto-ship floor from 4 to 3: "I'\''m allowing all the changes that you guys make because we'\''ve made refinements already... just ship it and just tell me what happened." Reversible polish/copy/anchor fixes ship without ping.
   - Severity ≤ 2: PING Mack via `YODA_AUTHOR='"$DISPATCH_AGENT_LOWER"' bash /root/scripts/precontext-reply.sh "<message>"` with the LAB-NOTEBOOK report + 2-3 explicit options under "Action". Do NOT auto-ship — Mack picks. Sev 1-2 = catastrophic / serious money-losing / brand-damaging — these need his eyes. Also: any NEW PRODUCT decision (like a pricing tier change) regardless of severity → ping, do not ship.

POSTING IDENTITY (Mack 2026-05-03 6:31 PM EDT — per-agent author rendering): every PreContext post from this audit MUST set `YODA_AUTHOR='"$DISPATCH_AGENT_LOWER"'` so the chat renders YOUR identity ('"$DISPATCH_AGENT"'), not Yoda'\''s. The PWA renders distinct emoji + accent color per agent.

5. Append a JSON line to '"$FINDINGS"' with: {ts, pair_key="'"$PAIR_KEY"'", domain="'"$DOMAIN"'", lens="'"$LENS"'", severity, surface, issue, action_taken}.

6. Update '"$SCOREBOARD"' for this pair: set last_explored_at to NOW (UTC ISO), set last_finding_severity to the severity you assigned.

HARD RULES:
- Restaurant-only filter (memory: feedback_apply_restaurant_focus_filter.md). Skip non-restaurant niches.
- NO customer-website builds (memory: feedback_no_autonomous_customer_website_builds.md).
- One finding per fire. No barrage.
- Sonnet enough for routine. Escalate to Opus only if the lens needs deep research.
- NEVER write "queue clear" or "nothing actionable" — find SOMETHING. Best-in-class research is always available.

You have ~15 min of API time. One finding. Ship or escalate. Update scoreboard. Exit.'

PULSE_LOG="$PULSE_OUTPUT_DIR/$(date +%Y%m%d-%H%M%S)-heartbeat.log"
# Resolve the agent's persona directory so claude -p loads the right CLAUDE.md
# (Mack 2026-05-03 4:23 PM EDT — caught that Alex/Texting heartbeat shipped under
# Yoda context instead of Padmé context. Paperclip ticket alone isn't real
# delegation — claude -p needs to RUN inside the agent's persona dir.)
case "$DISPATCH_AGENT" in
  "Anakin")  AGENT_DIR="/root/website-pipeline/agents/anakin" ;;
  "Padme")   AGENT_DIR="/root/website-pipeline/agents/padme" ;;
  "Obi-Wan") AGENT_DIR="/root/website-pipeline/agents/obiwan" ;;
  "Luke")    AGENT_DIR="/root/website-pipeline/agents/luke" ;;
  "Leia")    AGENT_DIR="/root/website-pipeline/agents/leia" ;;
  *)         AGENT_DIR="/root/website-pipeline" ;;
esac
[ -f "$AGENT_DIR/CLAUDE.md" ] || AGENT_DIR="/root/website-pipeline"
log "agent persona dir: $AGENT_DIR"

log "firing audit heartbeat → $PULSE_LOG"

(
  cd "$AGENT_DIR" || cd /root/website-pipeline
  echo "=== Audit Heartbeat @ $(ts) — assigned to $DISPATCH_AGENT ==="
  echo "Pair: $DOMAIN × $LENS"
  echo "Persona dir: $AGENT_DIR"
  echo "Paperclip issue: $ISSUE_ID"
  echo ""
  echo "=== Output ==="
  echo "$PROMPT" | PRECONTEXT_BATCH_MODE=1 timeout "$TIMEOUT_SECS" "$CLAUDE_BIN" -p --model "$MODEL" 2>&1
  EXIT_CODE=$?
  echo ""
  echo "=== Exit: $EXIT_CODE @ $(ts) ==="

  # SCRIPT-OWNED scoreboard update — Mack 2026-05-04 1:37 PM EDT.
  # Previously the dispatched agent was supposed to write last_explored_at to
  # the scoreboard at the end of its prompt. Sonnet skipped that step roughly
  # 4 of 5 fires (caught by yoda-heartbeat-coverage-watchdog.sh — Alex/Texting
  # × Best-in-class picked 5× in 24h, scoreboard updated only once). Rotation
  # got stuck because picker sorts by oldest last_explored_at and the same
  # pair kept looking oldest.
  # Fix: script writes the timestamp itself after the agent exits, regardless
  # of whether the agent did. Severity stays whatever the agent wrote (agent
  # has the finding context); timestamp is reliability-critical.
  if [ "$EXIT_CODE" -eq 0 ]; then
    PAIR_KEY="$PAIR_KEY" SCOREBOARD="$SCOREBOARD" python3 - <<'PY'
import json, os
from datetime import datetime, timezone
sb_path = os.environ["SCOREBOARD"]
key = os.environ["PAIR_KEY"]
now_iso = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
with open(sb_path) as f:
    sb = json.load(f)
updated = False
for p in sb.get("pairs", []):
    if p.get("key") == key:
        p["last_explored_at"] = now_iso
        updated = True
        break
if updated:
    with open(sb_path, "w") as f:
        json.dump(sb, f, indent=2)
    print(f"[scoreboard] script-wrote last_explored_at={now_iso} for {key}")
else:
    print(f"[scoreboard] WARN: pair {key} not found")
PY
  fi

  # Lesson-extraction step (Mack 2026-05-05 12:23 PM EDT step 3 ship). After
  # a successful audit, ask Opus to extract ONE durable lesson and post it as
  # a candidate that Mack must explicitly approve or reject.
  if [ "$EXIT_CODE" -eq 0 ] && [ -x /root/scripts/yoda-extract-lesson-candidate.sh ]; then
    /root/scripts/yoda-extract-lesson-candidate.sh \
      "$DISPATCH_AGENT" "$AGENT_DIR" "$PAIR_KEY" "$PULSE_LOG" "" \
      >> "$LOG" 2>&1 || true
  fi

  # Close out the Paperclip issue so the dashboard reflects completion + assignee
  if [ -n "$ISSUE_ID" ]; then
    if [ "$EXIT_CODE" -eq 0 ]; then
      /root/scripts/paperclip-dispatch.sh complete "$ISSUE_ID" "Audit complete. Findings appended to heartbeat-research.md + heartbeat-findings.jsonl." 2>>"$LOG" || true
    else
      /root/scripts/paperclip-dispatch.sh comment "$ISSUE_ID" "Audit exited $EXIT_CODE — see $PULSE_LOG" 2>>"$LOG" || true
    fi
  fi
) > "$PULSE_LOG" 2>&1 &

PULSE_PID=$!
disown 2>/dev/null
log "spawned audit pid=$PULSE_PID"
exit 0
