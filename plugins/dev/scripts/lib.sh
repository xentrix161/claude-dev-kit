#!/usr/bin/env bash
# dev-kit: spoločné funkcie hookov a skriptov. Kontrakt: docs/SPEC.md §2–§4.
# Musí bežať na macOS /bin/bash 3.2 aj na bash 5 (bez asociatívnych polí, mapfile, ${x,,}, sed -i…).

DK_US=$'\x1f'
DK_RS=$'\x1e'
DK_NL=$'\n'
DK_TAB=$'\t'
DK_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)

# jq: s = bezpečný jednoriadkový reťazec; gl = glob alebo zoznam globov oddelený DK_RS;
# base = spoločné kľúče devkit.json (tagované riadky).
DK_JQ_DEFS='def s: if . == null then "" elif type == "string" then gsub("[\n\r\u001f\u001e]"; " ") else tojson end;
def gl: if type == "array" then map(s) | join("\u001e") else s end;
def base: "C\u001f\(.container|s)", "A\u001f\(.appRoot|s)", "K\u001f\(.stack|s)",
  ((.disabledRules // []) | .[] | "D\u001f\(.|s)"),
  "X\u001f\([(.lint // {} | keys[]), ((.check.steps // [])[] | (.ext // [])[])] | unique | join(","))",
  "Y\u001f\([(.lint // {} | keys[]), ((.check.steps // [])[] | select(any((.modes // ["quick","full"])[]?; . == "stop")) | (.ext // [])[])] | unique | join(","))";'
# Príkazy, ktoré hooky spúšťajú (lint, run, runFiles) — snímka dk_cfg_trust; zmena runtime = iný príkaz.
DK_JQ_CMDS='def rt: if type == "object" and .runtime != null then " (\(.runtime|s))" else "" end;
[ ((.lint // {}) | if type == "object" then to_entries[] else empty end | .key as $e
    | .value | if type == "array" then .[] else . end
    | if type == "object" then "lint \($e|s)\(rt): \(.run|s)" else "lint \($e|s): \(.|s)" end),
  ((.check.steps // []) | if type == "array" then .[] else empty end | select(type == "object") | (.id|s) as $id
    | (select(.run != null) | "krok \($id) run\(rt): \(.run|s)"),
      (select(.runFiles != null) | "krok \($id) runFiles\(rt): \(.runFiles|s)"))
] | unique'
# Text hooku pre Clauda (additionalContext, systemMessage, plain stdout) ≤ 9 000 jednotiek UTF-16, potom „…“ —
# Claude Code text nad 10 000 znakov nahradí cestou k súboru a začiatkom (SPEC §4).
DK_JQ_CAP='def dk_cap: if length <= 4500 then . else
  [foreach explode[] as $c (0; . + (if $c > 65535 then 2 else 1 end))] as $u
  | if $u[-1] <= 9000 then . else .[0:($u | map(select(. < 9000)) | length)] + "…" end end;'

# Začiatok príkazu (oddeľovač, obal, env priradenia) + git s globálnymi prepínačmi (SPEC §4.4).
# Obsahujú '/', sed s nimi používa oddeľovač \001.
DK_RE_GITPFX='(^|[;&|({!]|&&|\|\||(^|[[:space:]])(then|do|else|time|nice|nohup|command|builtin|exec|env))[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]"'"'"';&|])*[[:space:]]+)*\\?([^[:space:];&|()"'"'"']*/)?git([[:space:]]+(-C[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|]+)|-c[[:space:]]+[^[:space:];&|]+|-[pP]|--no-pager|--paginate|--no-replace-objects|--literal-pathspecs|--bare|--(git-dir|work-tree|namespace)(=|[[:space:]]+)("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|]+)))*'
DK_RE_COMMIT="$DK_RE_GITPFX[[:space:]]+commit([[:space:]]|\$)"
# --continue týchto príkazov commitne staged súbory (gate a tajomstvá ako pri commit).
DK_RE_COMMIT_CONT="$DK_RE_GITPFX[[:space:]]+(rebase|merge|cherry-pick|revert|am)([[:space:]]+[^;&|]*)?--continue"
DK_RE_ADD="$DK_RE_GITPFX[[:space:]]+(add|stage)([[:space:]]|\$)"
# Rýchla cesta pre-bash.sh: git, $… alebo ` a za nimi na riadku commit či --continue; o commite rozhodne parser.
DK_RE_COMMIT_ANY='(git|[$]|`).*[[:space:]](commit|--continue)'

# Najstaršia podporovaná verzia Claude Code (úvodná karta upozorní na staršiu); SPEC §0 predpoklad 8.
DK_MIN_CC=2.1.314

# Predvolené vzory tajomstiev (POSIX ERE, (?i) = bez ohľadu na veľkosť písmen).
DK_SECRET_DEFAULTS='(?i)(password|passwd|heslo|secret|api[_-]?key|token)["'"'"']?[[:space:]]*(=>|[:=])[[:space:]]*["'"'"'][^"'"'"'[:space:]]{6,}
-----BEGIN [A-Z ]*PRIVATE KEY-----
AKIA[0-9A-Z]{16}
[A-Z0-9_]*TEST_PASS(WORD)?=[^[:space:]]+'
# Hodnoty, ktoré nie sú tajomstvo (odkaz na premennú, zástupný text).
# Ukotvené na celú hodnotu; {{ a < ostávajú prefixom, lebo grep -o hodnotu oreže na prvej medzere.
DK_SECRET_PLACEHOLDER='^(%env\([^)]*\)%|%[A-Za-z0-9_.]+%|\$\{[^}]*\}?|\$[A-Za-z_][A-Za-z0-9_]*(->[A-Za-z_][A-Za-z0-9_]*)*|\{\{.*|<.*|\*+|[xX]+|\.\.\.)$'

# Zlyhanie nástroja samotného (nie nález v kóde) — taký výstup kontrolu preskočí, neblokuje.
# Sieť: composer (curl, „could not be downloaded“) a pip-audit (urllib3, rada pri chybe spojenia).
DK_RE_INFRA='Could not open input file|command not found|No such file or directory|Error response from daemon|OCI runtime|is not running|Cannot connect to the Docker daemon|executable file not found|No files were checked|curl error [0-9]+ while downloading|could not be downloaded|Max retries exceeded|network may be blocking this service'

dk_now() { date +%s; }

dk_ms() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        local t=${EPOCHREALTIME/./}
        t=${t/,/}
        printf '%s\n' "${t%???}"
        return 0
    fi
    perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000' 2>/dev/null || printf '%s000\n' "$(date +%s)"
}

# Dátový adresár len pre používateľa (700). umask len v subshelle — dk_exec spúšťa príkazy na hoste.
dk_data_dir() {
    local d="${DK_DATA:-${DEVKIT_DATA:-$HOME/.claude/dev-kit}}"
    if [ ! -d "$d" ]; then
        (umask 077; mkdir -p "$d") 2>/dev/null
    elif [ -z "${DK_DATA_OK:-}" ] && [ -O "$d" ]; then
        chmod 700 "$d" 2>/dev/null
    fi
    DK_DATA_OK=1
    return 0
}

# Nad 1 MB ostane posledných 500 riadkov.
dk_err() {
    local f
    dk_data_dir
    f="${DK_DATA:-${DEVKIT_DATA:-$HOME/.claude/dev-kit}}/errors.log"
    printf '%s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${DK_HOOK:-?}" "$*" 2>/dev/null >> "$f"
    if [ -f "$f" ] && [ "$(wc -c < "$f" 2>/dev/null | tr -d ' ')" -gt 1048576 ] 2>/dev/null; then
        { tail -n 500 "$f" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"; } 2>/dev/null || rm -f "$f.tmp.$$" 2>/dev/null
    fi
    return 0
}

# Výsledok v DK_ESC (bez subshellu).
dk__esc() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$DK_NL/\\n}
    s=${s//$DK_TAB/\\t}
    s=${s//$'\r'/\\r}
    DK_ESC=$s
}

dk_log() {
    local hook="$1" rule="$2" dec="$3" file="${4:-}" ms="${5:-}" p r f h sess
    case "$ms" in ''|*[!0-9]*) ms=null ;; esac
    dk__esc "${DK_PROJECT:-}"; p=$DK_ESC
    dk__esc "$rule"; r=$DK_ESC
    dk__esc "$file"; f=$DK_ESC
    dk__esc "$hook"; h=$DK_ESC
    dk__esc "${DK_SESSION:-}"; sess=$DK_ESC
    dk_data_dir
    printf '{"ts":%s,"project":"%s","session":"%s","hook":"%s","rule":"%s","decision":"%s","file":"%s","ms":%s}\n' \
        "${DK_T0:-$(dk_now)}" "$p" "$sess" "$h" "$r" "$dec" "$f" "$ms" 2>/dev/null >> "$DK_DATA/decisions.jsonl"
    return 0
}

dk_plural() { # <n> <1> <2-4> <0,5+>
    case "$1" in
        1) printf '%s %s' "$1" "$2" ;;
        2|3|4) printf '%s %s' "$1" "$3" ;;
        *) printf '%s %s' "$1" "$4" ;;
    esac
}

