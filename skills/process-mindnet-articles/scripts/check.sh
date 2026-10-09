#!/usr/bin/env bash
# check.sh — one check (extractor/cold/fidelity/proofread) on GPT,
# a different family than the writer (Claude), clean context.
#
# Variant (a) per the operator's brief (8 October 2026): PRIMARILY a platform
# sub-agent (spawned through the driver SDK in judge.py, i.e. the same platform
# mechanism as MCP spawn_subagent/await_subagents, but with polling that
# does not suffer from the 60 s cap of MCP await). FALLBACK to --direct when
# the spawn fails — most often „liveness deadline exceeded“ even with free
# budget, or insufficient capacity (queueing).
#
# Usage (same arguments as judge.py, without --direct):
#   check.sh PROMPT_FILE --schema fidelity --label fid --out /tmp/fid.json
# Optionally CHECK_DIRECT=1 forces --direct straight away (when you know
# the budget is full and do not want to spend time waiting for the spawn to fail).
# CHECK_SLOTS (default 4) = max concurrent sandboxes in the pod; when all
# of them are taken (other sessions of the same pod), it goes straight to --direct.
#
# The result (validated JSON) goes to stdout and to --out; stderr carries progress
# and the path taken (spawn / fallback-direct). Exit code 0 done, 1 both paths
# failed, 2 bad arguments.
set -uo pipefail

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/judge.py"
if [ ! -f "$S" ]; then echo "check.sh: judge.py not found next to the script" >&2; exit 2; fi

# The former names KONTROLA_* (before the skill was renamed) still work.
if [ "${CHECK_DIRECT:-${KONTROLA_DIRECT:-0}}" = "1" ]; then
  echo "check.sh: CHECK_DIRECT=1 → straight to --direct" >&2
  exec python3 "$S" "$@" --direct
fi

# Sandbox slots: at most CHECK_SLOTS (default 4) spawns at once across
# the whole pod, over all concurrent sessions (since 8 October 2026
# articles run in parallel as separate sessions in one pod). When a slot
# is free, flock holds it for the duration of the spawn; when none is, it goes
# straight to --direct — nobody waits for a sandbox, the check is not delayed.
SLOTS="${CHECK_SLOTS:-${KONTROLA_SLOTS:-4}}"
LOCKDIR="${CHECK_LOCKDIR:-${KONTROLA_LOCKDIR:-/tmp/mindnet-check-slots}}"
mkdir -p "$LOCKDIR"
slot_fd=""
for i in $(seq 1 "$SLOTS"); do
  exec {fd}>"$LOCKDIR/slot-$i.lock"
  if flock -n "$fd"; then slot_fd=$fd; echo "check.sh: sandbox slot $i/$SLOTS" >&2; break; fi
  exec {fd}>&-
done
if [ -z "$slot_fd" ]; then
  echo "check.sh: all $SLOTS sandbox slots taken → straight to --direct" >&2
  exec python3 "$S" "$@" --direct
fi

# 1) Primary path: platform sub-agent (judge.py without --direct).
# `rc` straight from the call: after `if cmd; then …; fi` without an else,
# `$?` is the exit status of the `if` itself, which is 0.
python3 "$S" "$@"
rc=$?
if [ "$rc" -eq 0 ]; then
  exit 0
fi
exec {slot_fd}>&-   # release the slot before the fallback
echo "check.sh: platform spawn failed (rc=$rc) → fallback to --direct" >&2

# 2) Fallback: direct GPT call through LiteLLM, clean context, no sandbox.
if python3 "$S" "$@" --direct; then
  echo "check.sh: fallback --direct succeeded" >&2
  exit 0
fi
echo "check.sh: both paths failed (spawn and --direct)" >&2
exit 1
