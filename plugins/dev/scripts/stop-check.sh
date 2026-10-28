#!/usr/bin/env bash
# Stop: pripomienky (pairs, zmazané testy) raz za session, potom check.sh --stop nad kódom session + guardy v pridaných riadkoch.
# Infra (kontajner dole, krok sa nedal spustiť, nič nebežalo) nikdy neblokuje; rovnaký padajúci stav blokuje najviac 2×, potom len upozorní.
. "$(dirname "$0")/lib.sh" || exit 0
DK_HOOK=stop-check

# Pripomienky bez chyby: additionalContext (prepis ich ukáže ako Stop hook feedback, nie ako chybu hooku).
dk_remind() {
    [ -n "$1" ] || return 0
    jq -nc --arg c "[dev-kit] pripomienka pred koncom ťahu:$DK_NL$(printf '%s' "$1" | head -n 19)" \
        '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: $c}}'
}

dk_main() {
    dk_init
    [ "$DK_HAS_JQ" = 1 ] || return 0
    [ -n "$DK_CFG" ] || return 0
    local t0 tag a b c d on=true guards="" pairs="" files hash
    t0=$(dk_ms)
    dk_cfg_read '"S\u001f\(if .stopCheck == false then "false" else "true" end)",
        ((.guards // [])[] | "G\u001f\(.id|s)\u001f\((.ext // []) | join(","))\u001f\(.pattern|s)\u001f\(.message|s)"),
        ((.pairs // [])[] | "P\u001f\(.id|s)\u001f\(.when|s)\u001f\(.unless|s)\u001f\(.say|s)")' || return 0
    while IFS=$DK_US read -r tag a b c d; do
        case "$tag" in
            S) on=$a ;;
            G) guards="$guards$tag$DK_US$a$DK_US$b$DK_US$c$DK_US$d$DK_NL" ;;
            P) pairs="$pairs$a$DK_US$b$DK_US$c$DK_US$d$DK_NL" ;;
        esac
    done <<EOF
$DK_CFG_OUT
EOF
    [ "$on" = true ] || return 0
    dk_rule_on stopCheck || return 0

    # 1. Pripomienky — raz za session, nad všetkými súbormi session (aj nekódovými), pred skratkami nižšie.
    local rem="" done_f="$DK_PDATA/pairs-$DK_SESSION.done" sf changed="" chg_loaded=0 id when unless say hit f re
    sf=$(dk_session_file)
    if [ -f "$sf" ]; then
        while IFS=$DK_US read -r id when unless say; do
            [ -n "$id" ] && [ -n "$when" ] && [ -n "$say" ] || continue
            dk_rule_on "pair:$id" || continue
            [ -f "$done_f" ] && grep -Fxq -- "$id" "$done_f" 2>/dev/null && continue
            hit=0
            re=$(dk_glob_re "$when")
            while IFS= read -r f; do
                [ -n "$f" ] || continue
                if [[ $f =~ $re ]]; then hit=1; break; fi
            done < "$sf"
            [ "$hit" = 1 ] || continue
            if [ -n "$unless" ]; then
                if [ "$chg_loaded" = 0 ]; then changed=$(dk_changed_files); chg_loaded=1; fi
                hit=0
                re=$(dk_glob_re "$unless")
                while IFS= read -r f; do
                    [ -n "$f" ] || continue
                    if [[ $f =~ $re ]]; then hit=1; break; fi
                done <<EOF2
$changed
EOF2
                [ "$hit" = 0 ] || continue
            fi
            rem="$rem- [pair:$id] $say$DK_NL"
            printf '%s\n' "$id" 2>/dev/null >> "$done_f"
            dk_log stop-check "pair:$id" warn
        done <<EOF
$pairs
EOF
        # Zmazané test metódy a testovacie súbory (diff voči HEAD).
        if dk_rule_on testRemoved; then
            local df rm_n add_n key name
            re=$(dk_globs_re "tests/**$DK_NL**/*Test.php$DK_NL**/test_*.py$DK_NL**/*_test.py")
            while IFS= read -r f; do
                [ -n "$f" ] || continue
                dk_re_match "$f" "$re" || continue
                if [ ! -e "$DK_PROJECT/$f" ]; then
                    dk_git cat-file -e "HEAD:./$f" 2>/dev/null || continue
                    key="testRemoved:$f:-"
                    [ -f "$done_f" ] && grep -Fxq -- "$key" "$done_f" 2>/dev/null && continue
                    rem="$rem- [testRemoved] $f: zmazaný testovací súbor — over s používateľom, či je to zámer$DK_NL"
                    printf '%s\n' "$key" 2>/dev/null >> "$done_f"
                    dk_log stop-check testRemoved warn "$f"
                    continue
                fi
                df=$(dk_git diff -U0 --no-color --no-ext-diff HEAD -- "$f" 2>/dev/null)
                [ -n "$df" ] || continue
                rm_n=$(printf '%s\n' "$df" | sed -nE 's/^-[[:space:]]*((public|protected|private|static|final|abstract)[[:space:]]+)*function[[:space:]]+(test[A-Za-z0-9_]*).*/\3/p; s/^-[[:space:]]*(async[[:space:]]+)?def[[:space:]]+(test_[A-Za-z0-9_]*).*/\2/p' | sort -u)
                [ -n "$rm_n" ] || continue
                add_n=$(printf '%s\n' "$df" | sed -nE 's/^\+[[:space:]]*((public|protected|private|static|final|abstract)[[:space:]]+)*function[[:space:]]+(test[A-Za-z0-9_]*).*/\3/p; s/^\+[[:space:]]*(async[[:space:]]+)?def[[:space:]]+(test_[A-Za-z0-9_]*).*/\2/p' | sort -u)
                while IFS= read -r name; do
                    [ -n "$name" ] || continue
                    case "$DK_NL$add_n$DK_NL" in *"$DK_NL$name$DK_NL"*) continue ;; esac
                    key="testRemoved:$f:$name"
                    [ -f "$done_f" ] && grep -Fxq -- "$key" "$done_f" 2>/dev/null && continue
                    rem="$rem- [testRemoved] $f: zmazaná test metóda $name — over s používateľom, či je to zámer$DK_NL"
                    printf '%s\n' "$key" 2>/dev/null >> "$done_f"
                    dk_log stop-check testRemoved warn "$f"
                done <<EOF2
$rm_n
EOF2
            done < "$sf"
        fi
    fi

    files=$(dk_session_code_files)
    if [ -z "$files" ]; then dk_remind "$rem"; return 0; fi
    hash=$(set -f; IFS=$DK_NL; dk_hash_files $files)

    local phash="" pres="" pfails=0 pfh="" stf
    stf=$(dk_stop_file)
    if [ -f "$stf" ]; then
        local out
        out=$(jq -r '[.hash // "", .result // "", (.fails // 0 | tostring), .failHash // ""] | join("\u001f")' "$stf" 2>/dev/null)
        IFS=$DK_US read -r phash pres pfails pfh <<EOF
$out
EOF
        case "$pfails" in ''|*[!0-9]*) pfails=0 ;; esac
    fi
    if [ "$hash" = "$phash" ] && { [ "$pres" = PASS ] || [ "$pres" = PARTIAL ]; }; then
        dk_log stop-check stopCheck skip "" $(( $(dk_ms) - t0 ))
        dk_remind "$rem"
        return 0
    fi
    if [ "$hash" = "$pfh" ] && [ "$pres" = FAIL ] && [ "$pfails" -ge 3 ]; then
        dk_remind "$rem"
        return 0
    fi

    # 2. check.sh --stop
    local cout crc logp=""
    cout=$(cd "$DK_PROJECT" && bash "$DK_SCRIPTS/check.sh" --stop --session "$DK_SESSION" --project "$DK_PROJECT" </dev/null 2>&1)
    crc=$?
    logp=$(printf '%s\n' "$cout" | sed -n 's/^log: //p' | tail -n 1)
    if [ "$crc" = 3 ] || [ "$crc" -gt 4 ]; then
        dk_err "check.sh --stop exit $crc: $(printf '%s' "$cout" | head -n 1)"
    fi
    if [ "$crc" = 4 ] && printf '%s\n' "$cout" | head -n 1 | grep -q ': PARTIAL'; then
        rem="$rem- [partial] tieto kroky sa nedali spustiť — netvrď, že sú overené:$DK_NL$(printf '%s\n' "$cout" | grep '^! ' | head -n 5 | sed 's/^/  /')$DK_NL"
    fi

    # 3. Guardy (súbory mohli byť zmenené aj cez Bash).
    local gfind="" ng=0 r
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        while IFS=$DK_US read -r r a; do
            [ -n "$r" ] || continue
            if [ "$r" = more ]; then ng=$((ng + a)); continue; fi
            gfind="$gfind$a$DK_NL"; ng=$((ng + 1))
            dk_log stop-check "$r" block "$f"
        done <<EOF2
