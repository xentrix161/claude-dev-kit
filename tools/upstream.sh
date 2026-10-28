#!/usr/bin/env bash
# P3: porovná prevzaté kusy ECC (pin z PROVENANCE.md) s upstream vetvou a zapíše dátum kontroly.
set -u

KIT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROV="${DK_PROVENANCE:-$KIT_DIR/plugins/dev/PROVENANCE.md}"
ECC="${ECC_DIR:-$HOME/Projects/_tools/ECC}"
DK_DATA="${DEVKIT_DATA:-$HOME/.claude/dev-kit}"
REF="origin/main"
FETCH=1

usage() {
  cat <<'EOF'
Použitie: tools/upstream.sh [--no-fetch] [--ref <ref>]
  --no-fetch   bez git fetch (offline); dátum kontroly sa nezapíše
  --ref <ref>  porovnať s inou vetvou ECC (predvolené origin/main)
Premenné: ECC_DIR (klon ECC), DEVKIT_DATA (dáta kitu), DK_PROVENANCE (iný PROVENANCE.md)
EOF
}

pretty() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-fetch) FETCH=0 ;;
    --ref)
      shift
      REF="${1:-}"
      if [ -z "$REF" ]; then usage >&2; exit 2; fi
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[dev-kit] neznámy argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if ! git -C "$ECC" rev-parse --git-dir >/dev/null 2>&1; then
  echo "[dev-kit] chýba klon ECC: $(pretty "$ECC") → git clone https://github.com/affaan-m/ECC.git $(pretty "$ECC")" >&2
  exit 1
fi
if [ ! -f "$PROV" ]; then
  echo "[dev-kit] chýba $(pretty "$PROV")" >&2
  exit 1
fi

FETCHED=0
FETCH_NOTE=""
if [ "$FETCH" = 1 ]; then
  if git -C "$ECC" fetch -q >/dev/null 2>&1; then
    FETCHED=1
  else
    FETCH_NOTE="git fetch zlyhal (sieť?) → porovnané s lokálnym $REF, dátum kontroly nezapísaný"
  fi
else
  FETCH_NOTE="bez fetch → porovnané s lokálnym $REF, dátum kontroly nezapísaný"
fi

REF_SHA=$(git -C "$ECC" rev-parse -q --verify "$REF^{commit}" 2>/dev/null) || REF_SHA=""
if [ -z "$REF_SHA" ]; then
  echo "[dev-kit] v ECC chýba $REF" >&2
  exit 1
fi
REF_DESC="$(git -C "$ECC" log -1 --date=short --format='%h, %cd' "$REF_SHA" 2>/dev/null)"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/dk-upstream.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
ROWS="$WORK/rows"
LINES="$WORK/lines"
: > "$LINES"

# Riadky tabuľky: | kit path | ECC source path | ECC commit | date adopted | changes | (podľa poradia stĺpcov)
awk -F'|' '
  /^\|/ {
    kit = $2; src = $3; pin = $4
    gsub(/[`[:space:]]/, "", kit); gsub(/[`[:space:]]/, "", src); gsub(/[`[:space:]]/, "", pin)
    if (src != "" && pin ~ /^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]+$/)
      print kit "\t" src "\t" pin
  }' "$PROV" > "$ROWS"

total=0
changed=0
problems=0
FIRST_PIN=""
FIRST_SRC=""
TAB=$(printf '\t')
while IFS="$TAB" read -r kit src pin; do
  [ -n "$src" ] || continue
  total=$((total + 1))
  if ! git -C "$ECC" cat-file -e "$pin^{commit}" 2>/dev/null; then
    echo "- $kit: pin $pin v ECC neexistuje" >> "$LINES"
    problems=$((problems + 1))
    continue
  fi
  if ! git -C "$ECC" cat-file -e "$pin:$src" 2>/dev/null; then
    echo "- $kit: $src v $pin neexistuje (preklep v PROVENANCE.md?)" >> "$LINES"
    problems=$((problems + 1))
    continue
  fi
  if ! git -C "$ECC" cat-file -e "$REF_SHA:$src" 2>/dev/null; then
    echo "- $kit ← $src: upstream zmazané alebo presunuté" >> "$LINES"
    changed=$((changed + 1))
    continue
  fi
  stat=$(git -C "$ECC" diff --stat "$pin..$REF_SHA" -- "$src" 2>/dev/null | tail -n 1 | sed 's/^ *//')
  if [ -n "$stat" ]; then
    echo "- $kit ← $src: $stat" >> "$LINES"
    changed=$((changed + 1))
    if [ -z "$FIRST_SRC" ]; then FIRST_PIN="$pin"; FIRST_SRC="$src"; fi
  fi
done < "$ROWS"

if [ "$total" -eq 0 ]; then
  echo "[dev-kit] $(pretty "$PROV") nemá žiadny riadok s pinom ECC" >&2
  exit 1
fi

PROBLEM_NOTE=""
[ "$problems" -eq 0 ] || PROBLEM_NOTE=" · chybné riadky v PROVENANCE.md: $problems"
if [ "$changed" -gt 0 ]; then
  echo "[dev-kit] upstream ECC: zmenených $changed z $total prevzatých zdrojov$PROBLEM_NOTE · $REF = $REF_DESC"
else
  echo "[dev-kit] upstream ECC: bez zmien v $total prevzatých zdrojoch$PROBLEM_NOTE · $REF = $REF_DESC"
fi
cat "$LINES"
if [ -n "$FIRST_SRC" ]; then
  echo "detail: git -C $(pretty "$ECC") diff $FIRST_PIN..$REF -- $FIRST_SRC"
fi
if [ "$changed" -gt 0 ]; then
  echo "ďalej: preber zmysluplné zmeny ručne, posuň pin v plugins/dev/PROVENANCE.md, zapíš do CHANGELOG.md"
fi
if [ "$problems" -gt 0 ]; then
  echo "ďalej: oprav chybné riadky v $(pretty "$PROV")"
fi
[ -z "$FETCH_NOTE" ] || echo "pozor: $FETCH_NOTE"

if [ "$FETCHED" = 1 ]; then
  if mkdir -p "$DK_DATA" 2>/dev/null \
    && printf '{"lastUpstreamCheck": %s}\n' "$(date +%s)" > "$DK_DATA/maintenance.json.$$" \
    && mv "$DK_DATA/maintenance.json.$$" "$DK_DATA/maintenance.json"; then
    echo "zapísané: $(pretty "$DK_DATA/maintenance.json")"
  else
    rm -f "$DK_DATA/maintenance.json.$$"
    echo "pozor: nepodarilo sa zapísať $(pretty "$DK_DATA/maintenance.json")" >&2
  fi
fi

[ "$problems" -eq 0 ] || exit 1
exit 0
