#!/usr/bin/env bash
# Inventár pracovnej kópie pluginu a rozpočet always-on tokenov (plán §15.3 L).
# `claude plugin details` počíta aj skilly s disable-model-invocation: true, ktorých popis
# podľa docs (skills.md) v kontexte nie je → rozpočet sa stráži bez nich.
set -u

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PLUGIN="${1:-$KIT_DIR/plugins/dev}"
BUDGET="${BUDGET:-3000}"
INIT_BUDGET="${INIT_BUDGET:-1500}"
CLAUDE="${CLAUDE:-claude}"
MANIFEST="$PLUGIN/.claude-plugin/plugin.json"
for limit in "$BUDGET" "$INIT_BUDGET"; do
  case "$limit" in ''|*[!0-9]*) echo "[dev-kit] rozpočet musí byť nezáporné celé číslo"; exit 1 ;; esac
done

if [ ! -f "$MANIFEST" ]; then
  echo "[dev-kit] chýba $MANIFEST" >&2
  exit 1
fi
if command -v jq >/dev/null 2>&1; then
  NAME=$(jq -r '.name // empty' "$MANIFEST")
else
  NAME=$(sed -n 's/^  "name": *"\([^"]*\)".*/\1/p' "$MANIFEST" | head -n 1)
fi
[ -n "$NAME" ] || NAME=dev

out=$("$CLAUDE" --plugin-dir "$PLUGIN" plugin details "$NAME" 2>&1) || { echo "$out"; exit 1; }
echo "$out"

# Inventár z disku umožní odhaliť aj čiastočný výstup CLI.
expected=""
manual=" "
for f in "$PLUGIN"/skills/*/SKILL.md "$PLUGIN"/agents/*.md; do
  [ -f "$f" ] || continue
  fm=$(awk 'NR == 1 && /^---[[:space:]]*$/ { on = 1; next } on && /^---[[:space:]]*$/ { exit } on { print }' "$f")
  n=$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -n 1 | tr -d "\"\047 ")
  case "$f" in
    */SKILL.md) [ -n "$n" ] || n=$(basename "$(dirname "$f")") ;;
    *) [ -n "$n" ] || { n=${f##*/}; n=${n%.md}; } ;;
  esac
  expected="$expected $n"
  if printf '%s\n' "$fm" | grep -Eq '^disable-model-invocation:[[:space:]]*true[[:space:]]*$'; then
    manual="$manual$n "
  fi
done

# Riadky tabuľky "Per-component": <meno> ~N[k] ... ; hodnota "< 20" sa berie ako 20.
result=$(printf '%s\n' "$out" | awk -v manual="$manual" -v expected="$expected" '
  BEGIN {
    n = split(expected, names, " ")
    for (i = 1; i <= n; i++) {
      if (names[i] in want) invalid = 1
      want[names[i]] = 1
    }
  }
  function num(v,   m) {
    sub(/^~/, "", v); gsub(/,/, "", v); m = 1
    if (v ~ /[kK]$/) { sub(/[kK]$/, "", v); m = 1000 }
    if (v !~ /^[0-9]+([.][0-9]+)?$/) { invalid = 1; return 0 }
    return int(v * m)
  }
  /^[[:space:]]*Always-on:/ { raw = num($2); haveraw = 1 }
  /^[[:space:]]*component[[:space:]]+always-on/ { table = 1; next }
  table && NF == 0 { table = 0 }
  table {
    if (!($1 in want) || seen[$1]++) invalid = 1
    v = ($2 == "<") ? num($3) : num($2)
    i = ($2 == "<" ? 4 : 3)
    invoke = num($i == "<" ? $(i+1) : $i)
    if (NF != i + ($i == "<")) invalid = 1
    if ($1 == "project-init") { init = invoke; haveinit = 1 }
    if (index(manual, " " $1 " ") > 0) { mcount++ } else { eff += v }
  }
  END {
    for (name in want) if (!(name in seen)) invalid = 1
    if (!haveraw || !haveinit || invalid) exit
    printf "%d %d %d %d\n", raw, eff, mcount, init
  }')

if [ -z "$result" ]; then
  echo "[dev-kit] spotreba kontextu sa nedá prečítať z claude plugin details — rozpočet neoverený"
  exit 1
fi
set -- $result
raw=$1
eff=$2
mcount=$3
init=$4
if [ "$init" -gt "$INIT_BUDGET" ]; then
  echo "[dev-kit] project-init ~$init tok. > $INIT_BUDGET pri otvorení"
  exit 1
fi
echo "[dev-kit] project-init ~$init tok. ≤ $INIT_BUDGET pri otvorení"
if [ "$eff" -gt "$BUDGET" ]; then
  echo "[dev-kit] always-on ~$eff tok. > $BUDGET (details ~$raw vrátane $mcount príkazových skillov) — skráť popisy referenčných skillov a agentov"
  exit 1
fi
echo "[dev-kit] always-on ~$eff tok. ≤ $BUDGET (details ~$raw vrátane $mcount príkazových skillov, tie sú v kontexte 0)"
exit 0