dk_shq() {
    local s="$1" out=""
    while :; do
        case "$s" in
            *\'*) out="$out${s%%\'*}'\\''"; s=${s#*\'} ;;
            *) out="$out$s"; break ;;
        esac
    done
    printf "'%s'" "$out"
}

dk_phys() { (cd -P -- "$1" 2>/dev/null && pwd -P); }

dk_tmpdir() {
    if [ -z "${DK_TMP:-}" ] || [ ! -d "$DK_TMP" ]; then
        DK_TMP=$(mktemp -d "${TMPDIR:-/tmp}/devkit.XXXXXX" 2>/dev/null) || DK_TMP="${TMPDIR:-/tmp}/devkit.$$"
        mkdir -p "$DK_TMP" 2>/dev/null
        trap 'rm -rf "$DK_TMP" 2>/dev/null' EXIT
    fi
}

dk_git() { git -C "$DK_PROJECT" -c core.quotepath=off "$@"; }

# Koreň hlavného checkoutu (pre worktree = repo, z ktorého vznikol).
dk_main_root() {
    local p="${1:-$DK_PROJECT}" c
    if [ -d "$p/.git" ]; then printf '%s\n' "$p"; return 0; fi
    c=$(git -C "$p" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    case "$c" in
        */.git) printf '%s\n' "${c%/.git}" ;;
        '') printf '%s\n' "$p" ;;
        *) git -C "$p" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$p" ;;
    esac
}

# Projekt = git toplevel základného adresára; ak je hint (cwd alebo adresár súboru) v linked worktree toho istého repa, projekt je worktree.
dk_set_project() {
    local base="$1" cwd="${2:-}" p t c
    p=$(dk_phys "$base")
    [ -n "$p" ] || p=$base
    if [ ! -e "$p/.git" ]; then
        t=$(git -C "$p" rev-parse --show-toplevel 2>/dev/null)
        [ -n "$t" ] && p=$t
    fi
    if [ -n "$cwd" ] && [ "$cwd" != "$base" ] && [ "$cwd" != "$p" ]; then
        c=$(dk_phys "$cwd")
        if [ -n "$c" ] && [ "$c" != "$p" ]; then
            t=$(git -C "$c" rev-parse --show-toplevel 2>/dev/null)
            if [ -n "$t" ] && [ "$t" != "$p" ] && [ -f "$t/.git" ] && [ -e "$p/.git" ] \
                && [ "$(dk_main_root "$t")" = "$(dk_main_root "$p")" ]; then
                p=$t
            fi
        fi
    fi
    DK_PROJECT=$p
    DK_CFG=""
    if [ -f "$p/.claude/devkit.json" ]; then
        DK_CFG="$p/.claude/devkit.json"
    elif [ -f "$p/.git" ]; then
        t=$(dk_main_root "$p")
        [ -f "$t/.claude/devkit.json" ] && DK_CFG="$t/.claude/devkit.json"
    fi
    t=$(printf '%s' "$p" | git hash-object --stdin 2>/dev/null)
    [ -n "$t" ] || t=$(printf '%s' "$p" | cksum | cut -d' ' -f1)
    DK_PHASH=${t:0:12}
    DK_PDATA="$DK_DATA/projects/$DK_PHASH"
    if [ -n "$DK_CFG" ]; then
        [ -d "$DK_PDATA/sessions" ] || mkdir -p "$DK_PDATA/sessions" "$DK_PDATA/logs" 2>/dev/null
        # Cesta projektu pre údržbu karty: dáta zmazaného worktree sa podľa nej uprace (SPEC §2).
        if [ ! -f "$DK_PDATA/project.json" ] && [ -d "$DK_PDATA" ]; then
            dk__esc "$p"
            printf '{"path":"%s"}\n' "$DK_ESC" 2>/dev/null > "$DK_PDATA/project.json"
        fi
    fi
    DK_DISABLED_LOADED=""
    DK_CONTAINER_STATE=""
    DK_BASE_LOADED="" DK_CONTAINER="" DK_APPROOT="" DK_STACK="" DK_CODE_EXTS="" DK_STOP_EXTS=""
    return 0
}

