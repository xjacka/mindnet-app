#!/usr/bin/env bash
# Vybírá vyzvedávací dotaz z references/supabase.md opravdu to, co má?
#
# Jen pro cestu přes SQL (systémový agent provozovatele). Výběr pro
# vlastního agenta přes MCP dělá server (`ownAgentClaim` v repo.ts) a
# hlídá ho apps/server/test.
#
# Prázdná fronta o dotazu nedokáže nic — přeloží se a vrátí nic, ať je
# podmínka jakákoli. Tenhle test proto do `agent_requests` **dosadí časy**
# (čerstvý řádek, propadlá výpůjčka, řádek těsně před lhůtou), pustí na ně
# tentýž `where` jako references/supabase.md a porovná, co prošlo, s tím, co projít mělo.
# Běží v transakci, která se na konci vrátí — v databázi nezůstane nic.
# Přesto ho pouštěj na lokální (`supabase db reset --local`), ne na ostré:
# zapisuje, i když po sobě uklidí.
#
# Když měníš lhůty v references/supabase.md, změň je i tady — `where` níž je opsaný
# a test hlídá právě tu shodu.
#
# Návratový kód:
#   0  všechny případy sedí
#   1  aspoň jeden neprošel (vypíše který)
#   2  chybí DATABASE_URL nebo psql
#   3  dotaz selhal (spojení, tabulka neexistuje — migrace 0050)
#
# Použití:
#   test-vyzvednuti.sh
#   test-vyzvednuti.sh --env-file /cesta/.env
set -u

env_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --env-file) shift; env_file="${1:-}" ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "neznámý přepínač: $1" >&2; exit 2 ;;
  esac
  shift
done

root="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd)"
[ -n "$env_file" ] || env_file="$root/.env"
if [ -z "${DATABASE_URL:-}" ] && [ -f "$env_file" ]; then
  DATABASE_URL="$(sed -n 's/^DATABASE_URL=//p' "$env_file" | head -n 1 \
    | sed -e "s/^['\"]//" -e "s/['\"]$//")"
fi
[ -n "${DATABASE_URL:-}" ] || { echo "chybí DATABASE_URL" >&2; exit 2; }
command -v psql >/dev/null 2>&1 || { echo "chybí psql" >&2; exit 2; }

tmp="$(mktemp)"; trap 'rm -f "$tmp" "$tmp.err"' EXIT

if ! psql "$DATABASE_URL" -X -q -A -t -F '|' -v ON_ERROR_STOP=1 > "$tmp" 2> "$tmp.err" <<'SQL'
begin;

-- Dva joby: jeden běží, jeden doběhl. Řádek k doběhlému je mrtvý.
-- `url` chce constraint processing_jobs_url_check (job bez adresy je jen hledání).
insert into processing_jobs (id, state, url) values
  ('00000000-0000-4000-8000-00000000a11e', 'fragmenting', 'https://example.test/a'),
  ('00000000-0000-4000-8000-00000000dead', 'done', 'https://example.test/b');

