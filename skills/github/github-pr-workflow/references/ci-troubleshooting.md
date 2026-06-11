# CI Troubleshooting Quick Reference

Common CI failure patterns and how to diagnose them from the logs.

## Reading CI Logs

### Full log download (default)

```bash
# With gh
gh run view <RUN_ID> --log-failed

# With curl — download and extract
curl -sL -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/$GH_OWNER/$GH_REPO/actions/runs/<RUN_ID>/logs \
  -o /tmp/ci-logs.zip && unzip -o /tmp/ci-logs.zip -d /tmp/ci-logs
```

### Precision: annotations endpoint (faster, lighter)

When you just need the exact error message from a failed check (not the entire log archive), use the **annotations** endpoint. Each check run reports annotations — inline error markers with `message`, `path`, and `start_line`. This is much lighter than downloading + extracting a zip:

```bash
# 1. Get check runs → find the failed ones with their check_run_id
SHA=$(git rev-parse HEAD)
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$GH_OWNER/$GH_REPO/commits/$SHA/check-runs" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for cr in data.get('check_runs', []):
    if cr.get('conclusion') == 'failure':
        print(f\"{cr['name']}: check_run_id={cr['id']}\")
"

# 2. Get annotations for a specific failed check run
CHECK_RUN_ID=1234567890
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/$GH_OWNER/$GH_REPO/check-runs/$CHECK_RUN_ID/annotations" \
  | python3 -c "
import sys, json
anns = json.load(sys.stdin)
for a in anns:
    print(f\"{a.get('path','?')}:{a.get('start_line','?')} [{a.get('annotation_level','?')}]\")
    print(f\"  {a.get('message','')}\")
    if a.get('raw_details'):
        print(f\"  raw: {a['raw_details']}\")
"
```

