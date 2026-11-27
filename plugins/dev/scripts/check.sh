#!/usr/bin/env bash
# Jediný zdroj pravdy kontrol: /dev:check, Stop hook (--stop), commit gate (pass.json), CI.
# Exit: 0 = PASS (žiadny FAIL ani BLOCK, ≥ 1 PASS) · 1 = FAIL · 3 = chyba configu/argumentov
#       · 4 = neúplné overenie (PARTIAL: krok sa nedal spustiť · SKIP: nič nebežalo).
. "$(dirname "$0")/lib.sh" || { echo "[dev-kit] chýba scripts/lib.sh"; exit 3; }
DK_HOOK=check
DK_NO_STDIN=1
DK_NO_CONTAINER_CACHE=1

dk_usage() {
    echo "použitie: check.sh [--quick|--full|--auto|--stop] [--before-stage] [--session <id>] [--project <dir>] [--config <súbor>] [--files <rel>…]"
}

DK_EXCERPT_RE='^[0-9]+\) |^FAILED |^ERROR|:[0-9]+(:|$)|on line [0-9]+|[Ee]rror|[Ee]xception|FAILURES!|^Tests: |[Ff]ailed asserting|^E[[:space:]]|^-- FAILED: |^[[:space:]]+Failed: |^Found [0-9]+ |^(Package|Advisory ID|CVE|Title): |^Name +Version +ID|[[:space:]](PYSEC|GHSA|CVE)-[0-9A-Za-z]'
# Riadok nálezu v kóde: číslo riadku, test Nette Testeru (ten čísla riadkov s dvojbodkou nemá) alebo hlavička auditu.
DK_RE_FINDING=':[0-9]|on line [0-9]|^-- FAILED: |^Found [0-9]+ (security vulnerability advisor|known vulnerabilit|abandoned package)'

before_stage=0
mode=quick files_arg="" files_set=0 project="" session="" cfg_file="" cfg_set=0
while [ $# -gt 0 ]; do
    case "$1" in
        --quick|--full|--auto|--stop) mode=${1#--} ;;
        --before-stage) before_stage=1 ;;
        --session) session=${2:-}; [ $# -gt 1 ] && shift ;;
        --session=*) session=${1#*=} ;;
        --project) project=${2:-}; [ $# -gt 1 ] && shift ;;
        --project=*) project=${1#*=} ;;
        --config) cfg_file=${2:-}; cfg_set=1; [ $# -gt 1 ] && shift ;;
        --config=*) cfg_file=${1#*=}; cfg_set=1 ;;
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

# Iný config (CI bez kontajnera): --config › DEVKIT_CONFIG; relatívna cesta od pwd volajúceho.
[ "$cfg_set" = 1 ] || cfg_file=${DEVKIT_CONFIG:-}
if [ "$cfg_set" = 1 ] && [ -z "$cfg_file" ]; then echo "[dev-kit] --config bez súboru"; dk_usage; exit 3; fi
case "$cfg_file" in ''|/*) ;; *) cfg_file="$PWD/$cfg_file" ;; esac

DK_PROJECT_ARG=${project:-$PWD}
DK_SESSION_ARG=$session
dk_init
T0=$(dk_ms)

if [ "$DK_HAS_JQ" != 1 ]; then echo "[dev-kit] chýba jq → kontroly nebežia (brew install jq)"; exit 3; fi
# CFG_OVER = iný súbor než config projektu (markery nižšie).
CFG_SHOW=.claude/devkit.json CFG_OVER=""
if [ -n "$cfg_file" ]; then
    if [ ! -f "$cfg_file" ]; then echo "[dev-kit] config $cfg_file neexistuje (--config, DEVKIT_CONFIG)"; exit 3; fi
    { [ -n "$DK_CFG" ] && [ "$cfg_file" -ef "$DK_CFG" ]; } || CFG_OVER=$cfg_file
    DK_CFG=$cfg_file CFG_SHOW=$cfg_file
fi
if [ -z "$DK_CFG" ]; then echo "[dev-kit] chýba .claude/devkit.json — spusti /dev:project-init"; exit 3; fi
if [ "$before_stage" = 1 ] && { [ "$mode" = stop ] || [ -n "$CFG_OVER" ]; }; then dk_usage; exit 3; fi

# Každý beh publikuje do vlastného adresára. Spoločný odkaz vyberá naposledy začatú kontrolu.
RESULT_DIR=""
if [ "$mode" != stop ] && [ -z "$CFG_OVER" ]; then
    RESULT_DIR=$(mktemp -d "$DK_PDATA/result.XXXXXX") || exit 3
    generation=${RESULT_DIR##*/}
    ln -s "$generation" "$RESULT_DIR/current-check" && mv -f "$RESULT_DIR/current-check" "$DK_PDATA/" || exit 3
    for name in pass.json partial.json; do
        [ "$(readlink "$DK_PDATA/$name")" = "current-check/$name" ] && continue
        ln -s "current-check/$name" "$RESULT_DIR/link" && mv -f "$RESULT_DIR/link" "$DK_PDATA/$name" || exit 3
    done
    if [ "$before_stage" = 1 ]; then
        ln -s "$generation/before.ok" "$RESULT_DIR/link" && mv -f "$RESULT_DIR/link" "$DK_PDATA/before-stage.json" || exit 3
    fi
