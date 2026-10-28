#!/usr/bin/env bash
# PreToolUse (Edit|Write|MultiEdit): agenti kitu len do svojej pamäte (deny), zamknutý test počas /dev:fix (deny),
# commitnutá migrácia (ask).
. "$(dirname "$0")/lib.sh" || exit 0
DK_HOOK=pre-edit

dk_decide() { # <deny|ask> <reason>
    jq -nc --arg d "$1" --arg r "$2" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
}

dk_main() {
    dk_init
    [ "$DK_HAS_JQ" = 1 ] || return 0
    # Platí aj bez devkit.json: agenti kitu majú Write/Edit len kvôli pamäti (memory: user).
    case "$DK_AGENT" in
        dev:ecc-*)
            local mem="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agent-memory/"
            case "$DK_FILE" in
                *..*) ;;
                "$mem"*) return 0 ;;
            esac
            dk_log pre-edit agentReadOnly deny "${DK_FILE:-?}"
            dk_decide deny "[dev-kit] agent $DK_AGENT je len na čítanie — zapisovať smie iba do svojej pamäte v $mem. Opravu navrhni v odpovedi."
            return 0
            ;;
    esac
    [ -n "$DK_CFG" ] || return 0
    [ -n "$DK_FILE" ] || return 0
    local t0 rel tag a ttl=6 migs=""
    t0=$(dk_ms)
    rel=$(dk_rel "$DK_FILE")
    [ -n "$rel" ] || return 0

    dk_cfg_read '"T\u001f\(.testLock.ttlHours // 6 | s)", ((.migrations.paths // [])[] | "M\u001f\(.|s)")' || return 0
    while IFS=$DK_US read -r tag a; do
        case "$tag" in
            T) ttl=$a ;;
            M) [ -n "$a" ] && migs="$migs$a$DK_NL" ;;
        esac
    done <<EOF
$DK_CFG_OUT
EOF

    # Bez ohľadu na veľkosť písmen: APFS je case-insensitive a Tests/FooTest.php je ten istý súbor.
    if [ -f "$DK_PDATA/test-lock.json" ] && dk_rule_on testLock && dk_lock_read "$ttl"; then
        case "$DK_NL$(printf '%s' "$DK_LOCK_FILES" | tr '[:upper:]' '[:lower:]')$DK_NL" in
            *"$DK_NL$(printf '%s' "$rel" | tr '[:upper:]' '[:lower:]')$DK_NL"*)
                dk_log pre-edit testLock deny "$rel" $(( $(dk_ms) - t0 ))
                dk_decide deny "[dev-kit] Test $rel je zamknutý počas /dev:fix — oprav kód, nie test. Odomknúť môže používateľ: /dev:fix --unlock"
                return 0
                ;;
        esac
    fi

    if [ -n "$migs" ] && dk_rule_on migrations \
        && dk_first_glob "$(printf '%s' "$rel" | tr '[:upper:]' '[:lower:]')" "$(printf '%s' "$migs" | tr '[:upper:]' '[:lower:]')" >/dev/null; then
        local mrel=$rel real
        # Iná veľkosť písmen (APFS): skutočný názov z indexu, ak ide o ten istý súbor.
        if ! dk_git cat-file -e "HEAD:./$rel" 2>/dev/null; then
            real=$(dk_git ls-files -- ":(icase,literal)$rel" 2>/dev/null | head -n 1)
            if [ -n "$real" ] && [ "$real" != "$rel" ] && [ "$DK_PROJECT/$rel" -ef "$DK_PROJECT/$real" ]; then mrel=$real; fi
        fi
        if dk_first_glob "$mrel" "$migs" >/dev/null && dk_git cat-file -e "HEAD:./$mrel" 2>/dev/null; then
            dk_log pre-edit migrations ask "$mrel" $(( $(dk_ms) - t0 ))
            dk_decide ask "[dev-kit] $mrel je už commitnutá migrácia — aplikované migrácie sa neupravujú, vytvor novú. Pokračovať?"
            return 0
        fi
    fi
    return 0
}

dk_main
rc=$?
[ "$rc" = 0 ] || dk_err "pre-edit: neočakávaný návratový kód $rc"
exit 0
