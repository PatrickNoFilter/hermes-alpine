---
name: github-pr-workflow
description: "GitHub PR lifecycle: branch, commit, open, update, CI, merge. Pushing to a branch with an open PR auto-updates it; PATCH /pulls/N updates title/body; POST /issues/N/comments posts comments."
version: 1.3.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [GitHub, Pull-Requests, CI/CD, Git, Automation, Merge]
    related_skills: [github-auth, github-code-review]
---

# GitHub Pull Request Workflow

Complete guide for managing the PR lifecycle. Each section shows the `gh` way first, then the `git` + `curl` fallback for machines without `gh`.

## Prerequisites

- Authenticated with GitHub (see `github-auth` skill)
- Inside a git repository with a GitHub remote

### Quick Auth Detection

```bash
# Determine which method to use throughout this workflow
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  AUTH="gh"
else
  AUTH="git"
  # Ensure we have a token for API calls
  if [ -z "$GITHUB_TOKEN" ]; then
    if [ -f ~/.hermes/.env ] && grep -q "^GITHUB_TOKEN=" ~/.hermes/.env; then
      GITHUB_TOKEN=$(grep "^GITHUB_TOKEN=" ~/.hermes/.env | head -1 | cut -d= -f2 | tr -d '\n\r')
    elif grep -q "github.com" ~/.git-credentials 2>/dev/null; then
      GITHUB_TOKEN=$(grep "github.com" ~/.git-credentials 2>/dev/null | head -1 | sed 's|https://[^:]*:\([^@]*\)@.*|\1|')
    fi
  fi
fi
echo "Using: $AUTH"
```

### Extracting Owner/Repo from the Git Remote

Many `curl` commands need `owner/repo`. Extract it from the git remote:

```bash
# Works for both HTTPS and SSH remote URLs
REMOTE_URL=$(git remote get-url origin)
OWNER_REPO=$(echo "$REMOTE_URL" | sed -E 's|.*github\.com[:/]||; s|\.git$||')
OWNER=$(echo "$OWNER_REPO" | cut -d/ -f1)
REPO=$(echo "$OWNER_REPO" | cut -d/ -f2)
echo "Owner: $OWNER, Repo: $REPO"
```

---

## 1. Branch Creation

This part is pure `git` — identical either way:

```bash
# Make sure you're up to date
git fetch origin
git checkout main && git pull origin main

# Create and switch to a new branch
git checkout -b feat/add-user-authentication
```

Branch naming conventions:
- `feat/description` — new features
- `fix/description` — bug fixes
- `refactor/description` — code restructuring
- `docs/description` — documentation
- `ci/description` — CI/CD changes

## 2. Making Commits

Use the agent's file tools (`write_file`, `patch`) to make changes, then commit:

```bash
# Stage specific files
git add src/auth.py src/models/user.py tests/test_auth.py

# Commit with a conventional commit message
git commit -m "feat: add JWT-based user authentication

- Add login/register endpoints
- Add User model with password hashing
- Add auth middleware for protected routes
- Add unit tests for auth flow"
```

Commit message format (Conventional Commits):
```
type(scope): short description

Longer explanation if needed. Wrap at 72 characters.
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `ci`, `chore`, `perf`

## 3. Pushing and Creating a PR

### Push the Branch (same either way)

```bash
git push -u origin HEAD
```

### Create the PR

**With gh:**

```bash
gh pr create \
  --title "feat: add JWT-based user authentication" \
  --body "## Summary
- Adds login and register API endpoints
- JWT token generation and validation

## Test Plan
- [ ] Unit tests pass

Closes #42"
```

Options: `--draft`, `--reviewer user1,user2`, `--label "enhancement"`, `--base develop`

**With git + curl:**

```bash
BRANCH=$(git branch --show-current)

curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$OWNER/$REPO/pulls \
  -d "{
    \"title\": \"feat: add JWT-based user authentication\",
    \"body\": \"## Summary\nAdds login and register API endpoints.\n\nCloses #42\",
    \"head\": \"$BRANCH\",
    \"base\": \"main\"
  }"
```

The response JSON includes the PR `number` — save it for later commands.

To create as a draft, add `"draft": true` to the JSON body.

## 4. Monitoring CI Status

### Check CI Status

**CRITICAL PITFALL — Always verify CI via API, never trust the PR body.**

When someone hands you a PR URL and says "check this PR," the PR body may state "All N tests passing" but CI checks can fail *independently* — supply-chain audits, nix infrastructure, contributor attribution checks, etc. Unit test status ≠ CI check status. **Always query the check-runs endpoint** for the ground truth, even if the PR body reports success.

The `check-runs` endpoint returns GitHub Actions workflow runs and other check suites. The `status` endpoint returns commit statuses (e.g., branch protection checks). You need both for a complete picture. Some check suites only appear in `check-runs`.

**With gh:**

```bash
# One-shot check
gh pr checks

# Watch until all checks finish (polls every 10s)
gh pr checks --watch
```

**With git + curl:**

```bash
# Get the latest commit SHA on the current branch
SHA=$(git rev-parse HEAD)

