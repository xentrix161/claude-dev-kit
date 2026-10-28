#!/usr/bin/env bash
# Jediný zdroj pravdy kontrol: /dev:check, Stop hook (--stop), commit gate (pass.json), CI.
# Exit: 0 = PASS (žiadny FAIL, ≥ 1 PASS) · 1 = FAIL · 3 = chyba configu/argumentov · 4 = nič nebežalo.
. "$(dirname "$0")/lib.sh" || { echo "[dev-kit] chýba scripts/lib.sh"; exit 3; }
DK_HOOK=check
DK_NO_STDIN=1

dk_usage() {
    echo "použitie: check.sh [--quick|--full|--auto|--stop] [--session <id>] [--project <dir>] [--files <rel>…]"
}

DK_EXCERPT_RE='^[0-9]+\) |^FAILED |^ERROR|:[0-9]+(:|$)|on line [0-9]+|[Ee]rror|[Ee]xception|FAILURES!|^Tests: |[Ff]ailed asserting|^E[[:space:]]'

mode=quick files_arg="" files_set=0 project="" session=""
while [ $# -gt 0 ]; do
    case "$1" in
        --quick|--full|--auto|--stop) mode=${1#--} ;;
        --session) session=${2:-}; [ $# -gt 1 ] && shift ;;
        --session=*) session=${1#*=} ;;
        --project) project=${2:-}; [ $# -gt 1 ] && shift ;;
        --project=*) project=${1#*=} ;;
        --files)
            files_set=1
            shift
            while [ $# -gt 0 ]; do
                case "$1" in --*) break ;; esac
                [ -n "$1" ] && files_arg="$files_arg$1$DK_NL"
                shift
            done
            continue
            ;;
        -h|--help) dk_usage; exit 0 ;;
        *) echo "[dev-kit] neznámy argument: $1"; dk_usage; exit 3 ;;
    esac
    shift
done

DK_PROJECT_ARG=${project:-$PWD}
DK_SESSION_ARG=$session
dk_init
T0=$(dk_ms)

