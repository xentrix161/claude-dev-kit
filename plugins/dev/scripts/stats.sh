#!/usr/bin/env bash
# Štatistika rozhodnutí hookov (V8): stats.sh [--days 30] [--project P | --all]. ≤ 20 riadkov, exit 0.
. "$(dirname "$0")/lib.sh" || { echo "[dev-kit] chýba scripts/lib.sh"; exit 0; }
DK_HOOK=stats
DK_NO_STDIN=1

days=30 project="" all=false
while [ $# -gt 0 ]; do
    case "$1" in
        --days) days=${2:-30}; [ $# -gt 1 ] && shift ;;
        --days=*) days=${1#*=} ;;
        --project) project=${2:-}; [ $# -gt 1 ] && shift ;;
        --project=*) project=${1#*=} ;;
        --all) all=true ;;
        -h|--help) echo "použitie: stats.sh [--days N] [--project P | --all]"; exit 0 ;;
    esac
    shift
done
case "$days" in ''|*[!0-9]*) days=30 ;; esac

DK_PROJECT_ARG=${project:-$PWD}
dk_init
if [ "$DK_HAS_JQ" != 1 ]; then echo "[dev-kit] chýba jq — štatistika nefunguje (brew install jq)"; exit 0; fi

LOG="$DK_DATA/decisions.jsonl"
SRC=""
[ -f "$LOG.1" ] && SRC="$LOG.1"
[ -f "$LOG" ] && SRC="$SRC${SRC:+$DK_NL}$LOG"
if [ -z "$SRC" ]; then echo "[dev-kit] zatiaľ žiadne rozhodnutia hookov ($LOG neexistuje)"; exit 0; fi

since=$(( $(dk_now) - days * 86400 ))
out=$(printf '%s\n' "$SRC" | while IFS= read -r f; do cat "$f"; done | jq -Rrn --argjson since "$since" --arg p "$DK_PROJECT" --argjson all "$all" '
  def cnt(d): map(select(.decision == d)) | length;
  def noisy: .decision == "block" or .decision == "deny" or .decision == "ask" or .decision == "warn";
  [inputs | (try fromjson catch null) | select(type == "object") | select((.ts // 0) >= $since) | select($all or .project == $p)] as $e
  | if ($e | length) == 0 then "E" else
    "H\u001f\($e | length)",
    ($e | group_by((.hook // "?") + " " + (.rule // "?"))
        | map({k: ((.[0].hook // "?") + " " + (.[0].rule // "?")), b: cnt("block"), d: cnt("deny"), a: cnt("ask"), w: cnt("warn"), p: cnt("pass"), s: cnt("skip"), n: length})
        | sort_by(-(.b + .d + .a + .w), -.n) | .[:8][]
        | "R\u001f\(.k)\u001f\(.b)/\(.d)/\(.a)/\(.w)/\(.p)/\(.s)"),
    "N\u001f\($e | map(select(.hook != "check" and noisy)) | group_by(.rule // "?") | map({r: (.[0].rule // "?"), n: length}) | sort_by(-.n) | .[:5] | map("\(.r) \(.n)") | join(" · "))",
    ($e | map(select(.hook == "stop-check" and .rule == "stopCheck")) | "S\u001f\(cnt("block"))\u001f\(cnt("warn"))\u001f\(cnt("pass"))\u001f\(cnt("skip"))"),
    ($e | map(select(.hook == "pre-bash" and .rule == "commitGate")) | "G\u001f\(cnt("deny"))\u001f\(cnt("pass"))"),
    ($e | map(select(.hook == "pre-bash" and .rule == "commitGate" and (.file // "") != "")) | group_by(.file)
        | "F\u001f\(map(select(sort_by(.ts // 0) | .[0].decision == "pass")) | length)\u001f\(length)"),
    ($e | map(select(.hook == "pre-bash" and .rule == "secrets")) | "T\u001f\(cnt("deny"))"),
    "M\u001f\($e | map(select(.ms != null and (.ms | type) == "number")) | group_by(.hook // "?") | map("\(.[0].hook // "?") \((map(.ms) | add / length) | floor) ms") | join(" · "))"
  end' 2>/dev/null)

if [ -z "$out" ]; then echo "[dev-kit] log rozhodnutí sa nedá prečítať: $LOG"; exit 0; fi
if [ "$out" = E ]; then
    if [ "$all" = true ]; then
        echo "[dev-kit] zatiaľ žiadne rozhodnutia hookov · obdobie: $(dk_plural "$days" deň dni dní)"
    else
        echo "[dev-kit] zatiaľ žiadne rozhodnutia hookov v ${DK_PROJECT##*/} · obdobie: $(dk_plural "$days" deň dni dní) (všetky projekty: --all)"
    fi
    exit 0
fi

scope="${DK_PROJECT##*/}"
[ "$all" = true ] && scope="všetky projekty"
rules="" noisy="" stop="" gate="" first="" sec="" msl=""
while IFS=$DK_US read -r tag a b c d; do
    case "$tag" in
        H) total=$a ;;
        R) rules="$rules  $a  $b$DK_NL" ;;
        N) noisy=$a ;;
        S) stop="$a$DK_US$b$DK_US$c$DK_US$d" ;;
        G) gate="$a$DK_US$b" ;;
        F) first="$a$DK_US$b" ;;
        T) sec=$a ;;
        M) msl=$a ;;
    esac
done <<EOF
$out
EOF

pct() { if [ "${2:-0}" -gt 0 ]; then printf '%s %%' $(( ($1 * 100 + $2 / 2) / $2 )); else printf '– %%'; fi; }

echo "[dev-kit] hooky · $scope · obdobie: $(dk_plural "$days" deň dni dní) · záznamy: ${total:-0}"
echo "pravidlá (block/deny/ask/warn/pass/skip):"
printf '%s' "$rules"
echo "najhlučnejšie (bez /dev:check): ${noisy:-žiadne bloky ani upozornenia}"
IFS=$DK_US read -r sb sw sp ss <<EOF
$stop
EOF
runs=$(( ${sb:-0} + ${sw:-0} + ${sp:-0} ))
echo "Stop kontrola: behy $runs · bloky ${sb:-0} ($(pct "${sb:-0}" "$runs")) · upozornenia po 3× ${sw:-0} · bez zmeny ${ss:-0}"
IFS=$DK_US read -r gd gp <<EOF
$gate
EOF
gt=$(( ${gd:-0} + ${gp:-0} ))
IFS=$DK_US read -r fa fb <<EOF
$first
EOF
echo "commit gate: zamietnutia ${gd:-0} z $gt ($(pct "${gd:-0}" "$gt")) · PASS na prvý raz ${fa:-0} z ${fb:-0} ($(pct "${fa:-0}" "${fb:-0}")) · tajomstvá: zamietnutia ${sec:-0}"
echo "priemer: ${msl:-bez meraní}"
echo "log: $LOG"
exit 0
