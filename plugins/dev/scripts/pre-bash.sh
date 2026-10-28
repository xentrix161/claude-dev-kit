#!/usr/bin/env bash
# PreToolUse (Bash): pri `git commit` tajomstvá v pridaných riadkoch + commit gate (PASS z check.sh pre presne tento obsah).
# Rozpoznanie cez DK_RE_COMMIT / DK_RE_ADD z lib.sh (SPEC §4.4). Obmedzenie: `sh -c '…git commit…'` ani
# `bash -c '…'` sa nerozpozná.
. "$(dirname "$0")/lib.sh" || exit 0
DK_HOOK=pre-bash

DK_RE_CD='(^|[;&|({!]|&&|\|\||(^|[[:space:]])(then|do|else))[[:space:]]*cd[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^;&|[:space:]]+)'

dk_deny() {
    jq -nc --arg r "$1" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
}

dk_strip_quotes() {
    local s="$1"
    case "$s" in
        \"*\") s=${s#\"}; s=${s%\"} ;;
        \'*\') s=${s#\'}; s=${s%\'} ;;
    esac
    case "$s" in "~"|"~/"*) s="$HOME${s#\~}" ;; esac
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

# Cieľ cd / -C / --work-tree / --git-dir → absolútna cesta (~, $HOME, $PWD = base, $CLAUDE_PROJECT_DIR).
# Návrat 1 = nerozriešiteľné ($(…), iná premenná, `cd -`).
dk_expand_dir() { # <raw> <base>
    local raw="$1" base="$2"
    case "$raw" in
        \'*\') DK_X=$(dk_strip_quotes "$raw") ;;
        *)
            DK_X=$(dk_strip_quotes "$raw")
            DK_X=${DK_X//\"/}
            dk__repl '${HOME}' "$HOME" 0
            dk__repl '$HOME' "$HOME" 1
            dk__repl '${PWD}' "$base" 0
            dk__repl '$PWD' "$base" 1
            if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
                dk__repl '${CLAUDE_PROJECT_DIR}' "$CLAUDE_PROJECT_DIR" 0
                dk__repl '$CLAUDE_PROJECT_DIR' "$CLAUDE_PROJECT_DIR" 1
            fi
            case "$DK_X" in *'$'*|*'`'*) return 1 ;; esac
            ;;
    esac
    case "$DK_X" in ''|-) return 1 ;; esac
    dk_abs "$DK_X" "$base"
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
    case "$DK_INPUT" in *commit*) ;; *) return 0 ;; esac
    command -v jq >/dev/null 2>&1 || return 0
    local cmd lno t0 d
    cmd=$(printf '%s' "$DK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -n "$cmd" ] || return 0
    case "$cmd" in *'<<'*) cmd=$(printf '%s\n' "$cmd" | dk__no_heredoc) ;; esac
    lno=$(printf '%s\n' "$cmd" | grep -nE -e "$DK_RE_COMMIT" | cut -d: -f1 | tail -n 1)
    [ -n "$lno" ] || return 0
    t0=$(dk_ms)
    dk_init
    d=$(printf '\001')

    # Repo: cwd → každé `cd` pred posledným commitom (kumulatívne) → globálne prepínače gitu toho commitu.
    # Nerozriešiteľný cieľ = cwd session (fail closed).
    local line pre scan fb base t v seg tok nx="" wtree="" gdir=""
    fb=${DK_CWD:-${CLAUDE_PROJECT_DIR:-$PWD}}
    base=$fb
    line=$(printf '%s\n' "$cmd" | sed -n "${lno}p")
    pre=$(printf '%s\n' "$line" | sed -E "s${d}^(.*)${DK_RE_COMMIT}.*${d}\\1${d}")
    scan=$( { [ "$lno" -gt 1 ] && printf '%s\n' "$cmd" | sed -n "1,$((lno - 1))p"; printf '%s\n' "$pre"; } )
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        if v=$(dk_expand_dir "$t" "$base") && [ -d "$v" ]; then base=$v; else base=$fb; fi
    done <<EOF
$(printf '%s\n' "$scan" | grep -oE -e "$DK_RE_CD" | sed -E 's/^([;&|({!]|&&|\|\||[[:space:]]|then|do|else)*cd[[:space:]]+//')
EOF
    seg=$(printf '%s\n' "$line" | grep -oE -e "$DK_RE_COMMIT" | tail -n 1)
    while IFS= read -r tok; do
        case "$nx" in
            C) if v=$(dk_expand_dir "$tok" "$base") && [ -d "$v" ]; then base=$v; else base=$fb; fi; nx=""; continue ;;
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
        esac
    done <<EOF