if [ "$DK_HAS_JQ" != 1 ]; then echo "[dev-kit] chýba jq → kontroly nebežia (brew install jq)"; exit 3; fi
if [ -z "$DK_CFG" ]; then echo "[dev-kit] chýba .claude/devkit.json — spusti /dev:project-init"; exit 3; fi
if ! dk_cfg_read '((.check.steps // [])[] | "S\u001f\(.id|s)\u001f\(.requires|s)\u001f\(.run|s)\u001f\(.runFiles|s)\u001f\((.ext // []) | join(","))\u001f\((.modes // ["quick","full"]) | join(","))\u001f\(.changedLinesOnly // false | s)"),
    ((.check.fullWhen // [])[] | "W\u001f\(.|s)"),
    ((.check.knownFailures // [])[] | "F\u001f\(.step|s)\u001f\(.pattern|s)")'; then
    echo "[dev-kit] .claude/devkit.json nie je platný JSON → jq . .claude/devkit.json"
    exit 3
fi
mkdir -p "$DK_PDATA/logs" "$DK_PDATA/sessions" 2>/dev/null

FULLW="" KNOWN=""
while IFS=$DK_US read -r tag a b; do
    case "$tag" in
        W) FULLW="$FULLW$a$DK_NL" ;;
        F) KNOWN="$KNOWN$a$DK_US$b$DK_NL" ;;
    esac
done <<EOF
$DK_CFG_OUT
EOF

# Súbory: --files › session (stop) › zmenené voči HEAD + staged + nesledované.
ALL=""
if [ "$files_set" = 1 ]; then
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in /*) f=$(dk_rel "$f") ;; ./*) f=${f#./} ;; esac
        [ -n "$f" ] && ALL="$ALL$f$DK_NL"
    done <<EOF
$files_arg
EOF
elif [ "$mode" = stop ]; then
    SF=$(dk_session_file)
    [ -f "$SF" ] && ALL=$(cat "$SF")
else
    ALL=$(dk_changed_files)
fi
EXIST="" DELETED=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -f "$DK_PROJECT/$f" ]; then EXIST="$EXIST$f$DK_NL"; else DELETED="$DELETED$f$DK_NL"; fi
done <<EOF
$ALL
EOF

if [ "$mode" = auto ]; then
    mode=quick
    FRE=$(dk_globs_re "$FULLW")
    if [ -n "$FRE" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            if dk_re_match "$f" "$FRE"; then mode=full; break; fi
        done <<EOF
$ALL
EOF
    fi
fi

# Odtlačok obsahu pred krokmi: marker potvrdí presne to, čo sa kontrolovalo.
dk_tmpdir
if [ "$mode" = stop ]; then
    if [ "$files_set" = 1 ]; then
        HF=$(printf '%s' "$EXIST" | while IFS= read -r f; do [ -n "$f" ] && dk_is_code "$f" && printf '%s\n' "$f"; done)
    else
        HF=$(dk_session_code_files)
    fi
    SNAP_HASH=$(set -f; IFS=$DK_NL; dk_hash_files $HF)
else
    (set -f; IFS=$DK_NL; dk_blobs $ALL) > "$DK_TMP/blobs.snap"
fi

LOG="$DK_PDATA/logs/check-$mode-$DK_T0.log"
[ -e "$LOG" ] && LOG="$DK_PDATA/logs/check-$mode-$DK_T0-$$.log"
{
    echo "# dev-kit check $mode · $(date '+%Y-%m-%d %H:%M:%S') · $DK_PROJECT"
    echo "# súbory: $(printf '%s' "$EXIST" | tr '\n' ' ')"
} 2>/dev/null > "$LOG"

NOK=0 NFAIL=0 NSKIP=0 STEPLINES="" FAILSTEPS="" ENV_READY=0 ENV_SKIP=""

dk_env_check() { # kontajner + workdir raz pre všetky kroky
    [ "$ENV_READY" = 1 ] && return 0
    ENV_READY=1
    DK_WD=""
    [ -n "$DK_CONTAINER" ] || return 0
    if ! dk_container_ok; then ENV_SKIP="kontajner $DK_CONTAINER nebeží"; return 0; fi
    DK_WD=$(dk_workdir 2>/dev/null) || ENV_SKIP="worktree mimo mountu kontajnera"
    return 0
}

dk_files_for() { # <ext-csv> → existujúce súbory s danou príponou (prázdne csv = všetky)
    local f e
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if [ -n "$1" ]; then
            e=$(dk_ext "$f")
            case ",$1," in *",$e,"*) ;; *) continue ;; esac
        fi
        printf '%s\n' "$f"
    done <<EOF
$EXIST
EOF
}

dk_skip() { STEPLINES="${STEPLINES}– $1: $2$DK_NL"; NSKIP=$((NSKIP + 1)); }

dk_known_ok() { # <step-id> <outfile> → 0 keď všetky zlyhania sú známe; počet v KNOWN_N
    local id="$1" ids pats x p gi hit
    KNOWN_N=0
    pats=$(printf '%s' "$KNOWN" | awk -F"$DK_US" -v s="$id" '$1 == s { print $2 }')
    [ -n "$pats" ] || return 1
    ids=$(sed -nE 's/^[0-9]+\) ([^[:space:]]+::[^[:space:]]+).*/\1/p; s/^FAILED ([^[:space:]]+).*/\1/p' "$2" | sort -u)
    [ -n "$ids" ] || return 1
    while IFS= read -r x; do
        [ -n "$x" ] || continue
        hit=0
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            gi=""
            case "$p" in '(?i)'*) p=${p#'(?i)'}; gi=-i ;; esac
            if printf '%s\n' "$x" | grep -Eq $gi -e "$p"; then hit=1; break; fi
        done <<EOF2
$pats
EOF2
        [ "$hit" = 1 ] || return 1
        KNOWN_N=$((KNOWN_N + 1))
    done <<EOF
$ids
EOF
    return 0
}

while IFS=$DK_US read -r tag id req run runf exts modes cl <&3; do
    [ "$tag" = S ] || continue
    [ -n "$id" ] || continue
    case ",$modes," in *",$mode,"*) ;; *) continue ;; esac
    dk_rule_on "step:$id" || continue
    if [ -n "$req" ] && [ ! -e "$DK_PROJECT/$req" ]; then dk_skip "$id" "chýba $req"; continue; fi
    dk_env_check
    if [ -n "$ENV_SKIP" ]; then dk_skip "$id" "$ENV_SKIP"; continue; fi

    targets="" cmd=""
    if [ -n "$exts" ]; then
        targets=$(dk_files_for "$exts")
        if [ -z "$targets" ] && { [ "$mode" = stop ] || [ -z "$run" ]; }; then
            dk_skip "$id" "žiadne zmenené súbory"; continue
        fi
    fi
    if [ "$mode" != stop ] && [ -n "$run" ]; then
        cmd=$run
    elif [ -n "$runf" ] && [ -n "$exts" ] && [ -n "$targets" ]; then
        cmd=$runf
    elif [ -n "$run" ]; then
        cmd=$run
    elif [ -n "$runf" ]; then
        targets=$(dk_files_for "")
        [ -n "$targets" ] || { dk_skip "$id" "žiadne zmenené súbory"; continue; }
        cmd=$runf
    else
        dk_skip "$id" "bez príkazu (run/runFiles)"; continue
    fi
    case "$cmd" in
        *"{files}"*)
            q=""
            while IFS= read -r f; do
                [ -n "$f" ] || continue
                case "$f" in -*) f="./$f" ;; esac
                q="$q${q:+ }$(dk_shq "$f")"
            done <<EOF