# Číta stdin (hook JSON), ak nie je tty a nie je DK_NO_STDIN; nastaví projekt, dáta, config, session.
dk_init() {
    if [ -z "${DK_INPUT_DONE:-}" ]; then
        DK_INPUT_DONE=1
        DK_INPUT=${DK_INPUT:-}
        if [ -z "${DK_NO_STDIN:-}" ] && [ ! -t 0 ]; then
            DK_INPUT=$(cat 2>/dev/null)
        fi
    fi
    DK_T0=$(dk_now)
    DK_DATA="${DEVKIT_DATA:-$HOME/.claude/dev-kit}"
    dk_data_dir
    DK_HAS_JQ=0
    command -v jq >/dev/null 2>&1 && DK_HAS_JQ=1
    DK_SESSION="" DK_CWD="" DK_FILE="" DK_EVENT="" DK_TOOL="" DK_STOP_ACTIVE="" DK_SOURCE="" DK_AGENT=""
    if [ -n "$DK_INPUT" ] && [ "$DK_HAS_JQ" = 1 ]; then
        local line
        line=$(printf '%s' "$DK_INPUT" | jq -r '[.session_id, .cwd, (.tool_input.file_path // .tool_input.notebook_path), .hook_event_name, .tool_name, .stop_hook_active, .source, .agent_type]
            | map(if . == null then "" else (tostring | gsub("[\n\r\u001f]"; " ")) end) | join("\u001f")' 2>/dev/null)
        IFS=$DK_US read -r DK_SESSION DK_CWD DK_FILE DK_EVENT DK_TOOL DK_STOP_ACTIVE DK_SOURCE DK_AGENT <<EOF
$line
EOF
    fi
    [ -n "$DK_SESSION" ] || DK_SESSION=${DK_SESSION_ARG:-${CLAUDE_SESSION_ID:-nosession}}
    DK_SESSION=${DK_SESSION//[^A-Za-z0-9._-]/_}
    if [ -n "${DK_PROJECT_ARG:-}" ]; then
        dk_set_project "$DK_PROJECT_ARG" "$PWD"
        return 0
    fi
    # Worktree určuje upravovaný súbor (najbližší existujúci adresár), inak cwd zo vstupu.
    local hint="${DK_CWD:-$PWD}"
    case "$DK_FILE" in
        /*)
            hint=${DK_FILE%/*}
            while [ -n "$hint" ] && [ ! -d "$hint" ]; do hint=${hint%/*}; done
            [ -n "$hint" ] || hint=/
            ;;
    esac
    dk_set_project "${CLAUDE_PROJECT_DIR:-${DK_CWD:-$PWD}}" "$hint"
}

dk_in() {
    [ -n "${DK_INPUT:-}" ] || return 0
    printf '%s' "$DK_INPUT" | jq -r "($1) // empty" 2>/dev/null
}

dk_cfg() {
    if [ -z "${DK_CFG:-}" ]; then printf '%s\n' "${2:-}"; return 0; fi
    jq -r --arg d "${2:-}" "($1) as \$v | if \$v == null then \$d elif (\$v|type) == \"string\" then \$v else (\$v|tojson) end" \
        "$DK_CFG" 2>/dev/null || printf '%s\n' "${2:-}"
}

# Jedno volanie jq: base + <program>; ďalšie argumenty idú jq (napr. --arg). Výsledok v DK_CFG_OUT.
dk_cfg_read() {
    local prog="$1" tag a
    shift
    DK_CFG_OUT=$(jq -r "$@" "$DK_JQ_DEFS base, $prog" "$DK_CFG" 2>/dev/null) || {
        dk_err "neplatný alebo nečitateľný $DK_CFG"
        return 1
    }
    DK_CONTAINER="" DK_APPROOT="" DK_STACK="" DK_DISABLED="" DK_CODE_EXTS="" DK_STOP_EXTS=""
    DK_DISABLED_LOADED=1 DK_BASE_LOADED=1
    while IFS=$DK_US read -r tag a; do
        case "$tag" in
            C) DK_CONTAINER=$a ;;
            A) DK_APPROOT=$a ;;
            K) DK_STACK=$a ;;
            D) DK_DISABLED="$DK_DISABLED$a$DK_NL" ;;
            X) DK_CODE_EXTS=$a ;;
            Y) DK_STOP_EXTS=$a ;;
        esac
    done <<EOF
$DK_CFG_OUT
EOF
    return 0
}

# container/appRoot/stack/kódové prípony pre funkcie volané bez dk_cfg_read (napr. zo skillu po dk_init).
dk_base() {
    [ -z "${DK_BASE_LOADED:-}" ] || return 0
    DK_BASE_LOADED=1
    [ -n "${DK_CFG:-}" ] || return 0
    local keep="${DK_CFG_OUT:-}"
    dk_cfg_read empty
    DK_CFG_OUT=$keep
    return 0
}

# Dôvera k devkit.json (R3, SPEC §4.1): hash configu oproti config.hash, príkazy oproti config.cmds.json.
# Bez snímky ju len založí. Zmena ⇒ 0, DK_CFG_CMDS = nové či zmenené príkazy, snímka sa prepíše; nikdy nebráni.
# [note] = on-edit, pre-bash: so značkou sessions/<id>.cfgnote neporovnáva, takže zmenu po hláške ukáže až karta.
dk_cfg_trust() {
    DK_CFG_CHANGED="" DK_CFG_CMDS=""
    [ -n "${DK_CFG:-}" ] && [ "${DK_HAS_JQ:-0}" = 1 ] || return 1
    local mark="$DK_PDATA/sessions/$DK_SESSION.cfgnote" h old new prev
    [ "${1:-}" = note ] && [ -f "$mark" ] && return 1
    h=$(git hash-object --no-filters -- "$DK_CFG" 2>/dev/null)
    [ -n "$h" ] || return 1
    old=""
    [ -f "$DK_PDATA/config.hash" ] && old=$(head -n 1 "$DK_PDATA/config.hash" 2>/dev/null)
    [ "$h" != "$old" ] || return 1
    new=$(jq -c "$DK_JQ_DEFS $DK_JQ_CMDS" "$DK_CFG" 2>/dev/null)
    [ -n "$new" ] || return 1
    if [ -n "$old" ]; then
        prev=$(jq -c 'if type == "array" then . else [] end' "$DK_PDATA/config.cmds.json" 2>/dev/null)
        DK_CFG_CMDS=$(jq -rn --argjson n "$new" --argjson o "${prev:-[]}" '($n - $o)[]' 2>/dev/null)
        DK_CFG_CHANGED=1
    fi
    mkdir -p "$DK_PDATA/sessions" 2>/dev/null
    { printf '%s\n' "$new" > "$DK_PDATA/config.cmds.json.$$" && mv "$DK_PDATA/config.cmds.json.$$" "$DK_PDATA/config.cmds.json" &&
        printf '%s\n' "$h" > "$DK_PDATA/config.hash.$$" && mv "$DK_PDATA/config.hash.$$" "$DK_PDATA/config.hash"; } 2>/dev/null ||
        { rm -f "$DK_PDATA/config.cmds.json.$$" "$DK_PDATA/config.hash.$$" 2>/dev/null; dk_err "snímka devkit.json sa nezapísala do $DK_PDATA"; }
    [ -n "$DK_CFG_CHANGED" ] || return 1
    [ "${1:-}" != note ] || : 2>/dev/null > "$mark"
    return 0
}

# Hláška on-edit a pre-bash po dk_cfg_trust (najviac 5 príkazov).
dk_cfg_note() {
    local n list
    n=$(printf '%s' "$DK_CFG_CMDS" | grep -c .)
    if [ "$n" = 0 ]; then
        printf '[dev-kit] devkit.json sa zmenil — príkazy: žiadny nový ani zmenený'
        return 0
    fi
    list=$(printf '%s\n' "$DK_CFG_CMDS" | grep -v '^$' | head -n 5 | awk 'NR > 1 { printf " · " } { printf "%s", $0 }')
    [ "$n" -le 5 ] || list="$list · … ďalšie: $((n - 5))"
    printf '[dev-kit] devkit.json sa zmenil — príkazy: %s' "$list"
}

dk_rule_on() {
    if [ -z "${DK_DISABLED_LOADED:-}" ]; then
        DK_DISABLED=$(dk_cfg '(.disabledRules // []) | .[]')
        DK_DISABLED_LOADED=1
    fi
    case "$DK_NL${DK_DISABLED:-}$DK_NL" in
        *"$DK_NL$1$DK_NL"*) return 1 ;;
    esac
    return 0
}

dk_ext() {
    local b=${1##*/}
    case "$b" in
        *.*) printf '.%s' "${b##*.}" ;;
    esac
}

