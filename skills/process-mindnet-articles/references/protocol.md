# Protocol: the agent as a model over the queue

## Why through a queue and why like this

The MindNet server runs as a Supabase Edge Function (ADR-0008) and
`pg_cron` turns the `processing_jobs` queue every minute
(`supabase/cron.sql`). The server cannot call an agent: it does not know
where the agent runs, when it runs, or whether it runs at all. So it
leaves finished prompts in a queue — the `agent_requests` table — and
whoever answers them is the model.

There are **two ways to the queue**, with one protocol:

| who | how | rows |
|---|---|---|
| a reader's own agent (ADR-0018) | the MindNet MCP endpoint `POST /mcp` with the reader's key; tools `status`, `claim_article`, `claim`, `answer`, `fail` | `assignee = 'own'` and the reader's `user_id` |
| the operator's system agent (ADR-0012) | SQL over Supabase (`execute_sql` or `psql`), see [supabase.md](supabase.md) | `assignee = 'ours'`, including Discover rows without a job |

The MCP tools do exactly what the three SQL statements do — the same
`skip locked` pick-up, the same lease, the same states — only behind a
key and only over that reader's rows. SKILL.md describes the tools; this
file describes what lies underneath, so that you know what to expect
from the server either way.

The division is deliberate: **the server stays the worker, the agent is
only the model.** The alternative „the agent does the whole job“ would
mean copying the prompts, the normalisation, the gate and the writes into
seven tables into the skill — and all of it would diverge from the
repository at the first prompt change. This way only one thing is swapped:
who answers the prompt. Prompts, versions, the distillate cache, the gate,
RLS and notifications stay in code, where they are tested.

It is what ADR-0007 promised about the queue: „the caller gets swapped“.
Only this time not the one who takes jobs, but the one who answers the model.

## The `agent_requests` table

Migration `0050_agent_requests`, columns `user_id` and `assignee` from
`0087`:

```sql
create table agent_requests (
  id             uuid primary key default gen_random_uuid(),
  -- the job the server asks for; null for a call outside the queue
  job_id         uuid references processing_jobs on delete cascade,
  -- the job's owner, filled by the server; null for Discover
  user_id        uuid,
  -- who answers: 'ours' = the operator's system agent, 'own' = the reader's
  -- own agent through MCP; decided from the reader's llm_preference when
  -- the row is created, a later change applies to later rows
  assignee       text not null default 'ours' check (assignee in ('ours', 'own')),
  -- kind of prompt: fragment | select | terms | translate | summary | genre | snippet | …
  kind           text not null,
  role           text not null check (role in ('heavy', 'light', 'judge')),
  lane           text not null check (lane in ('private', 'public')),
  -- idempotence: the same request has the same key even after a job restart (see below)
  request_key    text not null unique,
  -- the whole prompt including the article text; the agent nulls it after answering
  prompt         text,
  prompt_version text,
  language       text,
  -- JSON Schema of the answer (DISTILLATE_SCHEMA, SELECT_SCHEMA…) when there is one;
  -- informative for the agent, the prompt itself states the shape too
  schema         jsonb,
  max_tokens     int,
  state          text not null default 'pending'
                 check (state in ('pending', 'claimed', 'answered',
                                  'failed', 'superseded')),
  attempts       int not null default 0,
  claimed_at     timestamptz,
  claimed_by     text,
  answer         jsonb,
  -- id of the model the agent answered with; the server records it on the post
  model          text,
  answered_at    timestamptz,
  error          text,
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null default now() + interval '12 hours'
);

create index agent_requests_open_idx on agent_requests (created_at)
  where state in ('pending', 'claimed');

-- No policy: only the server (service role) and the operator's agent
-- (postgres) read and write the table. A reader's own agent reaches its
-- rows only through the MCP endpoint; the client never touches the table.
alter table agent_requests enable row level security;
```

`prompt` is nullable **on purpose**: the article text is not stored on
the server (ADR-0006) and this row is the only place it lies temporarily.
The agent nulls it when answering, the clean-up deletes the row within 24
hours. Pasted text (ADR-0009) is the only one living in the database anyway.

## The request key must not depend on the article text

`runJob` runs again from the start after every deferral and **fetches the
article again** — and the fetched text can differ between two ticks (ads,
date, comment counts). If the key were a hash of the whole prompt, the
second tick would create a new request and nobody would take the answer
to the first.

The key is therefore composed from **stable inputs**, not from the prompt:

