#!/usr/bin/env bash
# Čeká ve frontě `agent_requests` práce pro agenta?
#
# Jen pro systémového agenta provozovatele (cesta přes SQL,
# references/supabase.md). Vlastní agent čtenáře přes MCP volá nástroj
# `status` a tenhle skript nepotřebuje.
#
# Návratový kód je odpověď, výpis jen doplněk:
#   0  ano — vypíše, kolik požadavků a jakého druhu čeká
#   1  ne — fronta je prázdná
#   2  chybí nastavení: DATABASE_URL, nebo SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
#   3  dotaz selhal: spojení, klíč, tabulka neexistuje (migrace 0050), chyba API
#
# Za práci se počítá řádek, který si smí agent vzít — `pending`, nebo
# `claimed` s propadlou výpůjčkou (fragment 20 minut, ostatní druhy 5),
# jen dokud nevypršel (`expires_at`), jen dokud se na něm dá stihnout
# lhůta pro odpověď (45 min od created_at minus měřené maximum druhu)
# — a **na jehož odpověď ještě někdo čeká**: job, kvůli kterému vznikl,
# nesmí být `done` ani `failed`.
# Řádek k dokončenému jobu je mrtvý: odpověď na něj nikdo nečte. Server
# je od migrace 0055 zavírá sám (`superseded` při přepadu na zálohu, mazání
# v úklidu), tohle je pojistka na okno, než úklid tikne — a na řádky po
# jobu, který spadl z jiného důvodu. Totéž, co vybírá dotaz v references/supabase.md.
#
# Použití:
#   ceka-prace.sh            vypíše souhrn a vrátí kód
#   ceka-prace.sh -q         jen kód, nic nevypisuje
#   ceka-prace.sh --env-file /cesta/.env
#
# Cesta k databázi: přednostně `psql` s DATABASE_URL; bez něj REST rozhraní
# Supabase (PostgREST) se servisním klíčem přes `curl`. Proměnné bere
# z prostředí, chybějící doplní z `.env` v kořeni repozitáře (nebo z
# --env-file). Nic nezapisuje — jsou to jen SELECTy.
set -u

quiet=0
env_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    -q|--quiet) quiet=1 ;;
    --env-file) shift; env_file="${1:-}" ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "neznámý přepínač: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { [ "$quiet" -eq 1 ] || echo "$*"; }
err() { echo "$*" >&2; }

# --- proměnné: prostředí, potom .env -----------------------------------------
root="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd)"
[ -n "$env_file" ] || env_file="$root/.env"
from_env_file() {  # from_env_file NÁZEV → hodnota bez uvozovek, nebo nic
  [ -f "$env_file" ] || return 0
  sed -n "s/^$1=//p" "$env_file" | head -n 1 | sed -e "s/^['\"]//" -e "s/['\"]$//"
}
: "${DATABASE_URL:=$(from_env_file DATABASE_URL)}"
: "${SUPABASE_URL:=$(from_env_file SUPABASE_URL)}"
: "${SUPABASE_SERVICE_ROLE_KEY:=$(from_env_file SUPABASE_SERVICE_ROLE_KEY)}"

tmp="$(mktemp)"
trap 'rm -f "$tmp" "$tmp".err "$tmp".json "$tmp".job' EXIT

# --- vyhodnocení řádků „kind|počet“ -------------------------------------------
report() {  # čte $tmp: řádky kind|n
  total=0; parts=""
  while IFS='|' read -r kind n; do
    [ -n "${kind:-}" ] || continue
    total=$((total + n))
    parts="${parts:+$parts, }$kind $n"
  done < "$tmp"
  if [ "$total" -gt 0 ]; then
    say "čeká $total: $parts"
    exit 0
  fi
  say "fronta je prázdná"
  exit 1
}

