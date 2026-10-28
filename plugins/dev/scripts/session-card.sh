#!/usr/bin/env bash
# SessionStart: jeden JSON objekt — additionalContext = úvodná karta (≤ 10 riadkov, kontext pre Clauda),
# systemMessage = len upozornenia pre používateľa (plain stdout by používateľ nevidel).
# Bez hooku: session-card.sh --record-handoff <cesta> <názov> [--project P] → last-handoff.json (/dev:handoff).
. "$(dirname "$0")/lib.sh" || exit 0
DK_HOOK=session-card

dk_record_handoff() {
    local path="" title="" project=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --project) project=${2:-}; [ $# -gt 1 ] && shift ;;
            --project=*) project=${1#*=} ;;
            *) if [ -z "$path" ]; then path=$1; elif [ -z "$title" ]; then title=$1; fi ;;
        esac
        shift
    done
    if [ -z "$path" ]; then
        echo "použitie: session-card.sh --record-handoff <cesta> <názov> [--project P]"
        return 2
    fi
    DK_NO_STDIN=1
    DK_PROJECT_ARG=${project:-$PWD}
    dk_init
    if [ "$DK_HAS_JQ" != 1 ]; then echo "[dev-kit] chýba jq — handoff sa nezaznamenal (brew install jq)"; return 1; fi
    case "$path" in /*) local r; r=$(dk_rel "$path"); [ -n "$r" ] && path=$r ;; ./*) path=${path#./} ;; esac
    [ -n "$title" ] || title=${path##*/}
    mkdir -p "$DK_PDATA" 2>/dev/null
    if jq -n --argjson t "$(dk_now)" --arg ti "$title" --arg p "$path" '{time: $t, title: $ti, path: $p}' \
        2>/dev/null > "$DK_PDATA/last-handoff.json.tmp" && mv "$DK_PDATA/last-handoff.json.tmp" "$DK_PDATA/last-handoff.json"; then
        echo "[dev-kit] handoff zaznamenaný: $title → $path (úvodná karta ho ukáže 24 h)"
        return 0
    fi
    echo "[dev-kit] handoff sa nepodarilo zapísať do $DK_PDATA"
    return 1
}

dk_emit() { # <karta> <upozornenia>
    [ -n "$1$2" ] || return 0
    jq -nc --arg c "$1" --arg w "$2" \
        '(if $c == "" then {} else {hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}} end)
         + (if $w == "" then {} else {systemMessage: $w} end)'
}

# Verzia Claude Code staršia ako DK_MIN_CC → riadok upozornenia; `claude --version` najviac raz za deň.
dk_cc_old() { # <today>
    local f="$DK_DATA/cc-version.$1" v="" a b i
    if [ -f "$f" ]; then
        v=$(head -n 1 "$f" 2>/dev/null)
    elif command -v claude >/dev/null 2>&1; then
        v=$(claude --version 2>/dev/null </dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
        rm -f "$DK_DATA"/cc-version.* 2>/dev/null
        printf '%s\n' "$v" 2>/dev/null > "$f"
    fi
    [ -n "$v" ] || return 1
    i=1
    while [ "$i" -le 3 ]; do
        a=$(printf '%s' "$v" | cut -d. -f"$i")
        b=$(printf '%s' "$DK_MIN_CC" | cut -d. -f"$i")
        if [ "${a:-0}" -lt "${b:-0}" ]; then printf 'Claude Code %s je starší ako %s → claude update' "$v" "$DK_MIN_CC"; return 0; fi
        [ "${a:-0}" -gt "${b:-0}" ] && return 1
        i=$((i + 1))
    done
    return 1
}

dk_card() {
    dk_init
    if [ "$DK_HAS_JQ" != 1 ]; then
        printf '%s\n' '{"systemMessage":"[dev-kit] chýba jq → hooky kitu nebežia (brew install jq)"}'
        return 0
    fi
    local today hint msg
    today=$(date +%Y%m%d)
    if [ -z "$DK_CFG" ]; then
        if [ -f "$DK_PROJECT/composer.json" ] || [ -f "$DK_PROJECT/pyproject.toml" ] || [ -f "$DK_PROJECT/package.json" ]; then
            hint="$DK_PDATA/card-hint.$today"
            if [ ! -f "$hint" ]; then
                msg="[dev-kit] projekt nemá .claude/devkit.json — /dev:project-init ho nastaví"
                dk_emit "$msg" "$msg"
                mkdir -p "$DK_PDATA" 2>/dev/null
                rm -f "$DK_PDATA"/card-hint.* 2>/dev/null
                : 2>/dev/null > "$hint"
            fi
        fi
        return 0
    fi
    if ! dk_cfg_read '"S\u001f\(if .stopCheck == false then "false" else "true" end)",
        "G\u001f\(if (.commitGate|type) == "boolean" then .commitGate elif .commitGate.enabled == false then false else true end | s)",
        "T\u001f\(.testLock.ttlHours // 6 | s)"'; then
        msg="[dev-kit] .claude/devkit.json nie je platný JSON → hooky kitu stoja (jq . .claude/devkit.json)"
        dk_emit "$msg" "$msg"
        return 0
    fi
    local tag a stop=true gate=true ttl=6 l1 cont now warn="" w
    while IFS=$DK_US read -r tag a; do
        case "$tag" in
            S) stop=$a ;;
            G) gate=$a ;;
            T) ttl=$a ;;
        esac
    done <<EOF
