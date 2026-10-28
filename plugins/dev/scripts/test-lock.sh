#!/usr/bin/env bash
# Zámok testu pre /dev:fix: lock <rel>… | unlock | status, voliteľne --project P. Vždy jeden riadok, exit 0.
. "$(dirname "$0")/lib.sh" || { echo "[dev-kit] chýba scripts/lib.sh"; exit 0; }
DK_HOOK=test-lock
DK_NO_STDIN=1

cmd="${1:-status}"
[ $# -gt 0 ] && shift
project="" files=""
while [ $# -gt 0 ]; do
    case "$1" in
        --project) project=${2:-}; [ $# -gt 1 ] && shift ;;
        --project=*) project=${1#*=} ;;
        *) [ -n "$1" ] && files="$files$1$DK_NL" ;;
    esac
    shift
done

DK_PROJECT_ARG=${project:-$PWD}
dk_init
if [ "$DK_HAS_JQ" != 1 ]; then echo "[dev-kit] chýba jq — zámok testu nefunguje (brew install jq)"; exit 0; fi
mkdir -p "$DK_PDATA" 2>/dev/null
LF="$DK_PDATA/test-lock.json"
TTL=$(dk_cfg '.testLock.ttlHours' 6)
case "$TTL" in ''|*[!0-9]*) TTL=6 ;; esac
NOTE=""
[ -n "$DK_CFG" ] || NOTE=" (bez .claude/devkit.json ho hook nevynúti)"

dk_list() { printf '%s' "$1" | grep -v '^$' | tr '\n' ' ' | sed 's/ $//; s/ /, /g'; }

case "$cmd" in
    lock)
        rels=""
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            case "$f" in
                /*) r=$(dk_rel "$f"); [ -n "$r" ] || { echo "[dev-kit] $f je mimo projektu $DK_PROJECT — nezamknuté"; exit 0; }; f=$r ;;
                ./*) f=${f#./} ;;
            esac
            rels="$rels$f$DK_NL"
        done <<EOF
$files
EOF
        if [ -z "$rels" ]; then echo "[dev-kit] použitie: test-lock.sh lock <cesta/k/testu>… [--project P]"; exit 0; fi
        if dk_lock_read "$TTL"; then rels="$DK_LOCK_FILES$rels"; fi
        rels=$(printf '%s' "$rels" | grep -v '^$' | awk '!seen[$0]++')
        now=$(dk_now)
        if printf '%s\n' "$rels" | jq -Rn --argjson t "$now" --argjson h "$TTL" \
            '{files: [inputs | select(length > 0)], time: $t, ttlHours: $h}' 2>/dev/null > "$LF.tmp" && mv "$LF.tmp" "$LF"; then
            echo "[dev-kit] test zamknutý: $(dk_list "$rels") (do $(dk_fmt_time $((now + TTL * 3600)))) — oprav kód, nie test; odomknutie: /dev:fix --unlock$NOTE"
        else
            echo "[dev-kit] zámok sa nepodarilo zapísať do $LF"
        fi
        ;;
    unlock)
        if [ -f "$LF" ]; then
            dk_lock_read "$TTL"
            was=$(dk_list "$DK_LOCK_FILES")
            rm -f "$LF"
            echo "[dev-kit] zámok testu zrušený${was:+: $was}"
        else
            echo "[dev-kit] žiadny zamknutý test"
        fi
        ;;
    status)
        if dk_lock_read "$TTL"; then
            echo "[dev-kit] zamknutý test: $(dk_list "$DK_LOCK_FILES") (do $(dk_fmt_time "$DK_LOCK_UNTIL"))$NOTE"
        elif [ -n "$DK_LOCK_EXPIRED" ]; then
            echo "[dev-kit] zámok testu vypršal ($(dk_list "$DK_LOCK_FILES")) — hook ho už nevynucuje"
        else
            echo "[dev-kit] žiadny zamknutý test"
        fi
        ;;
    *)
        echo "[dev-kit] použitie: test-lock.sh lock <rel>… | unlock | status [--project P]"
        ;;
esac
exit 0