# --- cesta 1: psql ------------------------------------------------------------
if [ -n "${DATABASE_URL:-}" ] && command -v psql >/dev/null 2>&1; then
  if ! psql "$DATABASE_URL" -X -q -A -t -F '|' -v ON_ERROR_STOP=1 -c "
      select r.kind, count(*)
        from agent_requests r
        left join processing_jobs j on j.id = r.job_id
       where r.expires_at > now()
         -- jen pro agenta MindNetu; own patří vlastnímu agentovi čtenáře (ADR-0018)
         and r.assignee = 'ours'
         -- výpůjčka podle toho, jak dlouho druh opravdu trvá
         and (r.state = 'pending'
              or (r.state = 'claimed'
                  and r.claimed_at < now() - case when r.kind = 'fragment'
                                                  then interval '20 minutes'
                                                  else interval '5 minutes' end))
         -- co do lhůty nestihne, není práce; 45 = MINDNET_AGENT_TIMEOUT_MIN
         and r.created_at > now() - interval '45 minutes'
                                  + case when r.kind = 'fragment'
                                         then interval '18 minutes'
                                         else interval '3 minutes' end
         -- job už doběhl → odpověď nikdo nečte; bez jobu je to volání mimo frontu
         and (r.job_id is null or j.state not in ('done', 'failed'))
       group by r.kind
       order by r.kind" > "$tmp" 2> "$tmp.err"; then
    if grep -q 'does not exist' "$tmp.err"; then
      err "tabulka agent_requests neexistuje — migrace 0050 není nasazená"
    else
      err "dotaz selhal: $(tr '\n' ' ' < "$tmp.err")"
    fi
    exit 3
  fi
  report
fi

# --- cesta 2: REST rozhraní Supabase ----------------------------------------
if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
  command -v curl >/dev/null 2>&1 || { err "chybí curl i psql"; exit 2; }
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  pred() {  # pred MINUT → čas o tolik minut zpátky v UTC
    date -u -d "$1 minutes ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u -v-"$1"M +%Y-%m-%dT%H:%M:%SZ
  }
  # Propadlá výpůjčka: fragment po 20 minutách, ostatní druhy po 5.
  vyp_f="$(pred 15)"; vyp_o="$(pred 5)"
  # Poslední chvíle, kdy řádek ještě stihne lhůtu (45 min minus maximum druhu).
  lht_f="$(pred 31)"; lht_o="$(pred 42)"
  # Opakované `or=` PostgREST spojuje AND, takže je to tatáž podmínka
  # jako `case` v references/supabase.md — jen rozepsaná na dvě větve podle druhu.
  otevrene=(
    --data-urlencode "expires_at=gt.$now"
    --data-urlencode "assignee=eq.ours"
    --data-urlencode "or=(state.eq.pending,and(state.eq.claimed,kind.eq.fragment,claimed_at.lt.$vyp_f),and(state.eq.claimed,kind.neq.fragment,claimed_at.lt.$vyp_o))"
    --data-urlencode "or=(and(kind.eq.fragment,created_at.gt.$lht_f),and(kind.neq.fragment,created_at.gt.$lht_o))"
  )
  dotaz() {  # dotaz SOUBOR PARAM… → tělo do souboru, HTTP kód na výstup
    curl -sS -G "${SUPABASE_URL%/}/rest/v1/agent_requests" \
      -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Accept: application/json" \
      "${otevrene[@]}" "${@:2}" \
      -o "$1" -w '%{http_code}'
  }
  overit() {  # overit KÓD SOUBOR
    case "$1" in
      200|206) return 0 ;;
      401|403) err "servisní klíč Supabase neplatí (HTTP $1)"; exit 2 ;;
      404) err "tabulka agent_requests není přes REST k dispozici — migrace 0050 není nasazená (HTTP 404)"; exit 3 ;;
      *) err "REST odpověděl HTTP $1: $(head -c 300 "$2")"; exit 3 ;;
    esac
  }
  # Dva dotazy místo jednoho: stav jobu je vnořený zdroj a filtrovat se dá
  # jen přes `!inner`, který by zahodil i řádky bez jobu (volání mimo frontu).
  code="$(dotaz "$tmp.job" \
      --data-urlencode "select=kind,processing_jobs!inner(state)" \
      --data-urlencode "processing_jobs.state=not.in.(done,failed)")" \
    || { err "spojení selhalo"; exit 3; }
  overit "$code" "$tmp.job"
  code="$(dotaz "$tmp.json" \
      --data-urlencode "select=kind" \
      --data-urlencode "job_id=is.null")" \
    || { err "spojení selhalo"; exit 3; }
  overit "$code" "$tmp.json"
  # [{"kind":"fragment",…},…] → kind|n bez závislosti na jq
  grep -ho '"kind":"[^"]*"' "$tmp.job" "$tmp.json" | sed 's/"kind":"\(.*\)"/\1/' | sort | uniq -c \
    | awk '{ print $2 "|" $1 }' > "$tmp"
  report
fi

err "chybí nastavení: DATABASE_URL (s psql), nebo SUPABASE_URL a SUPABASE_SERVICE_ROLE_KEY (s curl)"
exit 2
