#!/bin/bash
# PreToolUse Hook: SWIFT TRAP SCANNER
# Fires before git commit/push. Checks staged Swift diffs for Trinity's 4 known
# trap patterns that cause silent build failures (Trinity has no xcodebuild).
#
# Install on Maximus (or any Claude Code agent building iOS):
#   cp hooks/swift-trap-scanner.sh .claude/hooks/
#   chmod +x .claude/hooks/swift-trap-scanner.sh
#   Add to settings.json PreToolUse hooks with matcher: "Bash"

TOOL_JSON=$(cat)
COMMAND=$(echo "$TOOL_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('command',''))" 2>/dev/null)

# Only fire on git commit or git push
if ! echo "$COMMAND" | grep -qE 'git (commit|push)'; then
    exit 0
fi

# Only if Swift files are staged
STAGED_SWIFT=$(git diff --staged --name-only 2>/dev/null | grep '\.swift$')
if [ -z "$STAGED_SWIFT" ]; then
    exit 0
fi

STAGED_DIFF=$(git diff --staged -- '*.swift' 2>/dev/null)
WARNINGS=""

# TRAP 1: ObservableObject / @Published / Timer.publish without import Combine
for file in $STAGED_SWIFT; do
    FILE_CONTENT=$(git show ":$file" 2>/dev/null)
    if echo "$FILE_CONTENT" | grep -qE '(ObservableObject|@Published|Timer\.publish)'; then
        if ! echo "$FILE_CONTENT" | grep -q 'import Combine'; then
            WARNINGS="$WARNINGS\n• TRAP 1 in $file: uses ObservableObject/@Published but missing 'import Combine'"
        fi
    fi
done

# TRAP 2: Type name collision with SwiftUI primitives
if echo "$STAGED_DIFF" | grep -qE '^\+(struct|class|enum) (Circle|Triangle|Rectangle|Path)[ <{]'; then
    MATCH=$(echo "$STAGED_DIFF" | grep -oE '(struct|class|enum) (Circle|Triangle|Rectangle|Path)' | head -1)
    WARNINGS="$WARNINGS\n• TRAP 2: '$MATCH' shadows SwiftUI primitive. Prefix it (e.g. CommunityCircle, PinStemTriangle)"
fi

# TRAP 3: Invented Firebase APIs
if echo "$STAGED_DIFF" | grep -qE '^\+.*(getDocument\(as:|\.asOptional\(\))'; then
    WARNINGS="$WARNINGS\n• TRAP 3: Invented Firebase API. Real API: let snapshot = try await ref.getDocument(); let model = try snapshot.data(as: T.self)"
fi

# TRAP 4: await inside ?? operator
if echo "$STAGED_DIFF" | grep -qE '^\+.*\?\? \(await '; then
    WARNINGS="$WARNINGS\n• TRAP 4: 'value ?? (await fn())' won't compile. Use explicit if-let instead."
fi

if [ -n "$WARNINGS" ]; then
    REASON="Swift Trap Scanner: fix before committing:$WARNINGS"
    echo "{\"decision\": \"block\", \"reason\": $(printf '%s' "$REASON" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}"
fi

exit 0
