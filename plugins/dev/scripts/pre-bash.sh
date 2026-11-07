#!/usr/bin/env bash
# PreToolUse (Bash): pri `git commit` (aj `rebase|merge|cherry-pick|revert|am --continue`) tajomstvá v pridaných riadkoch
# + commit gate (PASS z check.sh pre presne tento obsah).
# Repo commitu (báza, kandidáti) dáva parser cmd-parse.sh (SPEC §4.4.1); kontroly bežia v každom dotknutom repe
# s configom. Obmedzenia (`sh -c`, aliasy): SPEC §4.4 Known limitations.
. "$(dirname "$0")/lib.sh" || exit 0
. "$(dirname "$0")/cmd-parse.sh" || exit 0
DK_HOOK=pre-bash

dk_deny() {
    jq -nc --arg r "$1" --arg s "${DK_CFG_NOTE:-}" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}
         + (if $s == "" then {} else {systemMessage: $s} end)'
    DK_CFG_NOTE=""
}

dk_strip_quotes() {
    local s="$1"
    case "$s" in
        \"*\") s=${s#\"}; s=${s%\"} ;;
        \'*\') s=${s#\'}; s=${s%\'} ;;
    esac
    # shellcheck disable=SC2088
    case "$s" in "~"|"~/"*) s="${DK_HOME:-$HOME}${s#\~}" ;; esac
    printf '%s' "$s"
}

dk_abs() { # <dir> <relative-to>
    case "$1" in
        /*) printf '%s' "$1" ;;
        *) printf '%s/%s' "$2" "$1" ;;
    esac
}

# V DK_X nahradí doslovný <token> hodnotou; s <boundary> 1 nie pred písmenom/číslicou/_ ($HOMEX ostane).
dk__repl() { # <token> <value> <boundary>
    local t="$1" v="$2" s=$DK_X out="" post
    while :; do
        case "$s" in
            *"$t"*)
                out="$out${s%%"$t"*}"
                post=${s#*"$t"}
                case "$3:${post:0:1}" in
                    1:[A-Za-z0-9_]) out="$out$t" ;;
                    *) out="$out$v" ;;
                esac
                s=$post
                ;;
            *) break ;;
        esac
    done
    DK_X="$out$s"
}

# Cieľ cd / -C / --work-tree / --git-dir → absolútna cesta (~, $HOME, $PWD a $(pwd) = base, $CLAUDE_PROJECT_DIR,
# úvodné priradenia príkazu z DK_VARS; DK_HOME = úvodné HOME=, DK_HOME_UNKNOWN = HOME v príkaze nie je známe).
# Návrat 1 = neznámy cieľ ($(…), iná premenná, ~iný, `cd -`, prepínač bez adresára).
dk_expand_dir() { # <raw> <base>
    local raw="$1" base="$2" home="${DK_HOME:-$HOME}" n v
    # shellcheck disable=SC2088
    case "$raw" in '~'|'~/'*) [ -z "${DK_HOME_UNKNOWN:-}" ] || return 1 ;; '~'*) return 1 ;; esac
    case "$raw" in
        \'*\') DK_X=$(dk_strip_quotes "$raw") ;;
        *)
            DK_X=$(dk_strip_quotes "$raw")
            DK_X=${DK_X//\"/}
            if [ -n "${DK_HOME_UNKNOWN:-}" ]; then case "$DK_X" in *'$HOME'*) return 1 ;; esac; fi
            dk__repl '${HOME}' "$home" 0
            dk__repl '$HOME' "$home" 1
            dk__repl '${PWD}' "$base" 0
            dk__repl '$PWD' "$base" 1
            dk__repl '$(pwd)' "$base" 0
            dk__repl '`pwd`' "$base" 0
            if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
                dk__repl '${CLAUDE_PROJECT_DIR}' "$CLAUDE_PROJECT_DIR" 0
                dk__repl '$CLAUDE_PROJECT_DIR' "$CLAUDE_PROJECT_DIR" 1
            fi
            while IFS="$DK_US" read -r n v; do
                [ -n "$n" ] || continue
                dk__repl "\${$n}" "$v" 0
                dk__repl "\$$n" "$v" 1
            done <<EOF
${DK_VARS:-}
EOF
            case "$DK_X" in *'$'*|*'`'*) return 1 ;; esac
            ;;
    esac
    case "$DK_X" in ''|-*) return 1 ;; esac
    dk_abs "$DK_X" "$base"
}

# Cieľ cd / pushd z operandov (SPEC §4.4.1): DK_T = slovo cieľa (bez operandu `~` alebo prefix HOME=), návrat 1 =
# neznámy (popd, prepínač mimo -L/-P, operand za `--` s `-`, 2+ operandy, CDPATH=). DK_TC = všetky operandy.
dk__cdtarget() { # <cmd> <home-prefix> <cdpath> <op>…
    local cmd="$1" hp="$2" cdp="$3" w x dd=0 n=0
    shift 3
    DK_T="" DK_TC=""
    for w in "$@"; do DK_TC="$DK_TC$w$DK_US"; done
    [ "$cmd" != popd ] && [ "$cdp" = 0 ] || return 1
    for w in "$@"; do
        x=$(dk_strip_quotes "$w")
        if [ "$dd" = 0 ]; then
            case "$x" in
                --) dd=1; continue ;;
                -?*) case "${x#-}" in *[!LP]*) ;; *) continue ;; esac ;;
            esac
        fi
        n=$((n + 1))
        [ "$n" = 1 ] && DK_T=$w
        case "$x" in -*|+[0-9]*) return 1 ;; esac
    done
    case "$n" in
        0) [ "$cmd" = cd ] || return 1; DK_T=${hp:-'~'} ;;
        1) ;;
        *) return 1 ;;
    esac
    return 0
}

# Kandidáti z hodnôt neznámych premenných (riadky K parsera v DK_KANDS) pre slová cieľa; HOME aj hodnota hooku.
dk__varkands() { # <base> <slovo>… → adresáre oddelené \x1f
    local b="$1" w n v r out=""
    shift
    for w in "$@"; do
        [ -n "$w" ] || continue
        while IFS="$DK_US" read -r n v; do
            [ -n "$n" ] || continue
            if [ "$n" = HOME ]; then
                case "$w" in '~'*|*'$HOME'*|*'${HOME}'*) ;; *) continue ;; esac
                r=$(DK_HOME_UNKNOWN="" dk_expand_dir "$v" "$b") || continue
                r=$(DK_HOME="$r" DK_HOME_UNKNOWN="" dk_expand_dir "$w" "$b") || continue
            else
                case "$w" in *"\$$n"*|*"\${$n}"*) ;; *) continue ;; esac
                r=$(dk_expand_dir "$v" "$b") || continue
                r=$(DK_VARS="${DK_VARS:-}$n$DK_US$r$DK_NL" dk_expand_dir "$w" "$b") || continue
            fi
            [ -d "$r" ] && out="$out$r$DK_US"
        done <<EOF
${DK_KANDS:-}
EOF
        if [ -n "${DK_HOME_UNKNOWN:-}" ]; then
            case "$w" in '~'*|*'$HOME'*|*'${HOME}'*)
                r=$(DK_HOME="$HOME" DK_HOME_UNKNOWN="" dk_expand_dir "$w" "$b") && [ -d "$r" ] && out="$out$r$DK_US" ;;
            esac
        fi
    done
    printf '%s' "$out"
}

# Položka záznamu (U = neznámy cieľ, N = nie je isté, či cd prebehne) s kandidátmi; relatívne isté cd ich posúva.
dk__item() { DK_RITEMS="$DK_RITEMS$1$DK_US$2$DK_US$3$DK_NL"; } # <U|N> <úryvok> <kandidáti \x1f…>
dk__items_rel() { # <relatívny cieľ>
    local kind snip kl k v out="" nk
    while IFS="$DK_US" read -r kind snip kl; do
        [ -n "$kind" ] || continue
        nk=""
        while IFS= read -r k; do
            [ -n "$k" ] || continue
            if v=$(dk_expand_dir "$1" "$k") && [ -d "$v" ]; then k=$v; fi
            nk="$nk$k$DK_US"
        done <<EOF
$(printf '%s' "$kl" | tr "$DK_US" '\n')
EOF
        out="$out$kind$DK_US$snip$DK_US$nk$DK_NL"
    done <<EOF
$DK_RITEMS
EOF
    DK_RITEMS=$out
}

# Jedno cd/pushd/popd/chdir pred commitom (riadok D parsera): isté a známe mení base; inak položka U/N.
dk__cdstep() { # <C|N> <cmd> <úryvok> <home> <cdpath> <op>…
    local class="$1" cmdn="$2" snip="$3" home="$4" cdp="$5" res indep=0 kl="" w v
    shift 5
    if dk__cdtarget "$cmdn" "$home" "$cdp" "$@" && res=$(dk_expand_dir "$DK_T" "$base"); then
        case "$(dk_expand_dir "$DK_T" "$DK_US")" in "$DK_US"*) ;; *) indep=1 ;; esac
        if [ "$class" = C ]; then
            [ -d "$res" ] || return 0
            base=$res
            if [ "$indep" = 1 ]; then DK_RITEMS=""; else dk__items_rel "$DK_T"; fi
        elif [ -d "$res" ]; then
            dk__item N "$snip" "$res$DK_US"
        fi
        return 0
    fi
    while IFS= read -r w; do
        [ -n "$w" ] || continue
        v=$(dk_expand_dir "$w" "$base") && [ -d "$v" ] && kl="$kl$v$DK_US"
    done <<EOF
$(printf '%s' "$DK_TC" | tr "$DK_US" '\n')
EOF
    # shellcheck disable=SC2046
    kl="$kl$(set -f; IFS=$DK_US; dk__varkands "$base" "$DK_T" $DK_TC)"
    dk__item U "$snip" "$base$DK_US$kl"
    [ "$class" != C ] || base=$fb
}

# Cieľ -C / --work-tree / --git-dir commitu: neznámy = položka U s kandidátom doterajšej bázy, base = cwd session.
dk__gtarget() { # <raw> <úryvok> [git-dir]
    local v
    if ! v=$(dk_expand_dir "$1" "$base"); then
        dk__item U "$2" "$base$DK_US"
        base=$fb
        return 0
    fi
    [ -z "${3:-}" ] || case "$v" in */.git) v=${v%/.git} ;; esac
    [ ! -d "$v" ] || base=$v
}