$targets
EOF
            cmd=${cmd//\{files\}/"$q"}
            ;;
        *) [ "$cmd" = "$runf" ] || targets=$EXIST ;;
    esac

    s0=$(dk_ms)
    dk_exec "$cmd" > "$DK_TMP/step.raw"
    rc=$?
    LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g" "$DK_TMP/step.raw" > "$DK_TMP/step.out"
    ms=$(( $(dk_ms) - s0 ))
    {
        echo
        echo "=== $id · exit $rc · $(dk_fmt_s "$ms") s"
        echo "\$ $cmd"
        cat "$DK_TMP/step.out"
    } 2>/dev/null >> "$LOG"

    if [ "$rc" = 0 ]; then
        STEPLINES="${STEPLINES}✓ $id $(dk_fmt_s "$ms") s$DK_NL"; NOK=$((NOK + 1)); continue
    fi
    if [ "$rc" -ge 125 ] && [ "$rc" -le 127 ]; then
        dk_skip "$id" "príkaz sa nedá spustiť (exit $rc)"; continue
    fi
    # Zlyhal nástroj alebo docker, nie kód (žiadny riadok s číslom) → SKIP, Stop na infraštruktúre neblokuje.
    if ! grep -Eq ':[0-9]|on line [0-9]' "$DK_TMP/step.out" && grep -Eq "$DK_RE_INFRA" "$DK_TMP/step.out"; then
        dk_skip "$id" "chyba prostredia, nie kódu ($(grep -Eo "$DK_RE_INFRA" "$DK_TMP/step.out" | head -n 1))"; continue
    fi
    src="$DK_TMP/step.out"
    if [ "$cl" = true ] || { [ "$cl" = stop ] && [ "$mode" = stop ]; }; then
        : > "$DK_TMP/step.map"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            sp=$(dk__added_spec "$f")
            if [ "$sp" = "*" ]; then
                printf '%s\t*\n' "$f" >> "$DK_TMP/step.map"
            elif [ -n "$sp" ]; then
                printf '%s\n' "$sp" | awk -v r="$f" 'NF { print r "\t" $0 }' >> "$DK_TMP/step.map"
            fi
        done <<EOF