# awk funkcie pre zoznamy súborov, výsledok ako shell dk_ext a dk_shq (volať s LC_ALL=C).
DK_AWK_FN='function dk_ext(p,   x) { x = p; sub(/.*\//, "", x); if (index(x, ".") == 0) return ""; sub(/.*\./, ".", x); return x }
function dk_shq(s,   o, i) { o = ""; while ((i = index(s, "\047")) > 0) { o = o substr(s, 1, i - 1) "\047\\\047\047"; s = substr(s, i + 1) } return "\047" o s "\047" }'

# stdin (cesta alebo cesta<TAB>…) → riadky, ktorých prípona je v <csv>; „code“ = bez prípony nikdy (dk_is_code).
dk_ext_filter() { # <csv> [code]
    DK_AWK_X=",$1," DK_AWK_C="${2:-}" LC_ALL=C awk -F'\t' "$DK_AWK_FN"'
        $1 != "" { e = dk_ext($1); if ((e != "" || ENVIRON["DK_AWK_C"] == "") && index(ENVIRON["DK_AWK_X"], "," e ",")) print }'
}

# <rel> [stop] — prípona je v lint kľúčoch alebo v ext niektorého kroku; „stop“ berie ext len krokov
# s mode stop, takže súbory, ktoré kontrolujú len kroky quick/full, Stop nespustia (SPEC §4.6).
dk_is_code() {
    local b=${1##*/} e x
    case "$b" in *.*) e=".${b##*.}" ;; *) return 1 ;; esac
    dk_base
    x=$DK_CODE_EXTS
    [ "${2:-}" = stop ] && x=$DK_STOP_EXTS
    case ",$x," in *",$e,"*) return 0 ;; esac
    return 1
}