$(dk__tokens "$seg")
EOF
    if [ -n "$wtree" ]; then
        if v=$(dk_expand_dir "$wtree" "$base") && [ -d "$v" ]; then base=$v; else base=$fb; fi
    elif [ -n "$gdir" ]; then
        if v=$(dk_expand_dir "$gdir" "$base"); then
            case "$v" in */.git) v=${v%/.git} ;; esac
            if [ -d "$v" ]; then base=$v; else base=$fb; fi
        else
            base=$fb
        fi
    fi
    [ -d "$base" ] || base=$fb
    dk_set_project "$base" ""
    [ -n "$DK_CFG" ] || return 0

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
$(printf '%s\n' "$cmd" | sed -E "s/\"[^\"]*\"/Q/g; s/'[^']*'/Q/g" | awk '{ gsub(/&&|\|\||;/, "\n"); print }')
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
$(printf '%s\n' "$scan" | grep -oE -e "${DK_RE_ADD}[^;&|]*" | sed -E "s${d}${DK_RE_ADD}${d}${d}")
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
        dk_deny "[dev-kit] nepodporovaný názov súboru $qn (úvodzovky, \\ alebo riadiace znaky) — kontrola ho nevie overiť, premenuj ho."
        return 0
    fi

    # Obsah: pracovný strom pre -a/pathspec/add, inak blob z indexu; zmazaný = "-".
    local map="" so=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$DK_NL$wt$DK_NL" in *"$DK_NL$f$DK_NL"*) ;; *) so="$so$f$DK_NL" ;; esac
    done <<EOF
$tbc
EOF
    if [ -n "$wt" ]; then
        # shellcheck disable=SC2086
        map=$(set -f; IFS=$DK_NL; dk_blobs $wt)
    fi
    if [ -n "$so" ]; then
        printf '%s' "$so" > "$DK_TMP/so.list"
        tr '\n' '\0' < "$DK_TMP/so.list" | xargs -0 git -C "$DK_PROJECT" -c core.quotepath=off ls-files -s -- 2>/dev/null \
            | awk -F'\t' '{ split($1, m, " "); print $2 "\t" m[2] }' > "$DK_TMP/so.idx"
        map="$map$DK_NL$(awk -F'\t' 'FILENAME == ARGV[1] { b[$1] = $2; next } NF { print $0 "\t" (($0 in b) ? b[$0] : "-") }' "$DK_TMP/so.idx" "$DK_TMP/so.list")"
    fi
    map=$(printf '%s\n' "$map" | grep -v '^$' | sort -u)

    local deny="" sfind="" nsec=0
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
        local dfiles_so="" dfiles_wt=""
        while IFS="$DK_TAB" read -r f b; do
            [ -n "$f" ] && [ "$b" != "-" ] || continue
            dk_re_match "$f" "$are" && continue
            case "$DK_NL$wt$DK_NL" in
                *"$DK_NL$f$DK_NL"*) dfiles_wt="$dfiles_wt$f$DK_NL" ;;
                *) dfiles_so="$dfiles_so$f$DK_NL" ;;
            esac
        done <<EOF
$map
EOF
        local dfiles_new=""
        if [ -n "$dfiles_wt" ]; then
            local known
            known=$(printf '%s' "$dfiles_wt" | tr '\n' '\0' | xargs -0 git -C "$DK_PROJECT" -c core.quotepath=off ls-files -- 2>/dev/null)
            while IFS= read -r f; do
                [ -n "$f" ] || continue
                case "$DK_NL$known$DK_NL" in
                    *"$DK_NL$f$DK_NL"*) ;;
                    *) dfiles_new="$dfiles_new$f$DK_NL" ;;
                esac
            done <<EOF
$dfiles_wt
EOF
        fi
        {
            [ -n "$dfiles_so" ] && printf '%s' "$dfiles_so" | tr '\n' '\0' | xargs -0 git -C "$DK_PROJECT" -c core.quotepath=off \
                diff --cached -U0 --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ -- 2>/dev/null
            [ -n "$dfiles_wt" ] && printf '%s' "$dfiles_wt" | tr '\n' '\0' | xargs -0 git -C "$DK_PROJECT" -c core.quotepath=off \
                diff -U0 --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ HEAD -- 2>/dev/null
            if [ -n "$dfiles_new" ]; then
                printf '%s' "$dfiles_new" | while IFS= read -r f; do
                    [ -f "$DK_PROJECT/$f" ] || continue
                    printf 'diff --git a/%s b/%s\n+++ b/%s\n@@ -0,0 +1 @@\n' "$f" "$f" "$f"
                    LC_ALL=C grep -Iq . "$DK_PROJECT/$f" 2>/dev/null && sed 's/^/+/' "$DK_PROJECT/$f"
                done
            fi
        } | awk -v meta="$DK_TMP/sec.meta" -v txt="$DK_TMP/sec.txt" '
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
            deny="$deny[dev-kit] commit zablokovaný — tajomstvo alebo zakázaný súbor ($nsec):$DK_NL$(printf '%s' "$sfind" | head -n 8)$DK_NL"
            [ "$nsec" -gt 8 ] && deny="${deny}… ďalšie nálezy: $((nsec - 8))$DK_NL"
            deny="${deny}Hodnotu nevypisuj ani sám neodstraňuj — nahlás používateľovi súbor:riadok a počkaj na jeho rozhodnutie (súbor z commitu: git restore --staged <súbor>; falošný poplach: secrets.allow v .claude/devkit.json).$DK_NL"
        fi
        if [ "$nsec" -gt 0 ] || [ "$forceall" = 1 ]; then
            dk_log pre-bash secrets deny "" $(( $(dk_ms) - t0 ))
        fi
    fi

    # 2. Commit gate. Kľúč obsahu (hash kódových blobov) zoskupí pokusy o ten istý commit pre /dev:stats.
    if [ "$gate_on" = 1 ]; then
        local code="" pmode="" pblobs="" bad="" nbad=0 fullg="" e gmsg="" ckey="" rerun=0
        if [ "$partial" = 1 ]; then
            gmsg="[dev-kit] čiastočný stage (git add -p/-i/-e) v tom istom príkaze ako commit sa nedá overiť — stage-uj zvlášť, potom commit zopakuj.$DK_NL"
        fi
        while IFS="$DK_TAB" read -r f b; do
            [ -n "$f" ] || continue
            e=$(dk_ext "$f")
            [ -n "$e" ] || continue
            case ",$gext," in *",$e,"*) code="$code$f$DK_TAB$b$DK_NL" ;; esac
        done <<EOF
