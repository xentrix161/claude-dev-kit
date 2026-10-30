#!/usr/bin/env bash
# PreCompact: stav session ako fakty pre súhrn kompakcie (≤ 10 riadkov). Plain text na stdout — Claude Code ho
# pridá k pokynom súhrnu; additionalContext PreCompact nepozná a systemMessage zahodí (SPEC §4.10).
. "$(dirname "$0")/lib.sh" || exit 0
DK_HOOK=pre-compact

dk_when() { # epoch → "30.10. 14:05" (lokálny čas; súhrn môže byť čítaný aj na druhý deň)
    jq -nr --argjson t "${1:-0}" '$t | strflocaltime("%d.%m. %H:%M")' 2>/dev/null || printf '?'
}

dk_main() {
    dk_init
    [ "$DK_HAS_JQ" = 1 ] || return 0
    [ -n "$DK_CFG" ] || return 0
    dk_cfg_read '"T\u001f\(.testLock.ttlHours // 6 | s)"' || return 0
    local tag a ttl=6 facts="" sf n list out t r m ht htitle hpath now
    while IFS=$DK_US read -r tag a; do
        case "$tag" in T) ttl=$a ;; esac
    done <<EOF
$DK_CFG_OUT
EOF
    now=$(dk_now)

    sf=$(dk_session_file)
    if [ -s "$sf" ]; then
        n=$(grep -c . "$sf")
        list=$(grep -v '^$' "$sf" | head -n 8 | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')
        [ "$n" -le 8 ] || list="$list · … ďalšie: $((n - 8))"
        [ "$n" = 0 ] || facts="${facts}- súbory session ($n): $list$DK_NL"
    fi

    if [ -f "$(dk_stop_file)" ]; then
        out=$(jq -r '[.result // "", (.time // 0 | tostring)] | join("\u001f")' "$(dk_stop_file)" 2>/dev/null)
        IFS=$DK_US read -r r t <<EOF
$out
EOF
        t=${t%%.*}
        case "$t" in ''|*[!0-9]*) t=0 ;; esac
        case "$r" in PASS|PARTIAL|FAIL) facts="${facts}- posledná Stop kontrola: $r, $(dk_when "$t")$DK_NL" ;; esac
    fi

    if [ -f "$DK_PDATA/pass.json" ]; then
        out=$(jq -r '[.mode // "", (.time // 0 | tostring)] | join("\u001f")' "$DK_PDATA/pass.json" 2>/dev/null)
        IFS=$DK_US read -r m t <<EOF
$out
EOF
        t=${t%%.*}
        case "$t" in ''|*[!0-9]*) t=0 ;; esac
        case "$m" in quick|full) facts="${facts}- posledný PASS /dev:check: $m, $(dk_when "$t")$DK_NL" ;; esac
    fi

    if [ -f "$DK_PDATA/test-lock.json" ] && dk_lock_read "$ttl"; then
        list=$(printf '%s' "$DK_LOCK_FILES" | grep -v '^$' | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')
        facts="${facts}- zamknutý test (/dev:fix): $list (do $(dk_when "$DK_LOCK_UNTIL"))$DK_NL"
    fi

    # Handoff za rovnakej podmienky ako úvodná karta (< 24 h).
    if [ -f "$DK_PDATA/last-handoff.json" ]; then
        out=$(jq -r '[(.time // 0 | tostring), .title // "", .path // ""] | map(gsub("[\n\r\u001f]"; " ")) | join("\u001f")' \
            "$DK_PDATA/last-handoff.json" 2>/dev/null)
        IFS=$DK_US read -r ht htitle hpath <<EOF
$out
EOF
        ht=${ht%%.*}
        case "$ht" in ''|*[!0-9]*) ht=0 ;; esac
        if [ -n "$hpath" ] && [ $((now - ht)) -lt 86400 ]; then
            facts="${facts}- posledný handoff: ${htitle:-${hpath##*/}}, $(dk_when "$ht") → $hpath$DK_NL"
        fi
    fi

    [ -n "$facts" ] || return 0
    printf '[dev-kit] stav session pred kompakciou (fakty pre súhrn):\n%s' "$facts" | head -n 10
    return 0
}

dk_main
rc=$?
[ "$rc" = 0 ] || dk_err "pre-compact: neočakávaný návratový kód $rc"
exit 0