# Rodič sa vždy rozrieši fyzicky (zlúči '.', '..', '//'), inak by zámok testu obišla iná podoba cesty.
dk_rel() {
    local f="$1" d rest
    [ -n "$f" ] || return 0
    case "$f" in /*) ;; *) return 0 ;; esac
    d=${f%/*}
    rest=${f##*/}
    while [ -n "$d" ] && [ ! -d "$d" ]; do
        rest="${d##*/}/$rest"
        d=${d%/*}
    done
    [ -n "$d" ] || d=/
    d=$(dk_phys "$d") || return 0
    f="${d%/}/$rest"
    case "$f" in
        "$DK_PROJECT"/*) printf '%s\n' "${f#"$DK_PROJECT"/}" ;;
    esac
    return 0
}

# Pracovný adresár v kontajneri pre DK_PROJECT; mimo mountu → prázdne + hláška na stderr, návrat 1.
dk_workdir() {
    local m root
    dk_base
    root=${DK_APPROOT%/}
    m=$(dk_main_root)
    if [ "$DK_PROJECT" = "$m" ]; then
        printf '%s\n' "${root:-/}"
        return 0
    fi
    case "$DK_PROJECT" in
        "$m"/*) printf '%s/%s\n' "$root" "${DK_PROJECT#"$m"/}"; return 0 ;;
    esac
    echo "worktree mimo mountu kontajnera" >&2
    return 1
}

# Stav kontajnera z container.state ("<epoch> <running|down> <kontajner>", 30 s); DK_NO_CONTAINER_CACHE
# (check.sh) ho nečíta, len zapíše čerstvý.
dk_container_ok() {
    dk_base
    [ -n "${DK_CONTAINER:-}" ] || return 0
    if [ -z "${DK_CONTAINER_STATE:-}" ]; then
        local cf="$DK_PDATA/container.state" now t="" s="" c=""
        now=$(dk_now)
        if [ -z "${DK_NO_CONTAINER_CACHE:-}" ] && [ -f "$cf" ]; then
            { read -r t s c < "$cf"; } 2>/dev/null
            case "$t" in ''|*[!0-9]*) t=0 ;; esac
            if [ "$c" = "$DK_CONTAINER" ] && [ "$t" -le "$now" ] && [ $((now - t)) -lt 30 ]; then
                case "$s" in running) DK_CONTAINER_STATE=true ;; down) DK_CONTAINER_STATE=none ;; esac
            fi
        fi
        if [ -z "$DK_CONTAINER_STATE" ]; then
            DK_CONTAINER_STATE=$(docker inspect -f '{{.State.Running}}' "$DK_CONTAINER" 2>/dev/null)
            [ -n "$DK_CONTAINER_STATE" ] || DK_CONTAINER_STATE=none
            s=down
            [ "$DK_CONTAINER_STATE" = true ] && s=running
            if [ -d "$DK_PDATA" ]; then
                { printf '%s %s %s\n' "$now" "$s" "$DK_CONTAINER" > "$cf.tmp.$$" && mv "$cf.tmp.$$" "$cf"; } 2>/dev/null \
                    || rm -f "$cf.tmp.$$" 2>/dev/null
            fi
        fi
    fi
    [ "$DK_CONTAINER_STATE" = "true" ]
}

# Efektívny runtime kroku či lintu do DK_RT (SPEC §3): host, container (bez kontajnera = host); iná hodnota → 1.
dk_runtime() {
    dk_base
    case "${1:-}" in
        host) DK_RT=host ;;
        ''|container) if [ -n "${DK_CONTAINER:-}" ]; then DK_RT=container; else DK_RT=host; fi ;;
        *) DK_RT=""; return 1 ;;
    esac
    return 0
}

# Spustí príkaz v kontajneri (docker exec -i -w) alebo na hoste v DK_PROJECT; stderr ide do stdout.
# Druhý parameter host = na hoste aj pri nastavenom kontajneri. Tretí = limit v sekundách (prázdny či 0 = bez
# limitu): po ňom TERM celému stromu procesov, o 2 s KILL, návrat 124 a DK_EXEC_TIMEOUT=1 (SPEC §4.5).
dk_exec() {
    local cmd="$1" lim="${3:-0}" ct="" hl pid w rc t0 mark
    DK_EXEC_TIMEOUT=0
    case "$lim" in ''|*[!0-9]*) lim=0 ;; esac
    dk_base
    [ "$lim" -gt 0 ] || { dk__exec "$cmd" "${2:-}" ""; return; }
    hl=$lim
    # V kontajneri limit drží timeout v ňom; hostiteľ zabije len klienta docker exec, preto až s rezervou.
    if [ "${2:-}" != host ] && [ -n "${DK_CONTAINER:-}" ]; then ct=$lim; hl=$((lim + 5)); fi
    dk_tmpdir
    mark="$DK_TMP/exec-timeout.$$"
    rm -f "$mark"
    [ -z "$ct" ] || t0=$(dk_ms)
    dk__exec "$cmd" "${2:-}" "$ct" &
    pid=$!
    dk__watchdog "$pid" "$hl" "$mark" </dev/null >/dev/null 2>&1 &
    w=$!
    { wait "$pid"; } 2>/dev/null
    rc=$?
    if [ -f "$mark" ]; then
        { wait "$w"; } 2>/dev/null
        DK_EXEC_TIMEOUT=1
    else
        { kill "$w"; wait "$w"; } 2>/dev/null
        [ -z "$ct" ] || [ "$rc" != 124 ] || [ $(( $(dk_ms) - t0 )) -lt $((lim * 1000)) ] || DK_EXEC_TIMEOUT=1
    fi
    rm -f "$mark"
    [ "$DK_EXEC_TIMEOUT" = 0 ] || return 124
    return "$rc"
}

# <príkaz> <host|""> <limit v kontajneri|""> — bez limitu presne ako docker exec … sh -c "<príkaz>".
dk__exec() {
    local cmd="$1" ct="${3:-}" wd
    if [ "${2:-}" != host ] && [ -n "${DK_CONTAINER:-}" ]; then
        wd=${DK_WD:-}
        if [ -z "$wd" ]; then
            wd=$(dk_workdir 2>/dev/null) || return 125
        fi
        set -- sh -c "$cmd"
        # timeout z coreutils či busyboxu, ak ho kontajner má a pozná tvar „timeout N príkaz“; inak bez neho.
        [ -z "$ct" ] || set -- sh -c 'timeout 1 true 2>/dev/null && exec timeout "$0" sh -c "$1"; exec sh -c "$1"' "$ct" "$cmd"
        if [ "$wd" = "/" ] && [ -z "${DK_APPROOT:-}" ]; then
            docker exec -i "$DK_CONTAINER" "$@" </dev/null 2>&1
        else
            docker exec -i -w "$wd" "$DK_CONTAINER" "$@" </dev/null 2>&1
        fi
    else
        (cd "$DK_PROJECT" && sh -c "$cmd") </dev/null 2>&1
    fi
}

# <pid> <sekundy> <značka>: po limite značka, TERM stromu procesov, po 2 s KILL tých, čo prežili.
dk__watchdog() {
    local i=0 t p alive=""
    while [ "$i" -lt "$2" ]; do
        sleep 1
        kill -0 "$1" 2>/dev/null || return 0
        i=$((i + 1))
    done
    : > "$3"
    t=$(dk__ptree "$1")
    # shellcheck disable=SC2086
    kill -TERM $t 2>/dev/null
    i=0
    while [ "$i" -lt 10 ]; do
        sleep 0.2
        alive=""
        for p in $t; do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
        [ -n "$alive" ] || return 0
        i=$((i + 1))
    done
    # shellcheck disable=SC2086
    kill -KILL $alive 2>/dev/null
}

# <pid> a jeho potomkovia (ps -A); bez ps len <pid>.
dk__ptree() {
    local t
    t=$(ps -A -o pid= -o ppid= 2>/dev/null | awk -v r="$1" '
        { c[$2] = c[$2] " " $1 }
        END {
            q = r
            while (q != "") {
                n = split(q, a, " "); q = ""
                for (i = 1; i <= n; i++) if (!s[a[i]]++) { o = o " " a[i]; q = q c[a[i]] }
            }
            print o
        }')
    printf '%s\n' "${t:-$1}"
}

# Glob → ERE (SPEC §3): **/ = 0+ adresárov, ** = čokoľvek, * = bez '/', ? = 1 znak, koncové '/' = prefix.
dk_glob_re() {
    local g="$1" re="" c i=0 n=${#1}
    while [ "$i" -lt "$n" ]; do
        c=${g:$i:1}
        if [ "$c" = "*" ]; then
            if [ "${g:$i:3}" = "**/" ]; then re="$re(.*/)?"; i=$((i + 3)); continue; fi
            if [ "${g:$i:2}" = "**" ]; then re="$re.*"; i=$((i + 2)); continue; fi
            re="$re[^/]*"
        elif [ "$c" = "?" ]; then
            re="$re[^/]"
        else
            case "$c" in
                '.'|'+'|'('|')'|'|'|'^'|'$'|'{'|'}'|'['|']'|'\') re="$re\\$c" ;;
                *) re="$re$c" ;;
            esac
        fi
        i=$((i + 1))
    done
    case "$g" in
        */) printf '^%s' "$re" ;;
        *) printf '^%s$' "$re" ;;
    esac
}

