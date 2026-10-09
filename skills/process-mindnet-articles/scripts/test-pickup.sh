#!/usr/bin/env bash
# Does the pick-up query from references/supabase.md really select what it should?
#
# Only for the SQL path (the operator's system agent). Selection for a
# reader's own agent over MCP is done by the server (`ownAgentClaim` in repo.ts)
# and guarded by apps/server/test.
#
# An empty queue proves nothing about the query — it compiles and returns nothing,
# whatever the condition. So this test **seeds timestamps** into `agent_requests`
# (a fresh row, an expired lease, a row just before the deadline), runs over them
# the same `where` as references/supabase.md and compares what passed with what should have.
# It runs in a transaction that is rolled back at the end — nothing stays in the database.
# Still, run it against a local database (`supabase db reset --local`), not production:
# it writes, even though it cleans up after itself.
#
# When you change the deadlines in references/supabase.md, change them here too — the
# `where` below is a copy and the test guards exactly that match.
#
# Exit code:
#   0  all cases match
#   1  at least one did not (prints which)
#   2  DATABASE_URL or psql missing
#   3  the query failed (connection, table missing — migration 0050)
#
# Usage:
#   test-pickup.sh
#   test-pickup.sh --env-file /path/.env
set -u

env_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --env-file) shift; env_file="${1:-}" ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

root="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd)"
[ -n "$env_file" ] || env_file="$root/.env"
if [ -z "${DATABASE_URL:-}" ] && [ -f "$env_file" ]; then
  DATABASE_URL="$(sed -n 's/^DATABASE_URL=//p' "$env_file" | head -n 1 \
    | sed -e "s/^['\"]//" -e "s/['\"]$//")"
fi
[ -n "${DATABASE_URL:-}" ] || { echo "DATABASE_URL is missing" >&2; exit 2; }
command -v psql >/dev/null 2>&1 || { echo "psql is missing" >&2; exit 2; }

tmp="$(mktemp)"; trap 'rm -f "$tmp" "$tmp.err"' EXIT

if ! psql "$DATABASE_URL" -X -q -A -t -F '|' -v ON_ERROR_STOP=1 > "$tmp" 2> "$tmp.err" <<'SQL'
begin;

-- Two jobs: one running, one finished. A row of the finished one is dead.
-- `url` is required by constraint processing_jobs_url_check (a job without a URL is just a search).
insert into processing_jobs (id, state, url) values
  ('00000000-0000-4000-8000-00000000a11e', 'fragmenting', 'https://example.test/a'),
  ('00000000-0000-4000-8000-00000000dead', 'done', 'https://example.test/b');