$targets
EOF
        dk_filter_changed "$DK_TMP/step.out" "$DK_TMP/step.map" > "$DK_TMP/step.kept"
        if [ ! -s "$DK_TMP/step.kept" ]; then
            STEPLINES="${STEPLINES}✓ $id $(dk_fmt_s "$ms") s (len staré nálezy mimo zmenených riadkov)$DK_NL"
            NOK=$((NOK + 1)); continue
        fi
        src="$DK_TMP/step.kept"
    fi
    if dk_known_ok "$id" "$DK_TMP/step.out"; then
        STEPLINES="${STEPLINES}✓ $id $(dk_fmt_s "$ms") s (známe zlyhania: $KNOWN_N)$DK_NL"
        NOK=$((NOK + 1)); continue
    fi
    STEPLINES="${STEPLINES}✗ $id $(dk_fmt_s "$ms") s$DK_NL"
    NFAIL=$((NFAIL + 1))
    ex=$(grep -E -e "$DK_EXCERPT_RE" "$src" 2>/dev/null | dk_strip_paths | head -n 8)
    [ -n "$ex" ] || ex=$(grep -v '^[[:space:]]*$' "$src" | tail -n 8 | dk_strip_paths)
    FAILSTEPS="$FAILSTEPS$id$DK_US$NFAIL$DK_NL"
    printf '%s\n' "$ex" > "$DK_TMP/ex.$NFAIL"
done 3<<EOF
$DK_CFG_OUT
EOF

TOTAL=$(( $(dk_ms) - T0 ))
if [ "$NFAIL" -gt 0 ]; then VERDICT=FAIL RC=1
elif [ "$NOK" -gt 0 ]; then VERDICT=PASS RC=0
else VERDICT=SKIP RC=4
fi
[ -n "$STEPLINES" ] || { STEPLINES="– žiadne kroky pre režim $mode$DK_NL"; }

# Markery a log pred výpisom: zatvorený stdout (SIGPIPE) ich nesmie zahodiť.
if [ "$RC" = 0 ]; then
    if [ "$mode" = stop ]; then
        jq -n --arg h "$SNAP_HASH" --argjson t "$(dk_now)" '{hash: $h, time: $t, fails: 0, result: "PASS"}' \
            2>/dev/null > "$DK_PDATA/stop.json.tmp" && mv "$DK_PDATA/stop.json.tmp" "$DK_PDATA/stop.json"
    else
        HEAD_SHA=$(dk_git rev-parse --verify -q HEAD 2>/dev/null)
        jq -Rn --argjson t "$(dk_now)" --arg m "$mode" --arg h "$HEAD_SHA" \
            '{time: $t, mode: $m, head: $h, blobs: ([inputs | select(length > 0) | split("\t") | {(.[0]): .[1]}] | add // {})}' \
            < "$DK_TMP/blobs.snap" 2>/dev/null > "$DK_PDATA/pass.json.tmp" && mv "$DK_PDATA/pass.json.tmp" "$DK_PDATA/pass.json"
    fi
fi

ls -1t "$DK_PDATA"/logs/check-*.log 2>/dev/null | tail -n +21 | while IFS= read -r f; do rm -f "$f"; done
case "$RC" in 0) dec=pass ;; 1) dec=block ;; *) dec=skip ;; esac
dk_log check "check:$mode" "$dec" "" "$TOTAL"

NSTEP=$(printf '%s' "$STEPLINES" | grep -c .)
BUDGET=$((20 - NSTEP - 2))
PER=$BUDGET
[ "$NFAIL" -gt 0 ] && PER=$((BUDGET / NFAIL))
{
    printf '[dev-kit] check %s: %s · %s ok · %s fail · %s skip · %s s\n' "$mode" "$VERDICT" "$NOK" "$NFAIL" "$NSKIP" "$(dk_fmt_s "$TOTAL")"
    printf '%s' "$STEPLINES" | head -n 17
    if [ -n "$FAILSTEPS" ] && [ "$BUDGET" -gt 1 ]; then
        while IFS=$DK_US read -r id k; do
            [ -n "$id" ] || continue
            [ "$BUDGET" -gt 1 ] || break
            echo "$id:"
            BUDGET=$((BUDGET - 1))
            n=$((PER - 1))
            [ "$n" -gt 8 ] && n=8
            [ "$n" -lt 1 ] && n=1
            [ "$n" -gt "$BUDGET" ] && n=$BUDGET
            head -n "$n" "$DK_TMP/ex.$k" | sed 's/^/  /'
            BUDGET=$((BUDGET - $(head -n "$n" "$DK_TMP/ex.$k" | grep -c .)))
        done <<EOF
$FAILSTEPS
EOF
    fi
    echo "log: $LOG"
}

exit "$RC"