fi
dk_tmpdir
cp "$DK_CFG" "$DK_TMP/check-config.json" || exit 3
DK_CFG="$DK_TMP/check-config.json"
CONFIG_HASH=$(git hash-object --no-filters -- "$DK_CFG") || exit 3
if ! dk_cfg_read '((.check.steps // [])[] | "S\u001f\(.id|s)\u001f\(.requires|s)\u001f\(.run|s)\u001f\(.runFiles|s)\u001f\((.ext // []) | join(","))\u001f\((.modes // ["quick","full"]) | join(","))\u001f\(.changedLinesOnly // false | s)\u001f\(.runtime|s)\u001f\(.timeoutSec // 300 | s)\u001f\(.required // false | s)\u001f\(.phase // "staged" | s)\u001f\(.output // "log" | s)\u001f\(.newPathsReport|s)"),
    "R\u001f\(any(.check.steps[]?; .required == true and any((.modes // ["quick","full"])[]; . == "quick" or . == "full")) | s)",
    ((.check.fullWhen // [])[] | "W\u001f\(.|s)"),
    ((.check.knownFailures // [])[] | "F\u001f\(.step|s)\u001f\(.pattern|s)"),
    "T\u001f\(.testLock.ttlHours // 6 | s)"'; then
    echo "[dev-kit] $CFG_SHOW nie je platný JSON → jq . $CFG_SHOW"
    exit 3
fi
mkdir -p "$DK_PDATA/logs" "$DK_PDATA/sessions" 2>/dev/null

FULLW="" KNOWN="" TTL=6 STRICT=false PROJECT_PROOF="" INDEX_PROOF=""
while IFS=$DK_US read -r tag a b; do
    case "$tag" in
        W) FULLW="$FULLW$a$DK_NL" ;;
        F) KNOWN="$KNOWN$a$DK_US$b$DK_NL" ;;
        T) TTL=$a ;;
        R) STRICT=$a ;;
    esac
done <<EOF
$DK_CFG_OUT
EOF

# Súbory: --files › session (stop: zoznam on-edit ∪ kód zmenený od začiatku session mimo neho) › zmenené voči
# HEAD + staged + nesledované.
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
    ALL=$({ [ -f "$SF" ] && cat "$SF"; dk_session_newer; } | awk 'NF && !s[$0]++')
else
    ALL=$(dk_changed_files)
fi
# Existujúce súbory výpisom, nie skladaním reťazca v cykle (tisíce súborov).
EXIST=$(printf '%s\n' "$ALL" | while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$DK_PROJECT/$f" ] && printf '%s\n' "$f"
done)
[ -z "$EXIST" ] || EXIST="$EXIST$DK_NL"

