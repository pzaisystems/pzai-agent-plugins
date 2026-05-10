#!/bin/bash
# yoda-apply-skill-lessons.sh
#
# Cron-driven companion to yoda-extract-lesson-candidate.sh. Scans recent
# PreContext inbound messages for "APPROVE LESSON-..." or "REJECT
# LESSON-..." commands. For each match:
# - APPROVE → append the lesson to the agent's persona file, mark candidate
#   "approved", commit + push the persona repo if it has a git remote
# - REJECT  → mark candidate "rejected"
#
# Mack 2026-05-10 12:51 AM EDT reversed the explicit-gate model:
# "No more asking for approvals for new behaviors for anyone. I trust that
# it's good. But keep bringing in the progress reports." Pending candidates
# now auto-approve on each pass. Inbound APPROVE/REJECT commands in chat are
# still honored for legacy reasons, but only REJECT changes anything (an
# auto-approved lesson is idempotent and a manual APPROVE is a no-op).
# Original explicit-gate design: Mack 2026-05-05 12:23 PM EDT.
#
# Idempotent — once a candidate is approved/rejected it's never reapplied.
#
# Run via cron (every ~15 min) or manually anytime.

set -u

CHAT_LOG=/root/website-pipeline/logs/precontext-chat.jsonl
CANDIDATES_LOG=/root/website-pipeline/logs/skill-lesson-candidates.jsonl
APPLY_LOG=/root/website-pipeline/logs/skill-lesson-apply.log

if [ ! -s "$CANDIDATES_LOG" ]; then
  exit 0  # No candidates to process
fi

# Build (id, status) map from the candidates JSONL.
# Then scan inbound chat for APPROVE/REJECT commands. Apply each.
python3 <<'PY' >> "$APPLY_LOG" 2>&1
import json, re, os, datetime, subprocess, pathlib

CHAT = "/root/website-pipeline/logs/precontext-chat.jsonl"
CANDS = "/root/website-pipeline/logs/skill-lesson-candidates.jsonl"

def load_candidates():
    rows = []
    if os.path.exists(CANDS):
        with open(CANDS) as f:
            for line in f:
                try: rows.append(json.loads(line))
                except: pass
    return rows

def save_candidates(rows):
    with open(CANDS, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")

def scan_chat_for_commands():
    """Return list of (action, lesson_id, msg_ts) tuples from inbound."""
    cmds = []
    if not os.path.exists(CHAT):
        return cmds
    pattern = re.compile(r"\b(APPROVE|REJECT)\s+(LSN-[A-Z0-9]+-\d+-[A-Z0-9]+)\b", re.IGNORECASE)
    with open(CHAT) as f:
        for line in f:
            try:
                row = json.loads(line)
            except:
                continue
            if row.get("direction") != "in":
                continue
            content = row.get("content", "") or ""
            for m in pattern.finditer(content):
                cmds.append((m.group(1).upper(), m.group(2).upper(), row.get("ts", "")))
    return cmds

def append_lesson_to_persona(persona_dir, lesson, lesson_id, agent, pair):
    """Append a one-line lesson bullet to the agent's CLAUDE.md persona."""
    persona_md = os.path.join(persona_dir, "CLAUDE.md")
    if not os.path.exists(persona_md):
        print(f"  [warn] persona file not found: {persona_md}")
        return False
    today = datetime.date.today().isoformat()
    bullet = f"- {today} ({lesson_id}, {pair}): {lesson}\n"
    # Find or create a "## Skill Lessons (auto-appended)" section.
    # Canonical layout: marker line, then trailer description in italics, then a
    # blank line, then bullets. New bullets go AT THE TOP of the bullet list.
    # The bug we're fixing: prior versions inserted bullets directly after the
    # marker line, which left any trailer line floating mid-section if it existed.
    with open(persona_md) as f:
        content = f.read()
    marker = "## Skill Lessons (auto-appended)"
    canonical_trailer = "_Lessons compounded from approved audit candidates. Each entry is dated + tagged with the originating audit pair. Read every bullet before picking a finding — if a current surface matches a past pattern, that's the priority._"
    if marker in content:
        # Detect existing trailer (any italic _..._ line on the line after marker).
        # Insert the new bullet right after the trailer (with blank line preserved).
        idx = content.find(marker)
        # Find end-of-marker-line.
        line_end = content.find("\n", idx)
        if line_end == -1:
            line_end = len(content)
        rest = content[line_end + 1:]
        # If next non-empty line is a trailer (starts with _), insert after it.
        rest_lines = rest.split("\n")
        insert_after_lines = 0
        for i, line in enumerate(rest_lines):
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith("_") and stripped.endswith("_"):
                insert_after_lines = i + 1
            break
        if insert_after_lines > 0:
            # Reassemble: keep marker line, lines through trailer, then bullet, then rest.
            head = content[:line_end + 1] + "\n".join(rest_lines[:insert_after_lines]) + "\n"
            tail = "\n".join(rest_lines[insert_after_lines:])
            # Ensure a blank line after trailer if missing.
            if not tail.startswith("\n"):
                head += "\n"
            content = head + bullet + tail
        else:
            # No trailer — fall back to old behavior (bullet right after marker).
            content = content.replace(marker + "\n", marker + "\n" + bullet, 1)
    else:
        # Add the section at the end with canonical layout.
        if not content.endswith("\n"):
            content += "\n"
        content += "\n" + marker + "\n"
        content += canonical_trailer + "\n\n"
        content += bullet
    with open(persona_md, "w") as f:
        f.write(content)
    print(f"  [ok] appended to {persona_md}")
    return True

def main():
    cands = load_candidates()
    if not cands:
        return
    cmds = scan_chat_for_commands()
    by_id = {c["id"]: c for c in cands}
    changed = False
    # Mack 2026-05-10 12:51 AM EDT: "No more asking for approvals for new
    # behaviors for anyone. I trust that it's good." Any pending candidate
    # auto-approves on the next pass. Inbound APPROVE/REJECT commands still
    # work for legacy reasons but are no longer required.
    for cand in cands:
        if cand.get("status") != "pending":
            continue
        now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
        ok = append_lesson_to_persona(
            cand.get("persona_dir", ""),
            cand.get("lesson", ""),
            cand["id"],
            cand.get("agent", ""),
            cand.get("pair", ""),
        )
        cand["status"] = "approved" if ok else "approve_failed"
        cand["decided_at"] = now_iso
        cand["decided_via"] = "auto-approved per Mack 2026-05-10"
        changed = True
        print(f"[{now_iso}] AUTO-APPROVED {cand['id']} → {cand.get('agent')}")
    for action, lid, ts in cmds:
        cand = by_id.get(lid)
        if not cand:
            continue
        if cand.get("status") in ("approved", "rejected", "approve_failed"):
            continue  # Idempotent — already processed (incl. just-auto-approved)
        now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
        if action == "REJECT":
            cand["status"] = "rejected"
            cand["decided_at"] = now_iso
            cand["decided_via"] = ts
            changed = True
            print(f"[{now_iso}] REJECTED {lid}")
    if changed:
        save_candidates(cands)

main()
PY

exit 0