dk_glob_match() {
    local re
    re=$(dk_glob_re "$2")
    [[ $1 =~ $re ]]
}

# Zoznam globov (riadky) → jeden ERE; prázdny zoznam → prázdny reťazec.
dk_globs_re() {
    local g out=""
    while IFS= read -r g; do
        [ -n "$g" ] || continue
        out="$out${out:+|}($(dk_glob_re "$g"))"
    done <<EOF
$1
EOF
    printf '%s' "$out"
}

dk_re_match() { [ -n "$2" ] && [[ $1 =~ $2 ]]; }

# Prvý glob zo zoznamu, ktorý sedí na cestu.
dk_first_glob() {
    local g
    while IFS= read -r g; do
        [ -n "$g" ] || continue
        if dk_glob_match "$1" "$g"; then printf '%s' "$g"; return 0; fi
    done <<EOF
$2
EOF
    return 1
}

# Pridané riadky voči HEAD: '*' = celý súbor (nesledovaný / nový / bez HEAD), inak čísla po riadkoch.
# Cestu, ktorú repo nepozná (súbor v submodule či vnorenom repe), zopakuje v koreni toho repa.
dk__added_spec() {
    local g="$DK_PROJECT" rel="$1" d top
    while :; do
        if d=$(git -C "$g" -c core.quotepath=off diff -U0 --no-color --no-ext-diff --no-textconv HEAD -- "$rel" 2>/dev/null); then
            [ -n "$d" ] && break
            git -C "$g" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 && return 0
        fi
        top=$(git -C "$g/$(dirname "$rel")" rev-parse --show-toplevel 2>/dev/null)
        case "$top" in
            "$g"/?*) rel=${g}/$rel; rel=${rel#"$top"/}; g=$top ;;
            *) echo '*'; return 0 ;;
        esac
    done
    printf '%s\n' "$d" | awk '/^@@ / { s = $3; sub(/^\+/, "", s); n = split(s, a, ","); st = a[1] + 0; c = (n > 1) ? a[2] + 0 : 1; for (i = 0; i < c; i++) print st + i }'
}

dk_added_lines() {
    local spec
    spec=$(dk__added_spec "$1")
    if [ "$spec" = "*" ]; then
        [ -f "$DK_PROJECT/$1" ] && awk '{ print NR }' "$DK_PROJECT/$1"
        return 0
    fi
    [ -n "$spec" ] && printf '%s\n' "$spec"
    return 0
}

# "rel<TAB>blob" zoradené podľa cesty; chýbajúci alebo nečitateľný súbor = "-". Symlink s príponou kódu
# vypadne: git z neho commitne cieľ odkazu, nie obsah, ktorý by sa tu hashoval.
dk_blobs() {
    local f all ex mi bl b
    # Výpis namiesto skladania reťazca v cykle (tisíce súborov).
    all=$(for f in "$@"; do
        [ -n "$f" ] || continue
        if [ -L "$DK_PROJECT/$f" ] && dk_is_code "$f"; then continue; fi
        if [ -f "$DK_PROJECT/$f" ]; then printf 'E%s\n' "$f"; else printf 'M%s\n' "$f"; fi
    done)
    ex=$(printf '%s\n' "$all" | LC_ALL=C sed -n 's/^E//p')
    mi=$(printf '%s\n' "$all" | LC_ALL=C sed -n 's/^M//p')
    bl=""
    # Jeden nečitateľný súbor zhodí celú dávku → po jednom.
    if [ -n "$ex" ] && ! bl=$(printf '%s\n' "$ex" | git -C "$DK_PROJECT" hash-object --stdin-paths 2>/dev/null); then
        bl=$(printf '%s\n' "$ex" | while IFS= read -r f; do
            b=$(git -C "$DK_PROJECT" hash-object -- "$f" 2>/dev/null)
            [ -n "$b" ] || { dk_err "nečitateľný súbor $f (git hash-object)"; b=-; }
            printf '%s\n' "$b"
        done)
    fi
    {
        [ -z "$bl" ] || { printf '%s\n\037\n%s\n' "$ex" "$bl" |
            LC_ALL=C awk 's { print n[++j] "\t" $0; next } $0 == "\037" { s = 1; next } { n[++i] = $0 }'; }
        [ -z "$mi" ] || printf '%s\n' "$mi" | LC_ALL=C awk '{ print $0 "\t-" }'
    } | sort -u
}

