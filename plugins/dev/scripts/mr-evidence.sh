#!/usr/bin/env bash
# Stručný výsledok kitovej kontroly pre commit na konci vetvy.
set -u
. "$(dirname "$0")/lib.sh"
unknown() { printf '[dev-kit] check full: neoverené · %s\n' "$1"; exit 0; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] && [ -d "$1" ] || { echo 'použitie: mr-evidence.sh <adresár projektu> [očakávaný HEAD]' >&2; exit 2; }
DK_DATA=${DEVKIT_DATA:-$HOME/.claude/dev-kit}
dk_set_project "$1" "$PWD" read-only
[ -n "$DK_CFG" ] || unknown 'projekt nemá konfiguráciu kitu'
generation=$(readlink "$DK_PDATA/current-check") || generation=""
case "$generation" in result.??????) ;; *) unknown 'chýba aktuálny beh kontroly' ;; esac
result=$DK_PDATA/$generation
if [ -f "$result/partial.json" ]; then unknown 'PARTIAL pri poslednej kontrole'; fi
marker=$result/pass.json
[ -f "$marker" ] || unknown 'chýba úspešná kontrola'
fields=$(jq -er 'select(.mode == "full" and .unfilteredRun == true)
    | select([.head,.configHash,.projectProof] | all(type == "string" and test("^([0-9a-f]{40}|[0-9a-f]{64})$")))
    | select(.log | test("^check-full-[0-9]+(-[0-9]+)?\\.log$"))
    | select(.indexProof == .projectProof)
    | [.head,.configHash,.projectProof,.log] | @tsv' "$marker") || unknown 'chýba dôkaz nefiltrovaného behu nad zhodným indexom a pracovným stromom'
IFS=$'\t' read -r base cfg proof log <<< "$fields"
cd -- "$DK_PROJECT" || exit 1
tip=$(git rev-parse --verify HEAD) || unknown 'chýba commit'
[ "$#" -lt 2 ] || [ "$2" = "$tip" ] || unknown 'kontrola patrí inému tipu MR'
if [ "$base" != "$tip" ] && [ "$base" != "$(git rev-parse --verify -q "$tip^1")" ]; then unknown 'zmenil sa základ kontroly'; fi
[ "$(git hash-object --no-filters -- "$DK_CFG")" = "$cfg" ] || unknown 'zmenila sa konfigurácia kontroly'
[ "$(dk_project_proof committed "$DK_PROJECT" "$base" "$tip")" = "$proof" ] || unknown 'kontrola patrí inému obsahu'
checked=$DK_PDATA/logs/$log
[ -f "$checked" ] || unknown 'chýba log kontroly'
[ "$(git rev-parse --verify HEAD)" = "$tip" ] || unknown 'zmenil sa HEAD'
[ "$(readlink "$DK_PDATA/current-check")" = "$generation" ] || unknown 'počas overenia začal nový beh'
printf '[dev-kit] check full: PASS · %s · %s\n' "$tip" "$log"
printf '[dev-kit] pokrytie MR: neoverené · rozsah musí doložiť výstup projektového harnessu alebo CI\n'
