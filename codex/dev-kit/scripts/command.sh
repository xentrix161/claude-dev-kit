#!/usr/bin/env bash
# Sprístupní jeden príkaz z tej istej pracovnej kópie ako tento skill.
set -eu
script_dir=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
plugin=$(cd -- "$script_dir/../../../plugins/dev" && pwd -P)

is_command() {
    awk 'NR == 1 && $0 != "---" { exit }
        NR > 1 && $0 == "---" { closed = 1; exit }
        $0 == "disable-model-invocation: true" { manual = 1 }
        END { exit !(closed && manual) }' "$1"
}

list_commands() {
    local file dir
    for file in "$plugin"/skills/*/SKILL.md; do
        is_command "$file" || continue
        dir=${file%/SKILL.md}
        printf '%s\n' "${dir##*/}"
    done
    printf '%s\n' 'init = project-init' 'audit = ecc-production-audit'
}

if [ "$#" = 0 ]; then list_commands; exit 0; fi
[ "$#" = 1 ] || { echo 'Očakávam jeden názov príkazu.' >&2; exit 2; }
case "$1" in
    --list) list_commands; exit 0 ;;
    init) name=project-init ;;
    audit) name=ecc-production-audit ;;
    ''|*[!a-z0-9-]*) echo 'Neplatný názov príkazu.' >&2; exit 2 ;;
    *) name=$1 ;;
esac
file="$plugin/skills/$name/SKILL.md"
if [ ! -f "$file" ] || ! is_command "$file"; then
    echo 'Neznámy príkaz. Zoznam zobrazíš cez --list.' >&2
    exit 2
fi
printf 'Adresár pluginu: %s\nPostup: %s\n\n' "$plugin" "$file"
cat "$file"
