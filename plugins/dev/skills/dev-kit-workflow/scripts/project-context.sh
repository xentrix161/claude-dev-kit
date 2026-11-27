#!/usr/bin/env bash
# Pri bežných súboroch s pokynmi číta nadpisy. Projektové príkazy nespúšťa.
set -eu
if [ "$#" -gt 1 ]; then echo "Použitie: project-context.sh [adresár]" >&2; exit 2; fi
start=$(cd -- "${1:-.}" && pwd -P)
root=$(git -C "$start" rev-parse --show-toplevel 2>/dev/null) || root=$start
inspect() {
    local dir=$1 rel f
    rel=${dir#"$root"}
    rel=${rel#/}
    for f in AGENTS.override.md AGENTS.md CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md .claude/AGENTS.md REVIEW.md .claude/REVIEW.md README.md bin/harness Makefile composer.json package.json Cargo.toml pyproject.toml go.mod .gitlab-ci.yml .github/workflows .claude/devkit.json; do
        if [ -e "$dir/$f" ] || [ -L "$dir/$f" ]; then
            printf '%s\n' "${rel:+$rel/}$f"
            case "$f" in AGENTS.md|AGENTS.override.md|.claude/AGENTS.md) ;; *) continue ;; esac
            [ -f "$dir/$f" ] && [ ! -L "$dir/$f" ] && [ -r "$dir/$f" ] || continue
            LC_ALL=C awk -v bytes="$(wc -c < "$dir/$f")" '
                /^#+[[:space:]]/ && tolower($0) ~ /test|harness|commit|check|overov|kontrol|verif|audit|valid|nasaden/ {
                    last = NR
                    if (++hits <= 6) lines = lines (hits > 1 ? ", " : "") NR
                }
                END {
                    printf "  %d B", bytes
                    if (hits) printf " · sekcie kontrol na riadkoch %s", lines
                    if (hits > 6) printf ", …, %d", last
                    print ""
                }' "$dir/$f"
        fi
    done
}
dir=$start
while :; do
    inspect "$dir"
    [ "$dir" != "$root" ] && [ "$dir" != / ] || break
    dir=$(dirname "$dir")
done
# Claude hľadá pokyny aj nad koreňom repa. Ukáž len cestu, súkromný obsah nečítaj.
dir=$root
while [ "$dir" != / ]; do
    dir=$(dirname "$dir")
    for f in CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md; do
        path=${dir%/}/$f
        [ "$path" != "${HOME:-}/.claude/CLAUDE.md" ] || continue
        if [ -f "$path" ] || [ -L "$path" ]; then
            printf 'Claude: %s môže tieniť projektové AGENTS.md\n' "$path"
        fi
    done
done