# Riadok V parsera (úvodné priradenie): hodnota rozvinutá známymi expanziami; relatívna ostáva relatívna.
dk__var() { # NAME\x1fvalue\x1f[E]
    local n v e res
    IFS="$DK_US" read -r n v e <<EOF
$1
EOF
    res=$(dk_expand_dir "$v" "$DK_US") || return 0
    case "$res" in "$DK_US"/*) res=${res#"$DK_US"/} ;; esac
    DK_VARS="$DK_VARS$n$DK_US$res$DK_NL"
    [ "$e" != E ] || DK_VARS_E="$DK_VARS_E$n$DK_US$res$DK_NL"
    [ "$n" != HOME ] || DK_HOME=$(dk_abs "$res" "$fb")
}
dk__kand() { # NAME\x1fvalue
    DK_KANDS="$DK_KANDS$1$DK_NL"
    case "$1" in HOME"$DK_US"*) DK_HOME_UNKNOWN=1 ;; esac
}
dk__snip() { DK_SNIPS="$DK_SNIPS$1$DK_US$2$DK_NL"; } # <U|N|R> <text>
# Úryvky druhu: najviac 3, každý do 60 znakov, spojené „; “.
dk__snips() { # <U|N|R>
    local k t out="" n=0 seen="$DK_NL"
    while IFS="$DK_US" read -r k t; do
        [ "$k" = "$1" ] && [ -n "$t" ] || continue
        case "$seen" in *"$DK_NL$t$DK_NL"*) continue ;; esac
        seen="$seen$t$DK_NL"
        n=$((n + 1))
        [ "$n" -le 3 ] || break
        [ "${#t}" -le 60 ] || t="${t:0:59}…"
        out="$out${out:+; }$t"
    done <<EOF
$DK_SNIPS
EOF
    printf '%s' "$out"
}

# Záznam commitu / add (riadok C parsera) s jeho D riadkami → báza a kandidáti, úryvky, riadok príkazu pre kontroly.
dk__crec() { # <kind\x1fslovo…> <D riadky>
    local rest="$1" dl="$2" kind words line c cmdn snip home cdp ops tok nx="" wtree="" gdir="" n v op=""
    kind=${rest%%"$DK_US"*}; words=${rest#*"$DK_US"}
    base=$fb; DK_RITEMS=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        IFS="$DK_US" read -r c cmdn snip home cdp ops <<EOF
$line
EOF
        # shellcheck disable=SC2046
        (set -f; IFS=$DK_US; dk__cdstep "$c" "$cmdn" "$snip" "$home" "$cdp" $ops; printf '%s\n%s' "$base" "$DK_RITEMS") > "$DK_TMP/rec"
        base=$(sed -n 1p "$DK_TMP/rec"); DK_RITEMS=$(sed 1d "$DK_TMP/rec")
        [ -z "$DK_RITEMS" ] || DK_RITEMS="$DK_RITEMS$DK_NL"
    done <<EOF
$dl
EOF
    while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        case "$nx" in
            C) dk__gtarget "$tok" "-C $tok"; nx=""; continue ;;
            W) wtree=$tok; nx=""; continue ;;
            G) gdir=$tok; nx=""; continue ;;
            S) nx=""; continue ;;
        esac
        case "$tok" in
            -C) nx=C ;;
            -c|--namespace) nx=S ;;
            --work-tree) nx=W ;;
            --git-dir) nx=G ;;
            --work-tree=*) wtree=${tok#--work-tree=} ;;
            --git-dir=*) gdir=${tok#--git-dir=} ;;
            GIT_WORK_TREE=*) wtree=${tok#GIT_WORK_TREE=} ;;
            GIT_DIR=*) gdir=${tok#GIT_DIR=} ;;
            commit|add|stage) break ;;
            rebase|merge|cherry-pick|revert|am) op=$tok; break ;;
        esac
    done <<EOF
$(printf '%s\n' "$words" | tr "$DK_US" '\n')
EOF
    if [ -z "$wtree$gdir" ]; then
        while IFS="$DK_US" read -r n v; do
            case "$n" in GIT_WORK_TREE) wtree=$v ;; GIT_DIR) gdir=$v ;; esac
        done <<EOF
${DK_VARS_E:-}
EOF
    fi
    if [ -n "$wtree" ]; then
        dk__gtarget "$wtree" "--work-tree $wtree"
    elif [ -n "$gdir" ]; then
        dk__gtarget "$gdir" "--git-dir $gdir" git
    fi
    [ -d "$base" ] || base=$fb
    line=$(printf '%s' "$words" | tr "$DK_US" ' ')
    case "$kind" in
        commit)
            DK_COMMIT_LINES="$DK_COMMIT_LINES$line$DK_NL"; DK_ADD_LINES="$DK_ADD_LINES$DK_ADD_PEND"; DK_ADD_PEND=""
            [ -z "$op" ] || [ -n "$DK_CONT" ] || DK_CONT="git $op --continue"
            ;;
        add) DK_ADD_PEND="$DK_ADD_PEND$line$DK_NL" ;;
    esac
    DK_RDIRS="$DK_RDIRS$base$DK_NL"
    local pb other k kl
    pb=$(dk__proj "$base")
    while IFS="$DK_US" read -r c snip kl; do
        [ -n "$c" ] || continue
        other=0
        while IFS= read -r k; do
            [ -n "$k" ] || continue
            DK_RDIRS="$DK_RDIRS$k$DK_NL"
            [ "$(dk__proj "$k")" = "$pb" ] || other=1
        done <<EOF
$(printf '%s' "$kl" | tr "$DK_US" '\n')
EOF
        case "$c" in U) dk__snip U "$snip" ;; N) [ "$other" = 0 ] || dk__snip N "$snip" ;; esac
    done <<EOF
$DK_RITEMS
EOF
}
dk__proj() { dk_set_project "$1" ""; printf '%s' "$DK_PROJECT"; }

# Záchrana (riadok R): báza = cwd session, kandidáti = slová za cd / pushd / -C kdekoľvek v texte, ktoré sú adresáre.
dk__rkands() { # <príkaz>
    local w v
    printf '%s\n' "$1" | awk '
        { n = length($0); w = ""
          for (i = 1; i <= n; i++) { c = substr($0, i, 1)
            if (c == "\\") { w = w substr($0, i + 1, 1); i++; continue }
            if (c == "\"" || c == "\047") continue
            if (c ~ /[ \t;&|(){}]/) { if (w != "") print w; w = ""; continue }
            w = w c }
          if (w != "") print w }' | awk 'p == "cd" || p == "pushd" || p == "-C" { print } { p = $0 }' | while IFS= read -r w; do
        v=$(dk_expand_dir "$w" "$fb") && [ -d "$v" ] && printf '%s\n' "$v"
    done
}

# Položky zoznamu pre dk__fit: \x1f<najviac>\x1f<text riadku „… <text>: N“>\x1f<riadok>.
dk__items() { # <najviac> <ďalšie …> <riadky>
    local l
    while IFS= read -r l; do
        [ -n "$l" ] && printf '%s%s%s%s%s%s\n' "$DK_US" "$1" "$DK_US" "$2" "$DK_US" "$l"
    done <<EOF
$3
EOF
    return 0
}

# Blok repa na najviac <max> riadkov: zoznamy najprv po svoj strop, potom skracuje najdlhší (pri zhode neskorší)
# s riadkom „… ďalšie …: N“, nakoniec orez. Riadok „Spusti kontrolu“ sa pridáva až za blok (SPEC §4.4).
dk__fit() { # <max>
    DK_AWK_MAX=$1 awk '
        BEGIN { US = "\037"; max = ENVIRON["DK_AWK_MAX"] + 0 }
        {   n++
            if (substr($0, 1, 1) != US) { T[n] = $0; pr = 0; fixed++; next }
            s = substr($0, 2); i = index(s, US); cap = substr(s, 1, i - 1) + 0; s = substr(s, i + 1)
            i = index(s, US); lab = substr(s, 1, i - 1); T[n] = substr(s, i + 1)
            if (pr == 0 || RL[pr] != lab) { pr = ++nr; RL[pr] = lab; RC[pr] = cap; RN[pr] = 0 }
            R[n] = pr; RN[pr]++ }
        END {
            for (r = 1; r <= nr; r++) S[r] = (RN[r] < RC[r]) ? RN[r] : RC[r]
            for (;;) {
                tot = fixed; for (r = 1; r <= nr; r++) tot += S[r] + (S[r] < RN[r])
                if (tot <= max) break
                b = 0; for (r = 1; r <= nr; r++) if (S[r] > 1 && (b == 0 || S[r] >= S[b])) b = r
                if (b == 0) break
                S[b]--
            }
            out = 0
            for (i = 1; i <= n; i++) {
                if (!(i in R)) { O[++out] = T[i]; continue }
                r = R[i]; k[r]++
                if (k[r] <= S[r]) O[++out] = T[i]
                if (k[r] == RN[r] && S[r] < RN[r]) O[++out] = "… " RL[r] ": " (RN[r] - S[r])
            }
            # Orez nenechá na konci nadpis zoznamu („…:“) bez položiek.
            if (out > max) { out = max; while (out > 1 && O[out] ~ /:$/) out-- }
            for (i = 1; i <= out; i++) print O[i]
        }'
}

# Slovo pre shell: bezpečné znaky ostanú, inak v apostrofoch.
dk__shq() {
    case "$1" in
        ''|*[!A-Za-z0-9._/@+=,:-]*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
        *) printf '%s' "$1" ;;
    esac
}

# Prečo posledná quick/full kontrola nedala PASS (partial.json z check.sh, < 24 h) a ako ďalej; inak nič.
# Bez ok kroku by vypnutie blokovaných krokov dalo SKIP (check.sh exit 4) → únik je celý commitGate.
dk_partial_note() {
    local f="$DK_PDATA/partial.json" out t ok ids lines why what=kroku
    [ -f "$f" ] || return 0
    out=$(jq -r '"\(.time // 0)", "\(.ok // 0)", ((.steps // []) | map("step:" + (tostring | gsub("[\n\r]"; " "))) | join(", ")),
        ((.lines // [])[:5][] | tostring | gsub("[\n\r]"; " "))' "$f" 2>/dev/null) || return 0
    t=$(printf '%s\n' "$out" | sed -n 1p)
    ok=$(printf '%s\n' "$out" | sed -n 2p)
    ids=$(printf '%s\n' "$out" | sed -n 3p)
    case "$t" in ''|*[!0-9]*) return 0 ;; esac
    case "$ok" in ''|*[!0-9]*) ok=0 ;; esac
    [ $(( $(dk_now) - t )) -lt 86400 ] || return 0
    lines=$(printf '%s\n' "$out" | sed 1,3d | grep -v '^[[:space:]]*$')
    [ -n "$lines" ] || return 0
    why="odstrániť príčinu"
    if [ -n "${DK_CONTAINER:-}" ]; then
        case "$lines" in *": kontajner $DK_CONTAINER nebeží"*) why="spustiť kontajner $DK_CONTAINER" ;; esac
    fi
    printf 'Posledná kontrola skončila PARTIAL:\n'
    dk__items 5 'ďalšie riadky' "$lines"
    if [ "$ok" -gt 0 ] && [ -n "$ids" ]; then
        case "$ids" in *", "*) what=krokov ;; esac
        printf 'Únik: navrhni používateľovi %s a kontrolu zopakuj, alebo mu navrhni dočasné vypnutie %s: disabledRules %s v .claude/devkit.json (config nemeň sám, počkaj na jeho rozhodnutie).\n' "$why" "$what" "$ids"
    else
        printf 'Únik: vypnutie krokov by dalo SKIP, nie PASS — navrhni používateľovi %s a kontrolu zopakuj, alebo mu navrhni dočasné vypnutie gate: disabledRules commitGate v .claude/devkit.json (kontrola tajomstiev aj Stop bežia ďalej; config nemeň sám).\n' "$why"
    fi
}

# Slová príkazu s ohľadom na úvodzovky (úvodzovky ostanú v slove), jedno na riadok.
dk__tokens() {
    local s="$1" i=0 n=${#1} c q="" tok="" has=0
    case "$s" in
        *[\"\']*) ;;
        *)
            set -f
            for tok in $s; do printf '%s\n' "$tok"; done
            set +f
            return 0
            ;;
    esac
    while [ "$i" -lt "$n" ]; do
        c=${s:$i:1}
        if [ -n "$q" ]; then
            tok="$tok$c"
            [ "$c" = "$q" ] && q=""
        else
            case "$c" in
                \"|\') q=$c; tok="$tok$c"; has=1 ;;
                ' '|"$DK_TAB") [ "$has" = 1 ] && printf '%s\n' "$tok"; tok=""; has=0 ;;
                *) tok="$tok$c"; has=1 ;;
            esac
        fi
        i=$((i + 1))
    done
    [ "$has" = 1 ] && printf '%s\n' "$tok"
    return 0
}

# Telo heredocu (napr. správa commitu cez <<'EOF') → prázdne riadky; čísla riadkov ostanú.
dk__no_heredoc() {
    awk -v q="'" '
        tag != "" { t = $0; if (strip) sub(/^\t+/, "", t); if (t == tag) tag = ""; print ""; next }
        { print
          if (match($0, "<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*") && !(RSTART > 1 && substr($0, RSTART - 1, 1) == "<")) {
              tag = substr($0, RSTART, RLENGTH); strip = (tag ~ /^<<-/)
              sub(/^<<-?[ \t]*/, "", tag); gsub("[\"" q "]", "", tag)
          } }'
}

