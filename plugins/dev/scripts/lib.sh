#!/usr/bin/env bash
# dev-kit: spoločné funkcie hookov a skriptov. Kontrakt: docs/SPEC.md §2–§4.
# Musí bežať na macOS /bin/bash 3.2 aj na bash 5 (bez asociatívnych polí, mapfile, ${x,,}, sed -i…).

DK_US=$'\x1f'
DK_NL=$'\n'
DK_TAB=$'\t'
DK_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)

# jq: s = bezpečný jednoriadkový reťazec; base = spoločné kľúče devkit.json (tagované riadky).
DK_JQ_DEFS='def s: if . == null then "" elif type == "string" then gsub("[\n\r\u001f]"; " ") else tojson end;
def base: "C\u001f\(.container|s)", "A\u001f\(.appRoot|s)", "K\u001f\(.stack|s)",
  ((.disabledRules // []) | .[] | "D\u001f\(.|s)"),
  "X\u001f\([(.lint // {} | keys[]), ((.check.steps // [])[] | (.ext // [])[])] | unique | join(","))";'

# Začiatok príkazu (oddeľovač, obal, env priradenia) + git s globálnymi prepínačmi (SPEC §4.4).
# Obsahujú '/', sed s nimi používa oddeľovač \001.
DK_RE_GITPFX='(^|[;&|({!]|&&|\|\||(^|[[:space:]])(then|do|else|time|nice|nohup|command|builtin|exec|env))[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]"'"'"';&|])*[[:space:]]+)*\\?([^[:space:];&|()"'"'"']*/)?git([[:space:]]+(-C[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|]+)|-c[[:space:]]+[^[:space:];&|]+|-[pP]|--no-pager|--paginate|--no-replace-objects|--literal-pathspecs|--bare|--(git-dir|work-tree|namespace)(=|[[:space:]]+)("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|]+)))*'
DK_RE_COMMIT="$DK_RE_GITPFX[[:space:]]+commit([[:space:]]|\$)"
DK_RE_ADD="$DK_RE_GITPFX[[:space:]]+(add|stage)([[:space:]]|\$)"

# Najstaršia podporovaná verzia Claude Code (úvodná karta upozorní na staršiu).
DK_MIN_CC=2.1.308

# Predvolené vzory tajomstiev (POSIX ERE, (?i) = bez ohľadu na veľkosť písmen).
DK_SECRET_DEFAULTS='(?i)(password|passwd|heslo|secret|api[_-]?key|token)["'"'"']?[[:space:]]*(=>|[:=])[[:space:]]*["'"'"'][^"'"'"'[:space:]]{6,}
-----BEGIN [A-Z ]*PRIVATE KEY-----
AKIA[0-9A-Z]{16}
[A-Z0-9_]*TEST_PASS(WORD)?=[^[:space:]]+'
# Hodnoty, ktoré nie sú tajomstvo (odkaz na premennú, zástupný text).
# Ukotvené na celú hodnotu; {{ a < ostávajú prefixom, lebo grep -o hodnotu oreže na prvej medzere.
DK_SECRET_PLACEHOLDER='^(%env\([^)]*\)%|%[A-Za-z0-9_.]+%|\$\{[^}]*\}?|\$[A-Za-z_][A-Za-z0-9_]*(->[A-Za-z_][A-Za-z0-9_]*)*|\{\{.*|<.*|\*+|[xX]+|\.\.\.)$'

# Zlyhanie nástroja samotného (nie nález v kóde) — taký výstup kontrolu preskočí, neblokuje.
DK_RE_INFRA='Could not open input file|command not found|No such file or directory|Error response from daemon|OCI runtime|is not running|Cannot connect to the Docker daemon|executable file not found|No files were checked'

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

# Dátový adresár len pre používateľa (700). Globálny umask sa nemení — dk_exec spúšťa príkazy na hoste.
dk_data_dir() {
    local d="${DK_DATA:-${DEVKIT_DATA:-$HOME/.claude/dev-kit}}"
    if [ ! -d "$d" ]; then
        mkdir -p "$d" 2>/dev/null && chmod 700 "$d" 2>/dev/null
    elif [ -z "${DK_DATA_OK:-}" ] && [ -O "$d" ]; then
        chmod 700 "$d" 2>/dev/null
    fi
    DK_DATA_OK=1
    return 0
}

dk_err() {
    dk_data_dir
    printf '%s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${DK_HOOK:-?}" "$*" \
        2>/dev/null >> "${DK_DATA:-${DEVKIT_DATA:-$HOME/.claude/dev-kit}}/errors.log"
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
    if [ -n "$DK_CFG" ] && [ ! -d "$DK_PDATA/sessions" ]; then
        mkdir -p "$DK_PDATA/sessions" "$DK_PDATA/logs" 2>/dev/null
    fi
    DK_DISABLED_LOADED=""
    DK_CONTAINER_STATE=""
    DK_BASE_LOADED="" DK_CONTAINER="" DK_APPROOT="" DK_STACK="" DK_CODE_EXTS=""
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
        line=$(printf '%s' "$DK_INPUT" | jq -r '[.session_id, .cwd, .tool_input.file_path, .hook_event_name, .tool_name, .stop_hook_active, .source, .agent_type]
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
    DK_CONTAINER="" DK_APPROOT="" DK_STACK="" DK_DISABLED="" DK_CODE_EXTS=""
    DK_DISABLED_LOADED=1 DK_BASE_LOADED=1
    while IFS=$DK_US read -r tag a; do
        case "$tag" in
            C) DK_CONTAINER=$a ;;
            A) DK_APPROOT=$a ;;
            K) DK_STACK=$a ;;
            D) DK_DISABLED="$DK_DISABLED$a$DK_NL" ;;
            X) DK_CODE_EXTS=$a ;;
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

