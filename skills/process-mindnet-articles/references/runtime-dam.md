# Runtime: DAM

For a session on the [DAM](https://github.com/dam-agents/dam) platform:
the platform tools `schedule_once` and `spawn_subagent` are there, or the
prompt starts with a `[mindnet:…]` marker (SKILL.md, „Which runtime you
are on“). Everything here is on top of SKILL.md; in a plain harness none
of it applies — see [runtime-plain.md](runtime-plain.md).

What DAM gives the run and the plain harness does not:

- **scheduled jobs with a preflight** — the dispatcher wakes every five
  minutes, and only when `status` shows work;
- **`schedule_once`** — the dispatcher starts one session per waiting
  article, and they run in parallel in one pod;
- **platform sub-agents on another harness and model family** — every
  check runs on GPT (harness `codex`) in a clean sandbox, through
  `scripts/check.sh`;
- **a shared pod** — the sessions share memory and the owner's compute
  for the check sandboxes.

`<skill dir>` below is the folder the skill was loaded from; on the
platform `/home/agent/.pi/agent/skills/process-mindnet-articles`.

## Scheduled job or onboarding

A prompt that starts with `[mindnet:dispatch …]` or `[mindnet:article …]`
is one of the scheduled jobs: follow that prompt and nothing else in this
section. Otherwise, on the first load on DAM, or when someone asks to set
up, check or repair the schedule, run the **onboarding** in
[onboarding.md](onboarding.md): it checks the tools and secrets, runs the
preflight once and creates the recurring dispatcher (every five minutes).
The dispatcher starts one `mindnet-article` session per waiting article
(`schedule_once`, up to six at once), and those sessions run in parallel.
Do it once; afterwards the jobs run on their own. A scheduler can call
`status` before waking the agent — that is what the preflight
(`scripts/precheck.py`) does.

When a person asks to process the queue by hand in a session without a
marker, do what an article session does (one article with
`claim_article`, carried to the end) and say in the report how many
articles still wait for the dispatcher.

## One session per article, in parallel

The 8 October 2026 probe that showed sessions colliding was **re-tested
the same day after a platform fix**: two `schedule_once` sessions started
at the same moment each ran their own `pi` process side by side for two
minutes, both finished with `completed/success`, a third, interactive
session kept running untouched, and memory rose by only ~100 MB (each
`pi` ≈ 90 MB RSS; the pod has 2 GB). So:

- The **dispatcher** ([onboarding.md](onboarding.md)) is a scheduled run
  every five minutes whose preflight calls `status`. It claims nothing. It
  works out `free = 6 − articles_in_progress` and starts
  `min(articles, free)` one-off `mindnet-article` sessions
  (`schedule_once`, no `at`), then ends.
- Each **article session** takes one article with `claim_article` and
  carries it to the end. Then it ends: it does **not** go on to the next
  article, the dispatcher starts a fresh session for each. If another
  session took the article first, it gets `empty` and ends at once.
- **Six at once at most** (raised from three on 8 Oct 2026; the owner's
  compute had 23 CPU / 48 GB free). The limit is memory in the pod (an
  article session with its GPT checks running), the owner's compute for
  the check sandboxes, and the platform's hourly limit on one-off
  schedules. It is not the server.
- **GPT-check sandboxes are shared across sessions.** `check.sh` holds a
  pod-wide semaphore (`flock`, `CHECK_SLOTS`, default 4): at most four
  sandbox spawns run in the whole pod at once. A check that finds no free
  slot goes straight to `--direct`, without waiting, so parallel sessions
  never queue for compute. Do not set `CHECK_DIRECT=1` just because other
  sessions are running.

A crashed session's article returns to the queue when its lease expires
and the next tick starts a new session for it. A dispatcher every five
minutes is enough: an empty `status` costs milliseconds.

## Checks on OpenAI (platform sub-agents)

Since 7 October 2026: **who writes and who checks are always from
different model families.** You write on Claude, so every check runs on
GPT, each in its own sandbox via harness `codex`: the extractor, the cold
reader, the fidelity reviewer (the judge) and the translate proofreader.
Self-preference bias (MSumBench; Wataoka et al. 2024) is a family trait;
Sonnet checking Opus buys a clean context, not an outside view. A Claude
subagent is never a checker of Claude text, not even as a fallback.

Script: `S=<skill dir>/scripts/check.sh` (a thin wrapper over
`judge.py`; schemas `extractor`, `cold`, `fidelity`, `proofread`; it
prints the validated JSON and writes it to `--out`, same arguments as
`judge.py` but **without** `--direct`).

**Which path (operator's call, 8 October 2026; spawn fixed same day).**
The check runs as a **platform sub-agent** (variant (a)): a fresh agent
in its own sandbox on harness `codex`, GPT model, empty context.
`check.sh` does this and **falls back to `--direct`** when the spawn
fails. So **call `check.sh`** (not `judge.py` straight): platform
sub-agent first, the reliable direct call only if it cannot start.

**The model-name bug (diagnosed 8 Oct).** Earlier that day every spawn
**hung silently until the liveness deadline**. The spawn passed the model
name with the **LiteLLM `azure/` prefix** (`azure/gpt-6-astra`) to the
codex harness, which rejects it with a 400 and then **hangs instead of
erroring** — a platform defect (admin confirmed; issue filed). What the
probes showed:
- `azure/gpt-6-astra` (with prefix) → **0/4 succeeded**, all hung to
  liveness.
- `gpt-6-astra` (**no prefix**) → **3/4 succeeded**, reported family
  GPT-6; `judge.py --spawn-model gpt-6-astra` returned `judge_model:
  gpt-6` in ~86 s.
- no model at all → harness default `gpt-5` (GPT family), 2/2 succeeded.

Rules that follow:
- `judge.py` now defaults `--spawn-model` to **`gpt-6-astra` (no
  prefix)**. **Never** send the `azure/` prefix to the spawn. `--model`
  (which keeps `azure/gpt-6-astra`) applies **only to `--direct`**, where
  the real LiteLLM name is correct.
- The spawn is still **flaky even with the right name** (~1 in 4 hangs to
  liveness, non-deterministic for an identical call). `check.sh`
  absorbs this: a hung spawn falls back to `--direct`. If a spawn hangs,
  that is expected tail behaviour, not a model error — do not switch
  names.
- Any spawn model is GPT (GPT-6 or gpt-5) — a different family than the
  Claude writer, as the rule requires.

**How the spawn reaches the platform.** `judge.py` spawns through the
driver SDK (`d.spawn(harness="codex", model="gpt-6-astra", …)`) — the
**same platform sub-agent mechanism** as the MCP
`spawn_subagent`/`await_subagents` tools, but it polls with a timeout of
`ttl/1000 + 60 s`, so it is **not** cut off by the MCP `await_subagents`
60-second window. **Do not** drive these checks by calling
`spawn_subagent`/`await_subagents` by hand: in tests on 8 Oct that path
failed 2/2 with „liveness deadline exceeded“ (the 60 s `await` kept
missing the ~40–50 s codex boot + model time, even with the budget
showing free CPU), whereas the same spawn via `d.spawn` / `check.sh`
finished in ~48 s. The MCP tools stay for one-off hand-offs; the
per-fragment checks go through `check.sh`.

**Forcing direct.** `CHECK_DIRECT=1 check.sh …` skips the spawn and calls
`--direct` at once — use it when `get_budget` shows the compute full (so
you do not pay the spawn wait just to fall back), and always for
`translate` (below).

1. **Extractor** — write the filled template into `/tmp/ex-<id>.txt`
   and start it right after reading the prompt:
   `$S /tmp/ex-<id>.txt --schema extractor --label ex --out /tmp/ex-<id>.json 2>/tmp/ex-<id>.log &`
   While it runs, read the article yourself and draft the outline.
   Over ~3,000 words: one call per third, side by side.
2. **Cold reader + fidelity reviewer** — after the cards, write both
   filled templates to files and start **both at once** in the
   background (`--schema cold`, `--schema fidelity`), then `wait`.
3. **Translate proofreader** — `--schema proofread`, one call with all
   cards of the request in one prompt (numbered), right after the
   draft; it returns `{ ok, errors: [{ where, found, problem, fix }] }`.
   Test 7 Oct: it caught the calque „Práce útočníka je…“ and the dangling
   „k němu“ but **missed an English em dash** — check dashes („–“ spaced
   en dash in Czech) yourself mechanically before answering.
4. Timing measured 7–8 Oct: the sandbox start alone is ~30–51 s; a real
   check adds ~10–20 s of model time. `--direct` (the fallback) is
   ~3–19 s. The compute ceiling was raised to 30 CPU / 60 GB on 8 Oct, so
   spawns no longer queue at normal load; still never more than four at
   once in the pod, which `check.sh` enforces itself across parallel
   sessions (`CHECK_SLOTS`). Fragment rounds keep their ≤ 4 min
   budget. For `translate` (15-min lease for the whole article) use
   `CHECK_DIRECT=1`: the same GPT model straight through the LiteLLM,
   clean context, no sandbox, ~3–19 s; the script checks the schema itself
   and retries once.
5. **When a check fails or is late:** `check.sh` already falls back
   from spawn to `--direct` on its own. If **both** paths fail, retry once
   with `--model azure/gpt-5.6-sol` (direct); if that also fails, go on
   **without** that check (never substitute a Claude subagent) and note in
   the report what was skipped and why.

Options: `--model` (OpenAI on the LiteLLM: `azure/gpt-6-astra` default,
`azure/gpt-5.6-sol`, `azure/gpt-5.5`), `--effort` (`minimal`…`xhigh`).
Ask the templates for string values in the article's language. The
platform validates only the JSON shape; you still work in the findings
by the rules in phase-a.md. The answer's `model` field stays the
**writer's** id, never a checker's.