$map
EOF
        if [ -n "$code" ]; then
            ckey=$(printf '%s' "$code" | git hash-object --stdin 2>/dev/null | cut -c1-12)
            if [ -f "$DK_PDATA/pass.json" ]; then
                local pout
                pout=$(jq -r '"M\u001f\(.mode // "")", ((.blobs // {}) | to_entries[] | "B\u001f\(.key)\u001f\(.value)")' "$DK_PDATA/pass.json" 2>/dev/null)
                while IFS=$DK_US read -r tag a b; do
                    case "$tag" in
                        M) pmode=$a ;;
                        B) pblobs="$pblobs$a$DK_TAB$b$DK_NL" ;;
                    esac
                done <<EOF
$pout
EOF
            fi
            local note
            while IFS="$DK_TAB" read -r f b; do
                [ -n "$f" ] || continue
                case "$DK_NL$pblobs" in
                    *"$DK_NL$f$DK_TAB$b$DK_NL"*) ;;
                    *)
                        nbad=$((nbad + 1))
                        note=""
                        # check.sh hashuje pracovný strom; iný obsah v indexe by ďalší /dev:check neopravil.
                        if [ "$nbad" -le 8 ] && [ "$b" != "-" ]; then
                            case "$DK_NL$so" in
                                *"$DK_NL$f$DK_NL"*)
                                    [ "$(dk_blobs "$f" | cut -f2)" = "$b" ] || note=" (index ≠ pracovný strom → git add $f)" ;;
                            esac
                        fi
                        bad="$bad- $f$note$DK_NL"
                        ;;
                esac
                if [ -z "$fullg" ] && [ -n "$fullw" ]; then fullg=$(dk_first_glob "$f" "$fullw"); fi
            done <<EOF
$code
EOF
            if [ "$nbad" -gt 0 ]; then
                gmsg="$gmsg[dev-kit] commit gate: $(dk_plural "$nbad" súbor súbory súborov) bez PASS z /dev:check pre presne tento obsah:$DK_NL$(printf '%s' "$bad" | head -n 8)$DK_NL"
                [ "$nbad" -gt 8 ] && gmsg="${gmsg}… ďalšie súbory: $((nbad - 8))$DK_NL"
                rerun=1
            fi
            if [ -n "$fullg" ] && [ "$pmode" != full ]; then
                gmsg="$gmsg[dev-kit] commit gate: zmena v $fullg vyžaduje /dev:check --full$DK_NL"
                rerun=1
            fi
        fi
        if [ -n "$gmsg" ]; then
            if [ "$rerun" = 1 ]; then
                cmode=--auto; [ -n "$fullg" ] && cmode=--full
                gmsg="${gmsg}Spusti kontrolu: bash \"$DK_SCRIPTS/check.sh\" $cmode --project \"$DK_PROJECT\" (to isté robí /dev:check), pri PASS commit zopakuj."
            fi
            deny="$deny$gmsg"
            dk_log pre-bash commitGate deny "$ckey" $(( $(dk_ms) - t0 ))
        elif [ -n "$code" ]; then
            dk_log pre-bash commitGate pass "$ckey" $(( $(dk_ms) - t0 ))
        fi
    fi

    if [ -n "$deny" ]; then
        dk_deny "$(printf '%s' "$deny" | grep -v '^$' | head -n 20)"
    fi
    return 0
}

dk_main
rc=$?
[ "$rc" = 0 ] || dk_err "pre-bash: neočakávaný návratový kód $rc"
exit 0
