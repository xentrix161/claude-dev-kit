#!/usr/bin/env bash
# Inventár pracovnej kópie pluginu a rozpočet always-on tokenov (plán §15.3 L).
# `claude plugin details` počíta aj skilly s disable-model-invocation: true, ktorých popis
# podľa docs (skills.md) v kontexte nie je → rozpočet sa stráži bez nich.
set -u

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PLUGIN="${1:-$KIT_DIR/plugins/dev}"
BUDGET="${BUDGET:-3000}"
CLAUDE="${CLAUDE:-claude}"
MANIFEST="$PLUGIN/.claude-plugin/plugin.json"

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

# Mená skillov len na ručné spustenie (frontmatter disable-model-invocation: true).
manual=" "
for f in "$PLUGIN"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  fm=$(awk 'NR == 1 && /^---[[:space:]]*$/ { on = 1; next } on && /^---[[:space:]]*$/ { exit } on { print }' "$f")
  if printf '%s\n' "$fm" | grep -Eq '^disable-model-invocation:[[:space:]]*true[[:space:]]*$'; then
    n=$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -n 1 | tr -d "\"' ")
    [ -n "$n" ] || n=$(basename "$(dirname "$f")")
    manual="$manual$n "
  fi
done

# Riadky tabuľky "Per-component": <meno> ~N[k] ... ; hodnota "< 20" sa berie ako 20.
result=$(printf '%s\n' "$out" | awk -v manual="$manual" '
  function num(v,   m) {
    sub(/^~/, "", v); gsub(/,/, "", v); m = 1
    if (v ~ /[kK]$/) { sub(/[kK]$/, "", v); m = 1000 }
    return int(v * m)
  }
  /^[[:space:]]*Always-on:/ { raw = num($2); haveraw = 1 }
  /^[[:space:]]*component[[:space:]]+always-on/ { table = 1; next }
  table && NF == 0 { table = 0 }
  table && NF >= 2 {
    v = ($2 == "<") ? num($3) : num($2)
    if (index(manual, " " $1 " ") > 0) { msum += v; mcount++ } else { eff += v }
    rows++
  }
  END {
    if (!haveraw) exit
    if (!rows) eff = raw
    printf "%d %d %d\n", raw, eff, mcount
  }')

if [ -z "$result" ]; then
  echo "[dev-kit] always-on sa nedá prečítať z claude plugin details — rozpočet neoverený"
  exit 0
fi
set -- $result
raw=$1
eff=$2
mcount=$3
if [ "$eff" -gt "$BUDGET" ]; then
  echo "[dev-kit] always-on ~$eff tok. > $BUDGET (details ~$raw vrátane $mcount príkazových skillov) — skráť popisy referenčných skillov a agentov"
  exit 1
fi
echo "[dev-kit] always-on ~$eff tok. ≤ $BUDGET (details ~$raw vrátane $mcount príkazových skillov, tie sú v kontexte 0)"
exit 0