$DK_CFG_OUT
EOF
    dk_rule_on stopCheck || stop=false
    dk_rule_on commitGate || gate=false
    [ "$stop" = true ] && stop=on || stop=off
    [ "$gate" = true ] && gate=on || gate=off
    if [ -z "$DK_CONTAINER" ]; then
        cont="bez kontajnera (host)"
    elif ! command -v docker >/dev/null 2>&1; then
        cont="chýba docker → kontroly v kontajneri sa preskočia"
        warn="$warn[dev-kit] $cont$DK_NL"
    elif dk_container_ok; then
        cont="kontajner $DK_CONTAINER beží"
    else
        cont="kontajner $DK_CONTAINER NEBEŽÍ — kontroly sa preskočia"
        warn="$warn[dev-kit] $cont$DK_NL"
    fi
    l1="[dev-kit] ${DK_STACK:-?} · $cont · Stop kontrola $stop · commit gate $gate"
    now=$(dk_now)

    # Voliteľné riadky (4–7) majú prednosť pred výpisom git status.
    local extra="" hout ht htitle hpath h m mt d
    if [ -f "$DK_PDATA/last-handoff.json" ]; then
        hout=$(jq -r '[(.time // 0 | tostring), .title // "", .path // ""] | join("\u001f")' "$DK_PDATA/last-handoff.json" 2>/dev/null)
        IFS=$DK_US read -r ht htitle hpath <<EOF