dk_hash_files() {
    dk_blobs "$@" | git hash-object --stdin 2>/dev/null
}

# Zmenené súbory voči HEAD + staged + nesledované (aj zmazané; volajúci ich rozlíši).
# Položky s koncovým '/' sú vnorené repozitáre a worktree (nedajú sa hashovať).
dk_changed_files() {
    {
        dk_git diff --name-only --no-renames HEAD 2>/dev/null
        dk_git diff --name-only --no-renames --cached 2>/dev/null
        dk_git ls-files --others --exclude-standard 2>/dev/null
    } | grep -v '/$' | sort -u
}

dk_session_file() { printf '%s/sessions/%s.files' "$DK_PDATA" "$DK_SESSION"; }
dk_stop_file() { printf '%s/sessions/%s.stop.json' "$DK_PDATA" "$DK_SESSION"; }
dk_t0_file() { printf '%s/sessions/%s.t0' "$DK_PDATA" "$DK_SESSION"; }

# Prvý zápis session uloží aj HEAD (.head): Stop podľa neho vidí súbory commitnuté počas session.
dk_session_add() {
    local sf
    sf=$(dk_session_file)
    mkdir -p "$DK_PDATA/sessions" 2>/dev/null
    if [ -f "$sf" ]; then
        grep -Fxq -- "$1" "$sf" 2>/dev/null && return 0
    else
        dk_git rev-parse -q --verify HEAD 2>/dev/null > "${sf%.files}.head"
    fi
    printf '%s\n' "$1" 2>/dev/null >> "$sf"
}

# Súbory zmenené commitmi od začiatku session (.head → HEAD); bez .head alebo bez posunu HEAD nič.
dk_session_committed() {
    local hf h cur
    hf="$(dk_session_file)"
    hf="${hf%.files}.head"
    [ -s "$hf" ] || return 0
    IFS= read -r h < "$hf"
    case "$h" in ''|*[!0-9a-f]*) return 0 ;; esac
    cur=$(dk_git rev-parse -q --verify HEAD 2>/dev/null)
    [ -n "$cur" ] && [ "$cur" != "$h" ] || return 0
    dk_git diff --name-only --no-renames "$h" "$cur" -- 2>/dev/null
    return 0
}

# Kódové súbory pre Stop zmenené mimo on-edit (Bash, editor): dk_changed_files novšie ako .t0 (začiatok session).
dk_session_newer() {
    local t0 f
    t0=$(dk_t0_file)
    [ -f "$t0" ] || return 0
    dk_changed_files | while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$DK_PROJECT/$f" ] && dk_is_code "$f" stop && printf './%s\n' "$f"
    done | tr '\n' '\000' | (cd "$DK_PROJECT" 2>/dev/null &&
        xargs -0 sh -c '[ $# -gt 0 ] || exit 0; find "$@" -prune -newer "$0" -print' "$t0" 2>/dev/null) | sed 's|^\./||'
    return 0
}

# Existujúce súbory session s príponou kódu pre Stop (dk_is_code … stop) ∪ dk_session_newer.
dk_session_code_files() {
    local sf f
    sf=$(dk_session_file)
    {
        if [ -f "$sf" ]; then
            while IFS= read -r f; do
                [ -n "$f" ] && [ -f "$DK_PROJECT/$f" ] && dk_is_code "$f" stop && printf '%s\n' "$f"
            done < "$sf"
        fi
        dk_session_newer
    } | awk '!s[$0]++'
    return 0
}

# Ponechá riadky výstupu nástroja, ktoré patria k pridaným riadkom. map: "rel<TAB>N" alebo "rel<TAB>*".
# Vždy ostanú chyby parsera/kompilácie (php -l, latte, yaml/twig lint) a pády nástroja — hlásený riadok
# býva za príčinou. Očíslovaný riadok inej cesty než cieľa vypadne; riadok bez čísla ostane len vtedy,
# keď vo výstupe nie je žiadny očíslovaný ani vždy ponechaný riadok.
dk_filter_changed() { # <outfile> <mapfile>
    awk -F'\t' '
    FILENAME == ARGV[1] {
        if ($2 == "*") all[$1] = 1; else add[$1 SUBSEP $2] = 1
        if (!($1 in rels)) { rels[$1] = 1; nrel++; last = $1 }
        next
    }
    {
        line = $0; num = ""; path = ""
        if (line ~ /[Pp]arse error|[Ss]yntax error|SyntaxError|IndentationError|\[ERROR\]|ERROR[ \t]+in[ \t]|^[ \t]*>>[ \t]|Unable to parse|Fatal error|Uncaught |Segmentation fault|Allowed memory size/) {
            numbered = 1; print line; next
        }
        if (match(line, /[^ \t:]+:[0-9]+([: \t]|$)/)) {
            tok = substr(line, RSTART, RLENGTH); sub(/[: \t]$/, "", tok)
            k = tok; sub(/:[0-9]+$/, "", k); path = k; num = substr(tok, length(k) + 2)
        } else if (match(line, /on line [0-9]+/)) {
            num = substr(line, RSTART + 8, RLENGTH - 8)
            if (match(line, / in [^ \t]+ on line /)) path = substr(line, RSTART + 4, RLENGTH - 13)
        }
        if (num == "") { if (line != "") nonum[++nn] = line; next }
        numbered = 1
        r = ""
        if (path == "" && nrel == 1) r = last
        else for (x in rels) {
            if (path == x || (length(path) > length(x) && substr(path, length(path) - length(x)) == "/" x)) { r = x; break }
        }
        if (r == "") next
        if ((r in all) || ((r SUBSEP num) in add)) print line
    }
    END { if (!numbered) for (i = 1; i <= nn; i++) print nonum[i] }
    ' "$2" "$1"
}

# Odstráni prefixy ciest (kontajner, projekt), aby nálezy boli relatívne.
dk_strip_paths() {
    local a=""
    case "${DK_WD:-}" in ''|/) ;; *) a="${DK_WD%/}/" ;; esac
    DK_AWK_A="$a" DK_AWK_B="$DK_PROJECT/" awk 'BEGIN { a = ENVIRON["DK_AWK_A"]; b = ENVIRON["DK_AWK_B"] } {
        if (a != "") while ((i = index($0, a)) > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(a))
        while ((i = index($0, b)) > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(b))
        if (length($0) > 220) $0 = substr($0, 1, 217) "..."
        print
    }'
}