$(dk_guard_scan "$f" "$(dk__added_spec "$f")" "$guards")
EOF2
    done <<EOF
$files
EOF

    local fail=0 ms fails reason extra="" room
    [ "$crc" = 1 ] && fail=1
    [ "$ng" -gt 0 ] && fail=1
    ms=$(( $(dk_ms) - t0 ))

    if [ "$fail" = 1 ]; then
        fails=1
        if [ "$hash" = "$pfh" ] && [ "$pres" = FAIL ]; then fails=$((pfails + 1)); fi
        jq -n --arg h "$hash" --argjson t "$(dk_now)" --argjson n "$fails" \
            '{hash: $h, time: $t, fails: $n, failHash: $h, result: "FAIL"}' \
            2>/dev/null > "$stf.tmp.$$" && mv "$stf.tmp.$$" "$stf"
        if [ "$fails" -ge 3 ]; then
            dk_log stop-check stopCheck warn "" "$ms"
            local sm="[dev-kit] kontrola stále padá (3×) — blokovanie vypnuté pre tento stav, pozri ${logp:-$DK_PDATA/logs}; vypnutie: disabledRules stopCheck"
            if [ -n "$rem" ]; then
                jq -nc --arg s "$sm" --arg r "[dev-kit] pripomienka pred koncom ťahu:$DK_NL$(printf '%s' "$rem" | head -n 19)" \
                    '{systemMessage: $s, hookSpecificOutput: {hookEventName: "Stop", additionalContext: $r}}'
            else
                jq -nc --arg s "$sm" '{systemMessage: $s}'
            fi
            return 0
        fi
        reason="[dev-kit] Stop kontrola zlyhala (blok $fails/2) — oprav, čo spôsobili zmeny tejto session; zlyhanie mimo nich neopravuj, nahlás ho používateľovi (knownFailures alebo disabledRules step:<id>); ak čakáš na súhlas používateľa s opravou, ukonči ťah jednou vetou so stavom.$DK_NL"
        if [ "$ng" -gt 0 ]; then
            extra="${extra}guardy v pridaných riadkoch:$DK_NL$(printf '%s' "$gfind" | head -n 6)$DK_NL"
        fi
        [ -n "$rem" ] && extra="${extra}pripomienky:$DK_NL$rem"
        # Pripomienky sa už nezopakujú (sú v pairs-*.done) — výpis kontroly sa skráti skôr než ony.
        room=$((18 - $(printf '%s' "$extra" | grep -c .)))
        [ "$room" -lt 3 ] && room=3
        if [ "$crc" = 1 ]; then
            reason="$reason$(printf '%s\n' "$cout" | grep -v '^log: ' | grep -v '^$' | head -n "$room")$DK_NL"
        fi
        reason=$(printf '%s\n%s' "$reason" "$extra" | grep -v '^$' | head -n 19)
        [ -n "$logp" ] && reason="$reason${DK_NL}log: $logp"
        dk_log stop-check stopCheck block "" "$ms"
        jq -nc --arg r "$reason" '{decision: "block", reason: $r}'
        return 0
    fi

    dk_log stop-check stopCheck pass "" "$ms"
    dk_remind "$rem"
    return 0
}

dk_main
rc=$?
[ "$rc" = 0 ] || dk_err "stop-check: neočakávaný návratový kód $rc"
exit 0
