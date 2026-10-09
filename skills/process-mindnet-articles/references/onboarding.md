# Onboarding: the scheduled jobs

How an own agent on a platform with scheduled jobs sets itself up to
process the reader's queue without anyone starting it (ADR-0020).

## The shape: one session per article, in parallel (re-tested 8 October 2026)

The first probe on 8 October showed two sessions in one pod colliding:
one froze and the pod restarted. That was a platform defect. **After the
fix, the same day**, two `schedule_once` sessions started at the same
moment each ran their own `pi` process side by side for two minutes and
both ended `completed/success`. A third, interactive session ran on
untouched, and memory rose by only ~100 MB (about 90 MB RSS per `pi`;
the pod has 2 GB). So articles run **in parallel, each in its own
session in this pod**:

| job | kind | runs | preflight | does |
|---|---|---|---|---|
| `mindnet-dispatch` | recurring | every 5 minutes | `precheck.py dispatch --max-sessions 6` | reads the precheck (`status`), starts `min(articles, 6 − articles_in_progress)` `mindnet-article` one-offs, ends. Claims nothing. |
| `mindnet-article` | one-off (`schedule_once`, no `at` = now), started by the dispatcher | once | — (the dispatcher just checked) | takes one article with `claim_article`, carries it to the end, ends |

The dispatcher is cheap: its preflight skips the run unless articles wait
and a slot is free, so most ticks never wake an agent.

Every prompt below starts with a marker line, `[mindnet:dispatch v4]` or
`[mindnet:article v4]`. The marker tells a session it **is** one of these
jobs (so it never runs onboarding itself) and its version tells onboarding
whether an existing job is up to date.

## When to run onboarding

Run it when the skill is loaded in a session whose prompt does **not**
start with a `[mindnet:…]` marker — the first load on a new platform, or a
person asking to set up, check or repair the schedule — and either the
person asks for it or `mindnet-dispatch` does not exist yet. A session
with a marker skips this file entirely.

## Steps

1. **The MCP tools work.** Call `status`. The tools must include
   `claim_article` and the result must have `articles` and
   `articles_in_progress`; otherwise the server is older than this skill
   — stop and say so.