dk_main() {
    DK_INPUT=""
    [ -t 0 ] || DK_INPUT=$(cat 2>/dev/null)
    DK_INPUT_DONE=1
    case "$DK_INPUT" in *commit*|*--continue*) ;; *) return 0 ;; esac
    command -v jq >/dev/null 2>&1 || return 0
    local cmd t0
    cmd=$(printf '%s' "$DK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -n "$cmd" ] || return 0
    case "$cmd" in *'<<'*) cmd=$(printf '%s\n' "$cmd" | dk__no_heredoc) ;; esac
    printf '%s\n' "$cmd" | grep -qE -e "$DK_RE_COMMIT_ANY" || return 0
    t0=$(dk_ms)
    dk_init
    dk_tmpdir

    # Repo každého commitu: báza (isté cd pred ním, -C, --work-tree, --git-dir) a kandidáti (neisté cd, neznámy
    # cieľ) z parsera; kontroly bežia v každom repe s configom (SPEC §4.4.1).
    local fb base line tag rest dl="" parsed rdirs=""
    fb=${DK_CWD:-${CLAUDE_PROJECT_DIR:-$PWD}}
    DK_VARS="" DK_VARS_E="" DK_KANDS="" DK_HOME="" DK_HOME_UNKNOWN="" DK_RITEMS="" DK_SNIPS="" DK_RDIRS=""
    DK_COMMIT_LINES="" DK_ADD_LINES="" DK_ADD_PEND="" DK_RESCUE=0 DK_RHARD=0 DK_CONT=""
    parsed=$(dk_cmd_parse "$cmd")
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        tag=${line%%"$DK_US"*}; rest=${line#*"$DK_US"}
        case "$tag" in
            V) dk__var "$rest" ;;
            K) dk__kand "$rest" ;;
            R) dk__snip R "$rest"; DK_RESCUE=1; [ "$rest" = 'commit mimo štruktúry' ] || DK_RHARD=1 ;;
            D) dl="$dl$rest$DK_NL" ;;
            C) dk__crec "$rest" "$dl"; dl="" ;;
        esac
    done <<EOF