| kind | request_key |
|---|---|
| `fragment` | `job_id \| fragment \| source_id \| language \| prompt_version` |
| `select` | `job_id \| select \| sha256(candidates JSON + reader parameters)` |
| `terms` | `job_id \| terms \| source_id \| target language \| terminology policy` |
| `translate` | `job_id \| translate \| fragment ordinal \| target language \| [policy \|] sha256(body)` — the policy segment only when it is not the default `keep_common` |
| `summary` | `job_id \| summary \| source_id \| language` |
| `genre` | `job_id \| genre \| source_id \| classifier version` |
| `fragment` from Discover | `discovery:<discovery_source_id> \| fragment \| source_id \| language \| prompt_version`, `job_id` is `null`, `lane` is `public` |
| outside the queue | `kind \| sha256(prompt)` |

And the other half of the same: **before fetching the article** the server
looks whether a `fragment` request for this job already exists. When it
does, it neither fetches nor composes anything — it takes the answer, or
keeps waiting.

## States

```
pending ──pick-up──► claimed ──answer──► answered ──clean-up after 24 h──► (deleted)
   ▲                    │
   │                    ├──permanent error / 3rd attempt / expires_at──► failed
   └──temporary error───┘──fallback answered after the deadline──► superseded ──► (deleted)
```

- **Lease**: a `claimed` row with an expired `claimed_at` is up for grabs
  again — for `fragment` after 20 minutes, for the other kinds after 5,
  the same for the MCP `claim` and the SQL pick-up. An agent that crashed
  midway blocks nothing. The deadlines are measured:
  `claimed_at` → `answered_at` over 7 days gave `fragment` 9.3 min on
  average and 14 at most, `translate` 74 s and 139 s, `select` 58 s and
  123 s, `summary` 25 s and 37 s. A uniform 20 minutes kept a stuck
  translation out of play ten times longer than it takes. One exception
  since ADR-0020: over MCP a `translate` has 15 minutes (reserve 10),
  because all translations of an article come to one session at once and
  their leases start together — 139 s per card times eight does not fit
  into five minutes. The other half
  is in `claim` and in the pick-up query: a row on which the answer
  deadline could not be met is not taken at all — for `fragment` at least
  18 minutes must remain, for the others 3. The SQL side is checked by
  `scripts/test-pickup.sh` on seeded timestamps, the MCP side by
  `apps/server/test`.
- **`attempts`** rises with every `claim`. The third failure = `failed`.
- **`expires_at`**: a request without an answer within 12 hours the
  clean-up marks `failed` with `error = 'agent neodpověděl'`; the job ends
  as failed and the reader gets a „Try again“ card with that reason.
- **`superseded`**: we asked, someone else answered. The server writes it
  the moment it reaches for the fallback after the deadline (see „Deadline
  and fallback“ below). It is not `failed` — the job does not fail on it,
  it just goes to the API model. Your answer would be discarded, so do not
  pick such a row up.
- **A dead row**: an open request for a job that is already `done` or
  `failed` the clean-up deletes on the next tick. Until it gets there, do
  not pick it up — `claim`, the pick-up query in supabase.md and
  `has-work.sh` bypass it with the job-state condition.
- **`answered` is not deleted at once.** When the job fails later (say on
  the embedding) and runs again from the start, it gets the same answers
  for free.

## What the server does

The server side is complete since 13 September 2026
(`packages/pipeline/src/agent.ts`, `llm.ts`, `apps/server/src/index.ts`,
migration `0050_agent_requests.sql`). How it works, so you know what to expect:

1. **The agent is a provider like any other.** In `providers.ts` it has the
   shape `db` — no url and no key — and is switched on **by the order in
   the lane**: `MINDNET_LLM_PRIVATE=agent,groq` as a trial, permanently in
   `models.config.ts`. Until it is in the order, nothing is written to
   `agent_requests` and the table is empty. The direct API path does not
   go away: it is the same chain, just with one more link.
2. **The server asks, the agent answers, the server waits by deferring.**
   When `callChain` hits `agent` and the row holds no answer, it creates
   the request and throws `AgentPending`; the queue defers the job by a
   minute (`deferJob`, the attempt does not count) and asks again on the
   next tick — with the same `request_key`, so it finds your row. For a
   reader's own agent the tick is no longer the path (ADR-0020): `answer`
   and a permanent `fail` run the job at once (`advanceForAgent` in
   `apps/server/src/index.ts`), and what the job asks next is claimed for
   the same key and returned in `next`. The job is then deferred for the
   length of the lease, so the cron does not run it in vain meanwhile;
   the tick stays the safety net for a crashed session and for the
   system agent, which works over SQL.
