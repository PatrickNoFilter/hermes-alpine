#!/bin/bash
# Watchdog for PR #3395 (nesquena/hermes-webui)
# Silent if nothing changed. Prints change summary on transition.
# Unauthenticated: GitHub allows 60 reads/hour per IP.

set -u
PR="3395"
REPO="nesquena/hermes-webui"
STATE_FILE="/tmp/hermes-pr-${PR}.state"
GIT_BASE="https://api.github.com"

if [ ! -f "$STATE_FILE" ]; then
    echo "first_run|$(date -Iseconds)" > "$STATE_FILE"
fi

LAST_STATE=$(cut -d'|' -f1 "$STATE_FILE")
LAST_DETAIL=$(cut -d'|' -f2- "$STATE_FILE")
NOW=$(date -Iseconds)

# --- Pull PR + statuses (parallel) ---
PR_JSON=$(curl -sf -m 15 -H "Accept: application/vnd.github.v3+json" \
    "$GIT_BASE/repos/$REPO/pulls/$PR" 2>/dev/null) || {
    echo "[$NOW] ⚠️  GitHub API unreachable; will retry next tick"
    exit 0
}

STATE=$(echo "$PR_JSON"       | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('state','?')+':'+str(bool(d.get('merged'))))" 2>/dev/null)
COMMENTS=$(echo "$PR_JSON"    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('comments','?'))" 2>/dev/null)
COMMIT_COUNT=$(echo "$PR_JSON"| python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('commits','?'))" 2>/dev/null)
ADD=$(echo "$PR_JSON"         | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('additions','?'))" 2>/dev/null)
DEL=$(echo "$PR_JSON"         | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('deletions','?'))" 2>/dev/null)

SHA=$(echo "$PR_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('head',{}).get('sha',''))" 2>/dev/null)

# Combined status
STATUS=$(curl -sf -m 15 -H "Accept: application/vnd.github.v3+json" \
    "$GIT_BASE/repos/$REPO/commits/$SHA/status" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('state','none'))" 2>/dev/null)

# Check runs
CHECKRUNS=$(curl -sf -m 15 -H "Accept: application/vnd.github.v3+json" \
    "$GIT_BASE/repos/$REPO/commits/$SHA/check-runs" 2>/dev/null | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
runs = d.get('check_runs', [])
if not runs:
    print('none')
else:
    print('|'.join(f\"{r['name']}={r['status']}/{r.get('conclusion') or 'pending'}\" for r in runs))
" 2>/dev/null)

# New comments since last check (uses last-known comment count from state)
NEW_DETAIL="state=${STATE}|status=${STATUS}|comments=${COMMENTS}|commits=${COMMIT_COUNT}|+${ADD}/-${DEL}|runs=${CHECKRUNS}"

# If state is closed+merged, this is a final notification
if [ "$STATE" = "closed:true" ]; then
    if [ "$LAST_STATE" != "closed:true" ]; then
        echo "[$NOW] 🎉 PR #${PR} MERGED into nesquena/hermes-webui!"
        echo "     $NEW_DETAIL"
        echo "     URL: https://github.com/${REPO}/pull/${PR}"
        echo "merged|$NEW_DETAIL" > "$STATE_FILE"
    fi
    exit 0
fi

if [ "$STATE" = "closed:false" ]; then
    if [ "$LAST_STATE" != "closed:false" ]; then
        echo "[$NOW] ❌ PR #${PR} CLOSED (not merged)"
        echo "     $NEW_DETAIL"
        echo "     URL: https://github.com/${REPO}/pull/${PR}"
        echo "closed|$NEW_DETAIL" > "$STATE_FILE"
    fi
    exit 0
fi

# PR still open — notify on any change
if [ "$NEW_DETAIL" != "$LAST_DETAIL" ]; then
    echo "[$NOW] 🔄 PR #${PR} changed:"
    echo "     was: $LAST_DETAIL"
    echo "     now: $NEW_DETAIL"
    echo "     URL: https://github.com/${REPO}/pull/${PR}"
    echo "open|$NEW_DETAIL" > "$STATE_FILE"
    exit 0
fi

# No change — silent
exit 0