$hout
EOF
        ht=${ht%%.*}
        case "$ht" in ''|*[!0-9]*) ht=0 ;; esac
        if [ $((now - ht)) -lt 86400 ]; then
            h=$(((now - ht) / 3600))
            extra="${extra}posledný handoff: $htitle (pred $h h) → $hpath$DK_NL"
        fi
    fi
    # Upozornenia idú do karty aj do systemMessage.
    w=""
    if [ -f "$DK_PROJECT/.git" ]; then
        m=$(dk_main_root)
        if [ "$m" != "$DK_PROJECT" ]; then
            case "$DK_STACK" in
                python*)
                    [ -d "$m/.venv" ] && [ ! -e "$DK_PROJECT/.venv" ] && \
                        w="worktree nemá .venv/ → vytvor nový venv (uv sync alebo python3 -m venv .venv && .venv/bin/pip install -e '.[dev]')"
                    ;;
                *)
                    [ -d "$m/vendor" ] && [ ! -e "$DK_PROJECT/vendor" ] && w="worktree nemá vendor/ → doplň .worktreeinclude alebo composer install"
                    ;;
            esac
        fi
    fi
    if [ -n "$w" ]; then extra="$extra$w$DK_NL"; warn="$warn[dev-kit] $w$DK_NL"; fi
    mt=""
    [ -f "$DK_DATA/maintenance.json" ] && mt=$(jq -r '.lastUpstreamCheck // empty' "$DK_DATA/maintenance.json" 2>/dev/null)
    mt=${mt%%.*}
    case "$mt" in *[!0-9]*) mt="" ;; esac
    w=""
    if [ -z "$mt" ]; then
        w="údržba kitu: kontrola upstreamu ešte nebežala → make -C ~/Projects/_tools/claude-dev-kit upstream"
    elif [ $((now - mt)) -gt $((30 * 86400)) ]; then
        d=$(((now - mt) / 86400))
        w="údržba kitu: posledná kontrola upstreamu pred $d dňami → make -C ~/Projects/_tools/claude-dev-kit upstream"
    fi
    if [ -n "$w" ]; then extra="$extra$w$DK_NL"; warn="$warn[dev-kit] $w$DK_NL"; fi
    if [ -f "$DK_PDATA/test-lock.json" ] && dk_lock_read "$ttl"; then
        extra="${extra}zamknutý test: $(printf '%s' "$DK_LOCK_FILES" | grep -v '^$' | tr '\n' ' ' | sed 's/ $//; s/ /, /g') (do $(dk_fmt_time "$DK_LOCK_UNTIL"))$DK_NL"
    fi
    if w=$(dk_cc_old "$today"); then extra="$extra$w$DK_NL"; warn="$warn[dev-kit] $w$DK_NL"; fi

    local st branch n first rest nextra room
    st=$(dk_git status --short --branch 2>/dev/null)
    first=$(printf '%s\n' "$st" | head -n 1)
    rest=$(printf '%s\n' "$st" | sed -n '2,$p' | grep -v '^$')
    case "$first" in
        "## No commits yet on "*) branch=${first#"## No commits yet on "} ;;
        "## HEAD (no branch)"*) branch="detached HEAD" ;;
        "## "*) branch=${first#"## "}; branch=${branch%%...*}; branch=${branch%% *} ;;
        *) branch="?" ;;
    esac
    n=0
    [ -n "$rest" ] && n=$(printf '%s\n' "$rest" | grep -c .)
    nextra=0
    [ -n "$extra" ] && nextra=$(printf '%s' "$extra" | grep -c .)
    room=$((10 - 3 - nextra))
    [ "$room" -gt 3 ] && room=3
    [ "$room" -lt 0 ] && room=0

    local card
    card=$(
        echo "$l1"
        echo "kontroly: /dev:check (quick) · /dev:check --full · /dev:commit"
        if [ -n "$st" ]; then
            echo "git: $branch · $(dk_plural "$n" "zmenený súbor" "zmenené súbory" "zmenených súborov")"
            [ "$room" -gt 0 ] && [ -n "$rest" ] && printf '%s\n' "$rest" | head -n "$room" | sed 's/^/  /'
        fi
        [ -n "$extra" ] && printf '%s' "$extra"
    )
    dk_emit "$(printf '%s\n' "$card" | head -n 10)" "$(printf '%s' "$warn" | grep -v '^$')"

    # Údržba dát kitu: staré zoznamy session, veľký log rozhodnutí.
    if [ "${DK_SOURCE:-startup}" = startup ]; then
        find "$DK_PDATA/sessions" -name '*.files' -mtime +14 -exec rm -f {} + 2>/dev/null
        find "$DK_PDATA" -maxdepth 1 -name 'pairs-*.done' -mtime +14 -exec rm -f {} + 2>/dev/null
        if [ -f "$DK_DATA/decisions.jsonl" ] && [ "$(wc -c < "$DK_DATA/decisions.jsonl" | tr -d ' ')" -gt 10485760 ]; then
            mv "$DK_DATA/decisions.jsonl" "$DK_DATA/decisions.jsonl.1" 2>/dev/null
        fi
    fi
    return 0
}

if [ "${1:-}" = "--record-handoff" ]; then
    shift
    dk_record_handoff "$@"
    exit $?
fi
dk_card
rc=$?
[ "$rc" = 0 ] || dk_err "session-card: neočakávaný návratový kód $rc"
exit 0