dk_is_code() { # <rel> — prípona je v lint kľúčoch alebo v ext niektorého kroku
    local e
    e=$(dk_ext "$1")
    [ -n "$e" ] || return 1
    dk_base
    case ",$DK_CODE_EXTS," in *",$e,"*) return 0 ;; esac
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

dk_container_ok() {
    dk_base
    [ -n "${DK_CONTAINER:-}" ] || return 0
    if [ -z "${DK_CONTAINER_STATE:-}" ]; then
        DK_CONTAINER_STATE=$(docker inspect -f '{{.State.Running}}' "$DK_CONTAINER" 2>/dev/null)
        [ -n "$DK_CONTAINER_STATE" ] || DK_CONTAINER_STATE=none
    fi
    [ "$DK_CONTAINER_STATE" = "true" ]
}

# Spustí príkaz v kontajneri (docker exec -i -w) alebo na hoste v DK_PROJECT; stderr ide do stdout.
dk_exec() {
    local cmd="$1" wd
    dk_base
    if [ -n "${DK_CONTAINER:-}" ]; then
        wd=${DK_WD:-}
        if [ -z "$wd" ]; then
            wd=$(dk_workdir 2>/dev/null) || return 125
        fi
        if [ "$wd" = "/" ] && [ -z "${DK_APPROOT:-}" ]; then
            docker exec -i "$DK_CONTAINER" sh -c "$cmd" </dev/null 2>&1
        else
            docker exec -i -w "$wd" "$DK_CONTAINER" sh -c "$cmd" </dev/null 2>&1
        fi
    else
        (cd "$DK_PROJECT" && sh -c "$cmd") </dev/null 2>&1
    fi
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
dk__added_spec() {
    local rel="$1" d
    d=$(dk_git diff -U0 --no-color --no-ext-diff --no-textconv HEAD -- "$rel" 2>/dev/null) || { echo '*'; return 0; }
    if [ -z "$d" ]; then
        dk_git ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || echo '*'
        return 0
    fi
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

# "rel<TAB>blob" zoradené podľa cesty; chýbajúci súbor = "-".
dk_blobs() {
    local f ex="" mi="" bl="" b
    for f in "$@"; do
        [ -n "$f" ] || continue
        if [ -f "$DK_PROJECT/$f" ]; then ex="$ex$f$DK_NL"; else mi="$mi$f$DK_NL"; fi
    done
    [ -n "$ex" ] && bl=$(printf '%s' "$ex" | git -C "$DK_PROJECT" hash-object --stdin-paths 2>/dev/null)
    {
        if [ -n "$bl" ]; then
            while IFS= read -r f <&3 && IFS= read -r b <&4; do
                printf '%s\t%s\n' "$f" "$b"
            done 3<<EOF3 4<<EOF4
$ex
EOF3
$bl
EOF4
        fi
        [ -n "$mi" ] && printf '%s' "$mi" | awk '{ print $0 "\t-" }'
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

dk_session_add() {
    local sf
    sf=$(dk_session_file)
    mkdir -p "$DK_PDATA/sessions" 2>/dev/null
    [ -f "$sf" ] && grep -Fxq -- "$1" "$sf" 2>/dev/null && return 0
    printf '%s\n' "$1" 2>/dev/null >> "$sf"
}

# Existujúce súbory session s príponou kódu.
dk_session_code_files() {
    local sf f
    sf=$(dk_session_file)
    [ -f "$sf" ] || return 0
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$DK_PROJECT/$f" ] && dk_is_code "$f" && printf '%s\n' "$f"
    done < "$sf"
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
    awk -v a="$a" -v b="$DK_PROJECT/" '{
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
dk_mask() {
    local m="$1" v len
    v=${m##*[=:]}
    v=$(printf '%s' "$v" | sed -E "s/^[[:space:]>\"']+//; s/[\"'[:space:];,)]+\$//")
    [ -n "$v" ] || v=$m
    if printf '%s' "$v" | grep -Eq -e "$DK_SECRET_PLACEHOLDER"; then return 1; fi
    len=${#v}
    if [ "$len" -ge 8 ]; then
        printf '%s****%s' "${v:0:2}" "${v:$((len - 2))}"
    else
        printf '****'
    fi
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