AUTO_FULL=0
if [ "$mode" = auto ]; then
    mode=quick
    FRE=$(dk_globs_re "$FULLW")
    if [ -n "$FRE" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            if dk_re_match "$f" "$FRE"; then mode=full; AUTO_FULL=1; break; fi
        done <<EOF
$ALL
EOF
    fi
fi

BEFORE_RUN="" REQUIRED_OK="" BASE_PROOF=""
if [ "$before_stage" = 0 ] && [ "$mode" != stop ] && [ -f "$DK_PDATA/before-stage.json" ]; then
    cp "$DK_PDATA/before-stage.json" "$DK_TMP/before.json" || exit 3
fi

# Odtlačok obsahu pred krokmi: marker potvrdí presne to, čo sa kontrolovalo.
if [ "$mode" = stop ]; then
    # Bez --files rovnaká množina ako dk_session_code_files v stop-check (hash v stop.json).
    dk_base
    HF=$(printf '%s' "$EXIST" | dk_ext_filter "$DK_STOP_EXTS" code)
    SNAP_HASH=$(set -f; IFS=$DK_NL; dk_hash_files $HF)
else
    (set -f; IFS=$DK_NL; dk_blobs $ALL) > "$DK_TMP/blobs.snap"
    if { [ "$STRICT" = true ] || [ "$mode" = full ]; } && [ -z "$CFG_OVER" ]; then
        INDEX_PROOF=$(dk_project_proof index "$DK_PROJECT") || INDEX_PROOF=""
        if [ "$before_stage" = 1 ]; then
            BASE_PROOF=$(dk_project_proof base "$DK_PROJECT") || BASE_PROOF=""
            PROJECT_PROOF=$(dk_project_proof worktree "$DK_PROJECT" "$DK_TMP/new-paths") || PROJECT_PROOF=""
        else
            PROJECT_PROOF=$(dk_project_proof worktree "$DK_PROJECT") || PROJECT_PROOF=""
        fi
    fi
fi

LOG="$DK_PDATA/logs/check-$mode-$DK_T0-$$.log"
[ -z "$RESULT_DIR" ] || printf '%s\n' "${LOG##*/}" > "$RESULT_DIR/log-name" || exit 3
{
    echo "# dev-kit check $mode · $(date '+%Y-%m-%d %H:%M:%S') · $DK_PROJECT"
    echo "# súbory: $(printf '%s' "$EXIST" | tr '\n' ' ')"
    [ -z "$CFG_OVER" ] || echo "# config: $CFG_OVER"
} 2>/dev/null > "$LOG"

whole=false
[ "$mode" = full ] && [ "$files_set" = 0 ] && whole=true
NOK=0 NKNOWN=0 NFAIL=0 NSKIP=0 NBLOCK=0 STEPLINES="" FAILSTEPS="" BLOCKIDS="" ENV_READY=0 ENV_SKIP=""

dk_env_check() { # kontajner + workdir raz pre všetky kroky
    [ "$ENV_READY" = 1 ] && return 0
    ENV_READY=1
    DK_WD=""
    [ -n "$DK_CONTAINER" ] || return 0
    if ! dk_container_ok; then ENV_SKIP="kontajner $DK_CONTAINER nebeží"; return 0; fi
    DK_WD=$(dk_workdir 2>/dev/null) || ENV_SKIP="worktree mimo mountu kontajnera"
    return 0
}

dk_files_for() { # <ext-csv> → existujúce súbory s danou príponou (prázdne csv = kódové, v stop kódové pre Stop)
    if [ -n "$1" ]; then
        printf '%s' "$EXIST" | dk_ext_filter "$1"
    else
        dk_base
        if [ "$mode" = stop ]; then printf '%s' "$EXIST" | dk_ext_filter "$DK_STOP_EXTS" code
        else printf '%s' "$EXIST" | dk_ext_filter "$DK_CODE_EXTS" code; fi
    fi
}

# skip = krok sa zmien netýka · block = krok sa nedal spustiť (verdikt najviac PARTIAL)
dk_skip() { STEPLINES="${STEPLINES}– $1: $2$DK_NL"; NSKIP=$((NSKIP + 1)); }
dk_block() { STEPLINES="${STEPLINES}${3:-! $1: $2}$DK_NL"; BLOCKIDS="$BLOCKIDS$1$DK_NL"; NSKIP=$((NSKIP + 1)); NBLOCK=$((NBLOCK + 1)); }

# Záznamy zraniteľností: composer audit (plain aj table: bloky od Package: za hlavičkou „Found N … security
# vulnerability advisor…“, bez blokov s Ignore reason:) a pip-audit (riadky pod hlavičkou Name Version ID).
# Id záznamu = jeho identifikátory oddelené tabulátorom; iný riadok „Found N …“ composeru (abandoned) je id sám.
dk_audit_ids() {
    awk '
    function flush() {
        if (inb && !ign) print (ids != "" ? ids : pkg)
        inb = 0; ids = ""; pkg = ""; ign = 0
    }
    function val(s) { sub(/^[^:]*:[ \t]*/, "", s); sub(/[ \t].*$/, "", s); return s }
    {
        l = $0
        sub(/\r$/, "", l); sub(/^[| \t]+/, "", l); sub(/[| \t]+$/, "", l)
        if (l ~ /^[A-Z][A-Za-z ]*[A-Za-z] +[|] /) sub(/ +[|] +/, ": ", l)
        if (l ~ /^Found [0-9]+ /) {
            flush(); tab = 0
            if (l ~ /^Found [0-9]+ (ignored )?security vulnerability advisor/) comp = 1
            else if (l !~ /^Found [0-9]+ known vulnerabilit/) { sub(/[:.]$/, "", l); other = other l "\n" }
            next
        }
        if (comp && l ~ /^Package: /) { flush(); inb = 1; pkg = val(l); next }
        if (inb && l ~ /^(Advisory ID|CVE): /) {
            v = val(l)
            if (v != "" && v != "NO") ids = ids (ids != "" ? "\t" : "") v
            next
        }
        if (inb && l ~ /^Ignore reason: /) { ign = 1; next }
        if (l ~ /^Name +Version +ID( |$)/) { flush(); tab = 1; next }
        if (tab == 1) { tab = (l ~ /^-+( +-+)+$/) ? 2 : 0; next }
        if (tab == 2) {
            if (l == "" || l ~ /^Name +Skip Reason/) { tab = 0; next }
            n = split(l, a, " ")
            if (n < 3 || a[3] !~ /^[A-Za-z][A-Za-z0-9]*-[A-Za-z0-9-]+$/) next
            s = a[3]
            for (i = 4; i <= n; i++) {
                t = a[i]; sub(/,$/, "", t)
                if (t ~ /^[A-Za-z][A-Za-z0-9]*-[A-Za-z0-9-]+$/) s = s "\t" t
                else if (t !~ /^[0-9]/) break
            }
            print s
        }
    }
    END { flush(); if (comp) printf "%s", other }' "$1"
}

dk_known_ok() { # <step-id> <outfile> → 0 keď všetky zlyhania sú známe; počet v KNOWN_N
    local id="$1" ids pats x p gi hit
    KNOWN_N=0
    pats=$(printf '%s' "$KNOWN" | awk -F"$DK_US" -v s="$id" '$1 == s { print $2 }')
    [ -n "$pats" ] || return 1
    # PHPUnit „N) Trieda::metóda“, pytest „FAILED <id>“ a „ERROR <cesta>.py[::<test>]“,
    # Nette Tester „-- FAILED: [titulok | ]<cesta>[ <argumenty>]“, záznamy auditu;
    # záznam s viacerými id je známy, keď vzor pokryje aspoň jedno z nich.
    ids=$({ sed -nE 's/^[0-9]+\) ([^[:space:]]+::[^[:space:]]+).*/\1/p; s/^FAILED ([^[:space:]]+).*/\1/p
        s/^ERROR ([^[:space:]]+\.py(::[^[:space:]]+)?)( .*)?$/\1/p
        /^-- FAILED: /{ s/^-- FAILED: //; s/^.* \| ([^[:space:]|]+\.phpt?( |$))/\1/; p;}' "$2"; dk_audit_ids "$2"; } | sort -u)
    [ -n "$ids" ] || return 1
    while IFS= read -r x; do
        [ -n "$x" ] || continue
        hit=0
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            gi=""
            case "$p" in '(?i)'*) p=${p#'(?i)'}; gi=-i ;; esac
            if printf '%s\n' "$x" | tr '\t' '\n' | grep -Eq $gi -e "$p"; then hit=1; break; fi
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

step_number=0
while IFS=$DK_US read -r tag id req run runf exts modes cl rt tsec required phase output report <&3; do
    [ "$tag" = S ] || continue
    [ -n "$id" ] || continue
    case ",$modes," in
        *",$mode,"*) ;;
        *,quick,*) [ "$mode" = full ] && [ "$required" = true ] || continue ;;
        *) continue ;;
    esac
    if [ "$before_stage" = 1 ]; then [ "$required:$phase" = true:before-stage ] || continue; fi
    step_number=$((step_number + 1))
    scope_run=""
    case "$output" in log|status) ;; *) dk_block "$id" "neznámy režim výstupu"; continue ;; esac
    if [ "$required" = true ]; then
        if ! dk_rule_on "step:$id"; then dk_block "$id" "povinná kontrola je vypnutá"; continue; fi
        case "$run" in ''|*'{files}'*) dk_block "$id" "povinná kontrola potrebuje úplný príkaz run"; continue ;; esac
        # Rozsah a výsledok povinnej kontroly určuje jej vlastný príkaz.
        runf="" exts="" cl=false
        case "$phase" in
            before-stage)
                if [ "$before_stage" = 1 ] && { [ -z "$BASE_PROOF" ] || [ "$INDEX_PROOF" != "$BASE_PROOF" ]; }; then
                    dk_block "$id" "pred stagingom treba index bez pripravených zmien"; continue
                fi
                if [ "$mode" != stop ] && [ "$before_stage" = 0 ]; then
                    if [ -n "$PROJECT_PROOF" ] && [ "$PROJECT_PROOF" = "$INDEX_PROOF" ] &&
                        BEFORE_RUN=$(jq -er --arg cfg "$CONFIG_HASH" --arg p "$PROJECT_PROOF" --arg id "$id" --arg modes "$modes" \
                            'select(.newPathsVerified == true and .configHash == $cfg and .projectProof == $p and (.requiredSteps | index($id)))
                             | select(.mode == "full" or (.mode == "quick" and ($modes | split(",") | index("quick"))))
                             | .runId' \
                            "$DK_TMP/before.json" 2>/dev/null); then
                        REQUIRED_OK="$REQUIRED_OK$id$DK_NL"
                        STEPLINES="${STEPLINES}✓ $id (overené pred stagingom)$DK_NL"; NOK=$((NOK + 1))
                    else
                        dk_block "$id" "chýba overenie rovnakého obsahu pred stagingom (--before-stage)"
                    fi
                    continue
                fi
                if [ "$before_stage" = 1 ] && [ -s "$DK_TMP/new-paths" ]; then
                    scope_run="$generation-$step_number"
                    run="export DEVKIT_SCOPE_RUN='$scope_run'; $run"
                fi ;;
            staged) ;;
            *) dk_block "$id" "neznáma fáza $phase"; continue ;;
        esac
    else
        dk_rule_on "step:$id" || { whole=false; continue; }
        if [ -z "$run" ] || [ "$cl" = true ]; then whole=false; fi
        case "$run" in *'{files}'*) whole=false ;; esac
    fi
    if [ -n "$req" ] && [ ! -e "$DK_PROJECT/$req" ]; then
        if [ "$required" = true ]; then dk_block "$id" "chýba $req"
        else dk_skip "$id" "chýba $req"; fi
        continue
    fi
    if ! dk_runtime "$rt"; then dk_block "$id" "neznámy runtime \"$rt\" (host|container)"; continue; fi
    case "$tsec" in ''|*[!0-9]*) dk_block "$id" "neplatný timeoutSec \"$tsec\" (celé číslo ≥ 0)"; continue ;; esac
    srt=$DK_RT
    # Krok na hoste nečaká na kontajner ani mapovanie worktree.
    if [ "$srt" = container ]; then
        dk_env_check
        if [ -n "$ENV_SKIP" ]; then dk_block "$id" "$ENV_SKIP"; continue; fi
    fi

    targets="" cmd=""
    if [ -n "$exts" ]; then
        targets=$(dk_files_for "$exts")
        if [ -z "$targets" ] && { [ "$mode" = stop ] || [ -z "$run" ]; }; then
            dk_skip "$id" "žiadne zmenené súbory"; continue
        fi
    fi
    # Výslovné --files: krok s runFiles kontroluje len ich, aj keď má run.
    if [ "$files_set" = 1 ] && [ "$mode" != stop ] && [ -n "$runf" ]; then
        [ -n "$exts" ] || targets=$(dk_files_for "")
        [ -n "$targets" ] || { dk_skip "$id" "žiadne zmenené súbory"; continue; }
        cmd=$runf
    elif [ "$mode" != stop ] && [ -n "$run" ]; then
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
        dk_block "$id" "bez príkazu (run/runFiles)"; continue
    fi
    # {files}: dávky ≤ 64 KiB citovaných ciest (MAX_ARG_STRLEN na Linuxe), jedna dávka na riadok; krok beží na každú.
    case "$cmd" in
        *"{files}"*)
            printf '%s\n' "$targets" | LC_ALL=C awk "$DK_AWK_FN"'
                $0 == "" { next }
                { f = $0; if (substr(f, 1, 1) == "-") f = "./" f; q = dk_shq(f)
                  if (b != "" && length(b) + 1 + length(q) > 65536) { print b; b = "" }
                  b = (b == "" ? q : b " " q) }
                END { if (b != "") print b }' > "$DK_TMP/batches"
            [ -s "$DK_TMP/batches" ] || echo > "$DK_TMP/batches"
            ;;
        *) [ "$cmd" = "$runf" ] || targets=$EXIST; echo > "$DK_TMP/batches" ;;
    esac
    nb=$(grep -c '' "$DK_TMP/batches")

    # Výsledok kroku = spojený výstup dávok a najvyšší exit; timeoutSec platí pre celý krok.
    s0=$(dk_ms)
    : > "$DK_TMP/step.out"
    rc=0 tmo="" k=0
    while IFS= read -r q <&4; do
        k=$((k + 1))
        bcmd=$cmd
        case "$cmd" in *"{files}"*) bcmd=${cmd//\{files\}/"$q"} ;; esac
        lim=$tsec
        if [ "$tsec" -gt 0 ] && [ "$k" -gt 1 ]; then
            lim=$(( tsec - ($(dk_ms) - s0) / 1000 ))
            [ "$lim" -ge 1 ] || lim=1
        fi
        b0=$(dk_ms)
        if [ "$output" = status ]; then
            dk_exec "$bcmd" "$srt" "$lim" > /dev/null
            brc=$?
        else
            dk_exec "$bcmd" "$srt" "$lim" > "$DK_TMP/step.raw"
            brc=$?
            LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g" "$DK_TMP/step.raw" > "$DK_TMP/step.bout"
            cat "$DK_TMP/step.bout" >> "$DK_TMP/step.out"
        fi
        bms=$(( $(dk_ms) - b0 ))
        btmo=""
        [ "$DK_EXEC_TIMEOUT" = 1 ] && btmo=" · prekročil timeoutSec $tsec s"
        hdr="=== $id"
        [ "$nb" -le 1 ] || hdr="$hdr · dávka $k/$nb"
        {
            echo
            echo "$hdr · exit $brc · $(dk_fmt_s "$bms") s$btmo"
            if [ "$output" = log ]; then echo "\$ $bcmd"; cat "$DK_TMP/step.bout"; fi
        } 2>/dev/null >> "$LOG"
        [ "$brc" -le "$rc" ] || rc=$brc
        if [ -n "$btmo" ]; then tmo=$btmo; break; fi
    done 4< "$DK_TMP/batches"
    ms=$(( $(dk_ms) - s0 ))

    # Časový limit: krok nedobehol, výsledok nie je o kóde → PARTIAL (Stop neblokuje, commit gate vysvetlí).
    if [ -n "$tmo" ]; then dk_block "$id" "" "! krok $id prekročil $tsec s"; continue; fi
    if [ "$rc" = 0 ]; then
        if [ -n "$scope_run" ]; then
            case "/$report/" in //*|*/../*) dk_block "$id" "nové cesty potrebujú projektový newPathsReport pre tento beh"; continue ;; esac
        fi
        if [ -n "$scope_run" ] && ! { [ -f "$DK_PROJECT/$report" ] && jq -se --arg run "$scope_run" --rawfile paths "$DK_TMP/new-paths" '
            length == 1 and (.[0] | .run == $run and (.checked | type == "array" and all(.[]; type == "string"))
            and ((.excluded // {}) | type == "object" and all(.[]; type == "string" and test("\\S")))
            and (($paths | split("\u0000") | map(select(length > 0))) - .checked - ((.excluded // {}) | keys) | length == 0))' \
            "$DK_PROJECT/$report" >/dev/null 2>&1; }; then
            dk_block "$id" "projektový report nedoložil nové cesty pre tento beh"; continue
        fi
        [ "$required" != true ] || REQUIRED_OK="$REQUIRED_OK$id$DK_NL"
        STEPLINES="${STEPLINES}✓ $id $(dk_fmt_s "$ms") s$DK_NL"; NOK=$((NOK + 1)); continue
    fi
    if [ "$rc" -ge 125 ] && [ "$rc" -le 127 ]; then
        dk_block "$id" "príkaz sa nedá spustiť (exit $rc)"; continue
    fi
    if [ "$output" = status ]; then
        STEPLINES="${STEPLINES}✗ $id $(dk_fmt_s "$ms") s (exit $rc)$DK_NL"; NFAIL=$((NFAIL + 1)); continue
    fi
    # Zlyhal nástroj alebo docker, nie kód (žiadny riadok nálezu) → BLOCK, Stop na infraštruktúre neblokuje.
    if [ "$required" != true ] && [ "$rc" = 16 ] && ! grep -Eq "$DK_RE_FINDING" "$DK_TMP/step.out" && grep -Eq "$DK_RE_NO_FILES" "$DK_TMP/step.out"; then
        dk_skip "$id" "nástroj nič neskontroloval (No files were checked)"; continue
    fi
    if ! grep -Eq "$DK_RE_FINDING" "$DK_TMP/step.out" && grep -Eq "$DK_RE_INFRA" "$DK_TMP/step.out"; then
        dk_block "$id" "chyba prostredia, nie kódu ($(grep -Eo "$DK_RE_INFRA" "$DK_TMP/step.out" | head -n 1))"; continue
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
                printf '%s\n' "$sp" | DK_AWK_R="$f" awk 'NF { print ENVIRON["DK_AWK_R"] "\t" $0 }' >> "$DK_TMP/step.map"
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
    if [ "$required" != true ] && dk_known_ok "$id" "$DK_TMP/step.out"; then
        STEPLINES="${STEPLINES}✓ $id $(dk_fmt_s "$ms") s (známe zlyhania: $KNOWN_N)$DK_NL"
        NKNOWN=$((NKNOWN + 1)); continue
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

# Zámok testu (/dev:fix): obsah iný ako pri zamknutí (zmena cez Bash, mimo pre-edit) = FAIL v každom režime,
# lebo pass.json z quick či full odomyká commit. Cesta von je len vrátenie testu alebo /dev:fix --unlock.
LOCKLINES="" NLOCK=0
if dk_rule_on testLock && [ -f "$DK_PDATA/test-lock.json" ] && dk_lock_read "$TTL"; then
    jq -r '(.blobs // {}) | if type == "object" then to_entries[] | "\(.key)\u001f\(.value)" else empty end' \
        "$DK_PDATA/test-lock.json" 2>/dev/null > "$DK_TMP/lock.want"
    (set -f; IFS=$DK_NL; dk_blobs $DK_LOCK_FILES) > "$DK_TMP/lock.cur"
    while IFS=$DK_US read -r f b; do
        [ -n "$f" ] && [ -n "$b" ] || continue
        case "$DK_NL$DK_LOCK_FILES" in *"$DK_NL$f$DK_NL"*) ;; *) continue ;; esac
        cur=$(DK_AWK_P="$f" awk -F'\t' 'BEGIN { p = ENVIRON["DK_AWK_P"] } $1 == p { print $2; exit }' "$DK_TMP/lock.cur" 2>/dev/null)
        [ "${cur:--}" = "$b" ] && continue
        LOCKLINES="${LOCKLINES}! test $f zmenený počas /dev:fix (zámok)$DK_NL"
        NLOCK=$((NLOCK + 1))
        printf '\n=== zámok testu: %s · blob %s → %s\n' "$f" "$b" "${cur:--}" 2>/dev/null >> "$LOG"
    done < "$DK_TMP/lock.want"
fi

if { [ "$STRICT" = true ] || [ "$whole" = true ]; } && [ "$mode" != stop ] && [ -z "$CFG_OVER" ]; then
    current=$(dk_project_proof worktree "$DK_PROJECT") || current=""
    current_index=$(dk_project_proof index "$DK_PROJECT") || current_index=""
    if [ -z "$PROJECT_PROOF" ] || [ "$current" != "$PROJECT_PROOF" ] || [ -z "$INDEX_PROOF" ] || [ "$current_index" != "$INDEX_PROOF" ]; then
        whole=false
        PROJECT_PROOF=""
        INDEX_PROOF=""
        [ "$STRICT" != true ] || dk_block projekt "stav projektu počas kontroly sa zmenil alebo sa nedal overiť (pracovný strom alebo index)"
    fi
fi
TOTAL=$(( $(dk_ms) - T0 ))

if [ "$NFAIL" -gt 0 ] || [ "$NLOCK" -gt 0 ]; then VERDICT=FAIL RC=1
elif [ "$NBLOCK" -gt 0 ]; then VERDICT=PARTIAL RC=4
elif [ $((NOK + NKNOWN)) -gt 0 ]; then VERDICT=PASS RC=0
else VERDICT=SKIP RC=4
fi
[ -n "$STEPLINES" ] || { STEPLINES="– žiadne kroky pre režim $mode$DK_NL"; }
# fullWhen prepol na full, ale config nemá krok len pre jeden z režimov quick/full.
if [ "$AUTO_FULL" = 1 ]; then
    same=1
    while IFS=$DK_US read -r tag id req run runf exts modes cl rt tsec required phase; do
        [ "$tag" = S ] && [ -n "$id" ] || continue
        dk_rule_on "step:$id" || continue
        case ",$modes," in *,full,*) a=1 ;; *) a=0 ;; esac
        case ",$modes," in *,quick,*) b=1 ;; *) b=0 ;; esac
        [ "$a" = "$b" ] || { same=0; break; }
    done <<EOF
$DK_CFG_OUT
EOF
    [ "$same" = 0 ] || STEPLINES="– full: rovnaké kroky ako quick$DK_NL$STEPLINES"
fi
STEPLINES="$LOCKLINES$STEPLINES"

# Markery a log pred výpisom: zatvorený stdout (SIGPIPE) ich nesmie zahodiť.
# PARTIAL nikdy nezapíše pass.json: v quick/full ide do partial.json (vysvetlenie v commit gate),
# v Stop do stavu session (neopakovať kontrolu nad tým istým obsahom). Beh s iným configom
# markery nepíše ani nemaže: commit gate a Stop overujú config projektu.
if [ -z "$CFG_OVER" ] && [ "$mode" != stop ]; then
    if [ "$VERDICT" = PARTIAL ]; then
        # ok = kroky, ktoré by po vypnutí blokovaných dali PASS; steps úplné, lines len na zobrazenie.
        jq -n --argjson t "$(dk_now)" --arg m "$mode" --argjson ok "$((NOK + NKNOWN))" \
            --arg s "$(printf '%s' "$BLOCKIDS" | awk 'NF && !s[$0]++')" \
            --arg l "$(printf '%s' "$STEPLINES" | grep '^! ' | head -n 5)" \
            '{time: $t, mode: $m, ok: $ok, steps: ($s | split("\n") | map(select(length > 0))),
              lines: ($l | split("\n") | map(select(length > 0)))}' \
            2>/dev/null > "$RESULT_DIR/partial.tmp" && mv "$RESULT_DIR/partial.tmp" "$RESULT_DIR/partial.json"
    fi
