#!/usr/bin/env bash
# Pracovný priestor eval prípadu: projekt shop ako git repo s jedným commitom, voliteľne iný devkit.json,
# vetva a necommitnutá zmena. Volá ho scaffold.sh prípadu (case.yaml, beží len s --scaffold).
# Bash v behu evalu je v sandboxe, ktorý zapisuje len do pracovného adresára — dáta kitu
# ($HOME/.claude/dev-kit) preto vedú do .git/dev-kit-data, kde ich vidí check.sh aj hooky.
# scaffold.sh [--config <meno v config/>] [--branch <vetva>] [--change <meno v changes/>]
set -eu
FIX=$(cd "$(dirname "$0")" && pwd -P)
config="" branch="main" change=""
while [ $# -gt 0 ]; do
    case "$1" in
        --config) config=${2:?}; shift ;;
        --branch) branch=${2:?}; shift ;;
        --change) change=${2:?}; shift ;;
        *) echo "scaffold.sh: neznámy argument $1" >&2; exit 2 ;;
    esac
    shift
done

cp -R "$FIX/shop/." .
[ -z "$config" ] || cp "$FIX/config/$config.json" .claude/devkit.json
git init -q
git symbolic-ref HEAD "refs/heads/$branch"
git config user.name "shop eval"
git config user.email "eval@example.invalid"
git config commit.gpgsign false
git add -A
git commit -qm "[#11] feat: košík, ceny a objednávky"
[ -z "$change" ] || cp -R "$FIX/changes/$change/." .

mkdir -p .git/dev-kit-data "$HOME/.claude"
[ -e "$HOME/.claude/dev-kit" ] || ln -s "$(pwd -P)/.git/dev-kit-data" "$HOME/.claude/dev-kit"