2. **The preflight can reach the server.** It runs outside the MCP
   connection as a plain shell process. It needs the MindNet MCP address,
   which it finds on its own — it reads `.pi/agent/mcp.json` (server
   `mind-net-mcp`), the same address the running agent uses — so on a
   normal platform **nothing has to be set**. Two optional environment
   variables override this: `MINDNET_MCP_URL` (an address, when the config
   has none or you want a different one) and `MINDNET_AGENT_KEY` (the
   reader's key `mn_agent_…`, sent as a Bearer header). On a platform that
   routes MindNet through a connection proxy the egress gateway injects
   the credentials into the call itself, so no key is needed and
   `MINDNET_AGENT_KEY` stays unset. Set `MINDNET_AGENT_KEY` only on a
   platform that reaches the server directly without a proxy; never write
   the key into a prompt, a file, a job definition or the report.
3. **Run the preflight once by hand:**
   `python3 <skill dir>/scripts/precheck.py dispatch; echo "exit $?"`,
   where `<skill dir>` is the folder this skill was loaded from (on the
   platform `/home/agent/.pi/agent/skills/process-mindnet-articles`). Expected:
   a summary line and `exit 1` (nothing waits) or `exit 0`. A line
   starting `PRECHECK FAILED:` means the address is wrong or unreachable
   (and on a direct platform, that a key is missing); fix that before
   going on. Even then the dispatcher still runs and calls `status`
   itself — a broken preflight never stops the queue, it only loses the
   cheap skip of an empty tick.
4. **Look at the existing jobs.** List the platform's scheduled jobs.
   - `mindnet-dispatch` with marker `v4` → nothing to do, go to step 7.
   - `mindnet-dispatch` with marker `v3` → the same jobs under the skill's
     former name `zpracuj-clanky` (renamed 9 October 2026, file names
     too). Update its prompt to the one below **and** its preflight path to
     this skill's directory — the old directory may be gone.
   - `mindnet-dispatch` with an older marker (`v2`: the sequential worker
     or the sub-agent dispatcher) → update its prompt to the one below;
     the preflight stays.
   - **Older MindNet jobs without a marker** (a prompt that names
     `zpracuj-clanky`, `process-mindnet-articles`, `mind_net_mcp` or
     `claim`) take requests one by one
     and would compete with the article sessions. Show them to the person
     and replace them with their consent. When nobody is there to ask,
     leave them, create the new job anyway, and put the old ones at the
     top of the report.
5. **Create `mindnet-dispatch`**: recurring, every 5 minutes, preflight
   `python3 <skill dir>/scripts/precheck.py dispatch --max-sessions 6`,
   prompt „Dispatcher prompt“ below, verbatim with `<skill dir>` filled
   in.
6. **Nothing else to create.** The dispatcher starts the
   `mindnet-article` one-offs itself. Their prompt is below so it can
   copy it.
7. **Report**: which jobs exist now (name, schedule, marker version,
   mode), the preflight's output from step 3, what was replaced or left,
   and whether anything waits right now. When articles wait, say so: the
   next tick picks them up within five minutes.

## Dispatcher prompt

```text
[mindnet:dispatch v4]
You are the MindNet dispatcher. Do not process any article yourself and
do not claim anything.

The preflight summary is below under „Precheck output“. If it says
PRECHECK FAILED or is missing, call the MCP tool `status` of the MindNet
server yourself.

Free slots = 6 − articles_in_progress. If articles is 0 or there are no
free slots, end now.

Otherwise call `schedule_once` (platform tools, no `at` = run now)
N = min(articles, free slots) times, each with name `mindnet-article` and
task = the prompt from the section „Article session prompt“ of
<skill dir>/references/onboarding.md, copied verbatim, with its skill-directory
placeholder filled in as <skill dir>. They run in
parallel, one article each. Do not wait for them. If `schedule_once`
refuses (the hourly limit on one-off jobs), start as many as it allows;
the next tick starts the rest.

End with one sentence: how many articles waited, how many were in
progress and how many article sessions you started.
```

## Article session prompt

```text
[mindnet:article v4]
Process exactly one MindNet article. Load and follow the skill
`process-mindnet-articles` (<skill dir>/SKILL.md; before the first `fragment` also
references/phase-a.md, for the other kinds references/other-kinds.md). Work
only through the MCP tools of the MindNet server; if `claim_article` is
not among them, end and report that the server or the skill is out of
date. Skip the skill's onboarding: this session is a scheduled job. Other
article sessions may be running beside you; that is expected. Do not
start any session or schedule yourself.

1. Call `claim_article` with no arguments. An empty result means another
   session took the article: end.
2. Answer every request in `requests` with `answer` (id; answer = exactly
   the JSON the prompt asks for; model = the id of the model that wrote
   it). When a request cannot be answered, `fail` with one sentence for a
   human in the request's language; permanent=true for a paywall or an
   empty text.
3. Follow `article.state` from each answer, as the skill's table says:
   next → answer the requests in `next`; in_hand → answer the other
   requests of this article you still hold; processing → wait a minute,
   then `claim_article` with {"job": job_id}; waiting, done, failed → the
   article is over.
4. GPT checks (extractor, cold reader, fidelity reviewer, translate
   proofreader) go through `scripts/check.sh` (SKILL.md „Checks on
   OpenAI“). It shares four sandbox slots across all sessions of the pod
   and goes direct when they are taken. For `translate` use
   CHECK_DIRECT=1. The answer's `model` field stays the writer's id.
5. Keep to answer_by. When the article is over, end. Do not take another
   article: the dispatcher starts a fresh session for it.

End with the short report the skill describes: a table of id, kind,
result, model and notes, and how the article ended (`article.state`).
```

## Why this shape

- **One session per article, in parallel.** A session holds one article's
  context (the article, the outline, the checker reports) and nothing
  else, so a crash or a stuck check costs one article, not a batch. Since
  the platform fix of 8 October 2026 sessions in one pod run side by side,
  so six articles take about as long as one (~15–25 min) instead of
  six times that.
- **The tick only decides.** The dispatcher starts the sessions and ends
  within seconds, so the next tick is never blocked. The next tick's
  preflight counts the running articles (`articles_in_progress`) and
  fills only the free slots.
- **Preflight before the dispatcher.** An empty queue costs one HTTP call,
  not an agent start. An article session started for an article another
  session took meanwhile gets `empty` from `claim_article` and ends at
  once.
- **Six at most** (raised from three on 8 Oct 2026). The limit is not the server: `claim_article` is
  atomic, so two sessions never take the same article. It is pod memory
  (2 GB; each session runs its own `pi` plus the check scripts), the
  owner's compute for the GPT sandboxes (four slots pod-wide, enforced by
  `check.sh`) and the platform's hourly limit on one-off jobs.
- **`articles_in_progress` counts held leases.** A session that crashed
  stops counting when its lease expires (`fragment` 20 minutes,
  `translate` 15, other kinds 5). Its article then waits again and the
  next tick starts a new session for it.
- **Fallback if parallel sessions break again.** If the platform regresses
  (a session freezes on receipt, the pod OOM-restarts), set
  `--max-sessions 1` in the dispatcher's preflight and replace `6` with
  `1` in its prompt. That gives one article at a time with the same jobs.
