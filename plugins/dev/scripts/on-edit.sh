#!/usr/bin/env bash
# PostToolUse (Edit|Write|MultiEdit): lint podľa prípony + guardy a tajomstvá v pridaných riadkoch. Nález → stderr + exit 2.
. "$(dirname "$0")/lib.sh" || exit 0
DK_HOOK=on-edit

dk_main() {
    dk_init
    [ "$DK_HAS_JQ" = 1 ] || return 0
    [ -n "$DK_CFG" ] || return 0
    [ -n "$DK_FILE" ] || return 0
    local t0 rel ext tag a b c d lints="" guards="" only=false added="" addedset=0 pats="" allow="" forbid=""
    local findings="" rules="" n=0 more=0 cmd out rc kept q map esc
    t0=$(dk_ms)
    rel=$(dk_rel "$DK_FILE")
    [ -n "$rel" ] || return 0
    case "$rel" in .git/*) return 0 ;; esac
    dk_session_add "$rel"
    [ -f "$DK_PROJECT/$rel" ] || return 0
    ext=$(dk_ext "$rel")

    dk_cfg_read '"O\u001f\(.lintChangedLinesOnly // false | s)",
        (if $ext == "" then empty else ((.lint // {})[$ext] // [] | .[] | "L\u001f\(.|s)") end),
        ((.guards // [])[] | "G\u001f\(.id|s)\u001f\((.ext // []) | join(","))\u001f\(.pattern|s)\u001f\(.message|s)"),
        ((.secrets.patterns // [])[] | "P\u001f\(.|s)"),
        ((.secrets.allow // [])[] | "S\u001f\(.|s)"),
        ((.secrets.forbidFiles // [])[] | "F\u001f\(.|s)")' \
        --arg ext "$ext" || return 0
    while IFS=$DK_US read -r tag a b c d; do
        case "$tag" in
            O) only=$a ;;
            L) [ -n "$a" ] && lints="$lints$a$DK_NL" ;;
            G) guards="$guards$tag$DK_US$a$DK_US$b$DK_US$c$DK_US$d$DK_NL" ;;
            P) pats="$pats$a$DK_NL" ;;
            S) allow="$allow$a$DK_NL" ;;
            F) forbid="$forbid$a$DK_NL" ;;
        esac
    done <<EOF
$DK_CFG_OUT
EOF

    # Lint (len keď beží kontajner, resp. na hoste).
    if [ -n "$lints" ] && dk_rule_on "lint:$ext" && dk_container_ok; then
        DK_WD=""
        if [ -n "$DK_CONTAINER" ]; then DK_WD=$(dk_workdir 2>/dev/null) || lints=""; fi
        # Názov začínajúci '-' by nástroj čítal ako prepínač.
        case "$rel" in -*) q=$(dk_shq "./$rel") ;; *) q=$(dk_shq "$rel") ;; esac
        esc=$(printf '\033')
        while IFS= read -r cmd; do
            [ -n "$cmd" ] || continue
            cmd=${cmd//\{file\}/"$q"}
            out=$(dk_exec "$cmd")
            rc=$?
            [ "$rc" = 0 ] && continue
            if [ "$rc" -ge 125 ] && [ "$rc" -le 127 ]; then
                dk_err "lint '$cmd' sa nedá spustiť (exit $rc)"
                dk_log on-edit "lint:$ext" skip "$rel"
                continue
            fi
            dk_tmpdir
            printf '%s\n' "$out" | LC_ALL=C sed "s/$esc\[[0-9;]*[A-Za-z]//g" > "$DK_TMP/lint.out"
            if [ "$only" = true ]; then
                if [ "$addedset" = 0 ]; then added=$(dk__added_spec "$rel"); addedset=1; fi
                map="$DK_TMP/lint.map"
                if [ "$added" = "*" ]; then
                    printf '%s\t*\n' "$rel" > "$map"
                else
                    printf '%s\n' "$added" | awk -v r="$rel" 'NF { print r "\t" $0 }' > "$map"
                fi
                kept=$(dk_filter_changed "$DK_TMP/lint.out" "$map")
            else
                kept=$(grep -v '^[[:space:]]*$' "$DK_TMP/lint.out")
            fi
            [ -n "$kept" ] || continue
            if ! printf '%s\n' "$kept" | grep -q ':[0-9]' && printf '%s\n' "$kept" | grep -Eq "$DK_RE_INFRA"; then
                dk_err "lint '$cmd': $(printf '%s' "$kept" | head -n 1)"
                dk_log on-edit "lint:$ext" skip "$rel"
                continue
            fi
            kept=$(printf '%s\n' "$kept" | dk_strip_paths)
            findings="$findings$kept$DK_NL"
            case "$DK_NL$rules" in *"${DK_NL}lint:$ext$DK_NL"*) ;; *) rules="${rules}lint:$ext$DK_NL" ;; esac
        done <<EOF
$lints
EOF
    fi

    # Guardy (vždy na hoste, len pridané riadky).
    if [ -n "$guards" ]; then
        if [ "$addedset" = 0 ]; then added=$(dk__added_spec "$rel"); addedset=1; fi
        while IFS=$DK_US read -r a b; do
            [ -n "$a" ] || continue
            if [ "$a" = more ]; then more=$((more + b)); continue; fi
            findings="$findings$b$DK_NL"
            case "$DK_NL$rules" in *"$DK_NL$a$DK_NL"*) ;; *) rules="$rules$a$DK_NL" ;; esac
        done <<EOF
$(dk_guard_scan "$rel" "$added" "$guards")
EOF
    fi

    # Tajomstvá v pridaných riadkoch; allow, forbidFiles a súbory ignorované gitom (lokálne configy) sa preskočia.
    if dk_rule_on secrets && ! dk_re_match "$rel" "$(dk_globs_re "$allow")" && ! dk_re_match "$rel" "$(dk_globs_re "$forbid")" \
        && ! dk_git check-ignore -q -- "$rel" 2>/dev/null; then
        if [ "$addedset" = 0 ]; then added=$(dk__added_spec "$rel"); addedset=1; fi
        while IFS=$DK_US read -r a b; do
            [ -n "$a" ] || continue
            findings="$findings$rel:$a — možné tajomstvo ($b) — hodnotu nevypisuj, upozorni používateľa [secrets]$DK_NL"
            case "$DK_NL$rules" in *"${DK_NL}secrets$DK_NL"*) ;; *) rules="${rules}secrets$DK_NL" ;; esac
        done <<EOF
$(dk_secret_scan "$rel" "$added" "$DK_SECRET_DEFAULTS$DK_NL$pats")
EOF
    fi

    local ms first=1 r
    ms=$(( $(dk_ms) - t0 ))
    if [ -z "$rules" ]; then
        dk_log on-edit all pass "$rel" "$ms"
        return 0
    fi
    while IFS= read -r r; do
        [ -n "$r" ] || continue
        if [ "$first" = 1 ]; then dk_log on-edit "$r" block "$rel" "$ms"; first=0; else dk_log on-edit "$r" block "$rel"; fi
    done <<EOF
$rules
EOF
    findings=$(printf '%s' "$findings" | grep -v '^[[:space:]]*$')
    n=$(( $(printf '%s\n' "$findings" | grep -c .) + more ))
    {
        pron=ich; [ "$n" = 1 ] && pron=ho
        printf '[dev-kit] %s: %s [%s] — oprav %s; falošný poplach nahlás používateľovi s id pravidla (vypnutie: disabledRules v .claude/devkit.json)\n' \
            "$rel" "$(dk_plural "$n" nález nálezy nálezov)" "$(printf '%s' "$rules" | grep -v '^$' | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')" "$pron"
        printf '%s\n' "$findings" | head -n 15
        [ "$n" -gt 15 ] && printf '… ďalšie nálezy: %s\n' $((n - 15))
    } >&2
    return 2
}

dk_main
rc=$?
case "$rc" in
    0|2) exit "$rc" ;;
    *) dk_err "on-edit: neočakávaný návratový kód $rc"; exit 0 ;;
esac