fi
if [ -n "$CFG_OVER" ]; then
    :
elif [ "$mode" = stop ] && { [ "$RC" = 0 ] || [ "$VERDICT" = PARTIAL ]; }; then
    SF=$(dk_stop_file)
    jq -n --arg h "$SNAP_HASH" --argjson t "$(dk_now)" --arg r "$VERDICT" '{hash: $h, time: $t, fails: 0, result: $r}' \
        2>/dev/null > "$SF.tmp.$$" && mv "$SF.tmp.$$" "$SF"
elif [ "$RC" = 0 ] && [ "$before_stage" = 1 ]; then
    jq -n --arg gen "$generation" --arg m "$mode" --arg cfg "$CONFIG_HASH" --arg p "$PROJECT_PROOF" --arg ids "$REQUIRED_OK" \
        '{runId:$gen, newPathsVerified:true, mode:$m, configHash:$cfg, projectProof:$p, requiredSteps:($ids|split("\n")|map(select(length>0)))}' \
        > "$RESULT_DIR/before.tmp" && mv "$RESULT_DIR/before.tmp" "$RESULT_DIR/before.ok" || exit 3
elif [ "$RC" = 0 ]; then
    HEAD_SHA=$(dk_git rev-parse --verify -q HEAD 2>/dev/null)
    if [ "$NSKIP" != 0 ] || [ "$NKNOWN" != 0 ] || [ -z "$PROJECT_PROOF" ]; then whole=false; fi
    jq -n --arg ids "$REQUIRED_OK" --arg before "$BEFORE_RUN" --argjson whole "$whole" --arg log "${LOG##*/}" --argjson t "$(dk_now)" --arg m "$mode" --arg h "$HEAD_SHA" --arg cfg "$CONFIG_HASH" --arg proof "$PROJECT_PROOF" --arg idx "$INDEX_PROOF" --rawfile b "$DK_TMP/blobs.snap" \
        '{requiredSteps: ($ids|split("\n")|map(select(length>0))), beforeRun: $before, unfilteredRun: $whole, log: $log, time: $t, mode: $m, head: $h, configHash: $cfg, projectProof: $proof, indexProof: $idx, blobs: ($b | split("\n") | map(select(length > 0) | split("\t") | {(.[0]): .[1]}) | add // {})}' \
        2>/dev/null > "$RESULT_DIR/pass.tmp" && mv "$RESULT_DIR/pass.tmp" "$RESULT_DIR/pass.json" || exit 3