# Query the combined status (commit statuses — branch protection checks)
curl -s \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/$OWNER/$REPO/commits/$SHA/status \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f\"Overall: {data['state']}\")
for s in data.get('statuses', []):
    print(f\"  {s['context']}: {s['state']} - {s.get('description', '')}\")
"

# Also check GitHub Actions check runs (separate endpoint — more detailed)
curl -s \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/$OWNER/$REPO/commits/$SHA/check-runs \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
failures = []
for cr in data.get('check_runs', []):
    concl = cr.get('conclusion') or 'pending'
    name = cr['name']
    print(f\"  {name}: {cr['status']} / {concl}\")
    if concl == 'failure':
        failures.append(name)
if failures:
    print(f'\\n❌ FAILING CHECKS ({len(failures)}):')
    for f in failures:
        print(f'  - {f}')
else:
    print(f'\\n✅ All {len(data.get(\"check_runs\", []))} checks passing')
"

### Poll Until Complete (git + curl)

```bash
# Simple polling loop — check every 30 seconds, up to 10 minutes
SHA=$(git rev-parse HEAD)
for i in $(seq 1 20); do
  STATUS=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    https://api.github.com/repos/$OWNER/$REPO/commits/$SHA/status \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['state'])")
  echo "Check $i: $STATUS"
  if [ "$STATUS" = "success" ] || [ "$STATUS" = "failure" ] || [ "$STATUS" = "error" ]; then
    break
  fi
  sleep 30
done
```

## 4. PR from a fork (when direct push is denied)

Most open-source contributions flow through a fork because the
contributor doesn't have write access to the upstream repo. The
pattern:

```bash
# 1. Fork the upstream (creates $USER/$REPO on your account)
curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$OWNER/$REPO/forks

# 2. Add the fork as a SEPARATE remote — don't replace origin
git remote add fork https://github.com/$USER_LOGIN/$REPO.git

# 3. Push the branch to the fork
git push -u fork <branch-name>

# 4. Open the PR with head = "<user>:<branch>", base = "master"
curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$OWNER/$REPO/pulls \
  -d '{"title": "...", "body": "...", "head": "'$USER_LOGIN':'$BRANCH'", "base": "master", "maintainer_can_modify": true}'
```

`maintainer_can_modify: true` lets the upstream maintainer push
follow-up commits to your branch — useful so they don't have to
wait for a re-push from you for small fixes.

**Note on token storage**: the `Authorization: token $GITHUB_TOKEN`
form above is fine *if* `$GITHUB_TOKEN` was loaded from a file
inside `execute_code` (so the literal token never appears in a
tool-call argument). See the `github-auth` skill's "Critical
pitfall" section for the full reasoning.

### Extracting a token from an `x-access-token:` URL in a git remote

Some setups (including forks authenticated via the GitHub CLI's
`gh auth login --with-token` flow) embed the token in the remote
URL itself, in the form
`https://x-access-token:TOKEN@github.com/owner/repo.git`.
Extracting the token from this URL in Python avoids a separate
.env read and works when no env var is set:

```python
import re, subprocess
remote_url = subprocess.check_output(
    ['git', 'config', '--get', 'remote.fork.url'], text=True
).strip()
m = re.search(r'x-access-token:([^@]+)@', remote_url)
token = m.group(1) if m else None
print(f'token: ...{token[-6:]}')  # print only the suffix, never the full token
```

Print only the token **suffix** (last 4–6 chars) when logging —
never the full token. The same `re.search` pattern works for the
older `https://TOKEN@github.com/owner/repo.git` form (without the
`x-access-token:` prefix) by changing the regex to
`r'://([^@]+)@github\.com/'`.

---

## 4a. Syncing a Feature Branch with Upstream (Fetch + Merge)

When a feature branch has diverged from `master` (or the base branch), CI
often shows `mergeable_state: dirty`, or you simply need the latest upstream
changes. The safest approach is **fetch + merge** (not fetch + rebase), because
merge is commutative and preserves the exact commit history that reviewers
already saw.

### When to sync

- CI shows `mergeable_state: dirty` → there's a merge conflict with the base.
- CI shows `mergeable_state: blocked` → required checks are pending, but if
  the branch is many commits behind, syncing first avoids a later `dirty`.
- You need a fix or API change that landed upstream since you branched.
- The PR has been open for a while and the branch has drifted behind (the
  maintainer may ask you to sync before review).

### The workflow

```bash
# 1. Fetch latest upstream
git fetch origin master   # or 'main', 'develop', etc.

# 2. Merge upstream into your feature branch
git checkout feat/my-feature
git merge origin/master

# 3. If no conflicts → push and done
git push origin HEAD

# 4. If conflicts → resolve each one
git status
# Shows "both modified: path/to/file.py" for each conflicted file
```

### Conflict resolution strategies

For each conflicted file, decide which version to keep:

| Situation | Action |
|-----------|--------|
| **Keep your feature branch version** | `git checkout HEAD -- path/to/file.py` then `git add path/to/file.py` |
| **Accept upstream version** | `git checkout --theirs -- path/to/file.py` then `git add path/to/file.py` |
| **Manual merge needed** | Edit the file, remove conflict markers, keep the desired code, `git add path/to/file.py` |

Decision factors for common conflict patterns:
- **Core logic / behavioral code** — keep your version if your change was
  deliberate (e.g. a platform-specific workaround). Accept upstream if their
  change is a refactor the project needs and your feature adapts to it.
- **CHANGELOG / docs** — keep your [Unreleased] section, insert upstream's
  new release entries below. Both histories are important.
- **Generated / lock files** — accept upstream (`--theirs`) and regenerate
  locally afterward.

After resolving all conflicts:

```bash
git status            # verify no conflicts remain
git add -A            # stage all resolved files
git commit --no-edit  # auto-generated merge commit message
git push origin HEAD
```

### Why merge over rebase

| | Merge | Rebase |
|--|-------|--------|
| **History** | Adds one merge commit | Rewrites branch commits |
| **Conflict effort** | Resolve once | May resolve per-commit |
| **Reviewer impact** | Existing review threads stay valid | Force-push loses inline reviews |

Default to **merge** for any branch that has been reviewed or has open
review threads. Use **rebase** only for branches never pushed or with no
open PR.

### After syncing

- Push and re-check CI: `mergeable_state` should change from `dirty` to
  `clean` (or `blocked` if checks still running).
- If the sync introduced upstream changes that affect your feature (e.g. a
  renamed function), fix build errors as new commits on the branch.

## 4b. Long-running async PR monitoring

A PR can take hours or days to land. In-session polling burns the
session's time budget. The watchdog pattern: a no-agent cron job
that polls the PR state, diffs against the last-known state, and
delivers a one-line transition notice to the chat when something
changes. Silent when nothing changed.

```bash
# ~/.hermes/scripts/pr-monitor.sh
#!/bin/bash
set -u
PR="$1"                # pass as cron arg, e.g. "3395"
REPO="$2"              # pass as cron arg, e.g. "owner/repo"
STATE_FILE="/tmp/hermes-pr-${PR}.state"
GIT_BASE="https://api.github.com"

# Initialize state file on first run
[ -f "$STATE_FILE" ] || echo "first_run|$(date -Iseconds)" > "$STATE_FILE"
LAST=$(cut -d'|' -f2- "$STATE_FILE")
NOW=$(date -Iseconds)

PR_JSON=$(curl -sf -m 15 -H "Accept: application/vnd.github.v3+json" \
    "$GIT_BASE/repos/$REPO/pulls/$PR" 2>/dev/null) || exit 0
SHA=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['head']['sha'])")
STATE=$(echo "$PR_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state']+':'+str(bool(d.get('merged'))))")
COMMENTS=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('comments','?'))")
COMMIT_COUNT=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('commits','?'))")
STATUS=$(curl -sf -m 15 -H "Accept: application/vnd.github.v3+json" \
    "$GIT_BASE/repos/$REPO/commits/$SHA/status" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('state','none'))" 2>/dev/null)

NEW="state=${STATE}|status=${STATUS}|comments=${COMMENTS}|commits=${COMMIT_COUNT}"

# Final events (terminal state — only notify on transition)
if [ "$STATE" = "closed:true" ] && [ "$LAST" != "closed:true" ]; then
    echo "[$NOW] 🎉 PR #${PR} MERGED into ${REPO}!  https://github.com/${REPO}/pull/${PR}"
    echo "merged|$NEW" > "$STATE_FILE"
    exit 0
fi
if [ "$STATE" = "closed:false" ] && [ "$LAST" != "closed:false" ]; then
    echo "[$NOW] ❌ PR #${PR} CLOSED (not merged)"
    echo "closed|$NEW" > "$STATE_FILE"
    exit 0
fi

# Open — notify on any change, silent on no-change
if [ "$NEW" != "$LAST" ]; then
    echo "[$NOW] 🔄 PR #${PR} changed: $NEW  https://github.com/${REPO}/pull/${PR}"
    echo "open|$NEW" > "$STATE_FILE"
fi
# else: exit 0 with no stdout = silent
```

Schedule it with the `cronjob` tool:

```python
cronjob(action="create", name="pr-3395-watchdog",
        schedule="every 10m",
        script="pr-monitor.sh",
        no_agent=True, deliver="origin")
```

Notes:
- **`no_agent=True`** makes the script the entire job — its stdout is
  delivered verbatim. No LLM round-trip, zero token cost.
- **Unauthenticated reads** for public repos are 60/hr per IP, plenty
  for 10-min polling. The same limit applies to any unauthenticated
  search / list / status poll — if the agent is searching GitHub
  interactively without a token (e.g. to find related issues), back
  off to one search per turn or batch the queries; hitting the limit
  returns `403 rate limit exceeded` and a 1-hour cool-off.
- **`deliver="origin"`** routes the notification back to the current
  chat. Default `"local"` is silent — change it.
- **Final-state handling**: the script writes `merged` or `closed` to
  the state file on terminal events, so subsequent runs are silent
  forever and the cron job can keep running without spamming.
- A ready-to-use version of this script lives at
  `templates/pr-monitor.sh` in this skill — copy and invoke it as
  `pr-monitor.sh <PR_NUMBER> <OWNER/REPO>` from a cron `script=`.

## 5. Auto-Fixing CI Failures

When CI fails, diagnose and fix. This loop works with either auth method.

### Step 1: Get Failure Details

**With gh:**

```bash
# List recent workflow runs on this branch
gh run list --branch $(git branch --show-current) --limit 5

# View failed logs
gh run view <RUN_ID> --log-failed
```

**With git + curl:**

```bash
BRANCH=$(git branch --show-current)

# List workflow runs on this branch
curl -s \
  -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO/actions/runs?branch=$BRANCH&per_page=5" \
  | python3 -c "
import sys, json
runs = json.load(sys.stdin)['workflow_runs']
for r in runs:
    print(f\"Run {r['id']}: {r['name']} - {r['conclusion'] or r['status']}\")"

# Get failed job logs (download as zip, extract, read)
RUN_ID=<run_id>
curl -s -L \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/$OWNER/$REPO/actions/runs/$RUN_ID/logs \
  -o /tmp/ci-logs.zip
cd /tmp && unzip -o ci-logs.zip -d ci-logs && cat ci-logs/*.txt
```

### Step 2: Fix and Push

After identifying the issue, use file tools (`patch`, `write_file`) to fix it:

```bash
git add <fixed_files>
git commit -m "fix: resolve CI failure in <check_name>"
git push
```

### Step 3: Verify

Re-check CI status using the commands from Section 4 above.

### Auto-Fix Loop Pattern

When asked to auto-fix CI, follow this loop:

1. Check CI status → identify failures
2. Read failure logs → understand the error
3. Use `read_file` + `patch`/`write_file` → fix the code
4. `git add . && git commit -m "fix: ..." && git push`
5. Wait for CI → re-check status
6. Repeat if still failing (up to 3 attempts, then ask the user)

## 6. Merging

**With gh:**

```bash
# Squash merge + delete branch (cleanest for feature branches)
gh pr merge --squash --delete-branch

# Enable auto-merge (merges when all checks pass)
gh pr merge --auto --squash --delete-branch
```

**With git + curl:**

```bash
PR_NUMBER=<number>

# Merge the PR via API (squash)
curl -s -X PUT \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER/merge \
  -d "{
    \"merge_method\": \"squash\",
    \"commit_title\": \"feat: add user authentication (#$PR_NUMBER)\"
  }"

# Delete the remote branch after merge
BRANCH=$(git branch --show-current)
git push origin --delete $BRANCH

# Switch back to main locally
git checkout main && git pull origin main
git branch -d $BRANCH
```

Merge methods: `"merge"` (merge commit), `"squash"`, `"rebase"`

### Enable Auto-Merge (curl)

```bash
# Auto-merge requires the repo to have it enabled in settings.
# This uses the GraphQL API since REST doesn't support auto-merge.
PR_NODE_ID=$(curl -s \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['node_id'])")

curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/graphql \
  -d "{\"query\": \"mutation { enablePullRequestAutoMerge(input: {pullRequestId: \\\"$PR_NODE_ID\\\", mergeMethod: SQUASH}) { clientMutationId } }\"}"
```

## 7. Complete Workflow Example

```bash
# 1. Start from clean main
git checkout main && git pull origin main

# 2. Branch
git checkout -b fix/login-redirect-bug

# 3. (Agent makes code changes with file tools)

# 4. Commit
git add src/auth/login.py tests/test_login.py
git commit -m "fix: correct redirect URL after login

Preserves the ?next= parameter instead of always redirecting to /dashboard."

# 5. Push
git push -u origin HEAD

# 6. Create PR (picks gh or curl based on what's available)
# ... (see Section 3)

# 7. Monitor CI (see Section 4)

# 8. Merge when green (see Section 6)
```

## 8. Updating Existing PRs

After the initial `POST /pulls`, the same branch can be
force-updated with more commits and the PR is **automatically
updated** by GitHub — no re-create, no re-open. Pushing to a
branch that already has an open PR triggers GitHub to recompute
the PR's diff, commit count, and `additions`/`deletions`. The PR
URL stays the same.

```bash
# Just push — GitHub auto-updates the open PR
git push fork HEAD
# Or force-push if the maintainer approved a rebase/squash
git push fork HEAD --force-with-lease
```

When pushing **adds commits** the auto-update is non-destructive
(PR stays open, review state preserved). When the push is a
**force-push** (history rewritten), in-progress review threads
on individual commits may be lost — use `--force-with-lease`
(not `--force`) so a concurrent push from a teammate doesn't
get clobbered silently.

### Update PR title and/or body

```bash
PR_NUMBER=3407

curl -s -X PATCH \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER \
  -d "{
    \"title\": \"fix(server): ignore SIGPIPE + diag shim + fix(updates): outlast cgroup-kill window\",
    \"body\": \"## Summary\n...full updated body...\"
  }"
```

Only the fields you include in the body are updated. Omit
`title` to keep it; omit `body` to keep it. Common pattern:
when the PR scope grows (e.g. you discovered a second root
cause while testing the first fix), update both title and
body to reflect the broader scope, and post a summary
comment so reviewers know what changed since the last review.

### Post a comment

```bash
PR_NUMBER=3407

curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$OWNER/$REPO/issues/$PR_NUMBER/comments \
  -d "{\"body\": \"## What changed since last review\n\n...\"}"
```

Note: comments live on the **issue** endpoint, not the **pulls**
endpoint. The PR's issue number is the same as the PR number
(GitHub treats PRs as issues under the hood).

### Read PR metadata (for verifying what was changed)

```bash
PR_NUMBER=3407

curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER" \
  | python3 -c "
import sys, json
pr = json.load(sys.stdin)
print(f\"title: {pr['title']}\")
print(f\"state: {pr['state']}, merged: {pr.get('merged')}, draft: {pr['draft']}\")
print(f\"commits: {pr['commits']}, additions: {pr['additions']}, deletions: {pr['deletions']}\")
print(f\"changed_files: {pr['changed_files']}, mergeable: {pr.get('mergeable')}, mergeable_state: {pr.get('mergeable_state')}\")
print(f\"body: {len(pr.get('body') or '')} chars\")"
```

`mergeable_state: blocked` is not a code issue — it usually
means a branch-protection rule (required status checks,
required reviews, etc.) is not yet satisfied. The maintainer
needs to enable auto-merge, approve the required check, or
adjust the rule. It does NOT mean the code is wrong.

`mergeable_state: dirty` means the branch is behind the base
branch and has a merge conflict. Fix by `git pull --rebase
origin master` then re-push, or ask the maintainer to merge
master into your branch.

### List commits in a PR (for verifying the commit list matches the body)

```bash
PR_NUMBER=3407

curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER/commits?per_page=20" \
  | python3 -c "
import sys, json
for c in json.load(sys.stdin):
    print(f\"  {c['sha'][:10]} {c['commit']['message'].splitlines()[0]}\")
"

Useful for confirming the PR's commit order in the API matches
the order described in the body. API returns commits in the
order they were applied (oldest first), same as `git log`.

### List comments on a PR

```bash
PR_NUMBER=3407

curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO/issues/$PR_NUMBER/comments?per_page=20" \
  | python3 -c "
import sys, json
for c in json.load(sys.stdin):
    print(f\"  {c['id']} by {c['user']['login']} at {c['created_at']}: {c['body'][:60]}...\")
"

### Read a single comment by ID

When a PR URL anchors to a specific comment (`#issuecomment-NNN`), you
can fetch it directly — no need to paginate through all comments:

```bash
COMMENT_ID=4605799643

curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO/issues/comments/$COMMENT_ID" \
  | python3 -c "
import sys, json
c = json.load(sys.stdin)
print(f\"by {c['user']['login']} at {c['created_at']}\")
print(c['body'])
"
```

Note the URL shape: `issues/comments/{id}` (singular "comment", issue
endpoint). This works **across the whole repo** — you don't need the
issue/PR number, only the comment ID from the URL fragment.

### Check review timeline & events

Pull request **reviews** (approve/request-changes/comment events
submitted as formal reviews) live at a different endpoint than plain
comments. The `reviews` endpoint returns submitted formal reviews;
the `timeline` endpoint returns all events (commits, rename, label
changes, review submissions, etc.).

```bash
PR_NUMBER=3407

# Formal reviews only (approve/request-changes/comment review events)
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
  | python3 -c "
import sys, json
for r in json.load(sys.stdin):
    print(f\"  {r['submitted_at']} | {r['user']['login']} | {r['state']}\")
    if r.get('body'):
        print(f\"    {r['body'][:200]}\")
"

# All timeline events (commits, rename, label changes, review submissions, etc.)
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO/issues/$PR_NUMBER/timeline?per_page=30" \
  | python3 -c "
import sys, json
events = json.load(sys.stdin)
for e in events:
    ev = e.get('event', '')
    user = e.get('user', {}).get('login', '?')
    created = e.get('created_at', '')
    label = e.get('label', {}).get('name', '') if e.get('label') else ''
    state = e.get('state', '')
    print(f'{created} | {user} | {ev} {label} {state}')
"
```

**Why both matter:** A reviewer may leave feedback as a **plain
comment** (appears in `/issues/N/comments` but NOT in
`/pulls/N/reviews`) or as a **formal review** (appears in
`/pulls/N/reviews` AND also in the timeline). If you only check
comments, you might miss a submitted review. If you only check
reviews, you might miss a top-level discussion comment. Check
both. The timeline gives you the full picture including non-review
events (commits, branch rename, label adds).

### When to update a PR vs open a new one

Updating in place (push more commits + PATCH title/body) is
right when the new work is **thematically the same** as the
existing PR (e.g. "discovered a second root cause while testing
the first fix"). The maintainer can review the diff
incrementally.

Opening a new PR is right when the new work is **logically
separate** (e.g. "fixed a different bug, unrelated to the
first PR's scope"). Two focused PRs are easier to review
and merge independently than one mega-PR.

**Hybrid pattern**: when the new work is borderline (thematically
linked but a different root cause), update the existing PR
**and** explicitly offer to split in the comment body. The
maintainer can then say "yes, please split" — the cost of
splitting after the fact is one `git rebase -i` and a new
branch, not a re-do of the original work. This is the
lowest-touch action that preserves the maintainer's choice.

## 9. When You Discover Another PR is Solving the Same Issue

A real scenario: you opened a PR (or filed an issue and opened a PR to fix it), and then notice **another contributor opened a competing PR against the same issue** — sometimes within hours of yours. Both are open, both target the same problem, the maintainer will likely pick one. The right move is **coordinate, don't compete**.

### Decision tree

1. **Search for related PRs** before assuming your PR is the only one:
   ```bash
   curl -s -H "Accept: application/vnd.github.v3+json" \
     "https://api.github.com/repos/$OWNER/$REPO/pulls?state=open&per_page=50" \
     | python3 -c "
   import sys, json
   for pr in json.load(sys.stdin):
       # search for keywords from your issue title
       if 'termux' in (pr.get('title','') + pr.get('body','')).lower():
           print(f'#{pr[\"number\"]} | {pr[\"user\"][\"login\"]} | {pr[\"title\"]}')"
   ```

2. **Diff your approach against theirs**. Look at:
   - Do they have a more complete fix? (helper functions, tests, multiple call sites)
   - Do they have a more focused fix? (smaller diff, easier to review)
   - What's unique to yours that they don't have? (timeout, error handling, env var)
   - What's unique to theirs that you don't have? (tests, broader detection)

3. **Three outcomes** to choose between:

   | Outcome | When to pick | Action |
   |---------|--------------|--------|
   | **Coordinate** (most common) | Both PRs have unique value, no one's clearly better | Comment on theirs offering complementary fixes; update your PR body to note overlap; wait for response before closing |
   | **Withdraw yours** | Theirs is clearly more complete and the maintainer will pick theirs | Add a comment to yours saying "superseded by #N", close yours with a reference |
   | **Keep both, differentiate** | They fix X, you fix Y; both can ship independently | Don't coordinate; let maintainer pick the one that fits their roadmap |
   | **Expand yours to subsume theirs** | The original issue spec enumerated multiple fixes (A, B, C…); their PR covers only a subset (e.g. just A); your PR can be expanded to cover the full spec and make theirs a strict subset | Implement the missing pieces (B, C, etc.) in the locations the issue specified; update your PR body to position it as the comprehensive one; comment on theirs offering to consolidate |

4. **The coordination message** (the polite, complete form):
   ```
   Hey! I filed the original issue #N and also opened #MYPR to fix it.
   Your PR is more thorough (the `_is_proot_env()` helper + tests
   covering both call sites are great — I only patched one site).

   I have two complementary fixes that might be worth pulling in here
   so we ship one comprehensive PR instead of two overlapping ones:

   1. **`UV_NO_BUILD_ISOLATION=1`** in the same Termux/PRoot block — ...
   2. **`timeout=120` on `subprocess.run` in `_ensure_uv_for_termux()`** — ...

   Both fixes have commits on #MYPR if you want to cherry-pick or
   rebase. I'm happy to push them to your branch instead if you'd
   prefer — just let me know. Otherwise, I'll close #MYPR once one
   of these lands.

   Thanks for picking this up!
   ```

   Note the **three explicit offers** (cherry-pick, push-to-their-branch, or close-mine-when-yours-lands). This gives the other contributor a choice, not a take-it-or-leave-it.

5. **Update your own PR body** with a closing note:
   ```bash
   # gh edit --body-file is the safe form for multi-line content
   # (do NOT use --body with $(...) capture — newlines + command-like
   # tokens break it; see pitfalls)
   cat > /tmp/pr-body.md <<'EOF'
   [original body]
   ---

   **Update:** [PR #OTHER](https://github.com/.../pull/OTHER) by @user
   addresses the same issue with a more complete approach. I've commented
   there offering complementary fixes. Closing this once that lands.
   EOF
   gh pr --repo $OWNER/$REPO edit $PR --body-file /tmp/pr-body.md
   ```

6. **Wait for response** — do NOT close immediately. Give the other contributor a few days to respond. If they don't, ping them with a follow-up comment, then ask the user (the agent's operator) what to do.

### When their PR is a subset of what the issue actually called for

This is the "expand yours" outcome from the table. The trigger: the **original issue body** enumerates specific fixes (A, B, C…) with their target functions, parameters, and file locations. The competing PR implements only one of them (say, A) in a different location. You have two options: (a) coordinate and combine, or (b) **expand your own PR to implement the full issue spec**, making theirs strictly a subset.

The expansion path wins when:
- The issue spec is unambiguous and names specific functions/parameters — the maintainer will likely merge whichever PR matches the spec
- You have time to do the additional work
- You want the comprehensive fix in YOUR PR (so the related issues from the spec all ship together)

Concrete steps:
1. Re-read the issue body, especially the "Proposed Fixes" or "Implementation Notes" section — list every change it asks for
2. Diff your PR against that list — what's missing?
3. For each missing piece, implement it **in the location the issue specifies** (not where you'd put it from the symptom). The issue author chose those locations for a reason (often: shared helper that benefits multiple call sites, not a per-caller change)
4. Update your PR body to enumerate the full coverage ("Implements fixes A, B, C, D from #N, in the architecture the issue specified")
5. Comment on the competing PR: "Hey, I expanded my PR to cover the full spec from the issue (A+B+C+D). My PR #M is now the comprehensive one — would you like to close yours in favor, or split?"
6. Don't force-close theirs — let the maintainer decide

This is the pattern that worked for the Termux/PRoot fix in issue #40328: the issue called for (A) `UV_LINK_MODE=copy` env injection in `_install_python_dependencies_with_optional_fallback()`, (B) a `no_build_isolation` parameter on that helper, and (C) `more_itertools` declared in `pyproject.toml`. A competing PR implemented only A in `_cmd_update_impl` with env-var hacks. Expanding to A+B+C in the locations the issue specified turned the competing PR into a strict subset that could be closed once mine landed.

### Why coordinate, not just close yours

- Your complementary fixes (e.g. timeout, error handling) are real fixes — don't throw them away
- Co-authoring gets you credit in git history (`Co-authored-by:` trailer)
- The maintainer gets one PR to review, not two
- The other contributor may have unique value you didn't see (tests, refactor, docs)

### Pitfalls

- **Don't be passive-aggressive** in the coordination comment. Frame it as "we both found this, let's combine" not "I got there first, let me take it"
- **Don't ask the user to choose the next step while still in coordinate mode** — the other contributor has 24-72h to respond. Just monitor (cron `pr-monitor.sh` from Section 4b)
- **Don't modify the other contributor's branch** without explicit permission — even with `--force-with-lease` it's their PR
- **Forks can't add labels to upstream PRs**: `gh pr edit --add-label "duplicate"` fails with `PatrickNoFilter does not have the correct permissions to execute AddLabelsToLabelable (addLabelsToLabelable)`. Labels are reserved for upstream maintainers. Don't waste time trying.
- **`gh pr edit --body` with inline multi-line breaks**: bash command substitution via `$(...)` strips newlines AND interprets `---` / `#` as commands. **Always use `--body-file`** for any body > 1 line, especially when capturing from existing PR via `curl | python3 -c "..."`.

## 10. Responding to "Changes Requested" Reviews

When a reviewer returns `CHANGES_REQUESTED`, the PR can't merge until you
resolve every blocking issue. Here's the systematic workflow for handling
review feedback efficiently.

### Step 1: Parse the Review — Blocking vs Non-Blocking

Reviews often mix three signal levels:

| Signal | Label | What to do |
|--------|-------|------------|
| **🔴 Blocking** | Explicit failure, `FAILED`, `can't merge`, `must fix` | Fix these first — they block merge |
| **🟠 Coverage gap** | `unaddressed`, `what about X`, `also need to` | Fix if justified, otherwise explain |
| **🔵 Minor / non-blocking** | `suggestion`, `nit`, `optional`, `minor` | Acknowledge — can fix or defer |

Extract these programmatically:

```bash
# Fetch all reviews on the PR
PR_NUMBER=40377
OWNER_REPO="NousResearch/hermes-agent"

gh pr view "$PR_NUMBER" --repo "$OWNER_REPO" --json reviews --jq '.reviews[] | "\(.state): \(.body[:100])..."'
# Output: CHANGES_REQUESTED: ## Hermes Agent Review — 🔴 Request Changes (4 tests fail)...

# If gh is unavailable:
curl -sf -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$OWNER_REPO/pulls/$PR_NUMBER/reviews" \
  | python3 -c "
import sys, json
for r in json.load(sys.stdin):
    state = r['state']
    body = (r.get('body') or '')[:80]
    author = r['user']['login']
    print(f'{state:20s} | {author:20s} | {body}')
"
```

### Step 2: Reproduce Each Claim in Code

Before fixing, **verify the reviewer's claim against the actual code**.
Do NOT assume the reviewer is always correct about the root cause —
but also don't dismiss them. Trace the code path yourself.

```bash
# 1. Fetch the PR branch locally
gh pr checkout "$PR_NUMBER" --repo "$OWNER_REPO"

# 2. For each code-relative claim, find the relevant line range
#    (e.g. "main.py:~9229" means "around line 9229")
grep -n "def _install(" hermes_cli/main.py
# Returns line numbers — confirm the area the reviewer references

# 3. Read the actual code flow at those lines
sed -n '9220,9240p' hermes_cli/main.py
```

**Key heuristic**: if the reviewer says "test N fails" — run the test
first to confirm the failure pattern, then trace *why* it fails rather
than fixing the symptom.

### Step 3: Diagnose Test Failures (Common Pitfalls)

Test harness bugs are the most common cause of false-positive review
blockers. Before touching production code, check if the test mock setup
is the actual problem.

**Pattern 1 — Uncaught exception from fallback path** (most common):

A `fake_run` mock raises `CalledProcessError` to stop execution after
capturing the first install attempt. But the production code may have a
fallback path (e.g. `_install(["install", "-e", "."])` after the main
`_install` fails). The second fallback call also hits `fake_run`, and if
there's no `try/except` around it, the exception propagates **past** the
assertion.

```python
# BAD — CalledProcessError propagates before assertion runs
fake_run(monkeypatch)
hm._some_function(call)       # ← raises CalledProcessError from fallback
assert env.get("KEY") == "value"   # ← never reached

# FIX — wrap in pytest.raises
with pytest.raises(subprocess.CalledProcessError):
    hm._some_function(call)   # ← exception caught by pytest
assert env.get("KEY") == "value"   # ← now executes
```

**Pattern 2 — Mock doesn't return a value the production code expects**:

If the code checks the return value of a function (e.g. `if _verify(...):`),
mocking it to raise unconditionally skips important code paths. Either
let it succeed after capturing what you need, or wrap in `pytest.raises`.

**Diagnostic command:**

```bash
# Run the failing tests to confirm the failure pattern
uv run pytest tests/hermes_cli/test_cmd_update.py \
  -k "test_install_deps_autosets or test_install_deps_preserves or test_install_deps_passes or test_install_deps_no_build" \
  -v --tb=long 2>&1 | tail -40
```

### Step 4: Address Coverage Gaps — the "Missing Parameter" Pattern

When a reviewer says "function X also needs this parameter," trace the
call chain from the entry point to the helper function:

```bash
# Example: find all call sites of a function
grep -n "_install_python_dependencies" hermes_cli/main.py
```

The fix typically follows the same shape:
1. Add the new parameter to each call site
2. Gate it on the same condition the original call site uses (e.g. `if _is_termux_env()`)
3. Commit as part of the same fix commit (don't split into separate commits unless the reviewer asked for it)

```python
# BEFORE — parameter not threaded through
if uv_bin:
    uv_env = {**os.environ, ...}
    _install_python_dependencies_with_optional_fallback([uv_bin, "pip"], env=uv_env)

# AFTER — parameter gated on same condition
if uv_bin:
    uv_env = {**os.environ, ...}
    no_build_isolation = False
    if _is_termux_env(uv_env):
        uv_env.pop("PYTHONPATH", None)
        no_build_isolation = True
    _install_python_dependencies_with_optional_fallback(
        [uv_bin, "pip"], env=uv_env, no_build_isolation=no_build_isolation
    )
```

### Step 5: Commit, Push, and Re-request Review

After fixing all blocking issues:

```bash
# Commit with a message that references the review
git add -A
git commit -m "fix: address review feedback on PR #N

- Wrap failing tests in pytest.raises (test harness bug:
  fallback install path propagated CalledProcessError before assertions)
- Wire parameter X through _update_via_zip path (coverage gap)"

# Push to the same branch — PR auto-updates
git push origin HEAD
```

Then notify the reviewer. **Do NOT re-request review via the API unless
the reviewer explicitly asked for it** — some maintainers prefer to
re-review at their own pace. A simple PR comment is sufficient:

```bash
gh pr comment "$PR_NUMBER" --repo "$OWNER_REPO" --body \
"## Review feedback addressed in <commit-sha>

- **🔴 4 failing tests**: wrapped in pytest.raises — the test harness
  mock propagated CalledProcessError from the fallback install path
  before assertions could run. Fixed.
- **🟠 Coverage gap**: wired \`no_build_isolation\` through
  \`_update_via_zip\` (both uv and pip paths), matching the main update
  path.
- **Minor notes**: left as-is (timeout/requirements changes are
  tangential but reviewed and correct).

Ready for re-review. Thanks for the thorough review!"
```

### Common Pitfalls

- **Don't fix the symptom before understanding the root cause**. A failing
  test doesn't mean the production logic is wrong — trace the execution
  path first.
- **Don't split fixes into separate commits unless the review requests it**.
  A single commit with a clear message is easier to re-review than 4 small
  commits the reviewer has to diff individually.
- **Don't force-push** (`git push --force`) when the PR already has review
  threads — force-pushing can lose inline review comments. Use `git push`
  (plain) or `git push --force-with-lease` only if you explicitly rebased.
- **Don't re-request review via the GitHub API immediately** — this sends a
  notification. If they asked to be notified when fixed, use the API;
  otherwise a comment respects their review queue.
- **Don't mark non-blocking issues as resolved** in the review UI — the
  reviewer wants to confirm the fix themselves.

### When the Reviewer is Wrong

If you trace the code and the reviewer's claim doesn't reproduce:

1. **Run the test or command they described** as-is, with no modifications
2. **Document the actual output** — paste the terminal output in the PR comment
3. **Explain why you believe their claim doesn't apply**
4. **Offer to change it anyway** if they still think it's important
5. **Never say "the reviewer is wrong"** — say "I traced this and the
   pattern doesn't fire under these conditions; here's what I found"

The most common cases where a reviewer is incorrect:
- They tested against the wrong commit (PR was force-pushed since review)
- They assumed a code path executes when it doesn't (conditional guard)
- The test harness didn't match CI environment
- They looked at the diff in isolation and missed surrounding context

In all cases, **verify first, then explain respectfully**.

---

## 11. Verifying if a PR's Changes Have Already Shipped to Master

A common scenario: someone hands you an open PR URL and asks "check if the fix is already on master." The PR is still open (cherry-pick landed), or was closed without merge but the fix was applied another way. Here's how to determine that.

### Strategy overview

There are three independent ways to check, each with different strengths:

| Method | Best for | How |
|--------|----------|-----|
| **Read the CHANGELOG** | Confirming the fix was intentional, seeing the release version | Search it on master for the PR number or commit keywords |
| **Read key file on master** | Verifying the actual code change is present | Fetch the file from `raw.githubusercontent.com` and grep |
| **Check git ancestry** | Confirming a PR's commit SHA is in master's history | `git merge-base --is-ancestor` |

### Step-by-step workflow

```bash
# REPLACE with the actual PR number and repo
PR_NUMBER=3407
OWNER_REPO="nesquena/hermes-webui"
OWNER=$(echo "$OWNER_REPO" | cut -d/ -f1)
REPO=$(echo "$OWNER_REPO" | cut -d/ -f2)
```

#### 1. Check if the PR itself was merged (fast path)

```bash
PR_JSON=$(curl -sf -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${OWNER}/${REPO}/pulls/${PR_NUMBER}")

echo "$PR_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'State: {d[\"state\"]}, Merged: {d.get(\"merged\")}')
if d.get('merged'):
    print(f'Merge SHA: {d[\"merge_commit_sha\"]}')
    print(f'By: {d[\"merged_by\"][\"login\"]}')
    print(f'At: {d[\"merged_at\"]}')
"
```

If `merged: true`, the PR was merged through the normal flow — done. If `merged: false` but the PR is still open, the fix might have been cherry-picked (common for urgent fixes shipped mid-cycle).

#### 2. Search the CHANGELOG on master for the PR reference

This is the most direct way to confirm a cherry-pick:

```bash
curl -sL "https://raw.githubusercontent.com/${OWNER}/${REPO}/master/CHANGELOG.md" \
  | grep -i "$PR_NUMBER" | head -10
```

If the fix was shipped, the changelog will reference the PR number, often tagged with "salvaged from #N" or "cherry-picked from #N":

```text
- The server no longer dies silently when a client drops the connection...
  (salvaged from #3407, @PatrickNoFilter).
```

Note the release version in the section header (e.g. `[v0.51.239]`) — that tells you which release to deploy to.

#### 3. Verify the code change exists on master

```bash
# Fetch the key file from master and grep for the specific code pattern
curl -sL "https://raw.githubusercontent.com/${OWNER}/${REPO}/master/server.py" \
  | grep -n "SIGPIPE\|SIG_IGN\|specific-pattern-from-the-pr" | head -10
```

If the fix is a code change (not a changelog-only change), grep the relevant file on master for the pattern the PR introduced.

#### 4. Deep verification: check if a PR commit is an ancestor of master

Only works when you have the repo cloned locally:

```bash
cd /path/to/repo
git fetch origin master

# For each candidate commit SHA from the PR:
PR_COMMIT_SHA="11e81fc9"
if git merge-base --is-ancestor "$PR_COMMIT_SHA" origin/master; then
  echo "✅ Commit ${PR_COMMIT_SHA} IS on master"
else
  echo "❌ Commit ${PR_COMMIT_SHA} is NOT on master"
fi
```

`git merge-base --is-ancestor` exits 0 if the commit is in the ancestry chain, 1 if not. **Cherry-picked commits have different SHAs** on master than on the PR branch — `is-ancestor` only matches exact SHAs. For cherry-picks, search by commit message or code content instead.

#### 5. Read the PR commit log to find candidate commits

```bash
curl -s -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${OWNER}/${REPO}/pulls/${PR_NUMBER}/commits?per_page=30" \
  | python3 -c "
import sys, json
commits = json.load(sys.stdin)
for c in commits:
    msg = c['commit']['message'].splitlines()[0]
    print(f'  {c[\"sha\"][:10]} {msg[:80]}')
"
```

Then for each commit that could have been cherry-picked, check if the **message keyword** or **code pattern** appears on master — SHAs won't match for cherry-picks but the diff content will.

#### 6. Report the findings

Synthesize your results into a clear verdict:

```
## PR #3407 Merge Status

**Verdict: Core fix already shipped, branch commits partly on master**

✅ SIGPIPE fix: shipped in **v0.51.239** (Release HG)
   - server.py on master has `signal.signal(SIGPIPE, SIG_IGN)` 
   - CHANGELOG: "(salvaged from #3407, @PatrickNoFilter)"

❌ Still unmerged from PR branch (10 commits remaining):
   - Diagnostic signal-trap shim
   - Post-update cgroup-kill restart fix (15s fork delay)
   - Watchdog/launcher scripts

→ Recommendation: switch local repo to master (latest v0.51.241) since
  the core fix is already released.
```

### Pitfalls

- **Cherry-picked commits have different SHAs** on master than on the PR branch. Never compare SHAs when checking for cherry-picks — compare code content or commit messages instead.
- **Branch names with slashes break the compare API.** A branch like `diag/observability-and-robustness` in the compare URL `master...diag/observability-and-robustness` gets the slash interpreted as a URL path. Either URL-encode the slash (`master...diag%2Fobservability-and-robustness`) or use commit-level comparison (list PR commits individually vs `master` log).
- **The compare API may 404** if the PR branch was force-pushed or deleted after the PR was created. Fall back to reading the key file and changelog from `raw.githubusercontent.com`.
- **`git reset --hard origin/master` is destructive** — it discards uncommitted local changes and any commits not on upstream. Always `git stash` first, then confirm with the user before running it.
- **`gh` CLI may not be available** on minimal environments (no `gh`). All the `curl`-based approaches work without it.

## 12. Fixing Author Email Attribution in PR Commits

When commits in a PR have the wrong author email (e.g., `hermes@agent.local` from an
AI agent, or a noreply address not linked to a GitHub account), the `check-attribution`
CI check will fail. Fix this with `git filter-branch` to rewrite author metadata.

### When to Fix

- `check-attribution` fails: "Check for unmapped contributor emails" — the commit
  author email isn't registered to any GitHub account.
- A reviewer asks you to correct the commit author (e.g., "use your real email").
- You need commits to show under your GitHub profile in the PR.

### Check Current Attribution

```bash
git log --format="%h %ae - %an (%ai)" <branch> | head -20
```

Identify which commits have the wrong email by comparing against your registered
GitHub emails (available at https://github.com/settings/emails).

### The Fix: git filter-branch

Rewrite author and committer identity for all commits matching a specific email:

```bash
cd /path/to/repo

export FILTER_BRANCH_SQUELCH_WARNING=1

git filter-branch --env-filter '
if [ "$GIT_AUTHOR_EMAIL" = "hermes@agent.local" ]
then
    export GIT_AUTHOR_NAME="YourName"
    export GIT_AUTHOR_EMAIL="your.email@example.com"
    export GIT_COMMITTER_NAME="YourName"
    export GIT_COMMITTER_EMAIL="your.email@example.com"
fi
' -- <branch-name>
```

**Key flags & env vars:**
- `FILTER_BRANCH_SQUELCH_WARNING=1` — suppress warnings about rewriting history.
- `-f` (or `--force`) — pass to `git filter-branch` when a previous backup already
  exists in `refs/original/`; required on re-runs after a failed or partial first
  attempt. Without it you get:
  ```
  Cannot create a new backup. A previous backup already exists in
  refs/original/ — Force overwriting the backup with -f
  ```

### Merge Commits vs Regular Commits

**Do NOT blindly rewrite all commits.** Merge commits in PRs (the merge-base
or the `gh pr merge` merge commit) often have a different, valid author email
(e.g., a personal laptop email or `noreply@github.com`). Only rewrite the
**regular commits** where the email is wrong.

The `--env-filter` pattern above automatically handles this — the `if` condition
only acts on commits whose author email matches the bad value, leaving merge
commits with a different email untouched. No need to carefully select a range.

### After Filter-Branch

```bash
# 1. Verify the rewrite
git log --format="%h %ae - %an" <branch> -10

# 2. Force push to update the PR
git push origin <branch> --force

# 3. Verify the PR auto-updated
git ls-remote origin <branch>
```

The force push updates the PR's commit list. GitHub will re-trigger all CI
checks, including `check-attribution`. A "Ref is unchanged" message from
filter-branch means the commits were **already rewritten** in a prior run —
the local branch already has the correct emails, so just force-push.

### Pitfalls

- **First filter-branch creates a backup** in `refs/original/`. Running
  filter-branch again without `-f` fails. Always use `-f` on re-runs.
- **Force-push invalidates existing review threads** on the rewritten commits.
  If the PR has active inline reviews, the maintainer may prefer a
  `Co-authored-by:` trailer or manual squash-and-reword instead of filter-branch.
- **Cherry-picks won't match filter-branch SHAs** — rewritten history has
  entirely new commit SHAs. If someone already referenced old SHAs in a comment,
  note the new ones.
- **Local copies need a fresh clone** or `git reset --hard origin/<branch>` after
  force-push — anyone who pulled the old branch will have diverging history.
- **Filter-branch is destructive** — it rewrites every commit's SHA. Consider
  `git rebase --interactive` + `exec` for smaller fixups (single author change
  on a few commits) as a lighter alternative when you have few commits and no
  merge commits to preserve.

## Useful PR Commands Reference

| Action | gh | git + curl |
|--------|-----|-----------|
| List my PRs | `gh pr list --author @me` | `curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$OWNER/$REPO/pulls?state=open"` |
| View PR diff | `gh pr diff` | `git diff main...HEAD` (local) or `curl -H "Accept: application/vnd.github.diff" ...` |
| Add comment | `gh pr comment N --body "..."` | `curl -X POST .../issues/N/comments -d '{"body":"..."}'` |
| Update title | `gh pr edit N --title "..."` | `curl -X PATCH .../pulls/N -d '{"title":"..."}'` |
| Update body | `gh pr edit N --body "..."` | `curl -X PATCH .../pulls/N -d '{"body":"..."}'` |
| List PR commits | `gh pr view N --json commits` | `curl .../pulls/N/commits` |
| List PR comments | `gh pr view N --comments` | `curl .../issues/N/comments` |
| Read PR metadata | `gh pr view N` | `curl .../pulls/N` (parse `state`, `mergeable_state`, `additions`, `deletions`, `commits`, `changed_files`) |
| Request review | `gh pr edit N --add-reviewer user` | `curl -X POST .../pulls/N/requested_reviewers -d '{"reviewers":["user"]}'` |
| Close PR | `gh pr close N` | `curl -X PATCH .../pulls/N -d '{"state":"closed"}'` |
| Check out someone's PR | `gh pr checkout N` | `git fetch origin pull/N/head:pr-N && git checkout pr-N` |