Use annotations FIRST. Only fall back to full log download when annotations are empty (some workflow steps don't produce annotations).

---

## Deep CI Debugging: Beyond the Web UI

The web UI and `web_extract` show a **truncated and potentially misleading** summary — annotations from different steps are merged into a flat list, and `continue-on-error: true` hides real failures. To see what actually happened, query the **Jobs API** for step-level data. This works even after raw logs have expired (404/403).

### The API Chain

```
/actions/runs/{run_id}          → run metadata
/actions/runs/{run_id}/jobs     → job list with step details
/actions/jobs/{job_id}          → single job with step breakdown
/actions/jobs/{job_id}/annotations → step annotations (often 404 if expired)
```

### Getting the Full Picture (When web UI is misleading)

```python
import urllib.request, json

RUN_ID = 27282991343        # from the job URL or run URL
OWNER_REPO = "owner/repo"   # from the git remote

# 1. Get run metadata
run_url = f"https://api.github.com/repos/{OWNER_REPO}/actions/runs/{RUN_ID}"
req = urllib.request.Request(run_url,
    headers={"Accept": "application/vnd.github+json", "User-Agent": "agent"})
with urllib.request.urlopen(req, timeout=15) as r:
    run = json.load(r)
    print(f"Run: {run['name']} on {run['head_branch']} — {run['conclusion']}")

# 2. Get all jobs for this run
jobs_url = f"https://api.github.com/repos/{OWNER_REPO}/actions/runs/{RUN_ID}/jobs"
req = urllib.request.Request(jobs_url,
    headers={"Accept": "application/vnd.github+json", "User-Agent": "agent"})
with urllib.request.urlopen(req, timeout=15) as r:
    data = json.load(r)
    for job in data["jobs"]:
        print(f"\nJob: {job['name']} (ID: {job['id']}) — {job['conclusion']}")
        for step in job["steps"]:
            print(f"  [{step['number']}] {step['name']}: "
                  f"status={step['status']} conclusion={step.get('conclusion','?')} "
                  f"outcome={step.get('outcome','?')}")
```

### Understanding `continue-on-error` + `conclusion` vs `outcome`

This is the **critical distinction** that most UI summaries hide:

| Field | Without `continue-on-error` | With `continue-on-error: true` |
|-------|---------------------------|-------------------------------|
| `conclusion` | `failure` if command exited non-zero | Always `success` (hidden failure) |
| `outcome` | Same as `conclusion` | `failure` if command exited non-zero |

**The trap:** The API's `conclusion` field reflects what GitHub *shows* (green checkmark in the UI for `continue-on-error` steps). The `outcome` field reflects what *actually happened*. Downstream step conditions like `if: steps.flake.outcome == 'failure'` use `outcome`, not `conclusion`.

**How to spot it:**
- A step with `conclusion=success` but whose downstream dependent steps triggered (ran instead of being skipped) tells you its `outcome` was actually `failure`.
- The API sometimes exposes `outcome=N/A` for all steps — in that case, **infer the real outcome from downstream behavior**: if step D runs only `if: steps.A.outcome == 'failure'`, and step D ran, then step A's outcome was `failure` regardless of its reported `conclusion`.

### Tracing the Execution Chain (Practical Example)

**Scenario:** Job shows as failed, web UI highlights 3 error annotations across 2 steps. But which step *caused* the job failure?

```python
# After getting job data, trace the step chain:
for step in job_data["steps"]:
    name = step["name"]
    number = step["number"]
    concl = step.get("conclusion", "?")
    outcome = step.get("outcome", "N/A")

    # Identify real failures hidden by continue-on-error
    if outcome != "N/A" and outcome == "failure":
        print(f"  ❌ Step {number}: {name} — ACTUAL failure (hidden by continue-on-error)")
    elif concl == "failure":
        print(f"  ❌ Step {number}: {name} — FAILED (unmasked)")

    # Identify the step that killed the job
    if concl == "failure" and "continue-on-error" not in name:
        print(f"     → THIS is the job-killing step")
```

**Key pattern from a real session:**

```
[5] Check flake:            conclusion=success outcome=N/A
                               (continue-on-error: true — actual outcome was failure)
[6] Diagnose npm hashes:    conclusion=success (continue-on-error: true)
[7] Fail if hash crashed:   conclusion=skipped (because step 6 outcome was success)
[8] Post sticky PR comment: conclusion=failure (NO continue-on-error — THIS killed the job)
[10] Final fail if flake:   conclusion=skipped (should have run if flake outcome=failure)
```

The web UI showed 5 error annotations from steps 5, 6, and 8, but only step 8 actually failed the job. Steps 5 and 6 had `continue-on-error: true`, so their errors were collected but didn't block the pipeline. The **real job-killer** was step 8's token permissions issue.

### Reading Workflow YAML to Cross-Reference

Fetch the workflow file and match step conditions to the API data:

```python
# Get the workflow file used for this run
wf_url = f"https://raw.githubusercontent.com/{OWNER_REPO}/{run['head_branch']}/.github/workflows/nix.yml"
# ... or from the run's path field
```

Key conditions to check when debugging:
- **`if: steps.X.outcome == 'failure'`** — only runs when step X actually failed
- **`if: steps.X.outputs.stale == 'true'`** — depends on the step's output, not its exit code (see: `continue-on-error` + `$GITHUB_OUTPUT` heredoc bugs)
- **`continue-on-error: true`** — errors don't propagate; actual outcome is hidden

### When Raw Logs Return 404/403

GitHub deletes log archives after a few hours/days. When `GET /actions/runs/{id}/logs` or `GET /actions/jobs/{id}/logs` returns 404 or 403:

1. **Do NOT give up** — the Jobs API (`/actions/runs/{id}/jobs` → `/actions/jobs/{id}`) still returns the step breakdown with `conclusion` and `outcome`.
2. **Annotations may also be gone** (`/actions/jobs/{id}/annotations` → 404). Fall back to cross-referencing step data with the workflow YAML.
3. **Check the run's `created_at`** — if it's >24h old, logs are likely purged. Learn what you can from the step-level API + workflow conditions.
4. **For recent runs (minutes old)**, 404 usually means the wrong endpoint. Try `GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs` instead of the job ID directly.

### Common Misleading UI Patterns

| UI Shows | Actual Reality | Why |
|----------|---------------|-----|
| "5 errors, 1 warning" | Only 1 error blocked the job | Other 4 were in `continue-on-error: true` steps |
| Step 5 annotation: "exit code 1" | Step 5 passed (conclusion=success) | The annotation is from the raw log, not the final status |
| "Check flake failed (exit 1)" | Flake check had `continue-on-error: true` and pipeline continued | Downstream steps that DID fail (without `continue-on-error`) are the real killer |
| One step shows failure | The failure is in a DIFFERENT step | The downstream step may have been skipped due to `if:` condition, and the actual killer is a post-job cleanup step |

### Concrete Checklist for CI Debugging

When a job URL points to a failing run:

1. Get the **run metadata** → extract `head_branch`, `head_sha`
2. Get the **workflow YAML** from that branch → understand step conditions
3. Get **job-level step data** via the Jobs API → see `conclusion` and `outcome` per step
4. **Identify which steps ran** vs were skipped → trace the `if:` conditions
5. **Find the step with `conclusion=failure` and no `continue-on-error`** → that's the real blocker
6. **Cross-reference annotations** from `continue-on-error` steps — they're informational, not blocking
7. **Check the workflow permissions** (`permissions:` block in YAML) for auth failures
8. When logs are gone, **reconstruct the failure chain** from step data + conditions alone

---

## Common Failure Patterns

### Test Failures

**Signatures in logs:**
```
FAILED tests/test_foo.py::test_bar - AssertionError
E       assert 42 == 43
ERROR tests/test_foo.py - ModuleNotFoundError
```

**Diagnosis:**
1. Find the test file and line number from the traceback
2. Use `read_file` to read the failing test
3. Check if it's a logic error in the code or a stale test assertion
4. Look for `ModuleNotFoundError` — usually a missing dependency in CI

**Common fixes:**
- Update assertion to match new expected behavior
- Add missing dependency to requirements.txt / pyproject.toml
- Fix flaky test (add retry, mock external service, fix race condition)

---

### Lint / Formatting Failures

**Signatures in logs:**
```
src/auth.py:45:1: E302 expected 2 blank lines, got 1
src/models.py:12:80: E501 line too long (95 > 88 characters)
error: would reformat src/utils.py
```

**Diagnosis:**
1. Read the specific file:line numbers mentioned
2. Check which linter is complaining (flake8, ruff, black, isort, mypy)

**Common fixes:**
- Run the formatter locally: `black .`, `isort .`, `ruff check --fix .`
- Fix the specific style violation by editing the file
- If using `patch`, make sure to match existing indentation style

---

### Type Check Failures (mypy / pyright)

**Signatures in logs:**
```
src/api.py:23: error: Argument 1 to "process" has incompatible type "str"; expected "int"
src/models.py:45: error: Missing return statement
```

**Diagnosis:**
1. Read the file at the mentioned line
2. Check the function signature and what's being passed

**Common fixes:**
- Add type cast or conversion
- Fix the function signature
- Add `# type: ignore` comment as last resort (with explanation)

---

### Build / Compilation Failures

**Signatures in logs:**
```
ModuleNotFoundError: No module named 'some_package'
ERROR: Could not find a version that satisfies the requirement foo==1.2.3
npm ERR! Could not resolve dependency
```

**Diagnosis:**
1. Check requirements.txt / package.json for the missing or incompatible dependency
2. Compare local vs CI Python/Node version

**Common fixes:**
- Add missing dependency to requirements file
- Pin compatible version
- Update lockfile (`pip freeze`, `npm install`)

---

### Contributor Attribution Failures

**Signatures in logs:**
```
❌ check-attribution — "Check for unmapped contributor emails" exit code 1
```

**Diagnosis:**
1. Run `git log --format="%h %ae - %an" <branch>` to list all commit authors
2. Cross-reference each email against the GitHub account's registered emails
3. Common culprits: `hermes@agent.local` (AI agent default), `root@hostname`,
   noreply addresses not linked to a GitHub profile

**Root cause identification:**

GitHub Actions workflows that validate commit attribution use one of two
approaches — determine which one applies before fixing:

| Approach | How to detect | Fix path |
|----------|---------------|----------|
| **Git history rewrite** | The CI check compares commit author email against a configured user in the workflow YAML, or a maintainer flagged the email as wrong. | `git filter-branch` (below, or §12 of the parent skill) |
| **AUTHOR_MAP registry** | The project has a dictionary (e.g. in a release script like `scripts/release.py`) mapping commit emails → GitHub usernames. The CI runs a script that queries this dict. Failure means your email isn't in the map. | Add your email → username entry to the dictionary (below) |

**Common fixes — git history rewrite (email is wrong):**
- Use `git filter-branch --env-filter` to rewrite author/committer emails for
  matching commits (see the `github-pr-workflow` skill, §12 for the full workflow).
- Push the rewritten branch with `git push origin <branch> --force` to trigger
  re-check.
- For any individual commit, `git commit --amend --author="Name <email>" --reset-author`
  works if it's the most recent commit.

**Common fixes — AUTHOR_MAP registry (email is valid but unknown to the project):**

Projects like Hermes Agent maintain a `scripts/release.py` with a giant
`AUTHOR_MAP` dict (`AUTHOR_MAP={"ema...m": "username", ...}`)
that maps contributor commit emails to GitHub usernames for changelog
generation. When your commit comes from an email not in the map, the
`check-attribution` CI job fails.

Fix:
1. Fetch the release script from the PR branch:
   ```bash
   curl -sL "https://raw.githubusercontent.com/$FORK_OWNER/$REPO/$BRANCH/scripts/release.py" \
     -o /tmp/release.py
   grep -n "YOUR_EMAIL" /tmp/release.py  # confirm it's missing
   ```
2. Clone the fork branch locally, add the entry (alphabetically positioned):
   ```bash
   git clone --depth 1 --branch $BRANCH https://github.com/$FORK_OWNER/$REPO.git
   # Edit scripts/release.py — add `"your.email@example.com": "YourGitHubUsername",`
   ```
3. Commit and push — the open PR auto-updates:
   ```bash
   git add scripts/release.py
   git commit -m "fix: add your.email@example.com to AUTHOR_MAP"
   git push origin $BRANCH
   ```
4. Verify: the push triggers a new `check-attribution` run on the PR.

**Key clues distinguishing the two patterns:**
- Failure message says "unmapped contributor email" → AUTHOR_MAP registry.
- Failure message says "author email not verified" or "commit authored by
  unknown user" → git history rewrite.
- If the PR body shows commits from your GitHub account but `git log` shows
  a different email (e.g. `hermes@agent.local`), it's a history rewrite fix.
- If your commit email is correct but the CI still fails, it's an AUTHOR_MAP fix.

---

### Permission / Auth Failures

**Signatures in logs:**
```
fatal: could not read Username for 'https://github.com': No such device or address
Error: Resource not accessible by integration
403 Forbidden
```

**Diagnosis:**
1. Check if the workflow needs special permissions (token scopes)
2. Check if secrets are configured (missing `GITHUB_TOKEN` or custom secrets)

**Common fixes:**
- Add `permissions:` block to workflow YAML
- Verify secrets exist: `gh secret list` or check repo settings
- For fork PRs: some secrets aren't available by design

---

### Timeout Failures

**Signatures in logs:**
```
Error: The operation was canceled.
The job running on runner ... has exceeded the maximum execution time
```

**Diagnosis:**
1. Check which step timed out
2. Look for infinite loops, hung processes, or slow network calls

**Common fixes:**
- Add timeout to the specific step: `timeout-minutes: 10`
- Fix the underlying performance issue
- Split into parallel jobs

---

### Docker / Container Failures

**Signatures in logs:**
```
docker: Error response from daemon
failed to solve: ... not found
COPY failed: file not found in build context
Client.Timeout exceeded while awaiting headers
```

**Diagnosis:**
1. Check Dockerfile for the failing step
2. Verify the referenced files exist in the repo
3. **Docker Hub registry timeouts**: `Client.Timeout exceeded while awaiting headers`
   from `registry-1.docker.io` is almost always a **transient infrastructure
   issue**, not a code bug. Check if other build jobs (e.g. `build-arm64` vs
   `build-amd64`) passed — asymmetric failures across parallel jobs are a strong
   signal of transient networking.
4. **Node.js 20 deprecation**: Logs containing
   `Node.js 20 actions are deprecated. Please update...` is a warning (soft until
   2026-09-16). Track it but don't block a PR for it.

**Common fixes:**
- Fix path in COPY/ADD command
- Update base image tag
- Add missing file to `.dockerignore` exclusion or remove from it
- **Docker Hub registry timeout → re-run failed jobs** (no code change needed):
  ```bash
  gh run list --branch <branch> --limit 5 --json databaseId --jq '.[].databaseId'
  gh run rerun <RUN_ID> --failed
  ```

---

### Fork PR CI Investigation

When a PR is from a **fork** (common in open-source), action-run URLs on the
upstream repo may 404 even for public repos if you're unauthenticated or the
run belongs to the fork's own Actions tab rather than the upstream's.

**How to check CI status on a fork PR:**

```bash
# 1. Get the latest commit SHA from the PR metadata
SHA=$(curl -sf -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$OWNER/$REPO/pulls/$PR_NUMBER" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['head']['sha'])")

# 2. Query ALL check runs for that commit — works on upstream, no auth needed
#    for public repos (60/hr unauthenticated rate limit)
curl -sf -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$OWNER/$REPO/commits/$SHA/check-runs" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for cr in data.get('check_runs', []):
    name = cr['name']
    status = cr['status']
    concl = cr.get('conclusion') or 'pending'
    detail_url = cr.get('details_url', '')
    print(f'{name:30s} | {status:10s} | {concl:10s}')
    if concl == 'failure':
        print(f'  → detail: {detail_url}')
"

# 3. For a failed check-run, read annotations (fast, no log download)
CHECK_RUN_ID=<id>
curl -sf -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$OWNER/$REPO/check-runs/$CHECK_RUN_ID/annotations" \
  | python3 -c "
import sys, json
for a in json.load(sys.stdin):
    print(f\"{a.get('path','?')}:{a.get('start_line','?')} {a.get('message','')}\")
"
```

**Why this matters over URL-based checking:** The check-runs endpoint returns
**every** workflow run for the commit — tests, lint, Docker builds,
check-attribution, etc. — in a single API call. The commit status endpoint
(`/commits/$SHA/status`) is a separate path that returns only commit statuses,
not workflow runs. Check-runs is more comprehensive. Fork PRs also run their
workflows on the **upstream** repo (if `pull_request_target` is used) or the
**fork** repo; the API resolves this for you.

**Key observations when investigating fork PR failures:**
- If `check-attribution` fails on a fork PR, it's usually unrelated to the code
  (the fork's commits aren't in the upstream's contributor database). Focus on
  the test/lint/build failures first.
- If all arch-specific builds (`build-amd64`, `build-arm64`) fail with the same
  error, it's likely a code issue. If only ONE fails with a network error
  (`Client.Timeout`, `Connection refused`), it's a transient infra issue.

---

## Auto-Fix Decision Tree

```
CI Failed
├── Test failure
│   ├── Assertion mismatch → update test or fix logic
│   └── Import/module error → add dependency
├── Lint failure → run formatter, fix style
├── Type error → fix types
├── Build failure
│   ├── Missing dep → add to requirements
│   └── Version conflict → update pins
├── Permission error → update workflow permissions (needs user)
└── Timeout → investigate perf (may need user input)
```

## Re-running After Fix

```bash
git add <fixed_files> && git commit -m "fix: resolve CI failure" && git push

# Then monitor
gh pr checks --watch 2>/dev/null || \
  echo "Poll with: curl -s -H 'Authorization: token ...' https://api.github.com/repos/.../commits/$(git rev-parse HEAD)/status"
```

## Troubleshooting `$GITHUB_OUTPUT` Heredoc Errors

When a CI step writes to `$GITHUB_OUTPUT` using heredoc syntax and you see:

```
Invalid value. Matching delimiter not found 'REPORT_EOF'
Unable to process file command 'output' successfully
```

This is a **shell escaping / newline bug** between the delimiter and the content.

### How GHA heredoc output works

```bash
# The syntax:
echo "output_name<<DELIMITER" >> "$GITHUB_OUTPUT"
printf "%s" "$VALUE"           >> "$GITHUB_OUTPUT"
echo "DELIMITER"                >> "$GITHUB_OUTPUT"
```

GitHub's runner parses `output_name<<DELIMITER` as the start of a heredoc, then reads lines until it finds `DELIMITER` on a line by itself.

### Root cause: value doesn't end with a real newline

If `$VALUE` does NOT end with a real newline character (`\n`, byte 0x0A), the closing `DELIMITER` lands on the **same line** as the last content — the parser never finds it on its own line and throws the error above.

**Common shell escaping mistake (in Nix `''` strings especially):**

```nix
# BAD — Nix '' strings don't process backslashes, so $'\\\\n' writes
# literal \\n (backslash + backslash + n), NOT a newline:
VALUE="...text..."$'\\\\n'
printf "%s" "$VALUE"
echo "DELIMITER"
# Output: ...text...\\nDELIMITER\n  ← DELIMITER not on its own line!
```

```nix
# GOOD — $'\n' in the shell produces an actual newline:
VALUE="...text..."$'\\n'       # Note: single backslash-n
printf "%s" "$VALUE"
echo "DELIMITER"
# Output: ...text...\nDELIMITER\n  ← correct!
```

### How to detect

When you see `echo "{name}<<{delimiter}"` followed by `printf "%s" "$VALUE"` in a CI script, check `$VALUE`'s trailing content:
- `$'\\n'` → real newline (correct)
- `$'\\\\n'` → literal `\\n` (bug — no real newline)
- No trailing newline at all → `echo` vs `printf` matters; `echo` auto-appends `\n`, `printf "%s"` does not
- If using `echo "$VALUE"` instead of `printf`, the echo adds a trailing newline, making the pattern *accidentally work* — but fragile if the output mode changes

### Fix

Change the trailing content of `$VALUE` to end with a real newline:

```bash
# Instead of:
VALUE="..."
VALUE+="$'\\\\n'"   # literal \\n

# Use:
VALUE="..."
VALUE+="$'\\n'"     # real newline character

# Or use echo for the whole thing (echo always appends \n):
echo "$VALUE" >> "$GITHUB_OUTPUT"
```

In Nix `''` strings specifically, `$'\\n'` stays as `$'\n'` in the shell script (Nix doesn't process backslashes), which bash interprets as a real newline.