$parsed
EOF
    if [ "$DK_RESCUE" = 1 ]; then
        rdirs="$fb$DK_NL$(dk__rkands "$cmd")$DK_NL"
        DK_RDIRS="$DK_RDIRS$rdirs"
    fi
    # Rýchla cesta je hrubé sito: bez commitu a bez R (napr. len git add a text „git … commit“) nič nekontroluj.
    [ -n "$DK_COMMIT_LINES" ] || [ "$DK_RESCUE" = 1 ] || return 0
    [ -n "$DK_COMMIT_LINES" ] || DK_COMMIT_LINES=$(printf '%s\n' "$cmd" | grep -E -e "$DK_RE_COMMIT" -e "$DK_RE_COMMIT_CONT")

    # Repá s configom, každé raz; kontroly v každom, deny po blokoch. Záznam R (okrem „commit mimo štruktúry“, ten
    # vzniká aj z textu v úvodzovkách iného programu) zamietne vždy, keď je niektoré z jeho repí s configom
    # a zapnutým commitGate: súbory commitu sa z textu nedajú určiť.
    local repos="" dir nden=0 hdr rproj="$DK_NL" rdeny=0
    DK_SEC_HINT=0
    [ "$DK_RHARD" = 1 ] || rdirs=""
    while IFS= read -r dir; do
        [ -n "$dir" ] && rproj="$rproj$(dk__proj "$dir")$DK_NL"
    done <<EOF