fi

if [ -n "$RESULT_DIR" ]; then
    # Odkazy sa posúvajú len na čerstvé adresáre. Predbežný dôkaz môže platiť aj viac dní.
    find "$DK_PDATA" ! -path "$DK_PDATA" -type d -prune -name 'result.??????' -mtime +1 -print |
    while IFS= read -r old; do
        [ "$old" != "$RESULT_DIR" ] && [ "$old" != "$DK_PDATA/$(readlink "$DK_PDATA/current-check")" ] || continue
        [ "$(readlink "$DK_PDATA/before-stage.json")" != "${old##*/}/before.ok" ] || continue
        rm -f "$old/pass.json" "$old/partial.json" "$old/before.ok" "$old/log-name"
        rmdir "$old" 2>/dev/null || :
    done
fi
ls -1t "$DK_PDATA"/logs/check-*.log 2>/dev/null | tail -n +21 | while IFS= read -r f; do
    [ "${f##*/}" = "$(cat "$DK_PDATA/current-check/log-name" 2>/dev/null)" ] || rm -f "$f"
done
case "$RC" in 0) dec=pass ;; 1) dec=block ;; *) dec=skip ;; esac
if [ -n "$RESULT_DIR" ] && [ "$(readlink "$DK_PDATA/current-check")" != "$generation" ]; then
    STEPLINES="! O stave commitu rozhoduje novší beh. Výsledok tohto behu: $VERDICT.$DK_NL$STEPLINES"
    if [ "$RC" = 0 ]; then VERDICT=PARTIAL RC=4 dec=skip; fi
fi
dk_log check "check:$mode" "$dec" "" "$TOTAL"

NSTEP=$(printf '%s' "$STEPLINES" | grep -c .)
BUDGET=$((20 - NSTEP - 2))
[ -z "$CFG_OVER" ] || BUDGET=$((BUDGET - 1))
PER=$BUDGET
[ "$NFAIL" -gt 0 ] && PER=$((BUDGET / NFAIL))
{
    kn=""
    [ "$NKNOWN" -gt 0 ] && kn=" · $NKNOWN známe"
    printf '[dev-kit] check %s: %s · %s ok%s · %s fail · %s skip · %s s\n' "$mode" "$VERDICT" "$NOK" "$kn" "$((NFAIL + NLOCK))" "$NSKIP" "$(dk_fmt_s "$TOTAL")"
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
    [ -z "$CFG_OVER" ] || echo "config: $CFG_OVER (namiesto .claude/devkit.json; výsledok neodomkne commit)"
    echo "log: $LOG"
}

exit "$RC"