3. **Deadline and fallback.** When another provider stands after the agent
   in the order and a request hangs longer than `MINDNET_AGENT_TIMEOUT_MIN`
   (default 45 min), the server lets the API answer and your late answer
   is discarded — closing the row as `superseded`, so you no longer see it
   in the queue. When the agent is alone in the lane, it waits until
   `expires_at` (12 h) and then the job fails with „agent neodpověděl“.
   **So answer within three quarters of an hour of `created_at`**; the
   deadline is this long on purpose, so that a second attempt at a
   `fragment` after an expired lease fits into it, not so the answer can
   drag; a run every five minutes meets it with room to spare. A reader's
   own agent gets 90 minutes (`MINDNET_AGENT_OWN_TIMEOUT_MIN`), because
   a cloud routine runs at most hourly; `claim` returns the exact moment
   as `answer_by`. Between `ours` and `own` nothing falls over: the
   fallback of an own agent is an API model, not the system agent.
4. **The prompt is composed separately for every provider.** The agent
   gets the whole article (ceiling 400,000 characters), Groq as the
   fallback one trimmed to its 16,000. The tag `[… middle of the article
   omitted …]` therefore appears in your prompt only for really long texts.
5. **Everything that needs a model the server asks before the first
   write**: distillate → selection → article terminology → translations of
   the selected fragments and the article's introduction → only then
   `insertThread` and the rest. The translations of one thread arise in
   one round, after the terminology, not one by one.
6. **Synchronous paths** (`/article/:id/rescan`, Discover, `/highlight`,
   `/ask`, instruction compilation, `pick`, the reader's article
   translation and terminology) skip the agent and go to the API providers
   in order. Into `agent_requests` therefore come only `fragment`,
   `genre`, `select`, `terms`, `translate` and `summary` from the queue.
7. **Clean-up in `/cron/tick`**: `answered` and `superseded` older than
   24 h are deleted, `pending` and `claimed` past `expires_at` end as
   `failed`, an open row for a job in state `done` or `failed` is deleted
   at once (nobody waits for its answer), and on everything nobody reads
   any more `prompt` is nulled — a safety net for an agent that did not
   null it when answering. **`/health`** reports
   `agent: { open, answered, oldest_s }`, where `open` is work actually
   waited for — rows for finished jobs are not counted, so that `oldest_s`
   does not raise an alarm over a dead queue. `/health` also reports
   `translations`: how many translations the gate passed and dropped, with
   reasons and by model.

## Timing

- The queue ticks every minute (`pg_cron` → `/cron/queue`); the Edge
  Function has 150 s per invocation and **does not wait** inside it — hence
  deferral, not sleep.
- An article for a reader whose language differs from the article's =
  up to five rounds: `genre` → `fragment` → `select` → `terms` +
  `summary` → `translate` × N. Over SQL (the system agent) every round
  waits for a tick and an agent run: with the agent launched every five
  minutes the article is in the feed in roughly 10–25 minutes. Over MCP
  (own agent, ADR-0020) the rounds follow at once: measured locally on
  8 October 2026 the server handed out the next step in 0.2–1.5 s, the
  `fragment` round in 15 s (the model gate A4 runs inside it), so the
  article takes what the writing takes — mostly the 10–18 minutes of a
  `fragment`.
- Cheapest is to wake the agent **often and briefly**, not rarely with a
  big batch: an empty query costs milliseconds, the waiting is paid by the reader.

## Lanes and content

The server keeps sending `lane`. So far it decided which provider the
content may go to: Gemini's free tier trains on inputs, hence only
`public`; Groq does not, hence `private` (ADR-0008). With the agent
everything goes through the Claude subscription of whoever runs the agent.
Whether that suffices for own articles, pasted text and readers'
instructions is the operator's decision and their terms, not the agent's.
The agent only states `lane` in the report and does not change behaviour by it.

## Check queries (system agent, SQL only)

A reader's own agent has `status` for this. These are for the operator
with database access, read only:

```sql
-- what waits and for how long
select state, kind, count(*), min(created_at), max(created_at)
  from agent_requests group by 1, 2 order by 1, 2;

-- the requests of one job
select id, kind, state, attempts, error, created_at, answered_at
  from agent_requests where job_id = '<job>' order by created_at;

-- the state of the job the server asks for (read only)
select id, state, attempts, next_attempt_at, last_error
  from processing_jobs where id = '<job>';
```
