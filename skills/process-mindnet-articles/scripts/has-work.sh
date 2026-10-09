#!/usr/bin/env bash
# Is there work for the agent waiting in the `agent_requests` queue?
#
# Only for the operator's system agent (the SQL path,
# references/supabase.md). A reader's own agent calls the MCP tool
# `status` and does not need this script.
#
# The exit code is the answer; the output is only a supplement:
#   0  yes — prints how many requests of which kind are waiting
#   1  no — the queue is empty
#   2  configuration missing: DATABASE_URL, or SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
#   3  the query failed: connection, key, table missing (migration 0050), API error
#
# A row counts as work when the agent may take it — `pending`, or
# `claimed` with an expired lease (fragment 20 minutes, other kinds 5),
# only until it expires (`expires_at`), only while the answer deadline can
# still be met on it (45 min from created_at minus the measured maximum of the kind)
# — and **only while someone still waits for its answer**: the job it was
# created for must be neither `done` nor `failed`.
# A row of a finished job is dead: nobody reads its answer. Since migration
# 0055 the server closes such rows itself (`superseded` when the fallback takes
# over, deletion in clean-up); this is a safeguard for the window before clean-up
# ticks — and for rows of a job that failed for another reason. Same selection as references/supabase.md.
#
# Usage:
#   has-work.sh            prints a summary and returns the code
#   has-work.sh -q         code only, prints nothing
#   has-work.sh --env-file /path/.env
#
# Database access: `psql` with DATABASE_URL first; without it the Supabase
# REST interface (PostgREST) with the service key via `curl`. Variables come
# from the environment; missing ones are filled from `.env` in the repository
# root (or from --env-file). Writes nothing — SELECTs only.
set -u

quiet=0
env_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    -q|--quiet) quiet=1 ;;
    --env-file) shift; env_file="${1:-}" ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { [ "$quiet" -eq 1 ] || echo "$*"; }
err() { echo "$*" >&2; }

# --- variables: environment first, then .env --------------------------------
root="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd)"
[ -n "$env_file" ] || env_file="$root/.env"
from_env_file() {  # from_env_file NAME → value without quotes, or nothing
  [ -f "$env_file" ] || return 0
  sed -n "s/^$1=//p" "$env_file" | head -n 1 | sed -e "s/^['\"]//" -e "s/['\"]$//"
}
: "${DATABASE_URL:=$(from_env_file DATABASE_URL)}"
: "${SUPABASE_URL:=$(from_env_file SUPABASE_URL)}"
: "${SUPABASE_SERVICE_ROLE_KEY:=$(from_env_file SUPABASE_SERVICE_ROLE_KEY)}"

tmp="$(mktemp)"
trap 'rm -f "$tmp" "$tmp".err "$tmp".json "$tmp".job' EXIT

# --- evaluate "kind|count" rows ----------------------------------------------
report() {  # reads $tmp: lines kind|n
  total=0; parts=""
  while IFS='|' read -r kind n; do
    [ -n "${kind:-}" ] || continue
    total=$((total + n))
    parts="${parts:+$parts, }$kind $n"
  done < "$tmp"
  if [ "$total" -gt 0 ]; then
    say "waiting $total: $parts"
    exit 0
  fi
  say "queue is empty"
  exit 1
}

# --- path 1: psql -------------------------------------------------------------
if [ -n "${DATABASE_URL:-}" ] && command -v psql >/dev/null 2>&1; then
  if ! psql "$DATABASE_URL" -X -q -A -t -F '|' -v ON_ERROR_STOP=1 -c "
      select r.kind, count(*)
        from agent_requests r
        left join processing_jobs j on j.id = r.job_id
       where r.expires_at > now()
         -- only for the MindNet agent; own rows belong to a reader's own agent (ADR-0018)
         and r.assignee = 'ours'
         -- the lease is as long as the kind really takes
         and (r.state = 'pending'
              or (r.state = 'claimed'
                  and r.claimed_at < now() - case when r.kind = 'fragment'
                                                  then interval '20 minutes'
                                                  else interval '5 minutes' end))
         -- what cannot be finished before the deadline is not work; 45 = MINDNET_AGENT_TIMEOUT_MIN
         and r.created_at > now() - interval '45 minutes'
                                  + case when r.kind = 'fragment'
                                         then interval '18 minutes'
                                         else interval '3 minutes' end
         -- job already finished → nobody reads the answer; no job = a call outside the queue
         and (r.job_id is null or j.state not in ('done', 'failed'))
       group by r.kind
       order by r.kind" > "$tmp" 2> "$tmp.err"; then
    if grep -q 'does not exist' "$tmp.err"; then
      err "table agent_requests does not exist — migration 0050 is not deployed"
    else
      err "query failed: $(tr '\n' ' ' < "$tmp.err")"
    fi
    exit 3
  fi
  report