-- Cases: age of the row, age of the lease and what the query is expected to do.
-- `age_min` is how long ago the row was created (the answer deadline runs from it),
-- `lease_min` how long ago someone claimed it (null = not claimed).
create temp table cases (
  name text primary key, kind text, state text,
  age_min numeric, lease_min numeric, expires_h numeric,
  job uuid, should_pass boolean
);
insert into cases values
  ('a1 fresh fragment',                      'fragment',  'pending',     1, null,  12, null, true),
  ('a2 fresh translate',                     'translate', 'pending',     1, null,  12, null, true),

  -- The lease is still running: the row belongs to whoever claimed it.
  ('b1 fragment under lease (10 min)',       'fragment',  'claimed',    11,   10,  12, null, false),
  ('c1 translate under lease (3 min)',       'translate', 'claimed',     4,    3,  12, null, false),

  -- Expired lease and enough time for a second attempt → take.
  -- b2 is a regression: with the subtraction from 30 minutes this row fell through
  -- a gap, because it would have to be younger than 16 minutes but older than 15.
  -- Since 6 October 2026 the fragment lease is 20 minutes and the reserve 18, so
  -- the window for a second attempt is an age of 20 to 27 minutes.
  ('b2 fragment after expired lease',        'fragment',  'claimed',    23,   22,  12, null, true),
  ('c2 translate after expired lease',       'translate', 'claimed',     7,    6,  12, null, true),

  -- Expired lease, but it can no longer be finished before the deadline → do not take.
  ('b3 fragment expired, no time left',      'fragment',  'claimed',    35,   34,  12, null, false),
  ('c3 translate expired, no time left',     'translate', 'claimed',    43,   42,  12, null, false),

  -- Remaining-time boundary: fragment needs 18 minutes, the others 3.
  ('d1 fragment 26 min (19 left)',           'fragment',  'pending',    26, null,  12, null, true),
  ('d2 fragment 28 min (17 left)',           'fragment',  'pending',    28, null,  12, null, false),
  ('d3 translate 41 min (4 left)',           'translate', 'pending',    41, null,  12, null, true),
  ('d4 translate 43 min (2 left)',           'translate', 'pending',    43, null,  12, null, false),

  ('e1 expired row',                         'fragment',  'pending',     1, null,  -1, null, false),

  ('f1 of a finished job',                   'fragment',  'pending',     1, null,  12, '00000000-0000-4000-8000-00000000dead', false),
  ('f2 of a running job',                    'fragment',  'pending',     1, null,  12, '00000000-0000-4000-8000-00000000a11e', true),

  -- Closed states are never picked up.
  ('g1 answered',                            'fragment',  'answered',    1, null,  12, null, false),
  ('g2 superseded',                          'fragment',  'superseded',  1, null,  12, null, false),
  ('g3 failed',                              'fragment',  'failed',      1, null,  12, null, false),

  -- A row of a reader's own agent (ADR-0018) is not taken by our agent.
  ('h1 reader''s own agent',                 'translate', 'pending',     1, null,  12, null, false);

insert into agent_requests
  (request_key, kind, role, lane, state, prompt, created_at, claimed_at, expires_at, job_id)
select name, kind, 'heavy', 'private', state, 'prompt',
       now() - (age_min || ' minutes')::interval,
       case when lease_min is null then null
            else now() - (lease_min || ' minutes')::interval end,
       now() + (expires_h || ' hours')::interval,
       job
  from cases;

-- The same `where` as in references/supabase.md. `order by`, `limit 1` and `for update
-- skip locked` are left out on purpose: they choose which single row you
-- take, whereas this checks which rows belong in the selection at all.
update agent_requests set assignee = 'own' where request_key like 'h1 %';

create temp table passed as
select request_key from agent_requests
 where expires_at > now()
   and assignee = 'ours'
   and (state = 'pending'
        or (state = 'claimed'
            and claimed_at < now() - case when kind = 'fragment'
                                          then interval '20 minutes'
                                          else interval '5 minutes' end))
   and created_at > now() - interval '45 minutes'
                          + case when kind = 'fragment'
                                 then interval '18 minutes'
                                 else interval '3 minutes' end
   and (job_id is null
        or exists (select 1 from processing_jobs j
                    where j.id = agent_requests.job_id
                      and j.state not in ('done', 'failed')));

select case when (v.request_key is not null) = p.should_pass then 'OK' else 'FAIL' end
       || '|' || p.name
       || '|' || case when p.should_pass then 'should pass' else 'should not pass' end
       || '|' || case when v.request_key is not null then 'passed' else 'did not pass' end
  from cases p
  left join passed v on v.request_key = p.name
 order by p.name;

rollback;
SQL
then
  if grep -q 'does not exist' "$tmp.err"; then
    echo "table agent_requests does not exist — migration 0050 is not deployed" >&2
  else
    echo "query failed: $(tr '\n' ' ' < "$tmp.err")" >&2
  fi
  exit 3
fi

failures=0; total=0
while IFS='|' read -r verdict name expected actual; do
  [ -n "${verdict:-}" ] || continue
  total=$((total + 1))
  if [ "$verdict" = "OK" ]; then
    echo "  ok    $name"
  else
    failures=$((failures + 1))
    echo "  FAIL  $name — $expected, but it $actual"
  fi
done < "$tmp"

if [ "$total" -eq 0 ]; then
  echo "the test evaluated nothing — did the query fail?" >&2
  exit 3
fi
if [ "$failures" -gt 0 ]; then
  echo "$failures of $total cases do not match"
  exit 1
fi
echo "all $total cases match"
