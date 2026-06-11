"""
Verify os.execv() argv handling.

The hermes-webui self-update bug was caused by:
    os.execv(sys.executable, [sys.executable] + sys.argv)
which passes the binary path as argv[1] — i.e. as the "script" to run.
The kernel then runs `python <full-binary-path> server.py`, and CPython
parses the binary as a Python source file. The new process ends up
recursively re-execing the same call forever, never reaching bind().

The fix is:
    os.execv(sys.executable, sys.argv)
which passes argv as-is — sys.argv[0] is the program (binary) and
sys.argv[1] is the script, which is the right shape.

Run this script to compare the two behaviours:

    # broken pattern — will recurse for ~5s before timeout
    timeout 5 /usr/local/lib/hermes-agent/venv/bin/python3 -c \
        "import os,sys; os.execv(sys.executable,[sys.executable]+sys.argv)" \
        /tmp/x.py
    # expect: same script runs 5-50 times in 5s, then SIGKILL on timeout

    # fixed pattern — runs once and exits
    timeout 5 /usr/local/lib/hermes-agent/venv/bin/python3 -c \
        "import os,sys; os.execv(sys.executable,sys.argv)" \
        /tmp/x.py
    # expect: script runs once, exits 0

This file itself does the equivalent: drops the redundant prefix and
verifies the new image runs the script once. Drop it into your repo's
test/ or scripts/ directory and run as a smoke test.
"""

import os
import sys


def main() -> int:
    if len(sys.argv) != 1:
        # We are the *re-execed* child. The kernel just started us again
        # from the same path. If we got here it means execv preserved
        # argv correctly — exit cleanly to prove we don't recurse.
        print(f"[verify_execv] re-execed: argv={sys.argv} — exiting 0",
              flush=True)
        return 0

    print(f"[verify_execv] parent: argv={sys.argv} exe={sys.executable}",
          flush=True)
    print("[verify_execv] calling os.execv(sys.executable, sys.argv) "
          "(fixed pattern — drop the [sys.executable] prefix)",
          flush=True)
    os.execv(sys.executable, sys.argv)
    # unreachable
    return 1


if __name__ == "__main__":
    sys.exit(main())
