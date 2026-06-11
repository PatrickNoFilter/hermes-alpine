# WebUI down — diagnosis and recovery flowchart

Step-by-step runbook for when `http://127.0.0.1:8787/health` is unreachable
on the Termux+PRoot box. Each step is independent — run the next only if
the previous one didn't reveal the problem.

## 0. Confirm it's actually down

```bash
curl -fsS --max-time 3 http://127.0.0.1:8787/health
```

If this returns `{"status":"ok",...}` the webui is fine — your problem is
client-side (browser tab, DNS, SSH tunnel, LAN reachability).

## 1. Is crond alive?

```bash
pgrep -x cron || echo CROND_DEAD
```

**If dead:**

```bash
service cron start
# verify
pgrep -x cron
```

This is the #1 cause of "webui down for hours" on Termux+PRoot — the
crontab watchdog never fires because crond itself was killed. After
restarting crond, the @reboot line will not retroactively run, so
manually start the webui (step 3) or wait up to 5 min for the */5
watchdog.

## 2. Is the webui process alive but not responding?

```bash
bash /root/hermes-webui/ctl.sh status
```

- **`running, PID …, uptime 00:0N`** — ctl thinks it's up. Could be
  two things:
  - The self-update `os.execv` recursion wedge — only on
    **frozen-binary** deploys (the local source-checkout runs the
    `if sys.frozen` guard and takes the canonical
    `[sys.executable] + sys.argv` path). If `fuser 8787/tcp` shows
    the PID but `/health` is unreachable, fix: `pkill -f server.py;
    sleep 2; cd /root/hermes-webui && bash ctl.sh start`.
  - **Silent death after a successful restart** — more likely on
    Termux+PRoot. The new process started, served ~1s of requests,
    then died with no traceback / log / signal. See the
    `hermes-webui-self-update-bug` skill section **B** for the
    diagnose recipe (add `try/except BaseException` around
    `serve_forever`, check dmesg for SIGKILL, etc.). Fastest
    recovery: `bash ctl.sh restart` — the new process is unlikely
    to die the same way twice in a row.
- **`stopped`** — ctl thinks it's down. Skip to step 3.

## 3. Was it actually killed? Check the log

```bash
tail -100 /root/.hermes/webui.log
```

Look for the last line. If the last line is `Hermes Web UI listening on http://127.0.0.1:8787` and nothing after, the process died silently (no traceback, no shutdown signal). This is the most common symptom on PRoot and is usually OOM, container suspension, or the silent-death-after-restart bug (see `hermes-webui-self-update-bug` section B). Distinguishing: if the log shows several 200 responses on the new process *before* the silence, it's the silent-death bug; if it goes from "listening" straight to silence with no requests served, it's more likely OOM/SIGKILL on startup.

## 4. Start it

```bash
cd /root/hermes-webui && bash ctl.sh start
```

`ctl.sh start` returns as soon as the PID is forked. The server takes
**8-10 seconds** to actually bind 127.0.0.1:8787 on this PRoot box.
Wait and then check:

```bash
sleep 20
curl -fsS --max-time 3 http://127.0.0.1:8787/health
```

If still not healthy, check the log again — the new bootstrap block
will tell you what went wrong (`No module named 'dotenv'`, `Address
already in use`, etc.). See the main `hermes-webui` skill for those
specific errors.

## 5. Was the in-app Update Now used recently?

If the user clicked **Update Now** in the webui settings right before
the downtime, look at the *shape* of the symptom:

- **No requests served on the new process** + PID still alive +
  `/health` unreachable → `os.execv` recursion wedge (only possible
  on frozen-binary deploys; local source-checkout is patched).
  Recovery:
  ```bash
  pkill -9 -f 'server.py'      # the wedged process
  sleep 2
  cd /root/hermes-webui && bash ctl.sh start
  sleep 20
  curl -fsS --max-time 3 http://127.0.0.1:8787/health
  ```
  Long-term fix is the `if sys.frozen` guard — already applied
  locally for source-checkout. See `hermes-webui-self-update-bug`
  skill section **A**.

- **New process served a flurry of 200s** (session load, static
  assets, /health probes) **then died silently within ~1 min** →
  the silent-death-after-restart bug, not the execv wedge. The
  execv fix is correct and not the issue here. Fastest recovery:
  ```bash
  bash /root/hermes-webui/ctl.sh restart
  sleep 20
  curl -fsS --max-time 3 http://127.0.0.1:8787/health
  ```
  See `hermes-webui-self-update-bug` skill section **B** for
  the diagnose recipe and likely root causes
  (Termux/Android SIGKILL, deferred async task crash, PRoot pause).

## 6. Port already in use?

```bash
python3 -c "
import socket
s = socket.socket()
try:
    s.bind(('127.0.0.1', 8787))
    print('Port 8787 is FREE')
except OSError as e:
    print('Port 8787 is IN USE:', e)
s.close()
"
```

If IN USE: there's a stale process. Don't use `pkill -9 -f server.py`
bluntly — prefer `pkill -f server.py` (TERM) first, wait 2s, then if
still bound, identify by `fuser 8787/tcp 2>/dev/null` and kill that
specific PID. (See main skill's safe-kill section.)

## 7. Sanity-check the watchdog will catch the next outage

```bash
crontab -l | grep -E '8787|hermes-webui'  # confirm lines are present
pgrep -x cron                              # confirm crond is up
```

If the */5 watchdog line is missing, the user replaced the crontab
with the broken one that called `/usr/local/bin/hermes-webui-ctl`
(dead code). Fix: reinstall the minimal working crontab from the
main `hermes-webui` skill.

## Quick decision tree

```
curl /health → ok?              YES → not a server problem, go home
                                NO ↓
pgrep -x cron → empty?          YES → service cron start; then go to "Start it"
                                NO ↓
ctl.sh status → running?        YES → pick by symptom shape:
                                  • no requests served → execv wedge (frozen only), step 5a
                                  • served some, then silent → silent-death, step 5b
                                NO ↓
tail webui.log                  (see what the last lines say)
ctl.sh start                    (wait 20s, recheck /health)
```

## Files referenced

- Log: `/root/.hermes/webui.log` (real ctl.sh log; NOT `/tmp/hermes-webui.log` which is for the dead-code script)
- State: `/root/.hermes/webui.ctl.env` (env vars ctl.sh wrote)
- PID: `/root/.hermes/webui.pid` (the REAL one — the system `/usr/local/bin/hermes-webui-ctl` uses `/tmp/hermes-webui.pid` which never gets written, hence its `status` always lies)