-- Případy: věk řádku, stáří výpůjčky a co se od dotazu čeká.
-- `vek_min` je jak dávno vznikl (od něj běží lhůta na odpověď),
-- `pujcka_min` jak dávno si ho někdo vzal (null = nevyzvednutý).
create temp table pripady (
  nazev text primary key, kind text, stav text,
  vek_min numeric, pujcka_min numeric, expires_h numeric,
  job uuid, ma_projit boolean
);
insert into pripady values
  ('a1 fragment čerstvý',                    'fragment',  'pending',     1, null,  12, null, true),
  ('a2 translate čerstvý',                   'translate', 'pending',     1, null,  12, null, true),

  -- Výpůjčka ještě běží: řádek patří tomu, kdo si ho vzal.
  ('b1 fragment ve výpůjčce (10 min)',       'fragment',  'claimed',    11,   10,  12, null, false),
  ('c1 translate ve výpůjčce (3 min)',       'translate', 'claimed',     4,    3,  12, null, false),

  -- Propadlá výpůjčka a dost času na druhý pokus → vzít.
  -- b2 je regrese: s odečtem od 30 minut tenhle řádek propadal dírou,
  -- protože by musel být mladší než 16 minut, ale starší než 15. Od
  -- 6. 10. 2026 je výpůjčka fragmentu 20 minut a rezerva 18, takže okno
  -- pro druhý pokus je stáří 20 až 27 minut.
  ('b2 fragment po propadlé výpůjčce',       'fragment',  'claimed',    23,   22,  12, null, true),
  ('c2 translate po propadlé výpůjčce',      'translate', 'claimed',     7,    6,  12, null, true),

  -- Propadlá výpůjčka, ale do lhůty už se to nestihne → nebrat.
  ('b3 fragment propadlý, bez času',         'fragment',  'claimed',    35,   34,  12, null, false),
  ('c3 translate propadlý, bez času',        'translate', 'claimed',    43,   42,  12, null, false),

  -- Hranice zbývajícího času: fragment potřebuje 18 minut, ostatní 3.
  ('d1 fragment 26 min (zbývá 19)',          'fragment',  'pending',    26, null,  12, null, true),
  ('d2 fragment 28 min (zbývá 17)',          'fragment',  'pending',    28, null,  12, null, false),
  ('d3 translate 41 min (zbývá 4)',          'translate', 'pending',    41, null,  12, null, true),
  ('d4 translate 43 min (zbývá 2)',          'translate', 'pending',    43, null,  12, null, false),

  ('e1 vypršelý řádek',                      'fragment',  'pending',     1, null,  -1, null, false),

  ('f1 k doběhlému jobu',                    'fragment',  'pending',     1, null,  12, '00000000-0000-4000-8000-00000000dead', false),
  ('f2 k běžícímu jobu',                     'fragment',  'pending',     1, null,  12, '00000000-0000-4000-8000-00000000a11e', true),

  -- Uzavřené stavy se nevyzvedávají vůbec.
  ('g1 answered',                            'fragment',  'answered',    1, null,  12, null, false),
  ('g2 superseded',                          'fragment',  'superseded',  1, null,  12, null, false),
  ('g3 failed',                              'fragment',  'failed',      1, null,  12, null, false),

  -- Řádek vlastního agenta čtenáře (ADR-0018) náš agent nebere.
  ('h1 vlastní agent čtenáře',               'translate', 'pending',     1, null,  12, null, false);

insert into agent_requests
  (request_key, kind, role, lane, state, prompt, created_at, claimed_at, expires_at, job_id)
select nazev, kind, 'heavy', 'private', stav, 'zadání',
       now() - (vek_min || ' minutes')::interval,
       case when pujcka_min is null then null
            else now() - (pujcka_min || ' minutes')::interval end,
       now() + (expires_h || ' hours')::interval,
       job
  from pripady;

-- Tentýž `where` jako v references/supabase.md. `order by`, `limit 1` a `for update
-- skip locked` tu nejsou schválně: ty vybírají, který jeden řádek si
-- vezmeš, kdežto tohle ověřuje, které řádky do výběru vůbec patří.
update agent_requests set assignee = 'own' where request_key like 'h1 %';

create temp table proslo as
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

select case when (v.request_key is not null) = p.ma_projit then 'OK' else 'CHYBA' end
       || '|' || p.nazev
       || '|' || case when p.ma_projit then 'mělo projít' else 'nemělo projít' end
       || '|' || case when v.request_key is not null then 'prošlo' else 'neprošlo' end
  from pripady p
  left join proslo v on v.request_key = p.nazev
 order by p.nazev;

rollback;
SQL
then
  if grep -q 'does not exist' "$tmp.err"; then
    echo "tabulka agent_requests neexistuje — migrace 0050 není nasazená" >&2
  else
    echo "dotaz selhal: $(tr '\n' ' ' < "$tmp.err")" >&2
  fi
  exit 3
fi

chyb=0; celkem=0
while IFS='|' read -r verdikt nazev cekano skutecnost; do
  [ -n "${verdikt:-}" ] || continue
  celkem=$((celkem + 1))
  if [ "$verdikt" = "OK" ]; then
    echo "  ok    $nazev"
  else
    chyb=$((chyb + 1))
    echo "  CHYBA $nazev — $cekano, ale $skutecnost"
  fi
done < "$tmp"

if [ "$celkem" -eq 0 ]; then
  echo "test nic nevyhodnotil — dotaz neprošel?" >&2
  exit 3
fi
if [ "$chyb" -gt 0 ]; then
  echo "$chyb z $celkem případů nesedí"
  exit 1
fi
echo "všech $celkem případů sedí"