$rdirs
EOF
    while IFS= read -r dir; do
        [ -n "$dir" ] || continue
        dk_set_project "$dir" ""
        [ -n "$DK_CFG" ] || continue
        case "$DK_NL$repos" in *"$DK_NL$DK_PROJECT$DK_US"*) continue ;; esac
        repos="$repos$DK_PROJECT$DK_US$dir$DK_NL"
    done <<EOF
$DK_RDIRS
EOF
    [ -n "$repos" ] || return 0
    while IFS="$DK_US" read -r dir base; do
        [ -n "$dir" ] || continue
        dk_set_project "$dir" ""
        [ -n "$DK_CFG" ] || continue
        DK_EDENY="" DK_ERUN="" DK_GATE_ON=0
        dk_eval_repo "$t0"
        case "$rproj" in
            *"$DK_NL$DK_PROJECT$DK_NL"*)
                if [ "$DK_GATE_ON" = 1 ]; then
                    rdeny=1
                    [ -n "$DK_EDENY$DK_ERUN" ] || dk_log pre-bash commitGate deny "" $(( $(dk_ms) - t0 ))
                fi
                ;;
        esac
        [ -n "$DK_EDENY$DK_ERUN" ] || continue
        nden=$((nden + 1))
        printf '%s\n%s\n' "$DK_PROJECT" "$DK_EDENY" > "$DK_TMP/deny.$nden"
        printf '%s' "$DK_ERUN" > "$DK_TMP/run.$nden"
    done <<EOF
$repos
EOF
    [ "$nden" -gt 0 ] || [ "$rdeny" = 1 ] || return 0
    local deny="" s i=0 per=0 b run fix="spusti git commit samostatným príkazom"
    s=$(dk__snips U); [ -z "$s" ] || deny="$deny[dev-kit] cieľ \`cd\`/\`git -C\` sa nedal určiť ($s) — použi doslovnú cestu$DK_NL"
    s=$(dk__snips N); [ -z "$s" ] || deny="$deny[dev-kit] nie je isté, či \`cd\` pred commitom prebehne ($s) — kontrola zahŕňa aj jeho cieľ; spoj cd s commitom cez && alebo použi git -C <cesta>$DK_NL"
    case "$DK_NL$DK_SNIPS" in *"${DK_NL}R${DK_US}commit cez "*) fix="napíš git doslovne a spusti commit samostatným príkazom" ;; esac
    s=$(dk__snips R); [ -z "$s" ] || deny="$deny[dev-kit] príkaz s commitom sa nedal rozložiť ($s) — $fix$DK_NL"
    # Blok repa ≤ 12 riadkov, pri viacerých repách menej, aby text ostal ≤ 20 riadkov; „Spusti kontrolu“ za orezom.
    [ "$nden" = 0 ] || per=$(( (20 - $(printf '%s' "$deny" | grep -c .)) / nden ))
    while [ "$i" -lt "$nden" ]; do
        i=$((i + 1))
        hdr=""; [ "$nden" -le 1 ] || hdr="[dev-kit] repo $(sed -n 1p "$DK_TMP/deny.$i"):$DK_NL"
        run=$(cat "$DK_TMP/run.$i")
        b=$per; [ -z "$hdr" ] || b=$((b - 1)); [ -z "$run" ] || b=$((b - 1))
        [ "$b" -le 12 ] || b=12
        [ "$b" -ge 1 ] || b=1
        deny="$deny$hdr$(sed 1d "$DK_TMP/deny.$i" | grep -v '^$' | dk__fit "$b")$DK_NL${run:+$run$DK_NL}"
    done
    dk_deny "$(printf '%s' "$deny" | grep -v '^$')"
    return 0
}

# Kontroly (tajomstvá, commit gate) v repe DK_PROJECT pre všetky commity a add príkazu; výsledok v DK_EDENY.
dk_eval_repo() { # <t0>
    local t0="$1" d
    d=$(printf '\001')
    # Zmena devkit.json repa commitu (R3): systemMessage raz za session, gate ani kontrola tajomstiev sa nemenia.
    [ -n "$DK_CFG_NOTE" ] || { dk_cfg_trust note && DK_CFG_NOTE=$(dk_cfg_note); }

    local tag a b enabled=true gext="" fullw="" pats="" allow="" forbid=""
    dk_cfg_read '"E\u001f\(if (.commitGate|type) == "boolean" then .commitGate elif .commitGate.enabled == false then false else true end | s)",
        "G\u001f\((.commitGate.ext // []) | join(","))",
        ((.check.fullWhen // [])[] | "W\u001f\(.|s)"),
        ((.secrets.patterns // [])[] | "P\u001f\(.|s)"),
        ((.secrets.allow // [])[] | "L\u001f\(.|s)"),
        ((.secrets.forbidFiles // [])[] | "F\u001f\(.|s)")' || return 0
    while IFS=$DK_US read -r tag a; do
        case "$tag" in
            E) enabled=$a ;;
            G) gext=$a ;;
            W) fullw="$fullw$a$DK_NL" ;;
            P) pats="$pats$a$DK_NL" ;;
            L) allow="$allow$a$DK_NL" ;;
            F) forbid="$forbid$a$DK_NL" ;;
        esac
    done <<EOF
$DK_CFG_OUT
EOF
    [ -n "$gext" ] || gext=$DK_CODE_EXTS
    local gate_on=0 sec_on=0
    [ "$enabled" != false ] && dk_rule_on commitGate && gate_on=1
    DK_GATE_ON=$gate_on
    dk_rule_on secrets && sec_on=1
    [ "$gate_on$sec_on" != 00 ] || return 0

    # Prepínače všetkých commitov príkazu (úvodzovky → Q, segmenty po novom riadku, &&, ||, ;; koniec pri |).
    local all=0 dd skip specs="" c i s rest
    while IFS= read -r s; do
        printf '%s\n' "$s" | grep -qE -e "$DK_RE_COMMIT" || continue
        rest=$(printf '%s\n' "$s" | sed -E "s${d}^.*${DK_RE_COMMIT}${d}${d}; s/\|.*//")
        dd=0 skip=0
        set -f
        for tok in $rest; do
            if [ "$dd" = 1 ]; then specs="$specs$(dk_strip_quotes "$tok")$DK_NL"; continue; fi
            if [ "$skip" = 1 ]; then skip=0; continue; fi
            case "$tok" in
                --) dd=1 ;;
                --all) all=1 ;;
                --message|--file|--reuse-message|--reedit-message|--author|--date|--template|--cleanup|--fixup|--squash|--trailer|--pathspec-from-file) skip=1 ;;
                --*) ;;
                -*)
                    i=1
                    while [ "$i" -lt "${#tok}" ]; do
                        c=${tok:$i:1}
                        case "$c" in
                            a) all=1 ;;
                            m|F|C|c|t) [ "$i" = $((${#tok} - 1)) ] && skip=1; break ;;
                        esac
                        i=$((i + 1))
                    done
                    ;;
                [\<\>\$\"\'\(\`]*|*\)) ;;
                *) [ -e "$base/$tok" ] && specs="$specs$tok$DK_NL" ;;
            esac
        done
        set +f
    done <<EOF
$(printf '%s\n' "$DK_COMMIT_LINES" | sed -E "s/\"[^\"]*\"/Q/g; s/'[^']*'/Q/g")
EOF

    # `git add`/`git stage` v tom istom príkaze pred commitom (hook beží pred celým príkazom, index ešte nie je naplnený).
    local addl atok a_all a_upd a_force a_part a_dry a_dd a_specs aall=0 aupd=0 partial=0 forceall=0 fspecs=""
    while IFS= read -r addl; do
        a_all=0 a_upd=0 a_force=0 a_part=0 a_dry=0 a_dd=0 a_specs=""
        while IFS= read -r atok; do
            [ -n "$atok" ] || continue
            if [ "$a_dd" = 1 ]; then a_specs="$a_specs$(dk_strip_quotes "$atok")$DK_NL"; continue; fi
            case "$atok" in
                --) a_dd=1 ;;
                --force) a_force=1 ;;
                --patch|--interactive|--edit) a_part=1 ;;
                --all) a_all=1 ;;
                --update) a_upd=1 ;;
                --dry-run) a_dry=1 ;;
                --*) ;;
                -[A-Za-z]*)
                    i=1
                    while [ "$i" -lt "${#atok}" ]; do
                        case "${atok:$i:1}" in
                            A) a_all=1 ;;
                            u) a_upd=1 ;;
                            f) a_force=1 ;;
                            p|i|e) a_part=1 ;;
                            n) a_dry=1 ;;
                        esac
                        i=$((i + 1))
                    done
                    ;;
                -*) ;;
                .|:/) a_all=1 ;;
                *) a_specs="$a_specs$(dk_strip_quotes "$atok")$DK_NL" ;;
            esac
        done <<EOF2