# Guardy nad pridanými riadkami súboru. guards: riadky "G<US>id<US>ext-csv<US>pattern<US>message".
# Výstup: "guard:<id><US><rel>:<riadok> — <message> [guard:<id>]", najviac 20 na guard; zvyšok ako "more<US><počet>".
dk_guard_scan() {
    local rel="$1" added="$2" guards="$3" f ext tag id exts pat msg gi csv n hits lines k
    f="$DK_PROJECT/$rel"
    [ -f "$f" ] || return 0
    [ -n "$added" ] || return 0
    ext=$(dk_ext "$rel")
    if [ "$added" = "*" ]; then csv="*"; else csv=",${added//$DK_NL/,},"; fi
    while IFS=$DK_US read -r tag id exts pat msg; do
        [ "$tag" = G ] || continue
        [ -n "$pat" ] || continue
        if [ -n "$exts" ]; then
            case ",$exts," in *",$ext,"*) ;; *) continue ;; esac
        fi
        dk_rule_on "guard:$id" || continue
        gi=""
        case "$pat" in '(?i)'*) pat=${pat#'(?i)'}; gi=-i ;; esac
        hits=$(grep -nIE $gi -e "$pat" "$f" 2>/dev/null)
        [ $? -gt 1 ] && dk_err "guard:$id: neplatný vzor (grep -E): $pat"
        [ -n "$hits" ] || continue
        lines=$(printf '%s\n' "$hits" | awk -F: -v a="$csv" '(a == "*") || index(a, "," $1 ",") { print $1 }')
        [ -n "$lines" ] || continue
        for n in $(printf '%s\n' "$lines" | head -n 20); do
            printf 'guard:%s%s%s:%s — %s [guard:%s]\n' "$id" "$DK_US" "$rel" "$n" "$msg" "$id"
        done
        k=$(printf '%s\n' "$lines" | grep -c .)
        [ "$k" -gt 20 ] && printf 'more%s%s\n' "$DK_US" $((k - 20))
    done <<EOF
$guards
EOF
    return 0
}

# Maskovaná hodnota tajomstva; návrat 1, keď je to zástupný text (nie tajomstvo).
dk_mask() { # žiadny znak hodnoty — hláška ide do kontextu modelu aj transkriptu
    local m="$1" v
    v=${m##*[=:]}
    v=$(printf '%s' "$v" | sed -E "s/^[[:space:]>\"']+//; s/[\"'[:space:];,)]+\$//")
    [ -n "$v" ] || v=$m
    if printf '%s' "$v" | grep -Eq -e "$DK_SECRET_PLACEHOLDER"; then return 1; fi
    printf '****'
}

# Tajomstvá v pridaných riadkoch súboru (on-edit). pats: vzory po riadkoch (lib defaults ∪ config).
# Výstup: "<riadok><US><maskovaná hodnota>", jeden nález na riadok.
dk_secret_scan() { # <rel> <added-spec> <pats>
    local f="$DK_PROJECT/$1" added="$2" p gi hits k m mv csv seen="$DK_NL"
    [ -f "$f" ] && [ -n "$added" ] || return 0
    if [ "$added" = "*" ]; then csv="*"; else csv=",${added//$DK_NL/,},"; fi
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        gi=""
        case "$p" in '(?i)'*) p=${p#'(?i)'}; gi=-i ;; esac
        hits=$(grep -nIE $gi -e "$p" "$f" 2>/dev/null)
        [ $? -gt 1 ] && dk_err "secrets: neplatný vzor (grep -E): $p"
        [ -n "$hits" ] || continue
        for k in $(printf '%s\n' "$hits" | awk -F: -v a="$csv" '(a == "*") || index(a, "," $1 ",") { print $1 }' | head -n 50); do
            case "$seen" in *"$DK_NL$k$DK_NL"*) continue ;; esac
            m=$(sed -n "${k}p" "$f" | grep -oE $gi -e "$p" | head -n 1)
            mv=$(dk_mask "$m") || continue
            seen="$seen$k$DK_NL"
            printf '%s%s%s\n' "$k" "$DK_US" "$mv"
        done
    done <<EOF
$3
EOF
    return 0
}

dk_fmt_s() { # ms → "2,1"
    local ms=${1:-0}
    case "$ms" in ''|*[!0-9]*) ms=0 ;; esac
    printf '%d,%d' $((ms / 1000)) $(((ms % 1000) / 100))
}

dk_fmt_time() { # epoch → HH:MM (lokálny čas)
    jq -nr --argjson t "${1:-0}" '$t | strflocaltime("%H:%M")' 2>/dev/null || printf '?'
}

# Zámok testu: platný → riadky súborov v DK_LOCK_FILES, koniec v DK_LOCK_UNTIL; návrat 0 keď je aktívny.
dk_lock_read() {
    local lf="$DK_PDATA/test-lock.json" out tag a ttl t
    DK_LOCK_FILES="" DK_LOCK_UNTIL="" DK_LOCK_EXPIRED=""
    [ -f "$lf" ] || return 1
    out=$(jq -r --arg dttl "${1:-6}" '"T\u001f\(.time // 0)", "H\u001f\(.ttlHours // ($dttl|tonumber))", ((.files // [])[] | "F\u001f\(.)")' "$lf" 2>/dev/null) || return 1
    t=0; ttl=6
    while IFS=$DK_US read -r tag a; do
        case "$tag" in
            T) t=${a%%.*} ;;
            H) ttl=${a%%.*} ;;
            F) DK_LOCK_FILES="$DK_LOCK_FILES$a$DK_NL" ;;
        esac
    done <<EOF
$out
EOF
    case "$t" in ''|*[!0-9]*) t=0 ;; esac
    case "$ttl" in ''|*[!0-9]*) ttl=6 ;; esac
    DK_LOCK_UNTIL=$((t + ttl * 3600))
    if [ "$(dk_now)" -ge "$DK_LOCK_UNTIL" ]; then DK_LOCK_EXPIRED=1; return 1; fi
    [ -n "$DK_LOCK_FILES" ]
}
