#!/usr/bin/env bash
# kontrola.sh — jedna kontrola (extractor/cold/fidelity/proofread) na GPT,
# jiná rodina než pisatel (Claude), čistý kontext.
#
# Varianta (a) dle zadání operátora (8. 10. 2026): PRIMÁRNĚ platformní
# subagent (spawn přes driver SDK v soudce.py, tj. tentýž platform
# mechanismus jako MCP spawn_subagent/await_subagents, ale s pollováním,
# které netrpí 60s stropem MCP await). FALLBACK na --direct, když spawn
# selže — nejčastěji „liveness deadline exceeded“ i při volném rozpočtu,
# nebo nedostatečná kapacita (fronta).
#
# Použití (stejné argumenty jako soudce.py, bez --direct):
#   kontrola.sh PROMPT_FILE --schema fidelity --label fid --out /tmp/fid.json
# Volitelně KONTROLA_DIRECT=1 vynutí rovnou --direct (když víš, že
# rozpočet je plný a nechceš platit čas čekáním na selhání spawnu).
# KONTROLA_SLOTS (default 4) = max. souběžných sandboxů v podu; když jsou
# všechny obsazené (jiné session téhož podu), jde se rovnou --direct.
#
# Výsledek (ověřený JSON) jde na stdout a do --out; stderr nese průběh
# a cestu (spawn / fallback-direct). Návratový kód 0 hotovo, 1 obě cesty
# selhaly, 2 špatné argumenty.
set -uo pipefail

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/soudce.py"
if [ ! -f "$S" ]; then echo "kontrola.sh: soudce.py nenalezen vedle skriptu" >&2; exit 2; fi

if [ "${KONTROLA_DIRECT:-0}" = "1" ]; then
  echo "kontrola.sh: KONTROLA_DIRECT=1 → rovnou --direct" >&2
  exec python3 "$S" "$@" --direct
fi

# Sloty na sandboxy: nejvýš KONTROLA_SLOTS (default 4) spawnů najednou
# v celém podu, napříč všemi souběžnými session (od 8. 10. 2026 běží
# články paralelně jako samostatné session v jednom podu). Když je volný
# slot, drží ho flock po dobu spawnu; když ne, jde se rovnou --direct —
# na sandbox se nečeká, kontrola se nezdržuje.
SLOTS="${KONTROLA_SLOTS:-4}"
LOCKDIR="${KONTROLA_LOCKDIR:-/tmp/kontrola-slots}"
mkdir -p "$LOCKDIR"
slot_fd=""
for i in $(seq 1 "$SLOTS"); do
  exec {fd}>"$LOCKDIR/slot-$i.lock"
  if flock -n "$fd"; then slot_fd=$fd; echo "kontrola.sh: sandbox slot $i/$SLOTS" >&2; break; fi
  exec {fd}>&-
done
if [ -z "$slot_fd" ]; then
  echo "kontrola.sh: všech $SLOTS sandbox slotů obsazeno → rovnou --direct" >&2
  exec python3 "$S" "$@" --direct
fi

# 1) Primární cesta: platformní subagent (soudce.py bez --direct).
if python3 "$S" "$@"; then
  exit 0
fi
rc=$?
exec {slot_fd}>&-   # slot uvolnit před fallbackem
echo "kontrola.sh: platformní spawn selhal (rc=$rc) → fallback na --direct" >&2

# 2) Fallback: přímé volání GPT přes LiteLLM, čistý kontext, bez sandboxu.
if python3 "$S" "$@" --direct; then
  echo "kontrola.sh: fallback --direct uspěl" >&2
  exit 0
fi
echo "kontrola.sh: selhaly obě cesty (spawn i --direct)" >&2
exit 1