$(dk__tokens "$addl")
EOF2
        [ "$a_dry" = 1 ] && continue
        [ "$a_part" = 1 ] && partial=1
        [ "$a_all" = 1 ] && aall=1
        [ "$a_upd" = 1 ] && aupd=1
        if [ "$a_force" = 1 ]; then
            [ "$a_all" = 1 ] && forceall=1
            fspecs="$fspecs$a_specs"
        fi
        specs="$specs$a_specs"
    done <<EOF
$(printf '%s\n' "$DK_ADD_LINES" | grep -oE -e "${DK_RE_ADD}.*" | sed -E "s${d}${DK_RE_ADD}${d}${d}")
EOF
    local wt=""
    if [ "$aall" = 1 ]; then
        all=1
        wt=$(dk_git ls-files --others --exclude-standard 2>/dev/null | grep -v '/$')
    elif [ "$aupd" = 1 ]; then
        all=1
    fi

    # Súbory, ktoré pôjdu do commitu: staged ∪ (-a: zmenené sledované) ∪ (pathspec / git add: zmenené voči HEAD + nové,
    # pri -f aj ignorované). Položky s koncovým '/' (vnorené repo, worktree) sa nedajú hashovať.
    local staged f sp
    staged=$(dk_git diff --cached --name-only --no-renames --diff-filter=ACMRD 2>/dev/null)
    [ "$all" = 1 ] && wt="$wt$DK_NL$(dk_git diff --name-only --no-renames --diff-filter=ACMRD HEAD 2>/dev/null)"
    dk_tmpdir
    printf '%s' "$specs" | grep -v '^$' | tr '\n' '\0' > "$DK_TMP/specs.z"
    if [ -s "$DK_TMP/specs.z" ]; then
        sp=$(xargs -0 git -C "$base" -c core.quotepath=off diff --name-only --no-renames HEAD -- < "$DK_TMP/specs.z" 2>/dev/null)
        [ -n "$sp" ] && wt="$wt$DK_NL$sp"
        sp=$(xargs -0 git -C "$base" -c core.quotepath=off ls-files --full-name --others --exclude-standard -- < "$DK_TMP/specs.z" 2>/dev/null | grep -v '/$')
        [ -n "$sp" ] && wt="$wt$DK_NL$sp"
    fi
    printf '%s' "$fspecs" | grep -v '^$' | tr '\n' '\0' > "$DK_TMP/fspecs.z"
    if [ -s "$DK_TMP/fspecs.z" ]; then
        sp=$(xargs -0 git -C "$base" -c core.quotepath=off ls-files --full-name --others --ignored --exclude-standard -- < "$DK_TMP/fspecs.z" 2>/dev/null | grep -v '/$')
        [ -n "$sp" ] && wt="$wt$DK_NL$sp"
    fi
    wt=$(printf '%s\n' "$wt" | grep -v '^$' | sort -u)
    local tbc qn
    tbc=$(printf '%s\n%s\n' "$staged" "$wt" | grep -v '^$' | sort -u)
    if [ "$partial" = 0 ] && [ "$forceall" = 0 ] && [ -z "$tbc" ]; then return 0; fi

    # Názov, ktorý git vypíše len v úvodzovkách (", \, riadiace znaky), sa nedá spoľahlivo overiť.
    qn=$(printf '%s\n' "$tbc" | grep '^"' | head -n 1)
    if [ -n "$qn" ]; then
        if [ "$gate_on" = 1 ]; then dk_log pre-bash commitGate deny "" $(( $(dk_ms) - t0 )); else dk_log pre-bash secrets deny "" $(( $(dk_ms) - t0 )); fi
        DK_EDENY="[dev-kit] nepodporovaný názov súboru $qn (úvodzovky, \\ alebo riadiace znaky) — kontrola ho nevie overiť, premenuj ho."
        return 0
    fi

    # Obsah: pracovný strom pre -a/pathspec/add, inak blob z indexu; zmazaný = "-".
    # Zoznamy súborov cez awk a súbory: reťazec skladaný v cykle bash rastie kvadraticky (tisíce súborov, hook 60 s).
    local map="" so=""
    printf '%s\n' "$wt" | grep -v '^$' > "$DK_TMP/wt.list"
    printf '%s\n' "$tbc" > "$DK_TMP/tbc.list"
    so=$(LC_ALL=C awk 'FILENAME == ARGV[1] { w[$0] = 1; next } $0 != "" && !($0 in w)' "$DK_TMP/wt.list" "$DK_TMP/tbc.list")
    [ -z "$so" ] || so="$so$DK_NL"
    if [ -n "$wt" ]; then
        # shellcheck disable=SC2086
        map=$(set -f; IFS=$DK_NL; dk_blobs $wt)
    fi
    if [ -n "$so" ]; then
        printf '%s' "$so" > "$DK_TMP/so.list"
        tr '\n' '\0' < "$DK_TMP/so.list" | xargs -0 git -C "$DK_PROJECT" -c core.quotepath=off ls-files -s -- 2>/dev/null \
            | awk -F'\t' '{ split($1, m, " "); print $2 "\t" m[2] "\t" m[1] }' > "$DK_TMP/so.idx"
        # Symlink (120000) s príponou kódu vypadne ako v dk_blobs: blob v indexe je cieľ odkazu.
        map="$map$DK_NL$(DK_AWK_EXT=",$gext,$DK_CODE_EXTS," awk -F'\t' '
            function ext(p,   x) { x = p; sub(/.*\//, "", x); if (index(x, ".") == 0) return ""; sub(/.*\./, ".", x); return x }
            FILENAME == ARGV[1] { b[$1] = $2; if ($3 == "120000") l[$1] = 1; next }
            NF {
                if (($0 in l) && (e = ext($0)) != "" && index(ENVIRON["DK_AWK_EXT"], "," e ",")) next
                print $0 "\t" (($0 in b) ? b[$0] : "-")
            }' "$DK_TMP/so.idx" "$DK_TMP/so.list")"
    fi
    map=$(printf '%s\n' "$map" | grep -v '^$' | sort -u)

    local deny="" sfind="" nsec=0 when=""
    [ -z "$DK_CONT" ] || when=" pred $DK_CONT"
    # 1. Tajomstvá.
    if [ "$sec_on" = 1 ]; then
        if [ "$forceall" = 1 ]; then
            deny="${deny}[dev-kit] git add -A -f pridá aj ignorované súbory — stage-uj konkrétne súbory.$DK_NL"
        fi
        local fre are p g
        fre=$(dk_globs_re "$forbid")
        are=$(dk_globs_re "$allow")
        while IFS="$DK_TAB" read -r f b; do
            [ -n "$f" ] && [ "$b" != "-" ] || continue
            if dk_re_match "$f" "$fre"; then
                sfind="$sfind- $f — zakázaný súbor (secrets.forbidFiles)$DK_NL"; nsec=$((nsec + 1))
            fi
        done <<EOF
$map
EOF
        # Diff pridaných riadkov: obsah z indexu (sec.so), z pracovného stromu (sec.wt), nesledovaný súbor celý (sec.new).
        # DK_TMP zdieľajú všetky repá príkazu → každý súbor najprv vyprázdniť.
        : > "$DK_TMP/sec.wt"; : > "$DK_TMP/sec.so"; : > "$DK_TMP/sec.new"; : > "$DK_TMP/sec.meta"; : > "$DK_TMP/sec.txt"
        while IFS="$DK_TAB" read -r f b; do
            [ -n "$f" ] && [ "$b" != "-" ] || continue
            dk_re_match "$f" "$are" && continue
            printf '%s\n' "$f"
        done > "$DK_TMP/sec.cand" <<EOF
$map
EOF
        DK_AWK_WT="$DK_TMP/sec.wt" DK_AWK_SO="$DK_TMP/sec.so" LC_ALL=C awk '
            BEGIN { wt = ENVIRON["DK_AWK_WT"]; so = ENVIRON["DK_AWK_SO"] }
            FILENAME == ARGV[1] { w[$0] = 1; next }
            { if ($0 in w) print > wt; else print > so }' "$DK_TMP/wt.list" "$DK_TMP/sec.cand"
        if [ -s "$DK_TMP/sec.wt" ]; then
            tr '\n' '\0' < "$DK_TMP/sec.wt" | xargs -0 git -C "$DK_PROJECT" -c core.quotepath=off ls-files -- 2>/dev/null > "$DK_TMP/sec.known"
            LC_ALL=C awk 'FILENAME == ARGV[1] { k[$0] = 1; next } !($0 in k)' "$DK_TMP/sec.known" "$DK_TMP/sec.wt" > "$DK_TMP/sec.new"
        fi
        {
            [ -s "$DK_TMP/sec.so" ] && tr '\n' '\0' < "$DK_TMP/sec.so" | xargs -0 git -C "$DK_PROJECT" -c core.quotepath=off \
                diff --cached -U0 --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ -- 2>/dev/null
            [ -s "$DK_TMP/sec.wt" ] && tr '\n' '\0' < "$DK_TMP/sec.wt" | xargs -0 git -C "$DK_PROJECT" -c core.quotepath=off \
                diff -U0 --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ HEAD -- 2>/dev/null
            # Nový súbor: textový (grep -I) celý ako pridané riadky; „./“ pred cestou, aby awk nečítal a=b ako priradenie.
            if [ -s "$DK_TMP/sec.new" ]; then
                (cd "$DK_PROJECT" 2>/dev/null && LC_ALL=C sed 's|^|./|' "$DK_TMP/sec.new" | tr '\n' '\0' |
                    LC_ALL=C xargs -0 grep -Il -e . -- 2>/dev/null | tr '\n' '\0' |
                    LC_ALL=C xargs -0 awk 'FNR == 1 { p = substr(FILENAME, 3); printf "diff --git a/%s b/%s\n+++ b/%s\n@@ -0,0 +1 @@\n", p, p, p }
                        { print "+" $0 }')
            fi
        } | DK_AWK_META="$DK_TMP/sec.meta" DK_AWK_TXT="$DK_TMP/sec.txt" awk '
            BEGIN { meta = ENVIRON["DK_AWK_META"]; txt = ENVIRON["DK_AWK_TXT"] }
            /^diff / { hd = 1; next }
            hd && /^\+\+\+ / { p = substr($0, 5); sub(/\t$/, "", p); sub(/^b\//, "", p); next }
            /^@@ / { hd = 0; s = $3; sub(/^\+/, "", s); split(s, q, ","); ln = q[1] + 0; next }
            hd { next }
            /^\+/ { if (p != "/dev/null") { print p ":" ln > meta; print substr($0, 2) > txt }; ln++ }
        '
        if [ -s "$DK_TMP/sec.txt" ]; then
            local seen="$DK_NL" gi k m mv hits
            while IFS= read -r p; do
                [ -n "$p" ] || continue
                gi=""
                case "$p" in '(?i)'*) p=${p#'(?i)'}; gi=-i ;; esac
                hits=$(grep -nE $gi -e "$p" "$DK_TMP/sec.txt" 2>/dev/null)
                [ $? -gt 1 ] && dk_err "secrets: neplatný vzor (grep -E): $p"
                [ -n "$hits" ] || continue
                for k in $(printf '%s\n' "$hits" | cut -d: -f1 | head -n 50); do
                    g=$(sed -n "${k}p" "$DK_TMP/sec.meta")
                    case "$seen" in *"$DK_NL$g$DK_NL"*) continue ;; esac
                    m=$(sed -n "${k}p" "$DK_TMP/sec.txt" | grep -oE $gi -e "$p" | head -n 1)
                    mv=$(dk_mask "$m") || continue
                    seen="$seen$g$DK_NL"
                    sfind="$sfind- $g — $mv$DK_NL"; nsec=$((nsec + 1))
                done
            done <<EOF
$DK_SECRET_DEFAULTS
$pats
EOF
        fi
        if [ "$nsec" -gt 0 ]; then
            deny="$deny[dev-kit] commit zablokovaný$when — tajomstvo alebo zakázaný súbor ($nsec):$DK_NL$(dk__items 8 'ďalšie nálezy' "$sfind")$DK_NL"
            if [ "$DK_SEC_HINT" = 0 ]; then
                deny="${deny}Hodnotu nevypisuj ani sám neodstraňuj — nahlás používateľovi súbor:riadok a počkaj na jeho rozhodnutie (súbor z commitu: git restore --staged <súbor>; falošný poplach: secrets.allow v .claude/devkit.json).$DK_NL"
                DK_SEC_HINT=1
            fi
        fi
        if [ "$nsec" -gt 0 ] || [ "$forceall" = 1 ]; then
            dk_log pre-bash secrets deny "" $(( $(dk_ms) - t0 ))
        fi
    fi

    # 2. Commit gate. Kľúč obsahu (hash kódových blobov) zoskupí pokusy o ten istý commit pre /dev:stats.
    if [ "$gate_on" = 1 ]; then
        local code="" pmode="" bad="" nbad=0 fullg="" gmsg="" ckey="" rerun=0 again fl
        if [ "$partial" = 1 ]; then
            gmsg="[dev-kit] čiastočný stage (git add -p/-i/-e) v tom istom príkaze ako commit sa nedá overiť — stage-uj zvlášť, potom commit zopakuj.$DK_NL"
        fi
        code=$(printf '%s\n' "$map" | dk_ext_filter "$gext" code)
        [ -z "$code" ] || code="$code$DK_NL"
        if [ -n "$code" ]; then
            ckey=$(printf '%s' "$code" | git hash-object --stdin 2>/dev/null | cut -c1-12)
            printf '%s' "$code" > "$DK_TMP/code.list"
            : > "$DK_TMP/pass.blobs"
            if [ -f "$DK_PDATA/pass.json" ]; then
                jq -r '"M\u001f\(.mode // "")", ((.blobs // {}) | to_entries[] | "B\u001f\(.key)\u001f\(.value)")' "$DK_PDATA/pass.json" 2>/dev/null > "$DK_TMP/pass.out"
                pmode=$(LC_ALL=C awk -F'\037' '$1 == "M" { print $2; exit }' "$DK_TMP/pass.out")
                LC_ALL=C awk -F'\037' '$1 == "B" { print $2 "\t" $3 }' "$DK_TMP/pass.out" > "$DK_TMP/pass.blobs"
            fi
            LC_ALL=C awk 'FILENAME == ARGV[1] { p[$0] = 1; next } $0 != "" && !($0 in p)' "$DK_TMP/pass.blobs" "$DK_TMP/code.list" > "$DK_TMP/bad.list"
            nbad=$(grep -c '' "$DK_TMP/bad.list")
            # check.sh hashuje pracovný strom; iný obsah v indexe by ďalší /dev:check neopravil (len zobrazených 8).
            local note k=0
            while IFS="$DK_TAB" read -r f b && [ "$k" -lt 8 ]; do
                k=$((k + 1))
                note=""
                if [ "$b" != "-" ]; then
                    case "$DK_NL$so" in
                        *"$DK_NL$f$DK_NL"*)
                            [ "$(dk_blobs "$f" | cut -f2)" = "$b" ] || note=" (index ≠ pracovný strom → git add $f)" ;;
                    esac
                fi
                bad="$bad- $f$note$DK_NL"
            done < "$DK_TMP/bad.list"
            [ "$nbad" -le 8 ] || bad="$bad$(LC_ALL=C awk -F'\t' 'NR > 8 { print "- " $1 }' "$DK_TMP/bad.list")$DK_NL"
            if [ -n "$fullw" ]; then
                local fwre
                fwre=$(dk_globs_re "$fullw")
                while IFS="$DK_TAB" read -r f b; do
                    if dk_re_match "$f" "$fwre"; then fullg=$(dk_first_glob "$f" "$fullw"); break; fi
                done < "$DK_TMP/code.list"
            fi
            if [ "$nbad" -gt 0 ]; then
                gmsg="$gmsg[dev-kit] commit gate$when: $(dk_plural "$nbad" súbor súbory súborov) bez PASS z /dev:check pre presne tento obsah:$DK_NL$(dk__items 8 'ďalšie súbory' "$bad")$DK_NL"
                rerun=1
            fi
            if [ -n "$fullg" ] && [ "$pmode" != full ]; then
                gmsg="$gmsg[dev-kit] commit gate$when: zmena v $fullg vyžaduje /dev:check --full$DK_NL"
                rerun=1
            fi
        fi
        if [ -n "$gmsg" ]; then
            if [ "$rerun" = 1 ]; then
                note=$(dk_partial_note)
                [ -z "$note" ] || gmsg="$gmsg$note$DK_NL"
                cmode=--auto; [ -n "$fullg" ] && cmode=--full
                again="commit zopakuj"; [ -z "$DK_CONT" ] || again="zopakuj $DK_CONT"
                # Najviac 8 kódových súborov commitu → --files: cudzí rozpracovaný súbor kontrolu nezhodí.
                fl=""
                if [ "$(printf '%s' "$code" | grep -c .)" -le 8 ]; then
                    while IFS="$DK_TAB" read -r f b; do
                        [ -n "$f" ] && fl="$fl $(dk__shq "$f")"
                    done <<EOF
$code
EOF
                    fl=" --files$fl"
                fi
                DK_ERUN="Spusti kontrolu: bash \"$DK_SCRIPTS/check.sh\" $cmode --project \"$DK_PROJECT\"$fl (to isté robí /dev:check), pri PASS $again."
            fi
            deny="$deny$gmsg"
            dk_log pre-bash commitGate deny "$ckey" $(( $(dk_ms) - t0 ))
        elif [ -n "$code" ]; then
            dk_log pre-bash commitGate pass "$ckey" $(( $(dk_ms) - t0 ))
        fi
    fi

    DK_EDENY=$deny
    return 0
}

DK_CFG_NOTE=""
dk_main
rc=$?
[ "$rc" = 0 ] || dk_err "pre-bash: neočakávaný návratový kód $rc"
# Bez rozhodnutia: len systemMessage, povolenie ide bežnou cestou.
[ -z "$DK_CFG_NOTE" ] || jq -nc --arg s "$DK_CFG_NOTE" '{systemMessage: $s}'
exit 0
