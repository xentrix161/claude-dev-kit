#!/usr/bin/env bash
# Pripojí existujúcu kontrolu commitu do osobných hookov Codexu.
set -eu
umask 077
kit=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)
config_dir=${CODEX_HOME:-$HOME/.codex}
file="$config_dir/hooks.json"
mkdir -p -- "$config_dir"
lock="$config_dir/.dev-kit-hook-install"
mkdir -- "$lock" || { echo 'Inštaláciu hooku už používa iný proces alebo zostal zámok.' >&2; exit 1; }
trap 'rm -f -- "$lock/original" "$lock/new"; rmdir -- "$lock"' EXIT
trap 'exit 1' HUP INT TERM

if [ -L "$file" ] || { [ -e "$file" ] && [ ! -f "$file" ]; }; then
    echo 'Osobné hooks.json musí byť bežný súbor. Over jeho cieľ.' >&2
    exit 1
fi
existed=0
if [ -f "$file" ]; then
    existed=1
    cp -- "$file" "$lock/original"
else
    printf '{}\n' > "$lock/original"
fi

jq -es --arg path "$kit/plugins/dev/scripts/pre-bash.sh" '
    if length == 1 and (.[0] | type == "object") then .[0] else error("neplatné hooks.json") end
    | ("bash " + ($path | @sh)) as $cmd
    | "[dev-kit] Kontrola commitu" as $label
    | {matcher:"^Bash$", hooks:[{type:"command", command:$cmd, timeout:60, statusMessage:$label}]} as $group
    | if ((.hooks | type) | IN("null", "object") | not)
        or ((.hooks.PreToolUse | type) | IN("null", "array") | not) then error("neplatné PreToolUse")
      elif ([.hooks.PreToolUse[]?.hooks[]? | select(.command == $cmd or .statusMessage == $label)] | length) > 1
        then error("kontrola commitu je zaregistrovaná viackrát, skontroluj osobné hooky")
      elif any(.hooks.PreToolUse[]?; .matcher == $group.matcher and (.hooks | index($group.hooks[0])) and (del(.hooks) == ($group | del(.hooks)))) then .
      elif any(.hooks.PreToolUse[]?.hooks[]?; .command == $cmd or .statusMessage == $label)
        then error("kontrola commitu už má inú registráciu, skontroluj jej cestu a nastavenia")
      else .hooks.PreToolUse += [$group] end
' "$lock/original" > "$lock/new"

if [ "$existed" = 1 ]; then
    cmp -s "$file" "$lock/original" || { echo 'Osobné hooky sa počas inštalácie zmenili.' >&2; exit 1; }
    if jq -e -s '.[0] == .[1]' "$lock/original" "$lock/new" >/dev/null; then
        echo '[dev-kit] Hook commitu už je zaregistrovaný.'
        exit 0
    fi
    backup=$(mktemp "$config_dir/hooks.json.dev-kit-backup.XXXXXX")
    cp -- "$lock/original" "$backup"
    echo "[dev-kit] Záloha pôvodných hookov: $backup"
    mv -f -- "$lock/new" "$file"
else
    ln -- "$lock/new" "$file"
fi
echo '[dev-kit] Hook commitu je zaregistrovaný. V novom Codexe ho skontroluj a potvrď cez /hooks.'
