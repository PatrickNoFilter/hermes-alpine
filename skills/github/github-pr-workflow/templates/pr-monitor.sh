#!/bin/bash
# PR state-change watchdog.
# Usage:  pr-monitor.sh <PR_NUMBER> <OWNER/REPO>
# Schedule via cronjob (no_agent=true) for silent in-background polling.
# Prints a one-line transition notice on change. Silent on no-change.
# Final-state events (merged/closed) only fire on the first transition.
#
# Unauthenticated reads — 60/hr per IP limit is fine for 5–10 min polling
# on public repos. For private repos, set GH_TOKEN env var before scheduling.
#
# Companion: see SKILL.md §4a "Long-running async PR monitoring".

set -u
PR="$1"
REPO="$2"
STATE_FILE="/tmp/hermes-pr-${PR}.state"
GIT_BASE="https://api.github.com"
AUTH_HEADER=()
[ -n "${GH_TOKEN:-}" ] && AUTH_HEADER=(-H "Authorization: token $GH_TOKEN")

# Initialize state file on first run
[ -f "$STATE_FILE" ] || echo "first_run|$(date -Iseconds)" > "$STATE_FILE"
LAST=$(cut -d'|' -f2- "$STATE_FILE")
NOW=$(date -Iseconds)

# Fetch PR JSON
PR_JSON=$(curl -sf -m 15 -H "Accept: application/vnd.github.v3+json" \
    "${AUTH_HEADER[@]}" \
    "$GIT_BASE/repos/$REPO/pulls/$PR" 2>/dev/null) || {
    echo "[$NOW] ⚠️  GitHub API unreachable for PR #${PR}; will retry next tick"
    exit 0
}

SHA=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['head']['sha'])" 2>/dev/null)
STATE=$(echo "$PR_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state']+':'+str(bool(d.get('merged'))))" 2>/dev/null)
COMMENTS=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('comments','?'))" 2>/dev/null)
COMMITS=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('commits','?'))" 2>/dev/null)
ADD=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('additions','?'))" 2>/dev/null)
DEL=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('deletions','?'))" 2>/dev/null)

STATUS=$(curl -sf -m 15 -H "Accept: application/vnd.github.v3+json" \
    "${AUTH_HEADER[@]}" \
    "$GIT_BASE/repos/$REPO/commits/$SHA/status" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('state','none'))" 2>/dev/null)

CHECKRUNS=$(curl -sf -m 15 -H "Accept: application/vnd.github.v3+json" \
    "${AUTH_HEADER[@]}" \
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

NEW="state=${STATE}|status=${STATUS}|comments=${COMMENTS}|commits=${COMMITS}|+${ADD}/-${DEL}|runs=${CHECKRUNS}"
URL="https://github.com/${REPO}/pull/${PR}"

# Terminal states — only fire once
if [ "$STATE" = "closed:true" ] && [ "$LAST" != "state=closed:true"* ]; then
    echo "[$NOW] 🎉 PR #${PR} MERGED into ${REPO}!"
    echo "     $NEW"
    echo "     $URL"
    echo "merged|$NEW" > "$STATE_FILE"
    exit 0
fi
if [ "$STATE" = "closed:false" ] && [ "$LAST" != "state=closed:false"* ]; then
    echo "[$NOW] ❌ PR #${PR} CLOSED (not merged)"
    echo "     $NEW"
    echo "     $URL"
    echo "closed|$NEW" > "$STATE_FILE"
    exit 0
fi

# Open — notify on any change, silent on no-change
if [ "$NEW" != "$LAST" ]; then
    echo "[$NOW] 🔄 PR #${PR} changed:"
    echo "     was: $LAST"
    echo "     now: $NEW"
    echo "     $URL"
    echo "open|$NEW" > "$STATE_FILE"
fi

# else: exit 0 with no stdout = silent (watchdog pattern)
exit 0