fi

# --- path 2: Supabase REST interface -----------------------------------------
if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
  command -v curl >/dev/null 2>&1 || { err "neither curl nor psql is available"; exit 2; }
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  minutes_ago() {  # minutes_ago N → the time N minutes ago in UTC
    date -u -d "$1 minutes ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u -v-"$1"M +%Y-%m-%dT%H:%M:%SZ
  }
  # Expired lease: fragment after 20 minutes, other kinds after 5 — the same
  # numbers as the SQL above; keep them in step when the lease changes.
  lease_f="$(minutes_ago 20)"; lease_o="$(minutes_ago 5)"
  # The last moment a row can still meet the deadline: 45 min minus the kind's
  # reserve (fragment 18 → 27, other kinds 3 → 42).
  deadline_f="$(minutes_ago 27)"; deadline_o="$(minutes_ago 42)"
  # PostgREST joins repeated `or=` with AND, so this is the same condition
  # as the `case` in references/supabase.md — just split into two branches by kind.
  open_rows=(
    --data-urlencode "expires_at=gt.$now"
    --data-urlencode "assignee=eq.ours"
    --data-urlencode "or=(state.eq.pending,and(state.eq.claimed,kind.eq.fragment,claimed_at.lt.$lease_f),and(state.eq.claimed,kind.neq.fragment,claimed_at.lt.$lease_o))"
    --data-urlencode "or=(and(kind.eq.fragment,created_at.gt.$deadline_f),and(kind.neq.fragment,created_at.gt.$deadline_o))"
  )
  query() {  # query FILE PARAM… → body into FILE, HTTP code to stdout
    curl -sS -G "${SUPABASE_URL%/}/rest/v1/agent_requests" \
      -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Accept: application/json" \
      "${open_rows[@]}" "${@:2}" \
      -o "$1" -w '%{http_code}'
  }
  check_http() {  # check_http CODE FILE
    case "$1" in
      200|206) return 0 ;;
      401|403) err "Supabase service key is not valid (HTTP $1)"; exit 2 ;;
      404) err "table agent_requests is not available over REST — migration 0050 is not deployed (HTTP 404)"; exit 3 ;;
      *) err "REST answered HTTP $1: $(head -c 300 "$2")"; exit 3 ;;
    esac
  }
  # Two queries instead of one: the job state is an embedded resource and can
  # only be filtered through `!inner`, which would also drop rows without a job
  # (calls outside the queue).
  code="$(query "$tmp.job" \
      --data-urlencode "select=kind,processing_jobs!inner(state)" \
      --data-urlencode "processing_jobs.state=not.in.(done,failed)")" \
    || { err "connection failed"; exit 3; }
  check_http "$code" "$tmp.job"
  code="$(query "$tmp.json" \
      --data-urlencode "select=kind" \
      --data-urlencode "job_id=is.null")" \
    || { err "connection failed"; exit 3; }
  check_http "$code" "$tmp.json"
  # [{"kind":"fragment",…},…] → kind|n without depending on jq
  grep -ho '"kind":"[^"]*"' "$tmp.job" "$tmp.json" | sed 's/"kind":"\(.*\)"/\1/' | sort | uniq -c \
    | awk '{ print $2 "|" $1 }' > "$tmp"
  report
fi

err "configuration missing: DATABASE_URL (with psql), or SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (with curl)"
exit 2
