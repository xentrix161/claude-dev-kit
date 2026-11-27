#!/usr/bin/env bash
# Podklad pre plán project-init. Projektové hooky nespúšťa.
set -eu
. "$(dirname "$0")/lib.sh"
root=$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null) || { echo 'Mimo pracovného stromu Gitu.'; exit 0; }
cd -- "$root"
DK_DATA=${DEVKIT_DATA:-$HOME/.claude/dev-kit}
dk_set_project "$root" "" read-only

hook=$(git rev-parse --git-path hooks/pre-commit)
if [ -f "$hook" ] && [ -x "$hook" ]; then
    printf 'Git pre-commit: %s\n' "$hook"
fi
# Novší Git podporuje aj pomenované hooky z konfigurácie.
if named=$(LC_ALL=C git hook list --show-scope pre-commit 2>/dev/null); then
    printf '%s\n' "$named" | awk -F '\t' 'NF == 2 && $1 != "disabled" {print "Git pre-commit (" $1 "): " $2}'
fi

if [ -n "$DK_CFG" ]; then
    state=$(jq -esr 'if length != 1 or (.[0] | type != "object" or .version != 1 or (.stack | type != "string"))
        then error("config") else .[0] end |
        if .commitGate == false or (.disabledRules // [] | index("commitGate")) != null then "vypnutá"
        elif .commitGate.enabled == false then "vypnutá" else "zapnutá" end' "$DK_CFG" 2>/dev/null) || state=neoverená
    printf 'Kontrola kitu v konfigurácii: %s (%s)\n' "$state" "$DK_CFG"
    if [ "$state" = zapnutá ] && native=$(jq -er '.commitGate.nativeHook? // empty' "$DK_CFG"); then
        if dk_native_pre_commit "$native"; then echo 'Bežný commit: povinný projektový krok vykoná Git.'
        elif [ "$?" = 2 ]; then echo 'Bežný commit je zablokovaný: oprav povinný náhradný krok pre nativeHook.'
        else echo 'Bežný commit: výsledok projektového kroku musí overiť kit.'; fi
    fi
elif [ -e .claude/devkit.json ] || [ -L .claude/devkit.json ]; then
    echo 'Kontrola kitu v konfigurácii: neoverená (.claude/devkit.json)'
else
    echo 'Projekt zatiaľ nemá konfiguráciu kitu.'
fi
