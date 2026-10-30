#!/usr/bin/env bash
# dev-kit selftest — kontrakty skriptov z docs/SPEC.md (§2–§4, §10), bez dockeru a siete.
# Použitie: bash tests/selftest.sh [podreťazec názvu prípadu]
#   DK_SELFTEST_KEEP=1          ponechá dočasné adresáre (cesta sa vypíše)
#   DK_SELFTEST_SCRIPTS=<dir>   testuje skripty z iného adresára (napr. nainštalovaný plugin)
#   DK_SELFTEST_JOBS=<n>        počet súbežných prípadov (predvolene 4; 1 = postupne)
# Každý prípad: vlastné git repo (mktemp -d), DEVKIT_DATA, CLAUDE_PROJECT_DIR, devkit.json s container "".

KIT=$(cd "$(dirname "$0")/.." && pwd -P)
S="${DK_SELFTEST_SCRIPTS:-$KIT/plugins/dev/scripts}"
FIX="$KIT/tests/fixtures"
FILTER="${1:-}"

for bin in git jq awk; do
  command -v "$bin" >/dev/null 2>&1 || { echo "not ok - predpoklady: chýba $bin"; echo "FAIL 1/1"; exit 1; }
done

# UTF-8 locale ako u používateľa: bash 3.2 v ňom číta "$x✓" ako meno premennej, v C locale chybu nevidno.
UTF=""
for l in C.UTF-8 en_US.UTF-8 C.utf8 en_US.utf8; do
  if [ "$(LC_ALL=$l locale charmap 2>/dev/null)" = UTF-8 ]; then UTF=$l; break; fi
done
if [ -n "$UTF" ]; then export LANG="$UTF" LC_ALL="$UTF"; else echo "# varovanie: chýba UTF-8 locale, výsledok nemusí sedieť s reálnym prostredím"; fi

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dk-selftest.XXXXXX") || { echo "FAIL: mktemp"; exit 1; }
ROOT=$(cd "$ROOT" && pwd -P)
cleanup() {
  if [ -n "${DK_SELFTEST_KEEP:-}" ]; then echo "# dočasné adresáre: $ROOT"; else rm -rf "$ROOT"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Izolácia: vlastný HOME (žiadny zápis do ~/.claude, žiadna globálna git konfigurácia),
# atrapa docker na PATH (selftest nikdy nesiahne na skutočné kontajnery).
unset CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA CLAUDE_ENV_FILE DEVKIT_DATA DEVKIT_CONFIG \
  GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_GLOBAL GIT_CONFIG_PARAMETERS GIT_CEILING_DIRECTORIES
export HOME="$ROOT/home" XDG_CONFIG_HOME="$ROOT/home/.config" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME/.config" "$ROOT/fakebin"
cat > "$HOME/.gitconfig" <<'EOF'
[user]
	name = dev-kit selftest
	email = selftest@example.invalid
[init]
	defaultBranch = main
[commit]
	gpgsign = false
[advice]
	detachedHead = false
EOF
# Atrapa docker: volania do $DK_FAKE_DOCKER_LOG; inspect hlási beh len pri DK_FAKE_DOCKER_RUNNING=1, exec nič nespustí.
cat > "$ROOT/fakebin/docker" <<'EOF'
#!/bin/sh
echo "$*" >> "${DK_FAKE_DOCKER_LOG:-/dev/null}"
case "$1" in
  inspect) [ "${DK_FAKE_DOCKER_RUNNING:-}" = 1 ] && { echo true; exit 0; }; echo "Error: No such object: $*" >&2; exit 1 ;;
  exec) exit 0 ;;
esac
exit 1
EOF
chmod +x "$ROOT/fakebin/docker"
# Atrapa claude: --version vypíše DK_FAKE_CC_VERSION (úvodná karta kontroluje verziu, skutočný claude sa nespúšťa).
cat > "$ROOT/fakebin/claude" <<'EOF'
#!/bin/sh
case "$1" in --version) echo "${DK_FAKE_CC_VERSION:-2.1.308} (Claude Code)" ;; esac
exit 0
EOF
chmod +x "$ROOT/fakebin/claude"
export PATH="$ROOT/fakebin:$PATH"

ICONV=""
command -v iconv >/dev/null 2>&1 && ICONV=1
BADUTF=""

if command -v perl >/dev/null 2>&1; then
  tmo() { perl -e '$t = shift @ARGV; alarm $t; exec { $ARGV[0] } @ARGV or exit 127' "$@"; }
else
  tmo() { shift; "$@"; }
fi

# ---------------------------------------------------------------- fixture

TPL="$ROOT/template"
mkdir -p "$TPL/bin" "$TPL/app/models" "$TPL/libs/Validator" "$TPL/tests" "$TPL/db/migrations" \
  "$TPL/sub" "$TPL/docs"
cp "$FIX/bin/fake-lint" "$FIX/bin/fake-phpunit" "$FIX/bin/fake-ok" "$FIX/bin/replay" "$TPL/bin/"
chmod +x "$TPL/bin/"*
printf '<?php\n// Foo\n$foo = 1;\n' > "$TPL/app/Foo.php"
printf '<?php\n$old = 1;\n' > "$TPL/app/Old.php"
printf '<?php\n$legacy = 1; // LINTERR\n$ok = 2;\n' > "$TPL/app/LegacyLint.php"
printf '<?php\ndump($legacy);\n$ok = 2;\n' > "$TPL/app/LegacyDump.php"
printf '<?php\n$model = 1;\n' > "$TPL/app/models/UserModel.php"
printf '<?php\n$validator = 1;\n' > "$TPL/libs/Validator/Validator.php"
printf '<?php\n$test = 1;\n' > "$TPL/tests/FooTest.php"
printf '<?php\n$migration = 1;\n' > "$TPL/db/migrations/20260101000000_init.php"
printf 'sub\n' > "$TPL/sub/readme.txt"
printf '# fixture\n' > "$TPL/README.md"
printf '# handoff\n' > "$TPL/docs/handoff.md"
printf '{"require": {"nette/application": "^3.2"}}\n' > "$TPL/composer.json"
git -C "$TPL" init -q || { echo "FAIL: git init"; exit 1; }
printf '.claude/\n.marks/\n' >> "$TPL/.git/info/exclude"
git -C "$TPL" add -A && git -C "$TPL" commit -qm init || { echo "FAIL: git commit fixture"; exit 1; }

# new_case [nocfg] — čerstvá kópia fixture; nastaví CASE REPO DATA PDATA SID
new_case() {
  CASE=$(mktemp -d "$ROOT/case.XXXXXX")
  REPO="$CASE/repo"
  DATA="$CASE/data"
  cp -Rp "$TPL" "$REPO"
  mkdir -p "$DATA" "$REPO/.claude"
  export DEVKIT_DATA="$DATA" CLAUDE_PROJECT_DIR="$REPO" DK_FAKE_DOCKER_LOG="$CASE/docker.calls"
  unset DK_FAKE_DOCKER_RUNNING DK_FAKE_CC_VERSION
  RUNDIR=""
  SID="sess-${CASE##*.}"
  PH=$(printf %s "$REPO" | git hash-object --stdin | cut -c1-12)
  PDATA="$DATA/projects/$PH"
  IN=/dev/null
  RC="" OUT="" ERR=""
  [ "${1:-}" = nocfg ] || cfg .
}
# cfg <jq-filter> — devkit.json = fixtures/devkit.json upravený filtrom
cfg() { jq "$@" "$FIX/devkit.json" > "$REPO/.claude/devkit.json"; }

g() { git -C "$REPO" "$@" >/dev/null 2>&1; }
add() { printf '%s\n' "$2" >> "$REPO/$1"; }
put() { mkdir -p "$(dirname "$REPO/$1")"; printf '%s\n' "$2" > "$REPO/$1"; }
now() { date +%s; }
fail_unit() { mkdir -p "$REPO/.marks"; printf '%s\n' "$@" > "$REPO/.marks/fail-unit"; }
unit_calls() { if [ -f "$REPO/.marks/unit.calls" ]; then grep -c . "$REPO/.marks/unit.calls"; else echo 0; fi; }
session_files() { mkdir -p "$PDATA/sessions"; printf '%s\n' "$@" > "$PDATA/sessions/$SID.files"; }

bad_line() { # prvý riadok s neplatným UTF-8, cez cat -v
  cat "$@" | while IFS= read -r l; do
    printf '%s\n' "$l" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || { printf '%s' "$l" | LC_ALL=C cat -v | LC_ALL=C cut -c1-80; break; }
  done
}
# run <script> [args…] — stdin z $IN, cwd $RUNDIR (predvolene $REPO); výsledok v RC OUT ERR
run() {
  local name="$1"
  shift
  (cd "${RUNDIR:-$REPO}" && tmo 30 bash "$S/$name.sh" "$@") < "$IN" > "$CASE/out" 2> "$CASE/err"
  RC=$?
  OUT=$(cat "$CASE/out")
  ERR=$(cat "$CASE/err")
  IN=/dev/null
  RUNDIR=""
  if [ -n "$ICONV" ] && [ -z "$BADUTF" ] && ! iconv -f UTF-8 -t UTF-8 "$CASE/out" "$CASE/err" >/dev/null 2>&1; then
    BADUTF="$name.sh: $(bad_line "$CASE/out" "$CASE/err")"
  fi
}
# hook <script> <json> [args…] — prostredie ako pri plugin hooku
hook() {
  local name="$1"
  printf '%s\n' "$2" > "$CASE/in.json"
  shift 2
  IN="$CASE/in.json"
  CLAUDE_PLUGIN_ROOT="$(dirname "$S")" CLAUDE_PLUGIN_DATA="$CASE/plugin-data" run "$name" "$@"
}

j_file() { # <event> <file-abs>
  jq -nc --arg s "$SID" --arg c "$REPO" --arg e "$1" --arg f "$2" \
    '{session_id: $s, transcript_path: "/dev/null", cwd: $c, permission_mode: "default",
      hook_event_name: $e, tool_name: "Edit", tool_use_id: "toolu_selftest",
      tool_input: {file_path: $f, old_string: "a", new_string: "b", replace_all: false}}
     + (if $e == "PostToolUse" then {tool_response: {filePath: $f, success: true}} else {} end)'
}
j_notebook() { # <event> <notebook-abs> — NotebookEdit má cestu v tool_input.notebook_path
  jq -nc --arg s "$SID" --arg c "$REPO" --arg e "$1" --arg f "$2" \
    '{session_id: $s, transcript_path: "/dev/null", cwd: $c, permission_mode: "default",
      hook_event_name: $e, tool_name: "NotebookEdit", tool_use_id: "toolu_selftest",
      tool_input: {notebook_path: $f, cell_id: "c1", new_source: "x = 1", edit_mode: "replace"}}'
}
j_bash() { # <príkaz> [cwd]
  jq -nc --arg s "$SID" --arg c "${2:-$REPO}" --arg cmd "$1" \
    '{session_id: $s, transcript_path: "/dev/null", cwd: $c, permission_mode: "default",
      hook_event_name: "PreToolUse", tool_name: "Bash", tool_use_id: "toolu_selftest",
      tool_input: {command: $cmd, description: "selftest"}}'
}
j_stop() {
  jq -nc --arg s "$SID" --arg c "$REPO" --argjson a "${1:-false}" \
    '{session_id: $s, transcript_path: "/dev/null", cwd: $c, permission_mode: "default",
      hook_event_name: "Stop", stop_hook_active: $a, last_assistant_message: "Hotovo.",
      background_tasks: [], session_crons: []}'
}
j_start() { # [cwd]
  jq -nc --arg s "$SID" --arg c "${1:-$REPO}" \
    '{session_id: $s, transcript_path: "/dev/null", cwd: $c, hook_event_name: "SessionStart",
      source: "startup", model: "claude-opus-5-5"}'
}
on_edit() { hook on-edit "$(j_file PostToolUse "$REPO/$1")"; }
pre_edit() { hook pre-edit "$(j_file PreToolUse "$REPO/$1")"; }
pre_bash() { hook pre-bash "$(j_bash "$1" "${2:-}")"; }
stop_check() { hook stop-check "$(j_stop "${1:-false}")"; }
# card [cwd] — RAW = stdout (jeden JSON objekt), OUT = karta (additionalContext), SYSMSG = systemMessage
card() {
  hook session-card "$(j_start "${1:-}")"
  RAW=$OUT SYSMSG=""
  [ -n "$RAW" ] || return 0
  if [ "$(nlines "$RAW")" != 1 ] || ! printf '%s' "$RAW" | jq -e 'type == "object"' >/dev/null 2>&1; then
    RC="$RC (stdout nie je jeden JSON objekt)"
    return 0
  fi
  OUT=$(printf '%s' "$RAW" | jq -r '.hookSpecificOutput.additionalContext // empty')
  SYSMSG=$(printf '%s' "$RAW" | jq -r '.systemMessage // empty')
}
check() { run check "$@"; }
# q <reťazec> — shell-quoting pre príkazy v devkit.json (fixtúry nemajú apostrof v ceste)
q() { printf "'%s'" "$1"; }
real() { printf 'sh bin/replay %s %s' "$(q "$FIX/real/$1.txt")" "$2"; }
# mkpath <adresár> <vynechaný nástroj>… — PATH len zo symlinkov bežných nástrojov (bez jq, docker…)
mkpath() {
  local d="$1" t p
  shift
  mkdir -p "$d"
  for t in bash sh git jq awk sed grep cat date mkdir chmod cksum cut rm tr wc find mv sort head tail dirname \
    basename uniq xargs ls cp ln env perl mktemp tee touch iconv; do
    case " $* " in *" $t "*) continue ;; esac
    p=$(command -v "$t" 2>/dev/null) || continue
    case "$p" in /*) ln -sf "$p" "$d/$t" ;; esac
  done
}
wt_add() { # <cesta> — linked worktree fixtúry (bez .claude/, config ostáva v hlavnom checkoute)
  git -C "$REPO" worktree add -q --detach "$1" >/dev/null 2>&1 || fail "fixture: git worktree add $1"
}
# kit_scripts [upstream] — S = kópia skriptov v $CASE/kit/plugins/dev/scripts; s „upstream“ aj
# $CASE/kit/tools/upstream.sh ako v pracovnej kópii kitu (SPEC §4.7 bod 6)
kit_scripts() {
  mkdir -p "$CASE/kit/plugins/dev/scripts" && cp "$S"/*.sh "$CASE/kit/plugins/dev/scripts/" ||
    { fail "fixture: kópia skriptov"; return 1; }
  S="$CASE/kit/plugins/dev/scripts"
  [ "${1:-}" != upstream ] || { mkdir -p "$CASE/kit/tools" && : > "$CASE/kit/tools/upstream.sh"; }
}

# ---------------------------------------------------------------- asserty

fail() { REASON="$*"; return 1; }
# Vlastné nástroje harnessu bežia v LC_ALL=C (porovnanie bajtov); platnosť UTF-8 stráži run().
flat() { printf '%s' "$1" | LC_ALL=C tr '\n' '|' | LC_ALL=C cut -c1-240; }
ctx() { printf ' [exit %s; stdout: %s; stderr: %s]' "$RC" "$(flat "$OUT")" "$(flat "$ERR")"; }
squash() { printf '%s' "$1" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr -s ' '; }
nlines() { if [ -n "$1" ]; then printf '%s\n' "$1" | wc -l | tr -d ' '; else echo 0; fi; }

want_rc() {
  [ "$RC" = "$1" ] && return 0
  if [ "$RC" = 142 ]; then fail "${2:+$2: }timeout 30 s$(ctx)"; return 1; fi
  fail "${2:+$2: }exit $RC, čakal som $1$(ctx)"
}
want_silent() { [ -z "$OUT$ERR" ] || fail "${1:+$1: }čakal som žiadny výstup$(ctx)"; }
want_no_stdout() { [ -z "$OUT" ] || fail "${1:+$1: }čakal som prázdny stdout$(ctx)"; }
want_out() { printf '%s' "$OUT" | LC_ALL=C grep -qF -- "$1" || fail "${2:+$2: }stdout neobsahuje '$1'$(ctx)"; }
want_err() { printf '%s' "$ERR" | LC_ALL=C grep -qF -- "$1" || fail "${2:+$2: }stderr neobsahuje '$1'$(ctx)"; }
want_not() {
  if printf '%s%s' "$OUT" "$ERR" | LC_ALL=C grep -qF -- "$1"; then fail "${2:+$2: }výstup obsahuje '$1'$(ctx)"; return 1; fi
}
want_json() {
  [ -n "$OUT" ] && printf '%s' "$OUT" | jq -e "$1" >/dev/null 2>&1 || fail "${2:+$2: }stdout nespĺňa jq '$(squash "$1")'$(ctx)"
}
# want_decision deny|ask — PreToolUse JSON s permissionDecision a dôvodom s prefixom [dev-kit]
want_decision() {
  want_rc 0 "${2:-}" && want_json "$(printf '.hookSpecificOutput.hookEventName == "PreToolUse"
    and .hookSpecificOutput.permissionDecision == "%s"
    and (.hookSpecificOutput.permissionDecisionReason | contains("[dev-kit]"))' "$1")" "${2:-}"
}
want_allow() { want_rc 0 "${1:-}" && want_silent "${1:-}" && want_no_errors "${1:-}"; }
# allow po zmene devkit.json v tej istej session: bez rozhodnutia, len systemMessage zmeny (R3, SPEC §4.4)
want_allow_cfgnote() {
  want_rc 0 "${1:-}" && want_json '(keys == ["systemMessage"])
    and (.systemMessage | startswith("[dev-kit] devkit.json sa zmenil — príkazy: "))' "${1:-}" || return 1
  [ -z "$ERR" ] || { fail "${1:+$1: }stderr: $(flat "$ERR")"; return 1; }
  want_no_errors "${1:-}"
}
# Stop bez bloku: prázdny stdout alebo JSON bez decision "block" (systemMessage je dovolený).
want_no_block() {
  [ -z "$OUT" ] && return 0
  printf '%s' "$OUT" | jq -e '(.decision // "") != "block"' >/dev/null 2>&1 || fail "${1:+$1: }čakal som Stop bez bloku$(ctx)"
}
want_logged() { # <hook> <rule> <decision> — záznam dk_log v decisions.jsonl (SPEC §4.1)
  jq -se --arg h "$1" --arg r "$2" --arg d "$3" 'any(.[]; .hook == $h and .rule == $r and .decision == $d)' \
    "$DATA/decisions.jsonl" >/dev/null 2>&1 || fail "decisions.jsonl bez {hook: $1, rule: $2, decision: $3}"
}
docker_calls() { if [ -f "$CASE/docker.calls" ]; then cat "$CASE/docker.calls"; fi; }
no_docker_exec() { ! docker_calls | grep -q '^exec ' || fail "${1:+$1: }docker exec: $(flat "$(docker_calls)")"; }
want_no_errors() {
  [ ! -s "$DATA/errors.log" ] || fail "${1:+$1: }errors.log: $(flat "$(cat "$DATA/errors.log")")"
}
want_file() { [ -f "$1" ] || fail "${2:+$2: }chýba ${1#$CASE/}$(ctx)"; }
want_jfile() { # <súbor> <jq-filter> [argumenty jq…] — kontrola JSON súboru
  local f="$1" q="$2"
  shift 2
  [ -f "$f" ] || { fail "chýba ${f#$CASE/}"; return 1; }
  jq -e "$@" "$q" "$f" >/dev/null 2>&1 || fail "${f#$CASE/} nespĺňa jq '$(squash "$q")': $(flat "$(cat "$f")")"
}
pre() { # <popis> <príkaz…> — predpoklad fixture (inak by test nič nedokazoval)
  local d="$1"
  shift
  "$@" >/dev/null 2>&1 || fail "fixture: $d"
}

# ---------------------------------------------------------------- on-edit

t_edit_lint_added() {
  new_case
  add app/Foo.php '$a = 1; // LINTERR'
  on_edit app/Foo.php
  want_rc 2 && want_err '[dev-kit] app/Foo.php: 1 nález' && want_err 'app/Foo.php:4' && want_no_stdout || return 1
  want_logged on-edit 'lint:.php' block
}
t_edit_parse_error() {
  new_case
  add app/Foo.php '$a = ; // PARSEERR'
  on_edit app/Foo.php
  want_rc 2 && want_err 'on line 4'
}
t_edit_lint_preexisting() {
  new_case
  pre "stub hlási riadok 2" sh -c "cd '$REPO' && sh bin/fake-lint app/LegacyLint.php | grep -q 'LegacyLint.php:2:'" || return 1
  add app/LegacyLint.php '$b = 3;'
  on_edit app/LegacyLint.php
  want_allow
}
t_edit_guard_added() {
  new_case
  add app/Foo.php 'dump($foo);'
  on_edit app/Foo.php
  want_rc 2 && want_err '[dev-kit]' && want_err 'app/Foo.php:4' && want_err 'debug výpis' || return 1
  want_logged on-edit 'guard:debug-php' block
}
t_edit_cap15() {
  new_case
  local i=1 n
  while [ $i -le 17 ]; do add app/Foo.php "dump(\$x$i);"; i=$((i + 1)); done
  on_edit app/Foo.php
  want_rc 2 && want_err '[dev-kit] app/Foo.php: 17 nálezov' && want_err '… ďalšie nálezy: 2' || return 1
  n=$(printf '%s\n' "$ERR" | LC_ALL=C grep -c 'app/Foo\.php:[0-9]')
  [ "$n" = 15 ] || fail "stderr má $n riadkov s nálezom, čakal som 15$(ctx)"
}
t_edit_outside_project() {
  new_case
  printf '<?php\ndump($x); // LINTERR\n' > "$CASE/outside.php"
  hook on-edit "$(j_file PostToolUse "$CASE/outside.php")"
  want_allow || return 1
  [ ! -s "$PDATA/sessions/$SID.files" ] || fail "súbor mimo projektu je v sessions/$SID.files"
}
t_edit_guard_preexisting() {
  new_case
  add app/LegacyDump.php '$c = 3;'
  on_edit app/LegacyDump.php
  want_allow
}
t_edit_guard_disabled() {
  new_case
  cfg '.disabledRules = ["guard:debug-php"]'
  add app/Foo.php 'dump($foo);'
  on_edit app/Foo.php
  want_allow
}
t_edit_no_config() {
  new_case nocfg
  add app/Foo.php 'dump($foo); // LINTERR'
  on_edit app/Foo.php
  want_allow
}
t_edit_session_files() {
  new_case
  add app/Foo.php '$d = 4;'
  on_edit app/Foo.php
  want_rc 0 "1. úprava" || return 1
  add app/Foo.php '$e = 5;'
  on_edit app/Foo.php
  want_rc 0 "2. úprava" || return 1
  put app/Bar.php '<?php'
  on_edit app/Bar.php
  want_rc 0 "nový súbor" || return 1
  local f="$PDATA/sessions/$SID.files"
  want_file "$f" || return 1
  local got
  got=$(sort "$f" | tr '\n' ' ')
  [ "$got" = "app/Bar.php app/Foo.php " ] || fail "sessions/$SID.files = '$got', čakal som 'app/Bar.php app/Foo.php'"
}

# ---------------------------------------------------------------- pre-edit

lock_at() { # <epoch> — test-lock.json na tests/FooTest.php
  mkdir -p "$PDATA"
  printf '{"files":["tests/FooTest.php"],"time":%s,"ttlHours":6}\n' "$1" > "$PDATA/test-lock.json"
}
t_pre_edit_lock_deny() {
  new_case
  lock_at "$(now)"
  pre_edit tests/FooTest.php
  want_decision deny && want_out 'tests/FooTest.php' && want_out '/dev:fix --unlock'
}
t_pre_edit_lock_other_file() {
  new_case
  lock_at "$(now)"
  pre_edit app/Foo.php
  want_allow
}
t_pre_edit_lock_expired() {
  new_case
  lock_at $(($(now) - 30 * 3600))
  pre_edit tests/FooTest.php
  want_allow
}
t_pre_edit_migration_committed() {
  new_case
  pre_edit db/migrations/20260101000000_init.php
  want_decision ask && want_out 'db/migrations/20260101000000_init.php'
}
t_pre_edit_migration_new() {
  new_case
  put db/migrations/20260202000000_add.php '<?php'
  pre_edit db/migrations/20260202000000_add.php
  want_allow
}
j_agent_file() { # <agent_type> <file-abs> — Edit volaný zo subagenta
  j_file PreToolUse "$2" | jq -c --arg a "$1" '. + {agent_id: "agent-selftest", agent_type: $a}'
}
t_pre_edit_agent_project_deny() {
  new_case nocfg
  hook pre-edit "$(j_agent_file dev:ecc-silent-failure-hunter "$REPO/app/Foo.php")"
  want_decision deny && want_out 'dev:ecc-silent-failure-hunter' && want_out 'agent-memory/' \
    && want_logged pre-edit agentReadOnly deny
}
t_pre_edit_agent_memory_allow() {
  new_case
  hook pre-edit "$(j_agent_file dev:ecc-pr-test-analyzer "$HOME/.claude/agent-memory/dev-ecc-pr-test-analyzer/MEMORY.md")"
  want_allow
}
t_pre_edit_agent_dotdot_deny() {
  new_case
  hook pre-edit "$(j_agent_file dev:ecc-pr-test-analyzer "$HOME/.claude/agent-memory/../settings.json")"
  want_decision deny
}
t_pre_edit_other_agent_allow() {
  new_case
  hook pre-edit "$(j_agent_file general-purpose "$REPO/app/Foo.php")"
  want_allow
}

# ---------------------------------------------------------------- pre-bash

t_bash_not_commit() {
  new_case
  pre_bash 'ls -la'
  want_allow
}
t_bash_commit_no_pass() {
  new_case
  add app/Foo.php '$f = 6;'
  g add app/Foo.php
  pre_bash 'git commit -m "x"'
  want_decision deny && want_out 'app/Foo.php' && want_out '/dev:check' || return 1
  pre_bash 'git commit --amend --no-edit'
  want_decision deny "--amend --no-edit"
}
t_bash_commit_after_pass() {
  new_case
  add app/Foo.php '$f = 6;'
  g add app/Foo.php
  g rm -q app/Old.php
  check --quick --project "$REPO"
  want_rc 0 "check.sh --quick" && want_file "$PDATA/pass.json" "check.sh --quick" || return 1
  pre_bash 'git commit -m "x"'
  want_allow
}
t_bash_commit_all_flag() {
  new_case
  add app/Foo.php '$u = 21;'
  pre_bash 'git commit -am "x"'
  want_decision deny "-am bez PASS" && want_out 'app/Foo.php' "-am bez PASS" || return 1
  check --quick --project "$REPO"
  want_rc 0 "check.sh --quick" || return 1
  pre_bash 'git commit -a -m "x"'
  want_allow "-a po PASS"
}
t_bash_commit_restaged() {
  new_case
  add app/Foo.php '$f = 6;'
  g add app/Foo.php
  check --quick --project "$REPO"
  want_rc 0 "check.sh --quick" || return 1
  add app/Foo.php '$g = 7;'
  g add app/Foo.php
  pre_bash 'git commit -m "x"'
  want_decision deny && want_out 'app/Foo.php'
}
t_bash_commit_docs_only() {
  new_case
  add README.md 'Doplnená veta.'
  g add README.md
  pre_bash 'git commit -m "docs"'
  want_allow
}
t_bash_commit_fullwhen() {
  new_case
  add app/models/UserModel.php '$h = 8;'
  g add app/models/UserModel.php
  check --quick --project "$REPO"
  want_rc 0 "check.sh --quick" || return 1
  pre_bash 'git commit -m "x"'
  want_decision deny "po --quick" && want_out '--full' "po --quick" || return 1
  check --full --project "$REPO"
  want_rc 0 "check.sh --full" || return 1
  pre_bash 'git commit -m "x"'
  want_allow "po --full"
}
t_bash_commit_forbidden_file() {
  new_case
  put .test-credentials 'APP_TEST_USER=a'
  g add .test-credentials
  pre_bash 'git commit -m "x"'
  want_decision deny && want_out '.test-credentials'
}
t_bash_commit_secret() {
  new_case
  put config/settings.ini 'password = "SuperSecret123"'
  g add config/settings.ini
  pre_bash 'git commit -m "x"'
  want_decision deny && want_out 'config/settings.ini:1' && want_not 'SuperSecret123' || return 1
  want_out 'nahlás používateľovi' && want_out 'neodstraňuj' && want_out 'secrets.allow' || return 1
  ! grep -rqF SuperSecret123 "$DATA" || fail "tajomstvo je v $(grep -rlF SuperSecret123 "$DATA" | sed "s|$CASE/||" | head -1)"
}
t_bash_commit_secret_allow() {
  new_case
  put tests/fixtures/settings.ini 'password = "SuperSecret123"'
  g add tests/fixtures/settings.ini
  pre_bash 'git commit -m "x"'
  want_allow
}
t_bash_detect_cd_commit() {
  new_case
  add app/Foo.php '$f = 6;'
  g add app/Foo.php
  pre_bash 'cd sub && git commit -m x'
  want_decision deny "cd sub && git commit" || return 1
  pre_bash 'git -C sub commit -m x'
  want_decision deny "git -C sub commit"
}
t_bash_detect_commit_tree() {
  new_case
  add app/Foo.php '$f = 6;'
  g add app/Foo.php
  pre_bash 'git commit-tree HEAD^{tree} -m x'
  want_allow
}

# ---------------------------------------------------------------- check.sh

t_check_quick_pass() {
  new_case
  add app/Foo.php '$i = 9;'
  put app/New.php '<?php'
  rm "$REPO/app/Old.php"
  check --quick --project "$REPO"
  want_rc 0 && want_out '[dev-kit] check quick: PASS · 2 ok · 0 fail · 0 skip' && want_out '✓ lint' && want_out '✓ unit' || return 1
  local log
  log=$(printf '%s\n' "$OUT" | sed -n 's/^log: //p' | tail -1)
  [ -n "$log" ] && [ -s "$log" ] || { fail "riadok 'log: <cesta>' chýba alebo log neexistuje$(ctx)"; return 1; }
  local p="$PDATA/pass.json" foo new head
  foo=$(git -C "$REPO" hash-object app/Foo.php)
  new=$(git -C "$REPO" hash-object app/New.php)
  head=$(git -C "$REPO" rev-parse HEAD)
  want_jfile "$p" '.mode == "quick" and .head == $h and .blobs["app/Foo.php"] == $foo
    and .blobs["app/New.php"] == $new and .blobs["app/Old.php"] == "-"' \
    --arg h "$head" --arg foo "$foo" --arg new "$new"
}
t_check_fail() {
  new_case
  local ids="" i=1
  while [ $i -le 25 ]; do ids="$ids Tests\\Unit\\FooTest::testCase$i"; i=$((i + 1)); done
  # shellcheck disable=SC2086
  fail_unit $ids
  add app/Foo.php '$j = 10;'
  check --quick --project "$REPO"
  want_rc 1 && want_out '[dev-kit] check quick: FAIL' && want_out '✗ unit' && want_out 'log:' || return 1
  [ "$(nlines "$OUT")" -le 20 ] || { fail "stdout má $(nlines "$OUT") riadkov (limit 20)$(ctx)"; return 1; }
  [ ! -f "$PDATA/pass.json" ] || fail "pass.json zapísaný napriek FAIL"
}
t_check_skip_missing() {
  new_case
  cfg '.check.steps += [{"id": "phantom", "requires": "vendor/bin/phantom", "run": "sh bin/fake-ok phantom", "modes": ["stop", "quick", "full"]}]'
  add app/Foo.php '$k = 11;'
  check --quick --project "$REPO"
  want_rc 0 && want_out '– phantom: chýba vendor/bin/phantom' || return 1
  [ ! -f "$REPO/.marks/ran-phantom" ] || fail "krok phantom bežal napriek chýbajúcemu requires"
}
t_check_all_skip() {
  new_case
  cfg '.check.steps |= map(.requires = "vendor/bin/nic")'
  add app/Foo.php '$l = 12;'
  check --quick --project "$REPO"
  want_rc 4 && want_out 'chýba vendor/bin/nic'
}
t_check_blocked_partial() {
  new_case
  cfg '.check.steps += [{"id": "tests", "run": "vendor/bin/phpunit", "modes": ["stop", "quick", "full"]}]'
  add app/Foo.php '$b = 21;'
  check --quick --project "$REPO"
  want_rc 4 && want_out '[dev-kit] check quick: PARTIAL · 2 ok · 0 fail · 1 skip' \
    && want_out '! tests: príkaz sa nedá spustiť (exit 127)' || return 1
  [ ! -f "$PDATA/pass.json" ] || fail "pass.json zapísaný napriek PARTIAL"
}
t_check_infra_partial() {
  new_case
  cfg --arg c "printf '%s\n' 'Cannot connect to the Docker daemon. Is the docker daemon running?'; exit 1" \
    '.check.steps += [{"id": "stan", "run": $c, "modes": ["quick"]}]'
  add app/Foo.php '$b = 22;'
  check --quick --project "$REPO"
  want_rc 4 && want_out 'check quick: PARTIAL' && want_out '! stan: chyba prostredia, nie kódu (Cannot connect to the Docker daemon)'
}
t_bash_commit_after_partial() {
  new_case
  cfg '.check.steps += [{"id": "tests", "run": "vendor/bin/phpunit", "modes": ["quick", "full"]}]'
  add app/Foo.php '$b = 23;'
  g add app/Foo.php
  check --quick --project "$REPO"
  want_rc 4 "check.sh --quick" || return 1
  pre_bash 'git commit -m "x"'
  want_decision deny && want_out 'commit gate'
}
t_bash_commit_partial_explained() {
  new_case
  DOCKER_OK=1
  cfg '.container = "app-php"'
  add app/Foo.php '$b = 27;'
  g add app/Foo.php
  check --quick --project "$REPO"
  want_rc 4 "check.sh --quick" && want_out '! unit: kontajner app-php nebeží' "check.sh --quick" || return 1
  want_jfile "$PDATA/partial.json" '.mode == "quick" and (.time | type == "number") and .ok == 0
    and .steps == ["lint", "unit"]
    and .lines == ["! lint: kontajner app-php nebeží", "! unit: kontajner app-php nebeží"]' || return 1
  pre_bash 'git commit -m "x"'
  want_decision deny && want_json '.hookSpecificOutput.permissionDecisionReason
    | contains("commit gate") and contains("Posledná kontrola skončila PARTIAL:\n! lint: kontajner app-php nebeží\n! unit:")
      and contains("vypnutie krokov by dalo SKIP, nie PASS")
      and contains("navrhni používateľovi spustiť kontajner app-php a kontrolu zopakuj")
      and contains("disabledRules commitGate v .claude/devkit.json (kontrola tajomstiev aj Stop bežia ďalej; zapíš to používateľovi)")
      and (contains("spusti kontajner") or contains("disabledRules step:") | not)
      and (split("\n") | last | startswith("Spusti kontrolu: bash"))' || return 1
  cfg '.container = "app-php" | .disabledRules = ["commitGate"]'
  pre_bash 'git commit -m "x"'
  want_allow_cfgnote "únik disabledRules commitGate" || return 1
  no_docker_exec
}
t_bash_commit_partial_one_ok() {
  new_case
  local c='.check.steps |= map(select(.id == "unit")) | .check.steps += [{"id": "tests", "run": "vendor/bin/phpunit", "modes": ["quick", "full"]}]'
  cfg "$c"
  add app/Foo.php '$b = 28;'
  g add app/Foo.php
  check --quick --project "$REPO"
  want_rc 4 "check PARTIAL" || return 1
  want_jfile "$PDATA/partial.json" '.ok == 1 and .steps == ["tests"]' || return 1
  pre_bash 'git commit -m "x"'
  want_decision deny "1 ok" && want_json '.hookSpecificOutput.permissionDecisionReason
    | contains("! tests: príkaz sa nedá spustiť (exit 127)")
      and contains("Únik: navrhni používateľovi odstrániť príčinu a kontrolu zopakuj, alebo krok dočasne vypni: disabledRules step:tests v .claude/devkit.json (zapíš to používateľovi).")
      and (contains("kontajner") or contains("commitGate") | not)' "1 ok" || return 1
  jq '.time -= 90000' "$PDATA/partial.json" > "$CASE/partial.json" && mv "$CASE/partial.json" "$PDATA/partial.json"
  pre_bash 'git commit -m "x"'
  want_decision deny "partial.json starší ako 24 h" && want_not 'PARTIAL' "partial.json starší ako 24 h" || return 1
  cfg "$c"' | .disabledRules = ["step:tests"]'
  check --quick --project "$REPO"
  want_rc 0 "únik disabledRules step:tests → PASS" || return 1
  [ ! -f "$PDATA/partial.json" ] || { fail "partial.json ostal po PASS"; return 1; }
  pre_bash 'git commit -m "x"'
  want_allow_cfgnote "commit po PASS"
}
t_bash_commit_partial_all_ids() {
  new_case
  cfg '.check.steps |= map(select(.id == "unit")) | .check.steps += [range(1; 8) as $i | {"id": "b\($i)", "run": "vendor/bin/b\($i)", "modes": ["quick"]}]'
  add app/Foo.php '$b = 29;'
  g add app/Foo.php
  check --quick --project "$REPO"
  want_rc 4 "check PARTIAL" || return 1
  want_jfile "$PDATA/partial.json" '.ok == 1 and .steps == ["b1", "b2", "b3", "b4", "b5", "b6", "b7"] and (.lines | length) == 5' || return 1
  pre_bash 'git commit -m "x"'
  want_decision deny && want_json '.hookSpecificOutput.permissionDecisionReason
    | contains("! b5: ") and (contains("! b6: ") | not)
      and contains("kroky dočasne vypni: disabledRules step:b1, step:b2, step:b3, step:b4, step:b5, step:b6, step:b7 v .claude/devkit.json")'
}
t_stop_partial_once() {
  new_case
  cfg '.check.steps += [{"id": "tests", "run": "vendor/bin/phpunit", "modes": ["stop"]}]'
  add app/Foo.php '$p = 24;'
  session_files app/Foo.php
  stop_check
  want_rc 0 "1. Stop" && want_no_block "1. Stop" \
    && want_json '.hookSpecificOutput.additionalContext | contains("[partial]") and contains("! tests")' "1. Stop" || return 1
  want_jfile "$PDATA/sessions/$SID.stop.json" '.result == "PARTIAL"' || return 1
  local calls
  calls=$(unit_calls)
  stop_check true
  want_rc 0 "2. Stop" && want_silent "2. Stop" || return 1
  [ "$(unit_calls)" = "$calls" ] || fail "nezmenený hash po PARTIAL, kontrola napriek tomu bežala (unit $calls → $(unit_calls))"
}
t_stop_sessions_separate() {
  new_case
  add app/Foo.php '$p = 25;'
  session_files app/Foo.php
  fail_unit 'Tests\X::testY'
  stop_check
  want_json '.decision == "block"' "A 1. Stop" || return 1
  local a=$SID
  SID="$a-b"
  add app/Old.php '$q = 26;'
  session_files app/Old.php
  stop_check
  want_json '.decision == "block"' "B 1. Stop" || return 1
  SID=$a
  stop_check true
  want_json '.decision == "block"' "A 2. Stop" || return 1
  stop_check true
  want_rc 0 "A 3. Stop" && want_json '(.decision // "") != "block" and (.systemMessage | contains("3"))' "A 3. Stop"
}
t_check_known_failures() {
  new_case
  cfg --arg p 'Tests\\X::testY' '.check.knownFailures = [{"step": "unit", "pattern": $p}]'
  fail_unit 'Tests\X::testY'
  add app/Foo.php '$m = 13;'
  check --quick --project "$REPO"
  want_rc 0 "jediné zlyhanie je známe" && want_out 'známe zlyhania' "jediné zlyhanie je známe" \
    && want_out 'PASS · 1 ok · 1 známe · 0 fail' "jediné zlyhanie je známe" || return 1
  fail_unit 'Tests\X::testY' 'Tests\X::testZ'
  check --quick --project "$REPO"
  want_rc 1 "neznáme zlyhanie testZ"
}
t_check_auto_full() {
  new_case
  add app/models/UserModel.php '$n = 14;'
  check --auto --project "$REPO"
  want_rc 0 "zmena v fullWhen" && want_out 'check full: PASS' "zmena v fullWhen" || return 1
  want_file "$REPO/.marks/ran-fullonly" "krok fullonly (modes [full])" || return 1
  want_jfile "$PDATA/pass.json" '.mode == "full"' || return 1
  g commit -qam model
  rm -f "$REPO/.marks/ran-fullonly"
  add app/Foo.php '$o = 15;'
  check --auto --project "$REPO"
  want_rc 0 "zmena mimo fullWhen" && want_out 'check quick: PASS' "zmena mimo fullWhen" || return 1
  [ ! -f "$REPO/.marks/ran-fullonly" ] || { fail "--auto bez fullWhen spustil full krok"; return 1; }
  want_jfile "$PDATA/pass.json" '.mode == "quick"'
}
t_check_no_config() {
  new_case nocfg
  check
  want_rc 3 && want_out 'devkit.json' && want_out '/dev:project-init'
}
t_check_changed_lines_only() {
  new_case
  cfg '.check.steps |= map(if .id == "lint" then .changedLinesOnly = true else . end)'
  add app/LegacyLint.php '$v = 22;'
  check --quick --project "$REPO"
  want_rc 0 "len pôvodná chyba na riadku 2" || return 1
  add app/LegacyLint.php '$w = 23; // LINTERR'
  check --quick --project "$REPO"
  want_rc 1 "nová chyba na riadku 5" && want_out 'LegacyLint.php:5' "nová chyba" && want_not 'LegacyLint.php:2' "nová chyba"
}

# ---------------------------------------------------------------- stop-check

t_stop_block() {
  new_case
  add app/Foo.php '$p = 16;'
  session_files app/Foo.php
  fail_unit 'Tests\X::testY'
  stop_check
  want_rc 0 && want_json '.decision == "block" and (.reason | length > 0)
    and (.reason | contains("unit")) and (.reason | split("\n") | length <= 20)
    and (.reason | contains("zmeny tejto session")) and (.reason | contains("knownFailures"))
    and (.reason | contains("súhlas"))'
}
t_stop_fixed_then_fast() {
  new_case
  add app/Foo.php '$p = 16;'
  session_files app/Foo.php
  fail_unit 'Tests\X::testY'
  stop_check
  want_json '.decision == "block"' "zlyhanie" || return 1
  rm -f "$REPO/.marks/fail-unit"
  add app/Foo.php '$fix = 16;'
  stop_check true
  want_rc 0 "po oprave" && want_no_stdout "po oprave" || return 1
  local calls
  calls=$(unit_calls)
  stop_check
  want_rc 0 "nezmenený stav" && want_silent "nezmenený stav" || return 1
  [ "$(unit_calls)" = "$calls" ] || fail "nezmenený hash, kontrola napriek tomu bežala (unit $calls → $(unit_calls))"
}
t_stop_cap3() {
  new_case
  add app/Foo.php '$p = 16;'
  session_files app/Foo.php
  fail_unit 'Tests\X::testY'
  stop_check false
  want_json '.decision == "block"' "1. Stop" || return 1
  stop_check true
  want_json '.decision == "block"' "2. Stop" || return 1
  stop_check true
  want_rc 0 "3. Stop" && want_json '(.decision // "") != "block"
    and (.systemMessage | contains("[dev-kit]")) and (.systemMessage | contains("3"))
    and (.systemMessage | contains("disabledRules stopCheck"))' "3. Stop"
}
t_stop_replay_same_fail() {
  new_case
  cfg '.pairs += [{"id": "doc", "when": "docs/**", "say": "DOCSAY"}]'
  add app/Foo.php '$p = 16;'
  session_files app/Foo.php
  fail_unit 'Tests\X::testY'
  stop_check
  want_json '.decision == "block" and (.reason | contains("blok 1/2"))' "1. Stop" || return 1
  [ "$(unit_calls)" = 1 ] || { fail "1. Stop: unit $(unit_calls)×, čakal som 1"; return 1; }
  want_jfile "$PDATA/sessions/$SID.stop.json" '.result == "FAIL" and .fails == 1 and (.ctx | length > 0)
    and (.reason | contains("testY")) and (.reason | split("\n") | length <= 20)' || return 1
  session_files app/Foo.php docs/handoff.md
  stop_check true
  want_rc 0 "2. Stop" && want_json '.decision == "block" and (.reason | contains("blok 2/2"))
    and (.reason | contains("súbory session sa nezmenili")) and (.reason | contains("testY"))
    and (.reason | contains("[pair:doc] DOCSAY")) and (.reason | contains("log: "))
    and (.reason | split("\n") | length <= 20)' "2. Stop" || return 1
  [ "$(unit_calls)" = 1 ] || { fail "2. Stop s rovnakým obsahom spustil krok znova (unit $(unit_calls)×)"; return 1; }
  stop_check true
  want_rc 0 "3. Stop" && want_json '(.decision // "") != "block" and (.systemMessage | contains("(3×)"))' "3. Stop" || return 1
  [ "$(unit_calls)" = 1 ] || fail "3. Stop spustil krok (unit $(unit_calls)×)"
}
t_stop_replay_needs_same_state() {
  new_case
  add app/Foo.php '$p = 16;'
  session_files app/Foo.php
  fail_unit 'Tests\X::testY'
  stop_check
  want_json '.decision == "block"' "1. Stop" || return 1
  local stf="$PDATA/sessions/$SID.stop.json"
  jq 'del(.reason, .ctx, .log)' "$stf" > "$stf.old" && mv "$stf.old" "$stf"
  stop_check true
  want_json '.decision == "block" and (.reason | contains("blok 2/2"))
    and (.reason | contains("nezmenili") | not)' "stop.json bez reason" || return 1
  [ "$(unit_calls)" = 2 ] || { fail "stop.json bez reason: kontrola sa nezopakovala (unit $(unit_calls)×)"; return 1; }
  add app/Foo.php '$p2 = 17;'
  stop_check true
  want_json '.decision == "block" and (.reason | contains("blok 1/2"))' "zmenený súbor session" || return 1
  add README.md 'mimo session'
  stop_check true
  want_json '.decision == "block" and (.reason | contains("blok 2/2"))
    and (.reason | contains("nezmenili") | not)' "zmenený súbor mimo session" || return 1
  [ "$(unit_calls)" = 4 ] || { fail "zmena mimo session: kontrola sa nezopakovala (unit $(unit_calls)×)"; return 1; }
  cfg --arg p 'Tests\\X::testY' '.check.knownFailures = [{"step": "unit", "pattern": $p}]'
  stop_check true
  want_rc 0 "zmenený devkit.json" && want_no_block "zmenený devkit.json" || return 1
  [ "$(unit_calls)" = 5 ] || fail "zmenený devkit.json: kontrola sa nezopakovala (unit $(unit_calls)×)"
}
t_stop_pair_once() {
  local rel=libs/Validator/Validator.php
  new_case
  add "$rel" '$q = 17;'
  session_files "$rel"
  stop_check
  want_rc 0 "1. Stop" && want_json '(.decision // "") != "block" and .hookSpecificOutput.hookEventName == "Stop"
    and (.hookSpecificOutput.additionalContext | contains("regresný test"))
    and (.hookSpecificOutput.additionalContext | contains("[pair:validator-test]"))' "1. Stop" || return 1
  add "$rel" '$r = 18;'
  stop_check true
  want_rc 0 "2. Stop" && want_no_stdout "2. Stop (pripomienka už bola)" || return 1
  SID="$SID-b"
  session_files "$rel"
  add "$rel" '$s = 19;'
  stop_check
  want_json '(.decision // "") != "block" and (.hookSpecificOutput.additionalContext | contains("regresný test"))' "nová session"
}
t_stop_pair_unless() {
  local rel=libs/Validator/Validator.php
  new_case
  add "$rel" '$q = 17;'
  add tests/FooTest.php '$q2 = 17;'
  session_files "$rel"
  stop_check
  want_allow
}
t_stop_pair_after_commit() {
  new_case
  cfg '.pairs = [{"id": "app-test", "when": "app/**", "unless": "tests/**", "say": "PAIRSAY app"}]'
  add app/Foo.php '$a = 1;'
  on_edit app/Foo.php
  want_allow "session a: on-edit" || return 1
  [ "$(cat "$PDATA/sessions/$SID.head" 2>/dev/null)" = "$(git -C "$REPO" rev-parse HEAD)" ] ||
    fail ".head nie je HEAD zo začiatku session ($(cat "$PDATA/sessions/$SID.head" 2>/dev/null))" || return 1
  add tests/FooTest.php '$a = 1;'
  on_edit tests/FooTest.php
  g commit -qam a
  stop_check
  want_rc 0 "session a" && want_no_block "session a" && want_not "[pair:" "session a" || return 1
  SID="$SID-b"
  add app/Foo.php '$b = 2;'
  on_edit app/Foo.php
  add tests/FooTest.php '$b = 2;'
  g commit -qam b
  stop_check
  want_rc 0 "session b (test len cez Bash)" && want_no_block "session b" && want_not "[pair:" "session b" || return 1
  SID="$SID-c"
  add app/Foo.php '$c = 3;'
  on_edit app/Foo.php
  g commit -qam c
  stop_check
  want_rc 0 "session c (bez testu)" && want_json '(.decision // "") != "block"
    and (.hookSpecificOutput.additionalContext | contains("[pair:app-test] PAIRSAY app"))' "session c (bez testu)"
}
t_stop_guard() {
  new_case
  add app/Foo.php 'dump($foo);'
  session_files app/Foo.php
  stop_check
  want_rc 0 && want_json '.decision == "block" and (.reason | contains("app/Foo.php:4"))'
}
t_container_down() {
  new_case
  DOCKER_OK=1
  cfg '.container = "app-php"'
  add app/Foo.php '$a = 1; // LINTERR'
  on_edit app/Foo.php
  want_allow "on-edit (lint sa preskočí)" || return 1
  session_files app/Foo.php
  fail_unit 'Tests\X::testY'
  stop_check
  want_rc 0 "stop-check" && want_no_block "stop-check" || return 1
  [ "$(unit_calls)" = 0 ] || { fail "stop-check: unit bežal na hoste napriek container"; return 1; }
  card
  want_rc 0 "session-card" && want_out 'app-php NEBEŽÍ' "session-card" || return 1
  no_docker_exec
}
t_stop_no_session() {
  new_case
  add app/Foo.php '$t = 20;'
  fail_unit 'Tests\X::testY'
  stop_check
  want_allow || return 1
  [ "$(unit_calls)" = 0 ] || fail "kontrola bežala bez súborov session"
}

# ---------------------------------------------------------------- session-card

t_card_hint_once() {
  new_case nocfg
  card
  want_rc 0 && want_out '/dev:project-init' || return 1
  [ "$(nlines "$OUT")" = 1 ] || { fail "čakal som 1 riadok$(ctx)"; return 1; }
  case "$SYSMSG" in *'/dev:project-init'*) ;; *) fail "systemMessage bez /dev:project-init: $(flat "$RAW")"; return 1 ;; esac
  card
  want_rc 0 "2. štart" && want_silent "2. štart v ten istý deň"
}
t_card_stack_maintenance() {
  new_case
  kit_scripts upstream || return 1
  card
  want_rc 0 && want_out 'údržba kitu' || return 1
  printf '%s\n' "$OUT" | head -1 | grep -qF 'php-nette' || { fail "1. riadok bez stacku$(ctx)"; return 1; }
  printf '%s\n' "$OUT" | head -1 | grep -qF '[dev-kit]' || { fail "1. riadok bez [dev-kit]$(ctx)"; return 1; }
  [ "$(nlines "$OUT")" -le 10 ] || { fail "karta má $(nlines "$OUT") riadkov (limit 10)$(ctx)"; return 1; }
  want_out 'Stop kontrola on' && want_out 'commit gate on' && want_out 'kontroly: /dev:check' || return 1
  printf '{"lastUpstreamCheck": %s}\n' $(($(now) - 40 * 86400 - 60)) > "$DATA/maintenance.json"
  card
  want_rc 0 "maintenance.json starší ako 30 dní" && want_out 'pred 40 dňami' "maintenance.json starší ako 30 dní" || return 1
  printf '{"lastUpstreamCheck": %s}\n' "$(now)" > "$DATA/maintenance.json"
  card
  want_rc 0 "čerstvý maintenance.json" && want_not 'údržba kitu' "čerstvý maintenance.json"
}
t_card_maintenance_checkout_only() {
  new_case
  kit_scripts || return 1
  card
  want_rc 0 "bez tools/upstream.sh" && want_not 'údržba' "bez tools/upstream.sh" || return 1
  case "$SYSMSG" in *'údržba'*) fail "bez tools/upstream.sh: systemMessage $(flat "$SYSMSG")"; return 1 ;; esac
  printf '{"lastUpstreamCheck": %s}\n' $(($(now) - 40 * 86400 - 60)) > "$DATA/maintenance.json"
  card
  want_rc 0 "bez tools/upstream.sh, starý maintenance.json" &&
    want_not 'údržba' "bez tools/upstream.sh, starý maintenance.json" || return 1
  case "$SYSMSG" in *'údržba'*) fail "starý maintenance.json: systemMessage $(flat "$SYSMSG")"; return 1 ;; esac
  mkdir -p "$CASE/kit/tools" && : > "$CASE/kit/tools/upstream.sh"
  card
  want_rc 0 "s tools/upstream.sh" && want_out "pred 40 dňami → make -C $CASE/kit upstream" "s tools/upstream.sh" || return 1
  case "$SYSMSG" in *'[dev-kit] údržba kitu'*) ;; *) fail "s tools/upstream.sh: systemMessage $(flat "$RAW")"; return 1 ;; esac
  rm -f "$DATA/maintenance.json"
  card
  want_rc 0 "bez maintenance.json" && want_out "ešte nebežala → make -C $CASE/kit upstream" "bez maintenance.json"
}
t_card_handoff() {
  new_case
  run session-card --record-handoff docs/handoff.md 'Môj handoff'
  want_rc 0 "--record-handoff" || return 1
  want_jfile "$PDATA/last-handoff.json" '.title == "Môj handoff" and (.path | contains("docs/handoff.md")) and has("time")' ||
    return 1
  card
  want_rc 0 && want_out 'posledný handoff' && want_out 'Môj handoff' || return 1
  printf '{"time": %s, "title": "Starý handoff", "path": "docs/handoff.md"}\n' $(($(now) - 25 * 3600)) > "$PDATA/last-handoff.json"
  card
  want_rc 0 "handoff starší ako 24 h" && want_not 'posledný handoff' "handoff starší ako 24 h"
}

# ---------------------------------------------------------------- test-lock, stats

t_test_lock_roundtrip() {
  new_case
  run test-lock lock tests/FooTest.php --project "$REPO"
  want_rc 0 "lock" || return 1
  [ "$(nlines "$OUT")" = 1 ] || { fail "lock: čakal som 1 riadok$(ctx)"; return 1; }
  want_jfile "$PDATA/test-lock.json" '(.files | index("tests/FooTest.php")) != null and (.time | type) == "number"' || return 1
  run test-lock status --project "$REPO"
  want_rc 0 "status" && want_out 'tests/FooTest.php' "status" || return 1
  card
  want_rc 0 "session-card" && want_out 'zamknutý test: tests/FooTest.php' "session-card" || return 1
  pre_edit tests/FooTest.php
  want_decision deny "pre-edit po lock" || return 1
  run test-lock unlock --project "$REPO"
  want_rc 0 "unlock" || return 1
  [ "$(nlines "$OUT")" = 1 ] || { fail "unlock: čakal som 1 riadok$(ctx)"; return 1; }
  run test-lock status --project "$REPO"
  want_rc 0 "status po unlock" && want_not 'tests/FooTest.php' "status po unlock" || return 1
  pre_edit tests/FooTest.php
  want_allow "pre-edit po unlock"
}
t_stats() {
  new_case
  # záznamy cez dk_log z lib.sh — formát riadku (ts…) určuje implementácia
  (cd "$REPO" && bash -c '
    . "$1" || exit 90
    set +eu
    dk_init || exit 91
    for i in 1 2 3 4 5 6 7; do dk_log on-edit guard:debug-php block app/Foo.php 12; done
    dk_log pre-bash commitGate deny "" 40
    dk_log pre-bash commitGate deny "" 40
    dk_log stop-check stopCheck block "" 500
    dk_log stop-check stopCheck pass "" 500
    dk_log pre-bash commitGate deny k1 40
    dk_log pre-bash commitGate pass k1 40
    dk_log pre-bash commitGate pass k2 40
  ' _ "$S/lib.sh") < /dev/null > "$CASE/log.out" 2>&1
  local rc=$?
  [ "$rc" = 0 ] || { fail "príprava cez lib.sh/dk_log zlyhala (exit $rc): $(flat "$(cat "$CASE/log.out")")"; return 1; }
  local n
  n=$(grep -c . "$DATA/decisions.jsonl" 2>/dev/null)
  [ "${n:-0}" -ge 14 ] || { fail "decisions.jsonl má ${n:-0} riadkov, čakal som 14"; return 1; }
  jq -e . "$DATA/decisions.jsonl" >/dev/null 2>&1 || { fail "decisions.jsonl nie je platné JSONL"; return 1; }
  run stats --days 30 --all
  want_rc 0 && want_out 'guard:debug-php' && want_out 'commitGate' || return 1
  [ "$(nlines "$OUT")" -le 20 ] || { fail "stdout má $(nlines "$OUT") riadkov (limit 20)$(ctx)"; return 1; }
  printf '%s\n' "$OUT" | grep -F 'guard:debug-php' | grep -q 7 || { fail "počet 7 pri guard:debug-php chýba$(ctx)"; return 1; }
  printf '%s\n' "$OUT" | grep -F 'commitGate' | grep -q 2 || { fail "počet 2 pri commitGate chýba$(ctx)"; return 1; }
  want_out 'PASS na prvý raz 1 z 2' && want_out 'obdobie: 30 dní' || return 1
  run stats --days 1 --all
  want_rc 0 "--days 1" && want_out 'obdobie: 1 deň' "--days 1"
}

# ---------------------------------------------------------------- lib.sh

t_glob() {
  new_case
  local cases bad
  cases='0|app/a/b.php|app/**
1|a/b.php|*.php
0|b.php|*.php
0|b.php|**/*.php
0|x/y/b.php|**/*.php
0|tests/Unit/A.php|tests/**
1|app/models.php|app/models/**
0|db/migrations/20260101000000_init.php|db/migrations/**
0|.env|**/.env
0|a/b/.env|**/.env
0|app/config/config.local.neon|app/config/config.local.neon
1|x/app/config/config.local.neon|app/config/config.local.neon
0|src/x/y/z.py|src/**.py
0|app/x.php|app/**/x.php
0|app/a/b/x.php|app/**/x.php
1|app/a/y.php|app/**/x.php
0|a/b.php|a/?.php
1|a/bc.php|a/?.php
1|fooXphp|foo.php'
  bad=$(printf '%s\n' "$cases" | bash -c '
    . "$1" >/dev/null 2>&1 || { echo "lib.sh sa nedá načítať"; exit 0; }
    set +eu
    while IFS="|" read -r want path glob; do
      dk_glob_match "$path" "$glob"; got=$?
      [ "$got" = 0 ] || got=1
      [ "$got" = "$want" ] || printf "%s ~ %s → %s; " "$path" "$glob" "$([ "$want" = 0 ] && echo "mal zhodovať" || echo "nemal zhodovať")"
    done
  ' _ "$S/lib.sh" 2>&1)
  [ -z "$bad" ] || fail "dk_glob_match: $bad"
}
t_worktree_workdir() {
  new_case
  cfg '.container = "c" | .appRoot = "/application"'
  local wt="$REPO/.claude/worktrees/x"
  git -C "$REPO" worktree add -q --detach "$wt" >/dev/null 2>&1 || { fail "fixture: git worktree add"; return 1; }
  mkdir -p "$wt/.claude"
  cp "$REPO/.claude/devkit.json" "$wt/.claude/devkit.json"
  local got_wt got_main
  got_wt=$(cd "$wt" && CLAUDE_PROJECT_DIR="$wt" bash -c '. "$1" && dk_init && dk_workdir' _ "$S/lib.sh" 2>/dev/null < /dev/null | tail -1)
  got_main=$(cd "$REPO" && CLAUDE_PROJECT_DIR="$REPO" bash -c '. "$1" && dk_init && dk_workdir' _ "$S/lib.sh" 2>/dev/null < /dev/null | tail -1)
  [ "$got_wt" = "/application/.claude/worktrees/x" ] ||
    { fail "worktree: dk_workdir = '$got_wt', čakal som /application/.claude/worktrees/x"; return 1; }
  [ "$got_main" = "/application" ] || fail "hlavné repo: dk_workdir = '$got_main', čakal som /application"
}
# check.sh v kontajneri: docker exec -i -w <appRoot + relpath(P, MAIN)> <c> sh -c (SPEC §3)
t_worktree_exec() {
  new_case
  DOCKER_OK=1
  export DK_FAKE_DOCKER_RUNNING=1
  cfg '.container = "c" | .appRoot = "/application"'
  local wt="$REPO/.claude/worktrees/x" out="$CASE/wt-out" d
  git -C "$REPO" worktree add -q --detach "$wt" >/dev/null 2>&1 &&
    git -C "$REPO" worktree add -q --detach "$out" >/dev/null 2>&1 || { fail "fixture: git worktree add"; return 1; }
  for d in "$wt" "$out"; do mkdir -p "$d/.claude" && cp "$REPO/.claude/devkit.json" "$d/.claude/devkit.json"; done
  check --quick --project "$REPO"
  want_rc 0 "hlavné repo" || return 1
  docker_calls | grep '^exec ' | grep -qF -- '-w /application c sh -c' ||
    { fail "hlavné repo: čakal som docker exec -i -w /application c sh -c …: $(flat "$(docker_calls)")"; return 1; }
  : > "$CASE/docker.calls"
  check --quick --project "$wt"
  want_rc 0 "worktree v mounte" || return 1
  docker_calls | grep '^exec ' | grep -qF -- '-w /application/.claude/worktrees/x c sh -c' ||
    { fail "worktree: čakal som docker exec -i -w /application/.claude/worktrees/x c sh -c …: $(flat "$(docker_calls)")"; return 1; }
  : > "$CASE/docker.calls"
  check --quick --project "$out"
  want_rc 4 "worktree mimo mountu" && want_out 'worktree mimo mountu kontajnera' "worktree mimo mountu" || return 1
  no_docker_exec "worktree mimo mountu"
}

# ---------------------------------------------------------------- pre-bash: rozpoznanie a repo

SECRET_PHP='$password = "SuperSecretValue123";'
bad_php() { put app/Bad.php '<?php'; add app/Bad.php "$SECRET_PHP"; }

t_bash_detect_global_opts() {
  new_case
  add app/Foo.php '$f = 6;'
  g add app/Foo.php
  ln -s "$REPO" "$CASE/sp ace"
  local c
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    pre_bash "$c"
    want_decision deny "$c" || return 1
  done <<EOF
git --no-pager commit -m x
GIT_EDITOR=true git commit -m x
A=1 B="x y" git commit -m x
git -P commit -m x
git --git-dir="$REPO/.git" --work-tree="$REPO" commit -m x
git -C "$CASE/sp ace" commit -m x
command git commit -m x
/usr/bin/git commit -m x
{ git commit -m x; }
if true; then git commit -m x; fi
EOF
  for c in 'git log --grep commit' 'git -C x log --grep commit' 'legit commit'; do
    pre_bash "$c"
    want_allow "$c" || return 1
  done
}
t_bash_stage_alias() {
  new_case
  add app/Foo.php '$f = 6;'
  pre_bash 'git stage app/Foo.php && git commit -m x'
  want_decision deny && want_out 'app/Foo.php'
}
t_bash_cd_var_project() {
  new_case
  bad_php
  pre_bash 'cd "$CLAUDE_PROJECT_DIR" && git add app/Bad.php && git commit -m b' "$CASE"
  want_decision deny && want_out 'app/Bad.php'
}
t_bash_cd_chain_relative() {
  new_case
  bad_php
  pre_bash 'cd app; cd ..; git add app/Bad.php && git commit -m b'
  want_decision deny && want_out 'app/Bad.php'
}
t_bash_cd_unresolvable_fallback() {
  new_case
  bad_php
  pre_bash 'cd "$(git rev-parse --show-toplevel)" && git add app/Bad.php && git commit -m b'
  want_decision deny && want_out 'app/Bad.php'
}
t_bash_cd_after_commit() {
  new_case
  bad_php
  g add app/Bad.php
  pre_bash 'git commit -m b && cd /tmp'
  want_decision deny && want_out 'app/Bad.php'
}
t_bash_cd_quoted_space() {
  new_case
  bad_php
  ln -s "$REPO" "$CASE/sp ace"
  pre_bash "cd \"$CASE/sp ace\" && git add app/Bad.php && git commit -m b" "$CASE"
  want_decision deny && want_out 'app/Bad.php'
}
# Dôvod deny obsahuje text (úvodzovky v JSON sú escapované, want_out by ich nenašiel).
want_reason() {
  printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null \
    | LC_ALL=C grep -qF -- "$1" || fail "${2:+$2: }dôvod neobsahuje '$1'$(ctx)"
}
# other_repo — $CASE/other: repo bez .claude/devkit.json so staged tajomstvom; nastaví O
other_repo() {
  O="$CASE/other"
  mkdir -p "$O/app" && git -C "$O" init -q && printf '<?php\n%s\n' "$SECRET_PHP" > "$O/app/Bad.php" \
    && git -C "$O" add app/Bad.php || fail "fixture: $O"
}
t_bash_cd_other_repo_allow() {
  new_case
  bad_php
  g add app/Bad.php
  other_repo || return 1
  local c
  for c in "git -C \"$O\" commit -m x" "cd -- \"$O\" && git commit -m x" "cd -P \"$O\" && git commit -m x" \
    "cd -L -P -- $O; git commit -m x"; do
    pre_bash "$c"
    want_allow "$c" || return 1
  done
  pre_bash 'git commit -m x'
  want_decision deny "kontrola: commit v cwd session" && want_out 'app/Bad.php' "kontrola" || return 1
  for c in "cd -e \"$O\"; git commit -m x" "cd -@ \"$O\"; git commit -m x" "cd -L -Pe -- $O; git commit -m x" \
    "cd -- -P \"$O\"; git commit -m x" "cd -- -- \"$O\"; git commit -m x" "cd -P -- -L $O; git commit -m x"; do
    pre_bash "$c"
    want_decision deny "$c" && want_out 'app/Bad.php' "$c" && want_reason 'sa nedal určiť (cd -' "$c" || return 1
  done
}
t_bash_cd_unresolved_note() {
  new_case
  bad_php
  other_repo || return 1
  local add='git add app/Bad.php && git commit -m b' raw long
  pre_bash "cd \"\$(nieco)\" && $add"
  want_decision deny '$(nieco)' && want_out 'app/Bad.php' '$(nieco)' || return 1
  want_reason 'sa nedal určiť (cd "$(nieco)") — použi doslovnú cestu' || return 1
  want_json '.hookSpecificOutput.permissionDecisionReason | startswith("[dev-kit] cieľ `cd`/`git -C` sa nedal určiť")' \
    "riadok je prvý" || return 1
  pre_bash "D=\"$O\"; cd \"\$D\" && $add"
  want_decision deny 'D=' && want_out 'app/Bad.php' 'D=' && want_reason 'sa nedal určiť (cd "$D")' 'D=' || return 1
  pre_bash 'git -C "$X" add app/Bad.php && git -C "$X" commit -m b'
  want_decision deny '-C $X' && want_reason 'sa nedal určiť (-C "$X")' '-C $X' || return 1
  pre_bash "cd ~nikto-selftest && $add"
  want_decision deny '~iný' && want_reason 'sa nedal určiť (cd ~nikto-selftest)' '~iný' || return 1
  g add app/Bad.php
  pre_bash "cd \"\$X\"; cd app; git commit -m b"
  want_decision deny 'relatívny cd za nerozriešeným' && want_reason 'sa nedal určiť (cd "$X")' 'relatívny cd' || return 1
  raw='"$(git rev-parse --show-toplevel)/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'
  long="cd $raw"
  pre_bash "$long && $add"
  want_decision deny 'dlhý cieľ' && want_reason "(${long:0:59}…)" 'dlhý cieľ' || return 1
  pre_bash "cd \"\$X\"; cd \"$REPO\" && $add" "$CASE"
  want_decision deny 'absolútny cd za nerozriešeným' && want_out 'app/Bad.php' 'absolútny cd' \
    && want_not 'sa nedal' 'absolútny cd'
}
t_bash_cd_pwd_base() {
  new_case
  bad_php
  g add app/Bad.php
  local c
  for c in "cd \"$REPO\" && cd \"\$(pwd)\" && git commit -m b" "cd \"$REPO/app\"; cd \$PWD/..; git commit -m b" \
    "cd \"$REPO/app\" && cd \"\`pwd\`/..\" && git commit -m b" "x=\$(cd \"$REPO\" && git commit -m b)"; do
    pre_bash "$c" "$CASE"
    want_decision deny "$c" && want_out 'app/Bad.php' "$c" && want_not 'sa nedal' "$c" || return 1
  done
}
t_bash_multiline_commits() {
  new_case
  add app/Foo.php '$f = 6;'
  bad_php
  check --quick --project "$REPO" --files app/Foo.php
  want_rc 0 "check --files app/Foo.php" || return 1
  pre_bash "$(printf '%s\n%s' 'git add app/Foo.php && git commit -m a' 'git add app/Bad.php && git commit -m b')"
  want_decision deny && want_out 'app/Bad.php' && want_not 'SuperSecretValue123'
}
t_bash_add_force_forbidden() {
  new_case
  printf '.test-credentials\n' > "$REPO/.gitignore"
  g add .gitignore && g commit -qm ignore
  put .test-credentials 'APP_TEST_PASS=hunter2pass'
  pre_bash 'git add -f .test-credentials && git commit -m x'
  want_decision deny "-f" && want_out 'zakázaný súbor' "-f" && want_out ' — ****' "-f" && want_not 'hu****' "-f" \
    && want_not 'hunter2pass' "-f" || return 1
  pre_bash 'git add --force .test-credentials; git commit -m x'
  want_decision deny "--force" && want_out 'zakázaný súbor' "--force" && want_out ' — ****' "--force" && want_not 'hu****' "--force"
}
t_bash_add_force_all() {
  new_case
  add app/Foo.php '$f = 6;'
  pre_bash 'git add -A -f && git commit -m x'
  want_decision deny && want_out 'git add -A -f'
}
t_bash_add_patch_same_cmd() {
  new_case
  add app/Foo.php '$f = 6;'
  check --quick --project "$REPO"
  want_rc 0 "check.sh --quick" || return 1
  pre_bash 'git add -p app/Foo.php && git commit -m x'
  want_decision deny && want_out 'čiastočný stage' || return 1
  want_logged pre-bash commitGate deny
}
t_bash_quoted_name() {
  new_case
  put 'app/q"x.php' '<?php'
  g add 'app/q"x.php'
  pre_bash 'git commit -m x'
  want_decision deny && want_out 'nepodporovaný názov'
}
t_bash_heredoc_message() {
  new_case
  add app/Foo.php '$f = 6;'
  check --quick --project "$REPO"
  want_rc 0 "check.sh --quick" || return 1
  pre_bash "$(printf '%s\n' 'git add app/Foo.php && git commit -m "$(cat <<'"'"'EOF'"'"'' 'fix: x' '' 'git add -p v správe' 'git commit gate' 'EOF' ')"')"
  want_allow "riadky heredocu nie sú príkazy"
}
t_bash_secret_placeholder_anchor() {
  new_case
  put config/b.txt "\$a = ['password' => '\$up3rS3cret!Long',"
  add config/b.txt "  'token' => '...realTokenValue123'];"
  g add config/b.txt
  pre_bash 'git commit -m x'
  want_decision deny && want_out '(2)' && want_out 'config/b.txt:1' && want_out 'config/b.txt:2' || return 1
  new_case
  put config/a.yaml 'password: "${DB_PASS}"'
  add config/a.yaml "'password' => \"\$pwd\""
  g add config/a.yaml
  pre_bash 'git commit -m x'
  want_allow "zástupné hodnoty"
}

# ---------------------------------------------------------------- worktree (D16)

t_worktree_check_project_main() {
  new_case
  local wt="$REPO/.claude/worktrees/wt1" wph log
  wt_add "$wt" || return 1
  printf '%s\n' '$wt = 1;' >> "$wt/app/Foo.php"
  wph=$(printf %s "$wt" | git hash-object --stdin | cut -c1-12)
  RUNDIR=$wt check --quick --project "$REPO"
  want_rc 0 && want_out 'check quick: PASS' || return 1
  log=$(printf '%s\n' "$OUT" | sed -n 's/^log: //p' | tail -1)
  grep -q '^# súbory: .*app/Foo\.php' "$log" 2>/dev/null || { fail "log bez app/Foo.php v '# súbory:'$(ctx)"; return 1; }
  want_file "$DATA/projects/$wph/pass.json" "pass.json pod phash worktree" || return 1
  [ ! -f "$PDATA/pass.json" ] || fail "pass.json zapísaný pod phash hlavného checkoutu"
}
t_worktree_lock_project_main() {
  new_case
  local wt="$REPO/.claude/worktrees/wt1" other="$CASE/other" oph
  wt_add "$wt" || return 1
  RUNDIR=$wt run test-lock lock tests/FooTest.php --project "$REPO"
  want_rc 0 "lock z worktree" || return 1
  hook pre-edit "$(j_file PreToolUse "$wt/tests/FooTest.php")"
  want_decision deny "pre-edit vo worktree" || return 1
  cp -Rp "$TPL" "$other"
  mkdir -p "$other/.claude" && cp "$REPO/.claude/devkit.json" "$other/.claude/devkit.json"
  oph=$(printf %s "$other" | git hash-object --stdin | cut -c1-12)
  RUNDIR=$wt run test-lock lock tests/FooTest.php --project "$other"
  want_rc 0 "lock --project iné repo" || return 1
  want_file "$DATA/projects/$oph/test-lock.json" "--project iného repa ostáva tým repom"
}
t_worktree_handoff_project_main() {
  new_case
  local wt="$REPO/.claude/worktrees/wt1"
  wt_add "$wt" || return 1
  RUNDIR=$wt run session-card --record-handoff docs/h.md T --project "$REPO"
  want_rc 0 "--record-handoff z worktree" || return 1
  card "$wt"
  want_rc 0 && want_out 'posledný handoff'
}

# ---------------------------------------------------------------- reálne výstupy nástrojov

t_edit_phpcs_no_files_checked() {
  new_case
  cfg --arg c "$(real phpcs-excluded-by-ruleset 16)" '.lint[".php"] = [$c]'
  add app/Foo.php '$f = 6;'
  on_edit app/Foo.php
  want_rc 0 && want_silent || return 1
  want_logged on-edit 'lint:.php' skip
}
t_check_phpcs_no_files_checked() {
  new_case
  cfg --arg c "$(real phpcs-excluded-by-ruleset 16)" '.check.steps += [{"id": "phpcs", "runFiles": $c, "ext": [".php"], "modes": ["quick"]}]'
  add app/Foo.php '$f = 6;'
  check --quick --project "$REPO"
  want_rc 0 && want_out '– phpcs: nástroj nič neskontroloval (No files were checked)' && want_not 'check quick: FAIL'
}
t_edit_latte_error_unchanged_line() {
  new_case
  cfg --arg c "$(real latte-lint-unclosed-if 1)" '.lint[".latte"] = [$c]'
  put templates/default.latte "$(printf '{block content}\n<p>a</p>\n<p>b</p>\n<p>c</p>\n{/block}\n<p>e</p>')"
  g add templates/default.latte && g commit -qm tpl
  sed '3s/.*/{if $x}/' "$REPO/templates/default.latte" > "$CASE/tpl" && mv "$CASE/tpl" "$REPO/templates/default.latte"
  on_edit templates/default.latte
  want_rc 2 && want_err 'Unexpected {/block}' && want_err '[lint:.latte]'
}
t_check_changed_lines_other_file() {
  new_case
  cfg --arg c "printf '%s\n' '/application/src/Old.php:11:Function old_undefined_fn not found.'; exit 1" \
    '.check.steps += [{"id": "stan", "run": $c, "ext": [".php"], "modes": ["quick"], "changedLinesOnly": true}]'
  put src/Fresh.php '<?php'
  check --quick --project "$REPO"
  want_rc 0 && want_out '✓ stan' && want_out '(len staré nálezy'
}
t_check_crash_not_filtered() {
  new_case
  cfg --arg c "printf '%s\n' 'PHP Fatal error:  Uncaught Error: Class \"X\" not found in /application/vendor/autoload.php:12'; exit 255" \
    '.check.steps += [{"id": "stan", "run": $c, "ext": [".php"], "modes": ["quick"], "changedLinesOnly": true}]'
  add app/Foo.php '$f = 6;'
  check --quick --project "$REPO"
  want_rc 1 && want_out '✗ stan' && want_out 'Fatal error' || return 1
  [ ! -f "$PDATA/pass.json" ] || fail "pass.json zapísaný napriek pádu nástroja"
}
t_check_known_failures_runner_warning() {
  new_case
  cfg --arg c "$(real phpunit-failure-with-runner-warning 1)" --arg p '^Tests\\Unit\\CalcTest::testAdd$' \
    '.check.steps |= map(if .id == "unit" then .run = $c else . end) | .check.knownFailures = [{"step": "unit", "pattern": $p}]'
  add app/Foo.php '$f = 6;'
  check --quick --project "$REPO"
  want_rc 0 && want_out 'známe zlyhania: 1'
}
t_check_strip_ansi() {
  new_case
  local esc log
  esc=$(printf '\033')
  cfg --arg c "$(real phpunit-failure-colors-true 1)" '.check.steps |= map(if .id == "unit" then .run = $c else . end)'
  add app/Foo.php '$f = 6;'
  check --quick --project "$REPO"
  want_rc 1 && want_out 'Tests: 1' || return 1
  ! printf '%s' "$OUT" | LC_ALL=C grep -q "$esc" || { fail "stdout obsahuje ESC$(ctx)"; return 1; }
  log=$(printf '%s\n' "$OUT" | sed -n 's/^log: //p' | tail -1)
  [ -s "$log" ] && ! LC_ALL=C grep -q "$esc" "$log" || fail "log chýba alebo obsahuje ESC"
}
# dk_filter_changed nad zaznamenanými výstupmi: <fixtúra>|<mapa rel:riadok>|<musí ostať>|<nesmie ostať>
t_filter_real_outputs() {
  new_case
  local bad="" name m keep drop got
  while IFS='|' read -r name m keep drop; do
    [ -n "$name" ] || continue
    printf '%s\t%s\n' "${m%:*}" "${m##*:}" > "$CASE/map"
    got=$(bash -c '. "$1" && dk_filter_changed "$2" "$3"' _ "$S/lib.sh" "$FIX/real/$name.txt" "$CASE/map" 2>&1)
    if [ -n "$keep" ]; then printf '%s' "$got" | LC_ALL=C grep -qF -- "$keep" || bad="$bad$name/$m: chýba '$keep'; "; fi
    if [ -n "$drop" ]; then ! printf '%s' "$got" | LC_ALL=C grep -qF -- "$drop" || bad="$bad$name/$m: ostalo '$drop'; "; fi
    if [ -z "$keep" ] && [ -n "$got" ]; then bad="$bad$name/$m: čakal som prázdny výstup, je '$(flat "$got")'; "; fi
  done <<'EOF'
php-l-parse-error|src/Parse.php:3|Parse error: syntax error|
phpstan-raw-new-and-legacy|lib/LegacyStan.php:16|fresh_undefined_fn|legacy_undefined_fn
phpcs-phinx-migration-no-namespace|db/migrations/20260301000000_add_x.php:7|Each class must be in a namespace|
phpcs-phinx-migration-no-namespace|db/migrations/20260301000000_add_x.php:8||
latte-lint-unclosed-if|templates/default.latte:3|Unexpected {/block}|Latte linter
phpcs-excluded-by-ruleset|db/migrations/20260301000000_add_x.php:3|No files were checked|
EOF
  [ -z "$bad" ] || fail "$bad"
}
t_filter_yaml_twig_kept() {
  new_case
  printf 'ERROR  in config/a.yaml\n >> Unable to parse at line 9 (near "x: [").\nsrc/Other.php:3:unrelated\n' > "$CASE/o.txt"
  printf 'config/a.yaml\t2\n' > "$CASE/m.txt"
  local got
  got=$(bash -c '. "$1" && dk_filter_changed "$2" "$3"' _ "$S/lib.sh" "$CASE/o.txt" "$CASE/m.txt" 2>&1)
  case "$got" in *'ERROR  in config/a.yaml'*) ;; *) fail "chýba 'ERROR in': $(flat "$got")"; return 1 ;; esac
  case "$got" in *'>> Unable to parse at line 9'*) ;; *) fail "chýba '>> … at line 9': $(flat "$got")"; return 1 ;; esac
  case "$got" in *unrelated*) fail "ostal riadok inej cesty: $(flat "$got")" ;; esac
}
t_check_changed_lines_stop_only() {
  new_case
  cfg '.check.steps |= map(if .id == "lint" then .run = "sh bin/fake-lint app/LegacyLint.php" | .changedLinesOnly = "stop" else . end)'
  add app/LegacyLint.php '$v = 22;'
  session_files app/LegacyLint.php
  check --stop --session "$SID" --project "$REPO"
  want_rc 0 "--stop" && want_out '(len staré nálezy' "--stop" || return 1
  check --quick --project "$REPO"
  want_rc 1 "--quick (celý súbor)" && want_out 'LegacyLint.php:2' "--quick (celý súbor)"
}
t_check_dash_filename() {
  new_case
  put bin/lint-getopt '#!/bin/sh
bad=0
for a in "$@"; do
  case "$a" in -*) continue ;; esac
  if grep -q LINTERR "$a"; then echo "$a:1:1: error - LINTERR"; bad=1; fi
done
exit $bad'
  cfg '.check.steps |= map(if .id == "lint" then .runFiles = "sh bin/lint-getopt {files}" | .requires = "bin/lint-getopt" else . end)'
  g add bin/lint-getopt && g commit -qm stub
  put '-n.php' '<?php // LINTERR'
  check --quick --project "$REPO"
  want_rc 1 && want_out '✗ lint'
}
t_check_template_latte_all_files() {
  new_case
  local rf
  rf=$(jq -r '.check.steps[] | select(.id == "latte") | .runFiles' "$KIT/plugins/dev/templates/php-nette/devkit.json")
  # latte-lint berie len prvú cestu — krok šablóny musí prejsť všetky súbory
  rf=${rf//php vendor\/bin\/latte-lint/sh bin/lint-one}
  put bin/lint-one '#!/bin/sh
[ "$#" = 1 ] || { echo "lint-one: čakám 1 cestu, mám $#"; exit 2; }
if grep -q LINTERR "$1"; then echo "$1:1:1: error - LINTERR"; exit 1; fi'
  cfg --arg rf "$rf" '.check.steps += [{"id": "latte", "requires": "bin/lint-one", "runFiles": $rf, "ext": [".latte"], "modes": ["quick", "full"]}]'
  g add bin/lint-one && g commit -qm stub
  put app/a.latte 'ok'
  put app/b.latte 'LINTERR'
  check --quick --project "$REPO"
  want_rc 1 && want_out '✗ latte' || return 1
  put app/b.latte 'ok'
  check --quick --project "$REPO"
  want_rc 0 && want_out '✓ latte'
}
t_check_ignores_nested_worktree() {
  new_case
  grep -v '^\.claude/$' "$REPO/.git/info/exclude" > "$CASE/ex" && cp "$CASE/ex" "$REPO/.git/info/exclude"
  wt_add "$REPO/.claude/worktrees/wt1" || return 1
  add app/Foo.php '$f = 6;'
  check --quick --project "$REPO"
  want_rc 0 || return 1
  want_jfile "$PDATA/pass.json" '(.blobs | keys | map(select(startswith(".claude/worktrees/"))) | length) == 0
    and .blobs["app/Foo.php"] != null'
}

# ---------------------------------------------------------------- on-edit: id pravidiel, tajomstvá

t_edit_rule_ids_in_message() {
  new_case
  add app/Foo.php 'dump($a); // LINTERR'
  on_edit app/Foo.php
  want_rc 2 && want_err '[lint:.php, guard:debug-php]' && want_err 'disabledRules' || return 1
  printf '%s\n' "$ERR" | LC_ALL=C grep -q 'app/Foo\.php:4 — debug výpis v kóde \[guard:debug-php\]$' ||
    fail "riadok guardu nekončí [guard:debug-php]$(ctx)"
}
t_edit_guard_count_over_20() {
  new_case
  local i=1
  while [ $i -le 25 ]; do add app/Foo.php "dump($i);"; i=$((i + 1)); done
  on_edit app/Foo.php
  want_rc 2 && want_err 'app/Foo.php: 25 nálezov' && want_err '… ďalšie nálezy: 10'
}
t_edit_secret_added_line() {
  new_case
  add app/Foo.php "$SECRET_PHP"
  on_edit app/Foo.php
  want_rc 2 && want_err '(****)' && want_err '[secrets]' && want_not 'Su****' && want_not 'SuperSecretValue123' || return 1
  want_logged on-edit secrets block
}
t_edit_secret_ignored_file() {
  new_case
  printf 'config/local.php\n' >> "$REPO/.git/info/exclude"
  put config/local.php '<?php'
  add config/local.php "$SECRET_PHP"
  on_edit config/local.php
  want_allow
}

# ---------------------------------------------------------------- pre-edit, dáta

t_pre_edit_lock_path_variants() {
  new_case
  lock_at "$(now)"
  local p
  for p in "$REPO/tests/./FooTest.php" "$REPO/app/../tests/FooTest.php" "$REPO//tests/FooTest.php" "$REPO/Tests/FooTest.php"; do
    hook pre-edit "$(j_file PreToolUse "$p")"
    want_decision deny "$p" || return 1
  done
}
t_pre_edit_migration_case() {
  new_case
  pre_edit DB/Migrations/20260101000000_init.php
  if [ -e "$REPO/DB/Migrations/20260101000000_init.php" ]; then
    want_decision ask && want_out 'db/migrations/20260101000000_init.php je už commitnutá'
  else
    want_allow
  fi
}
t_data_dir_mode() {
  new_case
  local d="$CASE/fresh/data"
  add app/Foo.php '$f = 6;'
  export DEVKIT_DATA="$d"
  on_edit app/Foo.php
  export DEVKIT_DATA="$DATA"
  [ "$(ls -ld "$d" 2>/dev/null | cut -c1-10)" = drwx------ ] || { fail "nový DEVKIT_DATA: $(ls -ld "$d" 2>&1)"; return 1; }
  chmod 755 "$DATA"
  on_edit app/Foo.php
  [ "$(ls -ld "$DATA" | cut -c1-10)" = drwx------ ] || fail "existujúci DEVKIT_DATA: $(ls -ld "$DATA")"
}

# ---------------------------------------------------------------- stop-check: pripomienky

t_stop_pairs_after_pass_shortcut() {
  new_case
  cfg '.pairs = [{"id": "app-x", "when": "app/x.php", "say": "PAIRSAY app-x"}]'
  put app/x.php '<?php'
  on_edit app/x.php
  stop_check
  want_rc 0 "session 1" && want_no_block "session 1" || return 1
  want_jfile "$PDATA/sessions/$SID.stop.json" '.result == "PASS"' || return 1
  SID="$SID-b"
  on_edit app/x.php
  stop_check
  want_rc 0 "session 2" && want_json '(.decision // "") != "block"
    and (.hookSpecificOutput.additionalContext | contains("PAIRSAY app-x"))' "session 2" || return 1
  local calls
  calls=$(unit_calls)
  stop_check true
  want_rc 0 "session 2, 2. Stop" && want_no_block "session 2, 2. Stop" || return 1
  [ "$(unit_calls)" = "$calls" ] || fail "session 2: kontrola bežala napriek rovnakému hashu (unit $calls → $(unit_calls))"
}
t_stop_pairs_non_code_only() {
  new_case
  cfg '.pairs = [{"id": "docs", "when": "docs/**", "say": "PAIRSAY docs"}]'
  put docs/readme.md '# x'
  session_files docs/readme.md
  stop_check
  want_rc 0 && want_json '(.decision // "") != "block" and (.hookSpecificOutput.additionalContext | contains("[pair:docs] PAIRSAY docs"))' || return 1
  [ "$(unit_calls)" = 0 ] || fail "kontrola bežala bez kódových súborov"
}
t_stop_removed_test_method() {
  new_case
  printf '<?php\nclass FooTest {\n    public function testA() {}\n    public function testB() {}\n}\n' > "$REPO/tests/FooTest.php"
  g add tests/FooTest.php && g commit -qm tests
  printf '<?php\nclass FooTest {\n    public function testA() {}\n}\n' > "$REPO/tests/FooTest.php"
  session_files tests/FooTest.php
  stop_check
  want_rc 0 "1. Stop" && want_json '(.decision // "") != "block"
    and (.hookSpecificOutput.additionalContext | contains("[testRemoved] tests/FooTest.php: zmazaná test metóda testB"))' "1. Stop" || return 1
  want_not 'testA' "1. Stop" || return 1
  want_logged stop-check testRemoved warn || return 1
  stop_check true
  want_rc 0 "2. Stop" && want_no_stdout "2. Stop (pripomienka už bola)"
}

# ---------------------------------------------------------------- session-card: upozornenia

t_card_warning_system_message() {
  new_case
  printf '{"lastUpstreamCheck": %s}\n' "$(now)" > "$DATA/maintenance.json"
  card
  want_rc 0 "zdravá karta" && want_out 'kontroly: /dev:check' "zdravá karta" || return 1
  [ -z "$SYSMSG" ] || { fail "zdravá karta má systemMessage: $(flat "$SYSMSG")"; return 1; }
  DOCKER_OK=1
  cfg '.container = "app-php"'
  card
  want_rc 0 "kontajner dole" || return 1
  case "$SYSMSG" in *'[dev-kit] kontajner app-php NEBEŽÍ'*) ;; *) fail "systemMessage bez NEBEŽÍ: $(flat "$RAW")" ;; esac
}
t_card_no_jq_json() {
  new_case
  local p="$CASE/nojq"
  mkpath "$p" jq
  printf '%s\n' "$(j_start)" > "$CASE/in.json"
  (cd "$REPO" && PATH="$p" bash "$S/session-card.sh") < "$CASE/in.json" > "$CASE/out" 2> "$CASE/err"
  RC=$? OUT=$(cat "$CASE/out") ERR=$(cat "$CASE/err")
  want_rc 0 && want_json '.systemMessage | contains("chýba jq")' || return 1
  [ -z "$ERR" ] || fail "stderr: $(flat "$ERR")"
}
t_card_no_docker_binary() {
  new_case
  DOCKER_OK=1
  cfg '.container = "app-php"'
  local p="$CASE/nodocker"
  mkpath "$p" docker
  printf '%s\n' "$(j_start)" > "$CASE/in.json"
  (cd "$REPO" && PATH="$p" bash "$S/session-card.sh") < "$CASE/in.json" > "$CASE/out" 2> "$CASE/err"
  RC=$? OUT=$(cat "$CASE/out") ERR=$(cat "$CASE/err")
  want_rc 0 && want_json '(.hookSpecificOutput.additionalContext | contains("chýba docker"))
    and (.systemMessage | contains("chýba docker"))'
}
t_card_worktree_venv() {
  new_case
  cfg '.stack = "python"'
  local wt="$REPO/.claude/worktrees/wt1"
  wt_add "$wt" || return 1
  mkdir -p "$REPO/.venv" "$REPO/vendor"
  card "$wt"
  want_rc 0 && want_out 'worktree nemá .venv/' && want_not 'worktree nemá vendor/' || return 1
  case "$SYSMSG" in *'worktree nemá .venv/'*) ;; *) fail "systemMessage bez .venv/: $(flat "$RAW")" ;; esac
}
t_card_cc_version() {
  new_case
  export DK_FAKE_CC_VERSION=2.0.9
  card
  want_rc 0 && want_out 'Claude Code 2.0.9 je starší ako' || return 1
  case "$SYSMSG" in *'claude update'*) ;; *) fail "systemMessage bez claude update: $(flat "$RAW")"; return 1 ;; esac
  export DK_FAKE_CC_VERSION=9.9.9
  card
  want_out 'Claude Code 2.0.9' "verzia sa kontroluje raz za deň (cache)"
}
# R3: zmena devkit.json → karta raz, on-edit a pre-bash raz za session (systemMessage); hooky bežia ďalej
t_cfg_trust() {
  new_case
  printf '{"lastUpstreamCheck": %s}\n' "$(now)" > "$DATA/maintenance.json"
  card
  want_rc 0 "1. štart" && want_not 'sa zmenil' "1. štart (snímka sa len založí)" || return 1
  want_file "$PDATA/config.hash" "1. štart" &&
    want_jfile "$PDATA/config.cmds.json" 'index("krok unit run: sh bin/fake-phpunit") != null' || return 1
  cfg '.check.steps |= map(if .id == "unit" then .run = "sh bin/fake-phpunit --v2" else . end)'
  check --quick --project "$REPO"
  want_rc 0 "check.sh po zmene" || return 1
  card
  want_rc 0 "zmena run" &&
    want_out 'devkit.json sa zmenil od poslednej session: 1 príkaz (lint/kroky) — skontroluj diff' "zmena run" || return 1
  case "$SYSMSG" in *'[dev-kit] devkit.json sa zmenil od poslednej session: 1 príkaz'*) ;;
    *) fail "zmena run: systemMessage $(flat "$RAW")"; return 1 ;; esac
  card
  want_rc 0 "2. štart bez zmeny" && want_not 'sa zmenil' "2. štart bez zmeny" || return 1
  [ -z "$SYSMSG" ] || { fail "2. štart bez zmeny: systemMessage $(flat "$SYSMSG")"; return 1; }

  local c='.check.steps |= map(if .id == "unit" then .run = "sh bin/fake-phpunit --v2" else . end)'
  cfg "$c"' | .lint[".php"] = ["sh bin/fake-lint {file} # v2", {"run": "sh bin/fake-ok lint2", "runtime": "host"}]'
  add app/Foo.php '$a = 1; // LINTERR'
  on_edit app/Foo.php
  want_rc 2 "on-edit po zmene" && want_err 'app/Foo.php:4' "on-edit po zmene (nový lint beží)" &&
    want_file "$REPO/.marks/ran-lint2" "on-edit po zmene" || return 1
  want_json '.systemMessage == "[dev-kit] devkit.json sa zmenil — príkazy: lint .php (host): sh bin/fake-ok lint2 · lint .php: sh bin/fake-lint {file} # v2"' \
    "on-edit po zmene" && want_file "$PDATA/sessions/$SID.cfgnote" "on-edit po zmene" || return 1
  cfg "$c"' | .lint[".php"] = ["sh bin/fake-lint {file} # v3"]'
  add app/Old.php '$c = 3;'
  on_edit app/Old.php
  want_rc 0 "2. zmena v tej istej session" && want_silent "2. zmena v tej istej session (hláška raz)" || return 1
  card
  want_out 'od poslednej session: 1 príkaz' "karta po potlačenej hláške" || return 1

  SID="$SID-2"
  cfg "$c"
  pre_bash 'git commit -m "x"'
  want_allow_cfgnote "pre-bash bez kódu" && want_json '.systemMessage | endswith("príkazy: lint .php: sh bin/fake-lint {file}")' "pre-bash bez kódu" &&
    want_file "$PDATA/sessions/$SID.cfgnote" "pre-bash bez kódu" || return 1
  SID="$SID-3"
  cfg "$c"' | .commitGate.ext += [".txt"]'
  g add app/Foo.php
  pre_bash 'git commit -m "x"'
  want_decision deny "pre-bash deny" && want_json '.systemMessage == "[dev-kit] devkit.json sa zmenil — príkazy: žiadny nový ani zmenený"
    and (.hookSpecificOutput.permissionDecisionReason | contains("commit gate"))' "pre-bash deny" &&
    want_file "$PDATA/sessions/$SID.cfgnote" "pre-bash deny" || return 1
  cfg "$c"' | .commitGate.ext += [".txt"] | .lint[".php"] = ["sh bin/fake-lint {file} # v4"]'
  pre_bash 'git commit -m "x"'
  want_decision deny "pre-bash 2. zmena v tej istej session" &&
    want_json 'has("systemMessage") | not' "pre-bash 2. zmena v tej istej session (hláška raz)" || return 1
  card
  want_out 'od poslednej session: 1 príkaz' "karta po potlačenej hláške pre-bash"
}

# ---------------------------------------------------------------- šablóny (D1, D5, SEC-13)

t_templates_lint() {
  local T="$KIT/plugins/dev/templates" f bad="" tag s p gi hit tab pats
  tab=$(printf '\t')
  [ -d "$T" ] || { fail "chýba $T"; return 1; }
  for f in "$T"/*/settings.json; do
    [ -f "$f" ] || continue
    s=$(jq -r '(.permissions.deny // [])[] | select(test("^Edit\\([^/~]"))' "$f" 2>&1)
    [ -z "$s" ] || bad="$bad${f#"$KIT"/}: neukotvené deny $(flat "$s"); "
  done
  for f in "$T"/*/devkit.json "$FIX/devkit.json"; do
    [ -f "$f" ] || continue
    s=$(jq -r '((.guards // [])[] | .pattern // empty), ((.secrets.patterns // [])[]), ((.check.knownFailures // [])[] | .pattern // empty)' "$f" 2>&1 |
      grep -E '\[(\[:[a-z]+:\]|[^]])*\\[swd]')
    [ -z "$s" ] || bad="$bad${f#"$KIT"/}: \\s/\\w/\\d v [...]: $(flat "$s"); "
  done
  [ -f "$FIX/secret-samples.txt" ] || { fail "chýba tests/fixtures/secret-samples.txt"; return 1; }
  for f in "$T"/*/devkit.json; do
    pats=$(jq -r '(.secrets.patterns // [])[]' "$f")
    while IFS= read -r s; do
      case "$s" in '#'*|'') continue ;; esac
      tag=${s%%"$tab"*}
      s=${s#*"$tab"}
      hit=0
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        gi=""
        case "$p" in '(?i)'*) p=${p#'(?i)'}; gi=-i ;; esac
        if printf '%s\n' "$s" | grep -qE $gi -e "$p"; then hit=1; break; fi
      done <<EOF
$pats
EOF
      case "$tag:$hit:${f#"$T"/}" in
        -:1:*) bad="$bad${f#"$KIT"/}: falošný nález '$s'; " ;;
        HIT:0:php-nette/*) bad="$bad${f#"$KIT"/}: nezachytené '$s'; " ;;
      esac
    done < "$FIX/secret-samples.txt"
  done
  for f in "$T"/*/rules/*.md; do
    [ -f "$f" ] || continue
    [ "$(sed -n 1p "$f")" = "---" ] && sed -n '2,/^---$/p' "$f" | grep -q '^paths:' || bad="$bad${f#"$KIT"/}: chýba frontmatter s paths:; "
    grep -q '^## Pasce' "$f" || bad="$bad${f#"$KIT"/}: chýba ## Pasce; "
    [ "$(wc -l < "$f" | tr -d ' ')" -le 60 ] || bad="$bad${f#"$KIT"/}: viac ako 60 riadkov; "
  done
  s=$(grep -o '<!-- db:[a-z]* -->' "$T/php-nette/CLAUDE.md.tmpl" | sort -u | grep -v -e '<!-- db:dibi -->' -e '<!-- db:doctrine -->')
  [ -z "$s" ] || bad="${bad}templates/php-nette/CLAUDE.md.tmpl: neznáma značka $(flat "$s"); "
  s=$(jq -r '(.check.steps // [])[] | select((.id | startswith("doctrine-")) and ((.requires // "") == "")) | .id' "$T/php-nette/devkit.json")
  [ -z "$s" ] || bad="${bad}templates/php-nette/devkit.json: krok doctrine-* bez requires $(flat "$s"); "
  [ -z "$bad" ] || fail "$bad"
}

# ---------------------------------------------------------------- okrajové stavy skriptov (A7)

# check.sh mimo kontraktu 0/1/4 (config, argumenty, pád skriptu) → Stop neblokuje, ale nehlási pass
t_stop_check_not_run() {
  new_case
  kit_scripts || return 1
  add app/Foo.php '$x = 1;'
  session_files app/Foo.php
  local c
  for c in 3 2; do
    printf '#!/usr/bin/env bash\necho "[dev-kit] atrapa check.sh"\nexit %s\n' "$c" > "$S/check.sh"
    stop_check
    want_rc 0 "exit $c" && want_no_block "exit $c" \
      && want_json ".hookSpecificOutput.additionalContext | contains(\"kontrola sa nedala spustiť (exit $c)\") and contains(\"errors.log\")" "exit $c" \
      || return 1
    grep -q "check.sh --stop exit $c" "$DATA/errors.log" 2>/dev/null || { fail "errors.log bez exit $c"; return 1; }
  done
  want_logged stop-check stopCheck skip || return 1
  ! jq -se 'any(.[]; .hook == "stop-check" and .rule == "stopCheck" and .decision == "pass")' "$DATA/decisions.jsonl" >/dev/null 2>&1 ||
    fail "decisions.jsonl má stopCheck pass, hoci kontrola nebežala"
}
# dk_blobs: nečitateľný súbor = "-" + errors.log (dávka nezhodí ostatné), symlink s príponou kódu vypadne
t_blobs_unreadable_symlink() {
  new_case
  put app/Bad.php '<?php $bad = 1;'
  ln -s Foo.php "$REPO/app/Link.php" && ln -s ../README.md "$REPO/app/link.md" || { fail "fixture: ln -s"; return 1; }
  chmod 000 "$REPO/app/Bad.php"
  local got root="" foo md bad
  [ -r "$REPO/app/Bad.php" ] && root=1
  got=$(cd "$REPO" && bash -c '. "$1" && dk_init && dk_blobs app/Foo.php app/Bad.php app/Link.php app/link.md app/Missing.php' \
    _ "$S/lib.sh" 2>/dev/null < /dev/null)
  chmod 644 "$REPO/app/Bad.php"
  foo=$(git -C "$REPO" hash-object app/Foo.php)
  md=$(git -C "$REPO" hash-object README.md)
  bad=-
  [ -z "$root" ] || bad=$(git -C "$REPO" hash-object app/Bad.php)
  printf '%s\n' "$got" | grep -qxF "app/Foo.php$(printf '\t')$foo" &&
    printf '%s\n' "$got" | grep -qxF "app/Bad.php$(printf '\t')$bad" &&
    printf '%s\n' "$got" | grep -qxF "app/link.md$(printf '\t')$md" &&
    printf '%s\n' "$got" | grep -qxF "app/Missing.php$(printf '\t')-" ||
    { fail "dk_blobs: $(flat "$got")"; return 1; }
  ! printf '%s\n' "$got" | grep -q '^app/Link\.php' || { fail "symlink .php v dk_blobs: $(flat "$got")"; return 1; }
  [ -n "$root" ] || grep -q 'nečitateľný súbor app/Bad.php' "$DATA/errors.log" 2>/dev/null ||
    fail "errors.log bez nečitateľného súboru"
}
# commit gate: symlink s príponou kódu (stage aj git add v príkaze) nežiada PASS, ktorý by nikdy nesedel
t_bash_commit_symlink_code() {
  new_case
  ln -s Foo.php "$REPO/app/Link.php" || { fail "fixture: ln -s"; return 1; }
  g add app/Link.php
  check --quick --project "$REPO"
  want_rc 0 "check" || return 1
  want_jfile "$PDATA/pass.json" '.blobs | has("app/Link.php") | not' || return 1
  pre_bash 'git commit -m "x"'
  want_allow "symlink v stage" || return 1
  pre_bash 'git add app/Link.php && git commit -m "x"'
  want_allow "git add symlinku"
}
t_err_log_rotation() {
  new_case
  awk 'BEGIN { for (i = 1; i <= 2100; i++) printf "%06d %0600d\n", i, 0 }' > "$DATA/errors.log"
  (cd "$REPO" && DK_HOOK=selftest bash -c '. "$1" && dk_err "ROTATE-MARK"' _ "$S/lib.sh" < /dev/null)
  local n
  n=$(wc -l < "$DATA/errors.log" | tr -d ' ')
  [ "$n" = 500 ] && tail -n 1 "$DATA/errors.log" | grep -q 'selftest ROTATE-MARK' && head -n 1 "$DATA/errors.log" | grep -q '^001602 ' ||
    { fail "errors.log nad 1 MB: $n riadkov, posledný $(tail -n 1 "$DATA/errors.log" | cut -c1-40)"; return 1; }
  (cd "$REPO" && DK_HOOK=selftest bash -c '. "$1" && dk_err "SMALL"' _ "$S/lib.sh" < /dev/null)
  n=$(wc -l < "$DATA/errors.log" | tr -d ' ')
  [ "$n" = 501 ] || fail "malý errors.log sa nemá skracovať: $n riadkov"
}
# stav kontajnera: on-edit a karta čítajú container.state (30 s, rovnaký kontajner), check.sh vždy docker inspect
t_container_state_cache() {
  new_case
  DOCKER_OK=1
  cfg '.container = "app-php"'
  add app/Foo.php '$c = 1;'
  local cf="$PDATA/container.state"
  on_edit app/Foo.php
  want_allow "1. on-edit" || return 1
  [ "$(docker_calls | grep -c '^inspect ')" = 1 ] && grep -q '^[0-9][0-9]* down app-php$' "$cf" 2>/dev/null ||
    { fail "1. on-edit: inspect $(docker_calls | grep -c '^inspect ')×, container.state: $(flat "$(cat "$cf" 2>&1)")"; return 1; }
  export DK_FAKE_DOCKER_RUNNING=1
  on_edit app/Foo.php
  want_allow "2. on-edit" && no_docker_exec "2. on-edit (stav z cache)" || return 1
  [ "$(docker_calls | grep -c '^inspect ')" = 1 ] || { fail "2. on-edit volal docker inspect napriek čerstvej cache"; return 1; }
  check --quick --project "$REPO"
  want_rc 0 "check.sh ignoruje cache" || return 1
  [ "$(docker_calls | grep -c '^inspect ')" = 2 ] && grep -q ' running app-php$' "$cf" ||
    { fail "check.sh: inspect $(docker_calls | grep -c '^inspect ')×, container.state: $(flat "$(cat "$cf")")"; return 1; }
  unset DK_FAKE_DOCKER_RUNNING
  printf '%s running app-php\n' $(( $(now) - 31 )) > "$cf"
  on_edit app/Foo.php
  [ "$(docker_calls | grep -c '^inspect ')" = 3 ] && grep -q ' down app-php$' "$cf" ||
    { fail "stará cache (31 s): inspect $(docker_calls | grep -c '^inspect ')×"; return 1; }
  printf '%s running iny-kontajner\n' "$(now)" > "$cf"
  on_edit app/Foo.php
  [ "$(docker_calls | grep -c '^inspect ')" = 4 ] || fail "cache iného kontajnera použitá"
}
t_check_runfiles_code_only() {
  new_case
  cfg --arg r 'mkdir -p .marks && printf "%s\n" {files} > .marks/files' '.check.steps = [{"id": "files", "runFiles": $r, "modes": ["quick"]}]'
  add app/Foo.php '$r = 1;'
  add README.md 'zmena'
  put docs/x.txt 'nový'
  check --quick --project "$REPO"
  want_rc 0 && want_out '✓ files' || return 1
  [ "$(cat "$REPO/.marks/files" 2>/dev/null)" = app/Foo.php ] || { fail "{files} = $(flat "$(cat "$REPO/.marks/files" 2>&1)")"; return 1; }
  g checkout -- app/Foo.php
  check --quick --project "$REPO"
  want_rc 4 "len nekódové zmeny" && want_out '– files: žiadne zmenené súbory' "len nekódové zmeny"
}
t_check_auto_full_same_steps() {
  new_case
  cfg '.check.steps |= map(select(.id != "fullonly"))'
  add app/models/UserModel.php '$s = 1;'
  check --auto --project "$REPO"
  want_rc 0 "--auto bez krokov len pre full" && want_out 'check full: PASS · 2 ok · 0 fail · 0 skip' "--auto bez krokov len pre full" \
    && want_out '– full: rovnaké kroky ako quick' "--auto bez krokov len pre full" || return 1
  check --full --project "$REPO"
  want_rc 0 "--full" && want_not '– full:' "--full" || return 1
  cfg .
  check --auto --project "$REPO"
  want_rc 0 "--auto s krokom fullonly" && want_out 'check full: PASS' "--auto s krokom fullonly" && want_not '– full:' "--auto s krokom fullonly"
}
# cesty do awk cez ENVIRON: awk -v by zo spätnej lomky v ceste urobil escape (\t → TAB)
t_awk_backslash_paths() {
  new_case
  local f='app/x\ty.php' got
  put "$f" '<?php'
  g add -A && g commit -qm bs || { fail "fixture: commit $f"; return 1; }
  add "$f" '$a = 1; // LINTERR'
  on_edit "$f"
  want_rc 2 "on-edit" && want_err 'app/x\ty.php:2' "on-edit" || return 1
  cfg '.check.steps[0].changedLinesOnly = true'
  check --quick --project "$REPO" --files "$f"
  want_rc 1 "check --files" && want_out '✗ lint' "check --files" || return 1
  got=$(bash -c '. "$1"; DK_PROJECT="$2"; DK_WD="$3"; printf "%s/app/A.php:1: x\n%s/app/B.php:2: y\n" "$2" "$3" | dk_strip_paths' \
    _ "$S/lib.sh" '/p/a\tb' '/w\nx' < /dev/null)
  [ "$got" = "app/A.php:1: x
app/B.php:2: y" ] || fail "dk_strip_paths: $(flat "$got")"
}

# ---------------------------------------------------------------- medzery pokrytia (A9)

# pytest: identifikátor z riadku „FAILED <id>“ krátkeho súhrnu (syntetický výstup vo formáte pytest 8)
t_check_known_failures_pytest() {
  new_case
  cat > "$CASE/pytest.out" <<'EOF'
============================= test session starts ==============================
platform linux -- Python 3.12.3, pytest-8.3.3, pluggy-1.5.0
rootdir: /app
configfile: pyproject.toml
collected 4 items

tests/test_x.py .FF.                                                     [100%]

=================================== FAILURES ===================================
____________________________________ test_y ____________________________________

    def test_y():
>       assert add(1, 2) == 4
E       assert 3 == 4

tests/test_x.py:12: AssertionError
_________________________________ test_z[2-3] __________________________________

a = 2, b = 3

    @pytest.mark.parametrize("a,b", [(1, 2), (2, 3)])
    def test_z(a, b):
>       assert a + b == 3
E       assert (2 + 3) == 3

tests/test_x.py:17: AssertionError
=========================== short test summary info ============================
FAILED tests/test_x.py::test_y - assert 3 == 4
FAILED tests/test_x.py::test_z[2-3] - assert (2 + 3) == 3
========================= 2 failed, 2 passed in 0.04s ==========================
EOF
  local c y='^tests/test_x\.py::test_y$' z='^tests/test_x\.py::test_z\[2-3\]$'
  c="sh bin/replay $(q "$CASE/pytest.out") 1"
  cfg --arg c "$c" --arg y "$y" \
    '.check.steps |= map(if .id == "unit" then .run = $c else . end) | .check.knownFailures = [{"step": "unit", "pattern": $y}]'
  add app/Foo.php '$f = 6;'
  check --quick --project "$REPO"
  want_rc 1 "test_z[2-3] nie je známe" && want_out '✗ unit' "test_z[2-3] nie je známe" || return 1
  cfg --arg c "$c" --arg y "$y" --arg z "$z" \
    '.check.steps |= map(if .id == "unit" then .run = $c else . end) | .check.knownFailures = [{"step": "unit", "pattern": $y}, {"step": "unit", "pattern": $z}]'
  check --quick --project "$REPO"
  want_rc 0 && want_out '✓ unit' && want_out '(známe zlyhania: 2)' && want_out 'PASS · 1 ok · 1 známe · 0 fail'
}
# Predvolené vzory tajomstiev (lib.sh) bez secrets.patterns; hodnoty skladané, aby ich v repe nenašiel skener tajomstiev.
SECRET_AKIA="AKIA""SELFTEST0000EXMP"
SECRET_PEM="-----BEGIN RSA ""PRIVATE KEY-----"
t_edit_secret_defaults() {
  new_case
  put config/aws.ini '[default]'
  g add config/aws.ini && g commit -qm aws || { fail "fixture: commit config/aws.ini"; return 1; }
  add config/aws.ini "aws_access_key_id = $SECRET_AKIA"
  on_edit config/aws.ini
  want_rc 2 "AKIA" && want_err 'config/aws.ini:2 — možné tajomstvo (****)' "AKIA" && want_err '[secrets]' "AKIA" \
    && want_not 'AKIA' "AKIA" || return 1
  put config/deploy.pem "$SECRET_PEM"
  add config/deploy.pem 'MIIEselftestBODYselftestBODY'
  on_edit config/deploy.pem
  want_rc 2 "PRIVATE KEY" && want_err 'config/deploy.pem:1 — možné tajomstvo (****)' "PRIVATE KEY" \
    && want_not 'PRIVATE KEY' "PRIVATE KEY" && want_not 'BODY' "PRIVATE KEY" || return 1
  want_logged on-edit secrets block
}
t_bash_commit_secret_defaults() {
  new_case
  put config/aws.ini "aws_access_key_id = $SECRET_AKIA"
  put config/deploy.pem "$SECRET_PEM"
  add config/deploy.pem 'MIIEselftestBODYselftestBODY'
  g add config
  pre_bash 'git commit -m x'
  want_decision deny && want_out '(2)' && want_out 'config/aws.ini:1 — ****' && want_out 'config/deploy.pem:1 — ****' \
    && want_not 'AKIA' && want_not 'PRIVATE KEY' && want_not 'BODY' && want_not 'commit gate' || return 1
  want_logged pre-bash secrets deny || return 1
  ! grep -rqF "$SECRET_AKIA" "$DATA" || fail "AWS kľúč je v $(grep -rlF "$SECRET_AKIA" "$DATA" | sed "s|$CASE/||" | head -1)"
}
# testRemoved: zmazaný celý commitnutý test súbor zo session; nový test súbor zmazaný v tej istej session mlčí
t_stop_removed_test_file() {
  new_case
  session_files tests/FooTest.php
  rm "$REPO/tests/FooTest.php"
  stop_check
  want_rc 0 "1. Stop" && want_json '(.decision // "") != "block"
    and (.hookSpecificOutput.additionalContext | contains("[testRemoved] tests/FooTest.php: zmazaný testovací súbor — over s používateľom"))' \
    "1. Stop" || return 1
  want_logged stop-check testRemoved warn || return 1
  stop_check true
  want_rc 0 "2. Stop" && want_no_stdout "2. Stop (pripomienka už bola)" || return 1
  g checkout -- tests/FooTest.php
  SID="$SID-b"
  session_files tests/NewTest.php tests/FooTest.php
  g rm -q tests/FooTest.php
  stop_check
  want_rc 0 "git rm" && want_json '(.decision // "") != "block" and (.hookSpecificOutput.additionalContext
    | contains("[testRemoved] tests/FooTest.php: zmazaný testovací súbor") and (contains("NewTest") | not))' "git rm"
}
# commitGate vypnutý (enabled: false aj disabledRules) → kód bez PASS prejde, tajomstvo ďalej blokuje
t_bash_gate_off_secrets_on() {
  local c
  for c in '.commitGate.enabled = false' '.disabledRules = ["commitGate"]'; do
    new_case
    cfg "$c"
    add app/Foo.php '$f = 6;'
    g add app/Foo.php
    pre_bash 'git commit -m x'
    want_allow "$c: kód bez PASS" || return 1
    bad_php
    g add app/Bad.php
    pre_bash 'git commit -m x'
    want_decision deny "$c: tajomstvo" && want_out 'app/Bad.php:2 — ****' "$c: tajomstvo" \
      && want_not 'SuperSecretValue123' "$c: tajomstvo" && want_not 'commit gate' "$c: tajomstvo" \
      && want_not 'Spusti kontrolu' "$c: tajomstvo" || return 1
    want_logged pre-bash secrets deny || return 1
    ! jq -se 'any(.[]; .rule == "commitGate")' "$DATA/decisions.jsonl" >/dev/null 2>&1 ||
      { fail "$c: decisions.jsonl má commitGate, hoci gate je vypnutý"; return 1; }
  done
}

# ---------------------------------------------------------------- nástroje kitu (A8)

# tools/upstream.sh: klon ECC predvolene <kit>/../ECC podľa umiestnenia skriptu, ECC_DIR ho prebije (SPEC §9)
t_upstream_ecc_default() {
  new_case nocfg
  unset ECC_DIR
  local ecc="$CASE/ECC" pin
  mkdir -p "$CASE/kit/tools" "$CASE/kit/plugins/dev" && cp "$KIT/tools/upstream.sh" "$CASE/kit/tools/" ||
    { fail "fixture: kópia upstream.sh"; return 1; }
  S="$CASE/kit/tools"
  run upstream --no-fetch
  want_rc 1 "bez klonu" && want_err "chýba klon ECC: $ecc → git clone" "bez klonu" || return 1
  mkdir -p "$ecc/skills/x" && printf 'v1\n' > "$ecc/skills/x/SKILL.md"
  git -C "$ecc" init -q && git -C "$ecc" add -A && git -C "$ecc" commit -qm v1 &&
    git -C "$ecc" update-ref refs/remotes/origin/main HEAD || { fail "fixture: klon ECC"; return 1; }
  pin=$(git -C "$ecc" rev-parse HEAD | cut -c1-7)
  printf '| kit path | ECC source path | ECC commit | date adopted | changes |\n|---|---|---|---|---|\n| `skills/x/` | `skills/x/SKILL.md` | %s | 2026-10-27 | — |\n' \
    "$pin" > "$CASE/kit/plugins/dev/PROVENANCE.md"
  run upstream --no-fetch
  want_rc 0 "klon vedľa kitu" && want_out 'bez zmien v 1 prevzatých zdrojoch' "klon vedľa kitu" || return 1
  printf 'v2\n' > "$ecc/skills/x/SKILL.md"
  git -C "$ecc" commit -qam v2 && git -C "$ecc" update-ref refs/remotes/origin/main HEAD ||
    { fail "fixture: zmena v ECC"; return 1; }
  run upstream --no-fetch
  want_rc 0 "zmena v ECC" && want_out 'zmenených 1 z 1' "zmena v ECC" &&
    want_out "detail: git -C $ecc diff $pin..origin/main -- skills/x/SKILL.md" "zmena v ECC" || return 1
  [ ! -e "$DATA/maintenance.json" ] || { fail "--no-fetch zapísal maintenance.json"; return 1; }
  export ECC_DIR="$CASE/iny"
  run upstream --no-fetch
  want_rc 1 "ECC_DIR" && want_err "chýba klon ECC: $CASE/iny →" "ECC_DIR"
}

# ---------------------------------------------------------------- zjednotenie šablón (B2)

# Guardy šablón php-nette a php-symfony cez on-edit: volanie metódy (->exit(, $this->dump(, ::dump() ani
# premenná $exit nie sú nález; die(, exit; a dump( áno; podmienka QueryBuildera skladaná reťazcom áno.
t_templates_php_guards() {
  local stack dql n want got
  for stack in php-nette php-symfony; do
    new_case
    cfg --slurpfile t "$KIT/plugins/dev/templates/$stack/devkit.json" '.guards = $t[0].guards' || return 1
    dql=dql-concat
    [ "$stack" = php-nette ] && dql=doctrine-dql-concat
    add app/Foo.php "$(printf '%s\n' '$this->exit(1);' '$this->dump($x);' 'Debugger::dump($x);' 'return $exit;' \
      "die('x');" '    exit;' 'dump($x);' "\$qb->where('a.id = ' . \$id);")"
    on_edit app/Foo.php
    want_rc 2 "$stack" || return 1
    want="app/Foo.php:10 guard:debug-php|app/Foo.php:11 guard:$dql|app/Foo.php:8 guard:die|app/Foo.php:9 guard:die|"
    got=$(printf '%s\n' "$ERR" | LC_ALL=C sed -n 's/^\(app\/Foo\.php:[0-9]*\) — .*\[\(guard:[a-z-]*\)\]$/\1 \2/p' |
      LC_ALL=C sort | LC_ALL=C tr '\n' '|')
    [ "$got" = "$want" ] || { fail "$stack: nálezy '$got', čakal som '$want'$(ctx)"; return 1; }
    n=$(printf '%s\n' "$ERR" | LC_ALL=C grep -c '^app/Foo\.php:[4-7] ')
    [ "$n" = 0 ] || { fail "$stack: nález na riadku 4–7 (volanie metódy, ::dump, \$exit)$(ctx)"; return 1; }
  done
}
# pairs: when/unless ako zoznam globov (šablóna php-nette model-test pokrýva app/models, app/model, app/Model)
t_stop_pair_glob_list() {
  new_case
  cfg --slurpfile t "$KIT/plugins/dev/templates/php-nette/devkit.json" \
    '.pairs = [($t[0].pairs[] | select(.id == "model-test")),
      {"id": "lib-spec", "when": "libs/**", "unless": ["tests/**", "spec/**"], "say": "PAIRSAY lib"}]' || return 1
  put app/Model/User.php '<?php $user = 1;'
  put libs/Lib.php '<?php $lib = 1;'
  session_files app/Model/User.php libs/Lib.php
  stop_check
  want_rc 0 "1. session" && want_json '(.hookSpecificOutput.additionalContext | contains("[pair:model-test]"))
    and (.hookSpecificOutput.additionalContext | contains("PAIRSAY lib"))' "1. session" || return 1
  SID="$SID-b"
  put app/model/Order.php '<?php $order = 1;'
  put spec/LibSpec.php '<?php $spec = 1;'
  put tests/OrderTest.php '<?php $test = 1;'
  session_files app/model/Order.php libs/Lib.php spec/LibSpec.php tests/OrderTest.php
  stop_check
  want_rc 0 "2. session" && want_not '[pair:' "2. session (unless zo zoznamu)" || return 1
  SID="$SID-c"
  session_files app/model/Order.php
  rm -f "$REPO/tests/OrderTest.php"
  stop_check
  want_rc 0 "3. session" && want_json '.hookSpecificOutput.additionalContext | contains("[pair:model-test]")' "3. session (app/model)"
}

# NotebookEdit: hooks.json ho má v matcheroch pre-edit aj on-edit, skripty berú cestu z notebook_path;
# guardy šablóny python platia aj pre .ipynb (riadky buniek v JSON).
t_notebook_edit() {
  local hj="$KIT/plugins/dev/hooks/hooks.json" nb=notebooks/explore.ipynb
  jq -e '[.hooks.PreToolUse[], .hooks.PostToolUse[] | select(.hooks[0].command | test("pre-edit|on-edit"))
    | .matcher | split("|") | index("NotebookEdit")] | length == 2 and all(. != null)' "$hj" >/dev/null 2>&1 ||
    { fail "hooks.json: NotebookEdit chýba v matcheri pre-edit alebo on-edit"; return 1; }
  new_case
  cfg --slurpfile t "$KIT/plugins/dev/templates/python/devkit.json" '.guards = $t[0].guards' || return 1
  put "$nb" '{"cells": [{"cell_type": "code", "id": "c1", "metadata": {}, "outputs": [],
  "source": ["x = 1\n"]}], "metadata": {}, "nbformat": 4, "nbformat_minor": 5}'
  put db/migrations/explore.ipynb '{"cells": []}'
  g add -A && g commit -qm nb || { fail "fixture: commit notebookov"; return 1; }
  put "$nb" '{"cells": [{"cell_type": "code", "id": "c1", "metadata": {}, "outputs": [],
  "source": ["x = 1\n",
    "breakpoint()\n"]}], "metadata": {}, "nbformat": 4, "nbformat_minor": 5}'
  hook on-edit "$(j_notebook PostToolUse "$REPO/$nb")"
  want_rc 2 "on-edit" && want_err "$nb:3 — debug kód" "on-edit" && want_err '[guard:debug-py]' "on-edit" || return 1
  grep -qxF "$nb" "$PDATA/sessions/$SID.files" 2>/dev/null || { fail "notebook chýba v sessions/$SID.files"; return 1; }
  hook pre-edit "$(j_notebook PreToolUse "$REPO/db/migrations/explore.ipynb")"
  want_decision ask "pre-edit" && want_out 'db/migrations/explore.ipynb' "pre-edit"
}

# ---------------------------------------------------------------- zástupné symboly (B3)

# Každý {{symbol}} šablón stackov má riadok v tabuľke project-init a skill nemenuje symbol, ktorý šablóny nemajú
t_templates_symbols() {
  local T="$KIT/plugins/dev/templates" sk="$KIT/plugins/dev/skills/project-init/SKILL.md" used rows named s bad=""
  [ -f "$sk" ] || { fail "chýba $sk"; return 1; }
  used=$(grep -rhoE '\{\{[a-zA-Z]+\}\}' "$T/php-nette" "$T/php-symfony" "$T/python" | LC_ALL=C sort -u)
  rows=$(sed -n '/^## Zástupné symboly/,/^## Pasce/p' "$sk" | awk -F'|' '/^\| `\{\{/ {print $2}' |
    grep -oE '\{\{[a-zA-Z]+\}\}' | LC_ALL=C sort -u)
  named=$(grep -oE '\{\{[a-zA-Z]+\}\}' "$sk" | LC_ALL=C sort -u)
  [ -n "$rows" ] || { fail "SKILL.md bez tabuľky Zástupné symboly"; return 1; }
  s=$(printf '%s\n' "$used" | LC_ALL=C comm -23 - <(printf '%s\n' "$rows"))
  [ -z "$s" ] || bad="${bad}bez riadku v tabuľke: $(flat "$s"); "
  s=$(printf '%s\n' "$named" | LC_ALL=C comm -23 - <(printf '%s\n' "$used"))
  [ -z "$s" ] || bad="${bad}skill menuje symbol mimo šablón: $(flat "$s"); "
  [ -z "$bad" ] || fail "$bad"
}

# ---------------------------------------------------------------- runtime host | container (B4)

# Atrapa docker, ktorá vždy zlyhá (inspect aj exec); volania idú do docker.calls.
docker_always_fails() {
  local fb="$CASE/fakebin"
  mkdir -p "$fb" &&
    printf '#!/bin/sh\necho "$*" >> "${DK_FAKE_DOCKER_LOG:-/dev/null}"\necho "docker: atrapa vždy zlyhá" >&2\nexit 1\n' > "$fb/docker" &&
    chmod +x "$fb/docker" || { fail "fixture: atrapa docker"; return 1; }
  export PATH="$fb:$PATH"
}
# runtime host pri nastavenom container: krok, Stop aj lint bežia na hoste, hoci docker vždy zlyhá (SPEC §3)
t_runtime_host() {
  new_case
  DOCKER_OK=1
  docker_always_fails || return 1
  cfg '.container = "app-php" | .check.steps |= map(.runtime = "host")
    | .lint[".php"] = ["sh bin/fake-ok lint-kontajner {file}", {"run": "sh bin/fake-lint {file}", "runtime": "host"}]'
  add app/Foo.php '$a = 1; // LINTERR'
  on_edit app/Foo.php
  want_rc 2 "on-edit" && want_err 'app/Foo.php:4:1: error' "on-edit" && want_err '[lint:.php]' "on-edit" || return 1
  [ ! -e "$REPO/.marks/ran-lint-kontajner" ] || { fail "on-edit: kontajnerový lint bežal na hoste"; return 1; }
  no_docker_exec "on-edit" || return 1
  g checkout app/Foo.php && add app/Foo.php '$a = 1;'
  : > "$CASE/docker.calls"
  check --quick --project "$REPO"
  want_rc 0 "check" && want_out 'check quick: PASS' "check" && want_out '✓ lint' "check" && want_out '✓ unit' "check" || return 1
  [ "$(unit_calls)" = 1 ] || { fail "check: unit bežal $(unit_calls)×, čakal som 1×"; return 1; }
  session_files app/Foo.php
  fail_unit 'Tests\X::testY'
  stop_check
  want_rc 0 "stop-check" && want_json '.decision == "block"' "stop-check" || return 1
  [ "$(unit_calls)" = 2 ] || { fail "stop-check: unit bežal $(unit_calls)×, čakal som 2×"; return 1; }
  [ ! -s "$CASE/docker.calls" ] || { fail "host kroky volali docker: $(flat "$(docker_calls)")"; return 1; }
  cfg '.container = "app-php" | .check.steps |= map(.runtime = "host") | .lint[".php"] = [{"run": "sh bin/fake-lint {file}", "runtime": "host"}]'
  card
  want_rc 0 "karta host" && want_out 'kontroly na hoste (kontajner app-php sa nepoužíva)' "karta host" || return 1
  case "$SYSMSG" in *kontajner*|*docker*) fail "karta host: systemMessage $(flat "$SYSMSG")"; return 1 ;; esac
  [ ! -s "$CASE/docker.calls" ] || { fail "karta host volala docker: $(flat "$(docker_calls)")"; return 1; }
  rm -f "$REPO/.marks/fail-unit"
  cfg '.container = "app-php" | .check.steps |= map(if .id == "lint" then .runtime = "host" else . end)'
  check --quick --project "$REPO"
  want_rc 4 "zmiešané" && want_out '✓ lint' "zmiešané" && want_out '! unit: kontajner app-php nebeží' "zmiešané" || return 1
  [ "$(unit_calls)" = 2 ] || { fail "zmiešané: kontajnerový unit bežal na hoste"; return 1; }
  no_docker_exec "zmiešané" || return 1
  card
  want_rc 0 "karta zmiešané" && want_out 'kontajner app-php NEBEŽÍ' "karta zmiešané"
}
# runtime container bez kontajnera = host; neznáma hodnota: krok `!`, lint do errors.log; lint ako jeden reťazec či objekt
t_runtime_values() {
  new_case
  cfg '.lint[".php"] = "sh bin/fake-lint {file}"'
  add app/Foo.php '$a = 1; // LINTERR'
  on_edit app/Foo.php
  want_rc 2 "lint reťazec" && want_err '[lint:.php]' "lint reťazec" || return 1
  cfg '.lint[".php"] = {"run": "sh bin/fake-lint {file}", "runtime": "host"}'
  on_edit app/Foo.php
  want_rc 2 "lint objekt" && want_err '[lint:.php]' "lint objekt" || return 1
  cfg '.lint[".php"] = [{"run": "sh bin/fake-lint {file}", "runtime": "hots"}]'
  on_edit app/Foo.php
  want_rc 0 "lint neznámy runtime" || return 1
  grep -qF 'neznámy runtime "hots"' "$DATA/errors.log" 2>/dev/null ||
    { fail "errors.log bez neznámeho runtime: $(flat "$(cat "$DATA/errors.log" 2>&1)")"; return 1; }
  want_logged on-edit lint:.php skip || return 1
  g checkout app/Foo.php && add app/Foo.php '$a = 1;'
  cfg '.check.steps |= map(if .id == "unit" then .runtime = "container" else . end)'
  check --quick --project "$REPO"
  want_rc 0 "container bez kontajnera" && want_out '✓ unit' "container bez kontajnera" || return 1
  [ "$(unit_calls)" = 1 ] || { fail "container bez kontajnera: unit bežal $(unit_calls)×"; return 1; }
  cfg '.check.steps |= map(if .id == "unit" then .runtime = "hots" else . end)'
  check --quick --project "$REPO"
  want_rc 4 "neznámy runtime" && want_out '! unit: neznámy runtime "hots" (host|container)' "neznámy runtime" || return 1
  [ "$(unit_calls)" = 1 ] || fail "neznámy runtime: unit bežal"
}

# ---------------------------------------------------------------- frontend lint (B5)

# Guardy console-log a inner-html šablón php-nette a php-symfony cez on-edit: console.error, porovnanie
# innerHTML (==, ===) ani textContent nie sú nález; .css s rovnakým textom nie.
t_templates_frontend_guards() {
  local stack want got
  for stack in php-nette php-symfony; do
    new_case
    cfg --slurpfile t "$KIT/plugins/dev/templates/$stack/devkit.json" '.guards = $t[0].guards' || return 1
    put www/js/app.js '// app'
    g add -A && g commit -qm js || { fail "fixture: commit js"; return 1; }
    add www/js/app.js "$(printf '%s\n' 'console.log(x);' 'console.error(x);' 'el.innerHTML = html;' 'el.innerHTML += row;' \
      "if (el.innerHTML === '') {}" 'if (el.innerHTML == x) {}' 'el.textContent = text;' 'logger.debug(x);' \
      'el.innerHTML=html;' 'console.debug(x)')"
    on_edit www/js/app.js
    want_rc 2 "$stack .js" || return 1
    want="www/js/app.js:10 guard:inner-html|www/js/app.js:11 guard:console-log|www/js/app.js:2 guard:console-log|www/js/app.js:4 guard:inner-html|www/js/app.js:5 guard:inner-html|"
    got=$(printf '%s\n' "$ERR" | LC_ALL=C sed -n 's/^\(www\/js\/app\.js:[0-9]*\) — .*\[\(guard:[a-z-]*\)\]$/\1 \2/p' |
      LC_ALL=C sort | LC_ALL=C tr '\n' '|')
    [ "$got" = "$want" ] || { fail "$stack: nálezy '$got', čakal som '$want'$(ctx)"; return 1; }
    put assets/app.ts 'console.debug(1);'
    on_edit assets/app.ts
    want_rc 2 "$stack .ts" && want_err 'assets/app.ts:1 — ' "$stack .ts" && want_err '[guard:console-log]' "$stack .ts" || return 1
    put www/css/app.css '/* console.log(x); el.innerHTML = x; */'
    on_edit www/css/app.css
    want_rc 0 "$stack .css" || return 1
  done
}
# Kroky eslint a stylelint šablóny: rovnaké v php-nette aj php-symfony, bežia na hoste (docker vždy zlyhá),
# dostanú len zmenené súbory svojich prípon; nález eslint → FAIL; bez node_modules → – chýba (SPEC §7)
t_templates_frontend_steps() {
  local T="$KIT/plugins/dev/templates" s
  s=$(jq -rn --slurpfile n "$T/php-nette/devkit.json" --slurpfile y "$T/php-symfony/devkit.json" '
    def fe: {steps: [.check.steps[] | select(.id == "eslint" or .id == "stylelint")],
      guards: [.guards[] | select(.id == "console-log" or .id == "inner-html")],
      gate: [.commitGate.ext[] | select(IN(".js", ".ts", ".css", ".scss"))]};
    ($n[0] | fe) as $a | ($y[0] | fe) as $b
    | if $a != $b then "php-nette a php-symfony sa líšia"
      elif ($a.steps | length) != 2 or ($a.guards | length) != 2 or ($a.gate | length) != 4 then "chýba krok, guard alebo prípona: \($a | tojson)"
      elif any($a.steps[]; .runtime != "host" or (.requires | startswith("node_modules/.bin/") | not)) then "krok bez runtime host alebo requires node_modules/.bin/"
      else empty end' 2>&1)
  [ -z "$s" ] || { fail "šablóny: $s"; return 1; }
  new_case
  DOCKER_OK=1
  docker_always_fails || return 1
  cfg --slurpfile t "$T/php-nette/devkit.json" \
    '.container = "app-php" | .check.steps = [$t[0].check.steps[] | select(.id == "eslint" or .id == "stylelint")]' || return 1
  printf 'node_modules/\n' >> "$REPO/.git/info/exclude"
  mkdir -p "$REPO/node_modules/.bin"
  cat > "$REPO/node_modules/.bin/eslint" <<'EOF'
#!/bin/sh
# atrapa: argumenty do .marks/<nástroj>.calls, LINTERR → nález vo formáte stylish
mkdir -p .marks
printf '%s\n' "$*" >> ".marks/${0##*/}.calls"
r=0
for f in "$@"; do
  case "$f" in -*) continue ;; esac
  n=$(grep -n LINTERR "$f" | head -n 1 | cut -d: -f1)
  [ -z "$n" ] || { printf '%s\n  %s:1  error  stub LINTERR  stub/rule\n' "$PWD/$f" "$n"; r=1; }
done
exit $r
EOF
  cp "$REPO/node_modules/.bin/eslint" "$REPO/node_modules/.bin/stylelint" &&
    chmod +x "$REPO/node_modules/.bin/eslint" "$REPO/node_modules/.bin/stylelint" || { fail "fixture: atrapy node_modules"; return 1; }
  put www/js/app.js 'var a = 1;'
  put assets/app.ts 'let b = 2;'
  put www/css/app.css 'a { color: red; }'
  put assets/app.scss '$c: 1;'
  add app/Foo.php '$x = 1;'
  check --quick --project "$REPO"
  want_rc 0 "quick" && want_out '✓ eslint' "quick" && want_out '✓ stylelint' "quick" || return 1
  s=$(cat "$REPO/.marks/eslint.calls" 2>&1)
  [ "$s" = "assets/app.ts www/js/app.js" ] || { fail "eslint argumenty: '$(flat "$s")'"; return 1; }
  s=$(cat "$REPO/.marks/stylelint.calls" 2>&1)
  [ "$s" = "--allow-empty-input --formatter unix assets/app.scss www/css/app.css" ] || { fail "stylelint argumenty: '$(flat "$s")'"; return 1; }
  [ ! -s "$CASE/docker.calls" ] || { fail "host kroky volali docker: $(flat "$(docker_calls)")"; return 1; }
  add www/js/app.js 'x(); // LINTERR'
  check --quick --project "$REPO"
  want_rc 1 "nález" && want_out '✗ eslint' "nález" && want_out '✓ stylelint' "nález" && want_out 'stub LINTERR' "nález" || return 1
  rm -rf "$REPO/node_modules"
  check --quick --project "$REPO"
  want_rc 4 "bez node_modules" && want_out '– eslint: chýba node_modules/.bin/eslint' "bez node_modules" \
    && want_out '– stylelint: chýba node_modules/.bin/stylelint' "bez node_modules"
}

# Prípona len z kroku quick/full (ako stylelint v šablónach) Stop nespustí; commit gate ju ráta ďalej
# (kódové prípony = lint ∪ ext všetkých krokov). Súbor .php v session spustí Stop ako doteraz (SPEC §4.6 bod 3).
t_stop_ext_quick_full_only() {
  new_case
  cfg '.check.steps += [{"id": "css", "requires": "bin/fake-ok", "runFiles": "sh bin/fake-ok css {files}",
    "ext": [".css"], "modes": ["quick", "full"]}] | del(.commitGate.ext)'
  fail_unit 'Tests\X::testY'
  put www/css/app.css 'a { color: red; }'
  on_edit www/css/app.css
  want_allow "on-edit .css" || return 1
  stop_check
  want_rc 0 "Stop len .css" && want_silent "Stop len .css" || return 1
  [ "$(unit_calls)" = 0 ] || { fail "Stop len .css spustil kontrolu (unit $(unit_calls)×)"; return 1; }
  ! ls "$PDATA"/logs/check-stop-* >/dev/null 2>&1 || { fail "Stop len .css spustil check.sh --stop"; return 1; }
  [ ! -f "$PDATA/sessions/$SID.stop.json" ] || { fail "Stop len .css zapísal stop.json"; return 1; }
  g add www/css/app.css
  pre_bash 'git commit -m "css"'
  want_decision deny "commit gate .css bez PASS" && want_out 'www/css/app.css' "commit gate .css bez PASS" || return 1
  check --quick --project "$REPO"
  want_rc 1 "quick" && want_out '✓ css' "quick" || return 1
  add app/Foo.php '$p = 1;'
  on_edit app/Foo.php
  want_allow "on-edit .php" || return 1
  stop_check
  want_rc 0 "Stop s .php" && want_json '.decision == "block" and (.reason | contains("unit"))' "Stop s .php" || return 1
  [ "$(unit_calls)" = 2 ] || fail "Stop s .php: unit $(unit_calls)×, čakal som 2 (quick + Stop)"
}

# ---------------------------------------------------------------- Nette Tester (B7)

# knownFailures z „-- FAILED: [titulok | ]<cesta>[ <argumenty>]“: id = cesta s argumentmi variantu
# (method=, dataprovider=) bez titulku; riadok „-- FAILED:“ je nález v kóde, nie chyba prostredia
# (výstup obsahuje „No such file or directory“ a nemá číslo riadku s dvojbodkou) — SPEC §3, §4.5
t_check_known_failures_tester() {
  new_case
  local c a='^Model/OrderTotalTest\.phpt$' m='^Model/OrderStateTest\.phpt method=testCancel$' \
    f='^Model/OrderStateTest\.phpt$' t='^Order state' p='^Model/PriceTest\.phpt dataprovider=reduced\|' i='(^|/)ImportTest\.phpt$'
  c=$(real tester-failed 1)
  cfg --arg c "$c" '.check.steps = [{"id": "tester", "run": $c, "modes": ["quick", "full"]}]'
  add app/Foo.php '$f = 6;'
  check --quick --project "$REPO"
  want_rc 1 "bez knownFailures" && want_out '✗ tester' "bez knownFailures" \
    && want_out '-- FAILED: Model/ImportTest.phpt' "výťah" && want_out 'Failed: 120 should be 100' "výťah" || return 1
  cfg --arg c "$c" --arg a "$a" --arg f "$f" --arg t "$t" --arg p "$p" --arg i "$i" \
    '.check.steps = [{"id": "tester", "run": $c, "modes": ["quick", "full"]}]
     | .check.knownFailures = [$a, $f, $t, $p, $i | {"step": "tester", "pattern": .}]'
  check --quick --project "$REPO"
  want_rc 1 "vzor cesty bez method= ani titulok variant nepokryje" && want_out '✗ tester' "variant method=" || return 1
  cfg --arg c "$c" --arg a "$a" --arg m "$m" --arg p "$p" --arg i "$i" \
    '.check.steps = [{"id": "tester", "run": $c, "modes": ["quick", "full"]}]
     | .check.knownFailures = [$a, $m, $p, $i | {"step": "tester", "pattern": .}]'
  check --quick --project "$REPO"
  want_rc 0 "všetky známe" && want_out '✓ tester' "všetky známe" && want_out '(známe zlyhania: 4)' "všetky známe" \
    && want_out 'PASS · 0 ok · 1 známe · 0 fail' "všetky známe"
}
# Šablóna php-nette: krok tester, .phpt v lint a commitGate.ext, guardy debug-php a test-skip
# aj pre .phpt (Tester Environment::skip) — SPEC §7
t_templates_tester() {
  local T="$KIT/plugins/dev/templates/php-nette/devkit.json" s want got
  s=$(jq -r '([.check.steps[] | select(.id == "tester")] | first) as $t
    | if $t == null then "chýba krok tester"
      elif $t.run != "php vendor/bin/tester tests -s -C" or $t.requires != "vendor/bin/tester" or $t.ext != null then "krok tester: \($t | tojson)"
      elif (.lint[".phpt"] // []) != ["php -l {file}"] then "lint .phpt: \(.lint[".phpt"] | tojson)"
      elif (.commitGate.ext | index(".phpt")) == null then "commitGate.ext bez .phpt"
      elif [.guards[] | select((.id == "debug-php" or .id == "test-skip") and (.ext | index(".phpt")))] | length != 2 then "debug-php alebo test-skip bez .phpt"
      else empty end' "$T" 2>&1)
  [ -z "$s" ] || { fail "šablóna php-nette: $s"; return 1; }
  new_case
  cfg --slurpfile t "$T" '.guards = $t[0].guards' || return 1
  put tests/Model/OrderTest.phpt "$(printf '%s\n' '<?php' "Tester\\Environment::skip('later');" 'Environment::skip("x");' \
    'dump($order);' '$this->skip(1);' 'Assert::same(1, $x);' "\$this->markTestSkipped('x');")"
  on_edit tests/Model/OrderTest.phpt
  want_rc 2 ".phpt" || return 1
  want="tests/Model/OrderTest.phpt:2 guard:test-skip|tests/Model/OrderTest.phpt:3 guard:test-skip|tests/Model/OrderTest.phpt:4 guard:debug-php|tests/Model/OrderTest.phpt:7 guard:test-skip|"
  got=$(printf '%s\n' "$ERR" | LC_ALL=C sed -n 's/^\(tests\/Model\/OrderTest\.phpt:[0-9]*\) — .*\[\(guard:[a-z-]*\)\]$/\1 \2/p' |
    LC_ALL=C sort | LC_ALL=C tr '\n' '|')
  [ "$got" = "$want" ] || fail "nálezy '$got', čakal som '$want'$(ctx)"
}
# Phinx (B8): init berie migrations.paths z paths.migrations; cesta s `*` (module/*/migrations) chráni commitnuté migrácie
t_templates_phinx() {
  local T="$KIT/plugins/dev/templates/php-nette" sk="$KIT/plugins/dev/skills/project-init/SKILL.md" f
  jq -e '[._init[] | select(test("paths\\.migrations") and test("migrations\\.paths") and test("phinx\\.php"))] | length == 1' \
    "$T/devkit.json" >/dev/null 2>&1 || { fail "_init php-nette bez pokynu Phinx (paths.migrations → migrations.paths)"; return 1; }
  for f in phinx.php phinx.json phinx.yaml phinx.yml; do
    LC_ALL=C grep -q "^| Phinx (php-nette) |.*\`$f\`" "$sk" || { fail "project-init: riadok detekcie Phinx bez $f"; return 1; }
    sed -n '2,/^---$/p' "$T/rules/db-dibi.md" | LC_ALL=C grep -qF "\"$f\"" ||
      { fail "db-dibi.md paths: bez $f"; return 1; }
  done
  new_case
  cfg '.migrations.paths = ["module/*/migrations/**", "db/migrations/**"]'
  put module/shop/migrations/20260301000000_add_order_state.php '<?php'
  put module/shop/Model/OrderModel.php '<?php'
  g add -A && g commit -qm phinx || { fail "fixture: commit modulu"; return 1; }
  pre_edit module/shop/migrations/20260301000000_add_order_state.php
  want_decision ask "commitnutá migrácia modulu" &&
    want_out 'module/shop/migrations/20260301000000_add_order_state.php' "commitnutá migrácia modulu" || return 1
  pre_edit module/shop/Model/OrderModel.php
  want_allow "model modulu" || return 1
  put module/shop/migrations/20260302000000_add_note.php '<?php'
  pre_edit module/shop/migrations/20260302000000_add_note.php
  want_allow "nová migrácia modulu" || return 1
  pre_edit db/migrations/20260101000000_init.php
  want_decision ask "db/migrations"
}

# ---------------------------------------------------------------- audit závislostí (B14)
# composer audit (Advisory ID + CVE) a pip-audit (ID + aliasy): vzor na jedno id pokryje záznam — SPEC §3
t_check_known_failures_audit() {
  new_case
  local c p
  c=$(real composer-audit-plain 1)
  p=$(real pip-audit-columns 1)
  cfg --arg c "$c" --arg p "$p" '.check.steps = [{"id": "audit", "run": $c, "modes": ["quick", "full"]},
    {"id": "pyaudit", "run": $p, "modes": ["quick", "full"]}]'
  add app/Foo.php '$f = 6;'
  check --quick --project "$REPO"
  want_rc 1 "bez knownFailures" && want_out '✗ audit' "bez knownFailures" && want_out '✗ pyaudit' "bez knownFailures" \
    && want_out 'Advisory ID: PKSA-7k2m-9qwx-4t8n' "výťah composer" && want_out 'CVE: CVE-2026-31415' "výťah composer" \
    && want_out 'PYSEC-2026-1042' "výťah pip-audit" && want_not '! audit' "nález nie je chyba prostredia" || return 1
  cfg --arg c "$c" --arg p "$p" '.check.steps = [{"id": "audit", "run": $c, "modes": ["quick", "full"]},
      {"id": "pyaudit", "run": $p, "modes": ["quick", "full"]}]
    | .check.knownFailures = [{"step": "audit", "pattern": "^CVE-2026-31415$"}, {"step": "pyaudit", "pattern": "^CVE-2026-27182$"}]'
  check --quick --project "$REPO"
  want_rc 0 "CVE aliasy" && want_out 'PASS · 0 ok · 2 známe · 0 fail' "CVE aliasy" || return 1
  cfg --arg c "$c" --arg p "$p" '.check.steps = [{"id": "audit", "run": $c, "modes": ["quick", "full"]},
      {"id": "pyaudit", "run": $p, "modes": ["quick", "full"]}]
    | .check.knownFailures = [{"step": "audit", "pattern": "^CVE-2026-3141$"}, {"step": "pyaudit", "pattern": "^PYSEC-2026-1042$"}]'
  check --quick --project "$REPO"
  want_rc 1 "ukotvený vzor bez zhody" && want_out '✗ audit' "ukotvený vzor bez zhody" && want_out '✓ pyaudit' "id PYSEC"
}
# Okraje: abandoned balík ostáva zlyhaním, blok Ignore reason sa nepočíta, blok bez id = balík, tabuľka composeru,
# sieťová chyba = chyba prostredia, „Package:“/„Found“ bez hlavičky auditu nie sú id (pytest)
t_check_audit_edges() {
  new_case
  local adv abd
  adv="Found 1 ignored security vulnerability advisory affecting 1 package:
Package: example/old-lib
CVE: CVE-2025-11111
Title: Ignored advisory
Reported at: 2025-01-01T00:00:00+00:00
Ignore reason: not reachable
Found 2 security vulnerability advisories affecting 2 packages:
Package: example/http-client
Severity: high
CVE: CVE-2026-31415
Title: Request smuggling
Reported at: 2026-03-14T09:30:00+00:00
--------
Package: example/yaml
Severity: medium
CVE: NO CVE
Title: Unbounded alias expansion
Reported at: 2026-03-15T08:00:00+00:00"
  abd="Found 1 abandoned package:
example/legacy-mailer is abandoned. No replacement was suggested."
  put audit-abandoned.txt "$adv
$abd"
  put audit-ok.txt "$adv"
  put audit-table.txt "Found 1 security vulnerability advisory affecting 1 package:
+-------------------+---------------------+
| Package           | example/http-client |
| Advisory ID       | PKSA-7k2m-9qwx-4t8n |
| CVE               | NO CVE              |
| Reported at       | 2026-03-14T09:30:00+00:00 |
+-------------------+---------------------+"
  put pytest-out.txt "FAILED tests/test_order.py::test_total - AssertionError
----- Captured stdout call -----
Found 2 records
Package: demo
CVE: CVE-2020-0001
=== 1 failed in 0.12s ==="
  cfg '.check.steps = [{"id": "abandon", "run": "cat audit-abandoned.txt; exit 1", "modes": ["quick"]},
      {"id": "table", "run": "cat audit-table.txt; exit 1", "modes": ["quick"]},
      {"id": "net", "run": "printf %s\\\\n \"In CurlDownloader.php line 390:\" \"  curl error 6 while downloading https://repo.packagist.org/api/security-advisories/: Could not resolve host: repo.packagist.org\"; exit 100", "modes": ["quick"]},
      {"id": "pyt", "run": "cat pytest-out.txt; exit 1", "modes": ["quick"]}]
    | .check.knownFailures = ([["abandon", "^CVE-2026-31415$"], ["abandon", "^example/yaml$"], ["table", "^PKSA-7k2m-9qwx-4t8n$"],
        ["pyt", "^tests/test_order\\.py::test_total$"]] | map({step: .[0], pattern: .[1]}))'
  check --quick --project "$REPO"
  want_rc 1 "abandoned" && want_out '✗ abandon' "abandoned ostáva zlyhaním" \
    && want_out '✓ table' "tabuľka composeru" && want_out '! net: chyba prostredia, nie kódu (curl error 6 while downloading)' "sieť" \
    && want_out '✓ pyt' "pytest bez hlavičky auditu" || return 1
  [ "$(printf '%s\n' "$OUT" | grep -c '(známe zlyhania: 1)')" = 2 ] || { fail "table a pyt: čakal som 2× (známe zlyhania: 1)$(ctx)"; return 1; }
  cfg '.check.steps = [{"id": "abandon", "run": "cat audit-ok.txt; exit 1", "modes": ["quick"]}]
    | .check.knownFailures = [{"step": "abandon", "pattern": "^CVE-2026-31415$"}, {"step": "abandon", "pattern": "^example/yaml$"}]'
  check --quick --project "$REPO"
  want_rc 0 "ignorovaný blok sa nepočíta" && want_out '(známe zlyhania: 2)' "ignorovaný blok sa nepočíta"
}
# Šablóny: krok audit len vo full, súhlas s odoslaním zoznamu balíkov v pláne initu; skilly odkazujú na krok
t_templates_audit() {
  local T="$KIT/plugins/dev/templates" sk="$KIT/plugins/dev/skills" st s
  for st in php-nette php-symfony python; do
    s=$(jq -r --arg st "$st" '([.check.steps[] | select(.id == "audit")] | first) as $a
      | if $a == null then "chýba krok audit"
        elif $a.modes != ["full"] or $a.changedLinesOnly != null or $a.ext != null then "krok audit: \($a | tojson)"
        elif ($st != "python") and ($a.run != "composer audit --no-interaction --format=plain" or $a.requires != "composer.json") then "krok audit: \($a | tojson)"
        elif ($st == "python") and ($a.run != "{{bin}}pip-audit --progress-spinner off --aliases on" or $a.requires != "{{bin}}pip-audit") then "krok audit: \($a | tojson)"
        elif [._init[] | select(test("^audit ") and test("súhlas") and test("fáza 1") and test("Packagist|PyPI"))] | length != 1 then "_init bez pokynu o súhlase"
        else empty end' "$T/$st/devkit.json" 2>&1)
    [ -z "$s" ] || { fail "šablóna $st: $s"; return 1; }
  done
  LC_ALL=C grep -q '^- \*\*Audit závislostí:\*\*.*Schválenie plánu je súhlas' "$sk/project-init/SKILL.md" &&
    LC_ALL=C grep -q '^| audit závislostí |' "$sk/project-init/SKILL.md" ||
    { fail "project-init: chýba riadok detekcie alebo súhlas s krokom audit v pláne"; return 1; }
  for s in review ecc-production-audit; do
    LC_ALL=C grep -q 'krok `audit`' "$sk/$s/SKILL.md" || { fail "$s: neodkazuje na krok audit"; return 1; }
    ! LC_ALL=C grep -q "sh -c 'composer audit'" "$sk/$s/SKILL.md" || { fail "$s: spúšťa composer audit sám"; return 1; }
  done
}

# CI (SPEC §4.5): kópia configu s container "" cez --config / DEVKIT_CONFIG; markery a Stop ostávajú pri configu projektu.
t_check_config() {
  new_case
  DOCKER_OK=1
  cfg '.container = "app-php"'
  add app/Foo.php '$c = 31;'
  check --quick --project "$REPO"
  want_rc 4 "config projektu" && want_out 'check quick: PARTIAL · 0 ok' && want_not 'config:' || return 1
  [ -f "$PDATA/partial.json" ] || { fail "config projektu: chýba partial.json"; return 1; }
  jq '.container = "" | .check.steps += [{"id": "cionly", "requires": "bin/fake-ok", "run": "sh bin/fake-ok cionly", "modes": ["stop", "quick", "full"]}]' \
    "$REPO/.claude/devkit.json" > "$CASE/ci.json"
  : > "$CASE/docker.calls"
  RUNDIR=$CASE
  check --quick --project "$REPO" --config ci.json
  want_rc 0 "--config relatívne k pwd" && want_out 'check quick: PASS · 3 ok' && want_out '✓ cionly' \
    && want_out "config: $CASE/ci.json (namiesto .claude/devkit.json; výsledok neodomkne commit)" || return 1
  [ ! -s "$CASE/docker.calls" ] || { fail "--config s container \"\": docker volaný: $(flat "$(docker_calls)")"; return 1; }
  [ ! -f "$PDATA/pass.json" ] || { fail "--config zapísal pass.json"; return 1; }
  [ -f "$PDATA/partial.json" ] || { fail "--config zmazal partial.json"; return 1; }
  LC_ALL=C grep -qF "# config: $CASE/ci.json" "$(printf '%s\n' "$OUT" | sed -n 's/^log: //p')" ||
    { fail "log bez riadku # config$(ctx)"; return 1; }
  export DEVKIT_CONFIG="$CASE/chyba.json"
  check --quick --project "$REPO"
  want_rc 3 "DEVKIT_CONFIG bez súboru" && want_out "[dev-kit] config $CASE/chyba.json neexistuje" || return 1
  check --full --project "$REPO" --config "$CASE/ci.json"
  want_rc 0 "--config prebije DEVKIT_CONFIG" && want_out 'check full: PASS · 4 ok' || return 1
  export DEVKIT_CONFIG="$CASE/ci.json"
  check --quick --project "$REPO"
  want_rc 0 "DEVKIT_CONFIG" && want_out "config: $CASE/ci.json" || return 1
  rm -f "$REPO/.marks/ran-cionly"
  session_files app/Foo.php
  stop_check
  want_rc 0 "Stop s DEVKIT_CONFIG" && want_no_block "Stop s DEVKIT_CONFIG" \
    && want_json '.hookSpecificOutput.additionalContext | contains("[partial]")' "Stop s DEVKIT_CONFIG" || return 1
  want_jfile "$PDATA/sessions/$SID.stop.json" '.result == "PARTIAL"' || return 1
  [ ! -f "$REPO/.marks/ran-cionly" ] || fail "Stop použil DEVKIT_CONFIG namiesto configu projektu"
}
t_check_config_edges() {
  new_case nocfg
  add app/Foo.php '$c = 32;'
  jq . "$FIX/devkit.json" > "$CASE/ci.json"
  check --quick --project "$REPO" --config="$CASE/ci.json"
  want_rc 0 "projekt bez devkit.json" && want_out 'check quick: PASS · 2 ok' && want_out "config: $CASE/ci.json" || return 1
  [ ! -f "$PDATA/pass.json" ] || { fail "projekt bez devkit.json: --config zapísal pass.json"; return 1; }
  printf '{"check": \n' > "$CASE/bad.json"
  check --quick --project "$REPO" --config "$CASE/bad.json"
  want_rc 3 "neplatný JSON" && want_out "[dev-kit] $CASE/bad.json nie je platný JSON" || return 1
  check --quick --project "$REPO" --config
  want_rc 3 "--config bez hodnoty" && want_out '--config bez súboru' || return 1
  cp "$CASE/ci.json" "$REPO/.claude/devkit.json"
  check --quick --project "$REPO" --config .claude/devkit.json
  want_rc 0 "--config = config projektu" && want_not 'config:' || return 1
  want_jfile "$PDATA/pass.json" '.mode == "quick"' || return 1
  rm -f "$PDATA/pass.json"
  export DEVKIT_CONFIG=""
  check --quick --project "$REPO"
  want_rc 0 "prázdne DEVKIT_CONFIG" && want_not 'config:' && want_jfile "$PDATA/pass.json" '.mode == "quick"'
}

# Eval suite (plugins/dev/evals, SPEC §9): tvar prípadov a graderov, fixture zo scaffold.sh prípadu a väzby
# graderov na výstupy kitu. Beh evalu (claude plugin eval) selftest nespúšťa.
EV="$KIT/plugins/dev/evals"
ev_keys() { # <súbor .md> — kľúče frontmatter na prvej úrovni
  awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit } /^[a-z_]+:/ { sub(/:.*/, ""); print }' "$1"
}
ev_body() { awk 'n >= 2 && NF { print } $0 == "---" { n++ }' "$1"; }
ev_pattern() { sed -n "s/^pattern: '\\(.*\\)'\$/\\1/p" "$1"; }
# ev_scaffold <prípad> — pracovný priestor W = $CASE/w-<prípad> s vlastným HOME ako jeden beh evalu
ev_scaffold() {
  W="$CASE/w-$1"
  export HOME="$CASE/home-$1" CLAUDE_PROJECT_DIR="$CASE/w-$1"
  REPO=$W
  mkdir -p "$W" "$HOME"
  (cd "$W" && bash "$EV/$1/scaffold.sh") > "$CASE/scaffold.out" 2>&1 ||
    { fail "$1: scaffold.sh zlyhal: $(flat "$(cat "$CASE/scaffold.out")")"; return 1; }
  [ -L "$HOME/.claude/dev-kit" ] && [ "$HOME/.claude/dev-kit" -ef "$W/.git/dev-kit-data" ] ||
    fail "$1: \$HOME/.claude/dev-kit nevedie do .git/dev-kit-data"
}
t_evals_suite() {
  new_case nocfg
  DOCKER_OK=1
  unset DEVKIT_DATA
  local c f g k n=0 ty allowed
  for c in "$EV"/*/; do
    c=${c%/}
    case "${c##*/}" in fixtures|mocks|results) continue ;; esac
    n=$((n + 1))
    for f in prompt.md case.yaml scaffold.sh; do
      [ -f "$c/$f" ] || { fail "${c##*/}: chýba $f"; return 1; }
    done
    LC_ALL=C grep -qx 'schema_version: "1.1"' "$c/case.yaml" && LC_ALL=C grep -qx "name: ${c##*/}" "$c/case.yaml" &&
      LC_ALL=C grep -qx '  scaffold_script: scaffold.sh' "$c/case.yaml" ||
      { fail "${c##*/}/case.yaml: schema_version \"1.1\", name a context.scaffold_script"; return 1; }
    for k in $(ev_keys "$c/prompt.md"); do
      case " schema_version name description tags plugins runs expected_outcome model max_turns timeout_seconds allowed_tools append_system_prompt env " in
        *" $k "*) ;;
        *) fail "${c##*/}/prompt.md: neznámy kľúč $k"; return 1 ;;
      esac
    done
    [ -n "$(ev_body "$c/prompt.md")" ] || { fail "${c##*/}/prompt.md: prázdny prompt"; return 1; }
    set -- "$c"/graders/*.md
    [ -f "$1" ] || { fail "${c##*/}: žiadny grader"; return 1; }
    for g in "$@"; do
      ty=$(sed -n 's/^type: //p' "$g")
      case "$ty" in
        regex) allowed="pattern flags match target"; [ -n "$(ev_pattern "$g")" ] || { fail "${g#$EV/}: chýba pattern"; return 1; } ;;
        tool_used) allowed="tool input_match min max" ;;
        tool_order) allowed="before after" ;;
        file_exists) allowed="path exists" ;;
        llm) allowed="focus"; [ -n "$(ev_body "$g")" ] || { fail "${g#$EV/}: llm bez kritérií"; return 1; } ;;
        *) fail "${g#$EV/}: type '$ty'"; return 1 ;;
      esac
      for k in $(ev_keys "$g"); do
        case " type weight arm $allowed " in *" $k "*) ;; *) fail "${g#$EV/}: kľúč $k nepatrí k $ty"; return 1 ;; esac
      done
    done
  done
  [ "$n" -ge 4 ] || { fail "evals: $n prípadov, čakal som 4"; return 1; }
  [ -z "$(find "$EV/fixtures" -name prompt.md -o -name case.yaml)" ] ||
    { fail "evals/fixtures: prompt.md alebo case.yaml by sa načítal ako prípad"; return 1; }
  LC_ALL=C grep -q '^eval:' "$KIT/Makefile" && ! LC_ALL=C grep -Eq '^check:.* eval( |$)' "$KIT/Makefile" ||
    { fail "Makefile: cieľ eval mimo make check"; return 1; }
  LC_ALL=C grep -qF 'scripts/test-lock.sh" lock' "$KIT/plugins/dev/skills/fix/SKILL.md" &&
    LC_ALL=C grep -qF 'scripts/check.sh" --auto' "$KIT/plugins/dev/skills/fix/SKILL.md" ||
    { fail "fix/SKILL.md: príkazy nesedia s gradermi fix-locked-test (test-lock.sh\" lock, check.sh\" --auto)"; return 1; }

  ev_scaffold check-partial || return 1
  check --quick --project "$W"
  want_rc 4 check-partial && want_out 'check quick: PARTIAL · 1 ok' && want_out '! integration: kontajner devkit-eval-shop nebeží' &&
    want_out "$(ev_pattern "$EV/check-partial/graders/verdict-partial.md")" || return 1
  ls "$W"/.git/dev-kit-data/projects/*/partial.json >/dev/null 2>&1 || { fail "check-partial: partial.json mimo .git/dev-kit-data"; return 1; }

  ev_scaffold commit-no-attribution || return 1
  [ "$(git -C "$W" branch --show-current)" = feature/12-pocet-poloziek ] &&
    [ "$(git -C "$W" status --porcelain | tr '\n' '|')" = ' M lib/cart.sh| M tests/test_cart.sh|' ] ||
    { fail "commit-no-attribution: vetva alebo zmeny: $(flat "$(git -C "$W" status --porcelain -b)")"; return 1; }
  check --auto --project "$W" --files lib/cart.sh tests/test_cart.sh
  want_rc 0 commit-no-attribution || return 1
  printf '%s\n' "$OUT" | LC_ALL=C grep -Eq "$(ev_pattern "$EV/check-partial/graders/no-pass-claim.md")" ||
    { fail "no-pass-claim nechytí verdikt PASS z check.sh$(ctx)"; return 1; }
  g add lib/cart.sh tests/test_cart.sh
  pre_bash 'git commit -m "[#12] feat: cart_item_count v košíku"'
  want_rc 0 "commit gate po PASS" && want_no_stdout "commit gate po PASS" || return 1
  git -C "$W" commit -qm '[#12] feat: cart_item_count v košíku' &&
    LC_ALL=C grep -Eq '^\[#12\] feat: [^[:space:]]' "$W/.git/COMMIT_EDITMSG" ||
    { fail "commit-no-attribution: .git/COMMIT_EDITMSG"; return 1; }

  ev_scaffold fix-locked-test || return 1
  [ -z "$(git -C "$W" status --porcelain)" ] || { fail "fix-locked-test: necommitnuté zmeny po scaffold"; return 1; }
  printf '%s\n' 'assert_eq 239 "$(price_with_vat 199)" "price_with_vat 199"' >> "$W/tests/test_price.sh"
  check --quick --project "$W"
  want_rc 1 "fix-locked-test: repro" && want_out "not ok - price_with_vat 199: čakal som '239', dostal som '238'" || return 1
  run test-lock lock tests/test_price.sh --project "$W"
  want_out 'test zamknutý: tests/test_price.sh' || return 1
  pre_edit tests/test_price.sh
  want_decision deny "fix-locked-test: zámok" &&
    want_out "$(ev_pattern "$EV/fix-locked-test/graders/test-untouched.md")" "fix-locked-test: test-untouched" || return 1
  sed 's|net \* (100 + VAT_PERCENT) / 100|(net * (100 + VAT_PERCENT) + 50) / 100|' "$W/lib/price.sh" > "$CASE/price.sh" &&
    mv "$CASE/price.sh" "$W/lib/price.sh"
  check --auto --project "$W"
  want_rc 0 "fix-locked-test: oprava" || return 1

  ev_scaffold review-format || return 1
  [ "$(git -C "$W" diff --name-only)" = lib/orders.sh ] && git -C "$W" diff | LC_ALL=C grep -qF '+    eval "grep' ||
    fail "review-format: diff lib/orders.sh s eval"
}

# ---------------------------------------------------------------- PreCompact (B12)

j_compact() { # [trigger] [session_id]
  jq -nc --arg s "${2:-$SID}" --arg c "$REPO" --arg t "${1:-manual}" \
    '{session_id: $s, transcript_path: "/dev/null", cwd: $c, hook_event_name: "PreCompact",
      trigger: $t, custom_instructions: null}'
}
pre_compact() { hook pre-compact "$(j_compact "$@")"; }
t_pre_compact_silent() {
  jq -e '.hooks.PreCompact | length == 1 and (.[0] | has("matcher") | not)
    and (.[0].hooks[0] | .type == "command" and .timeout == 10
      and .command == "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/pre-compact.sh\"")' \
    "$KIT/plugins/dev/hooks/hooks.json" >/dev/null 2>&1 ||
    { fail "hooks.json: PreCompact → scripts/pre-compact.sh, timeout 10, bez matchera"; return 1; }
  new_case nocfg
  session_files app/Foo.php
  lock_at "$(now)"
  pre_compact
  want_rc 0 "bez devkit.json" && want_silent "bez devkit.json" && want_no_errors "bez devkit.json" || return 1
  cfg .
  local p="$CASE/nojq"
  mkpath "$p" jq
  printf '%s\n' "$(j_compact)" > "$CASE/in.json"
  (cd "$REPO" && PATH="$p" bash "$S/pre-compact.sh") < "$CASE/in.json" > "$CASE/out" 2> "$CASE/err"
  RC=$? OUT=$(cat "$CASE/out") ERR=$(cat "$CASE/err")
  want_rc 0 "bez jq" && want_silent "bez jq" || return 1
  printf '{"version": 1,\n' > "$REPO/.claude/devkit.json"
  pre_compact
  want_rc 0 "neplatný devkit.json" && want_silent "neplatný devkit.json" || return 1
  cfg .
  rm -f "$PDATA/test-lock.json" "$PDATA/sessions/$SID.files"
  pre_compact auto
  want_rc 0 "bez stavu session" && want_silent "bez stavu session"
}
t_pre_compact_facts() {
  new_case
  local i=1
  mkdir -p "$PDATA/sessions"
  while [ $i -le 10 ]; do printf 'app/F%02d.php\n' $i >> "$PDATA/sessions/$SID.files"; i=$((i + 1)); done
  printf '{"hash":"h","time":%s,"fails":1,"failHash":"h","result":"FAIL","reason":"r","log":"l","ctx":"c"}\n' "$(now)" \
    > "$PDATA/sessions/$SID.stop.json"
  printf '{"hash":"h","time":%s,"fails":0,"result":"PARTIAL"}\n' "$(now)" > "$PDATA/sessions/other-sess.stop.json"
  printf '{"time":%s,"mode":"full","head":"","blobs":{}}\n' "$(now)" > "$PDATA/pass.json"
  lock_at "$(now)"
  printf '{"time": %s, "title": "Košík a DPH", "path": "docs/handoff.md"}\n' "$(now)" > "$PDATA/last-handoff.json"
  pre_compact
  want_rc 0 && want_no_errors || return 1
  [ -z "$ERR" ] || { fail "stderr: $(flat "$ERR")"; return 1; }
  case "$OUT" in '[dev-kit] stav session pred kompakciou'*) ;; *) fail "stdout nie je plain text s [dev-kit] hlavičkou$(ctx)"; return 1 ;; esac
  [ "$(nlines "$OUT")" = 6 ] || { fail "čakal som 6 riadkov (limit 10)$(ctx)"; return 1; }
  want_out '- súbory session (10): app/F01.php, app/F02.php' && want_out 'app/F08.php · … ďalšie: 2' &&
    want_not 'app/F09.php' || return 1
  printf '%s\n' "$OUT" | LC_ALL=C grep -q '^- posledná Stop kontrola: FAIL, [0-9][0-9]\.[0-9][0-9]\. [0-9][0-9]:[0-9][0-9]$' ||
    { fail "riadok Stop kontroly s časom dd.mm. HH:MM$(ctx)"; return 1; }
  want_not 'PARTIAL' "Stop inej session" || return 1
  want_out '- posledný PASS /dev:check: full, ' && want_out '- zamknutý test (/dev:fix): tests/FooTest.php (do ' &&
    want_out '- posledný handoff: Košík a DPH, ' && want_out ' → docs/handoff.md' || return 1
  lock_at $(($(now) - 7 * 3600))
  printf '{"time": %s, "title": "Starý handoff", "path": "docs/handoff.md"}\n' $(($(now) - 25 * 3600)) > "$PDATA/last-handoff.json"
  pre_compact auto other-sess
  want_rc 0 "iná session" && want_out '- posledná Stop kontrola: PARTIAL, ' "iná session" &&
    want_out '- posledný PASS /dev:check: full, ' "iná session" || return 1
  want_not 'súbory session' "iná session" && want_not 'FAIL' "iná session" &&
    want_not 'zamknutý test' "zámok po ttlHours" && want_not 'handoff' "handoff starší ako 24 h"
}

# ---------------------------------------------------------------- beh

N=0
NF=0
JOBS=${DK_SELFTEST_JOBS:-4}
case "$JOBS" in ''|*[!0-9]*|0) JOBS=1 ;; esac
RES="$ROOT/results"
mkdir -p "$RES"
# container "" ⇒ príkazy na hoste, docker sa nevolá (SPEC §3)
host_only() {
  [ -n "$DOCKER_OK" ] || [ -z "$CASE" ] || [ ! -s "$CASE/docker.calls" ] ||
    fail "docker volaný pri container \"\": $(flat "$(docker_calls)")"
}
# Prípad beží v subshelle (najviac JOBS naraz), výsledok ide do $RES/<poradie>; výpis v poradí po skončení všetkých.
t() { # t <názov> <funkcia>
  case "$1" in *"$FILTER"*) ;; *) return 0 ;; esac
  N=$((N + 1))
  (
    REASON="" BADUTF="" DOCKER_OK="" CASE=""
    if "$2" && [ -z "$BADUTF" ] && host_only; then
      echo "ok - $1"
    else
      [ -z "$BADUTF" ] || REASON="výstup nie je platné UTF-8 ($BADUTF)${REASON:+; $REASON}"
      echo "not ok - $1: ${REASON:-bez dôvodu}"
    fi
  ) > "$RES/$(printf '%04d' "$N")" 2>&1 &
  while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$JOBS" ]; do sleep 0.05; done
}

[ -d "$S" ] || echo "# varovanie: chýba $S — všetky prípady zlyhajú"

t "on-edit: chyba lintera na pridanom riadku → exit 2, [dev-kit] a rel:riadok" t_edit_lint_added
t "on-edit: php -l „on line N“ na pridanom riadku → exit 2" t_edit_parse_error
t "on-edit: chyba lintera len na pôvodnom riadku → exit 0, ticho" t_edit_lint_preexisting
t "on-edit: dump( na pridanom riadku → exit 2 (guard:debug-php)" t_edit_guard_added
t "on-edit: 17 nálezov → 15 riadkov + „… ďalšie nálezy: 2“" t_edit_cap15
t "on-edit: dump( len v commitnutých riadkoch → exit 0, ticho" t_edit_guard_preexisting
t "on-edit: disabledRules guard:debug-php → exit 0" t_edit_guard_disabled
t "on-edit: projekt bez devkit.json → exit 0, ticho" t_edit_no_config
t "on-edit: súbor mimo projektu → exit 0, ticho" t_edit_outside_project
t "on-edit: zapíše rel cestu do sessions/<id>.files bez duplicít" t_edit_session_files
t "pre-edit: aktívny zámok testu → deny" t_pre_edit_lock_deny
t "pre-edit: iný súbor pri aktívnom zámku → ticho" t_pre_edit_lock_other_file
t "pre-edit: expirovaný zámok → ticho" t_pre_edit_lock_expired
t "pre-edit: commitnutá migrácia → ask" t_pre_edit_migration_committed
t "pre-edit: nová necommitnutá migrácia → ticho" t_pre_edit_migration_new
t "pre-edit: agent kitu zapisuje do projektu → deny aj bez configu" t_pre_edit_agent_project_deny
t "pre-edit: agent kitu zapisuje do svojej pamäte → ticho" t_pre_edit_agent_memory_allow
t "pre-edit: agent kitu, cesta s .. z pamäte von → deny" t_pre_edit_agent_dotdot_deny
t "pre-edit: iný agent mimo kitu → ticho" t_pre_edit_other_agent_allow
t "pre-bash: príkaz bez commitu (ls) → ticho" t_bash_not_commit
t "pre-bash: commit .php bez pass.json → deny (aj --amend --no-edit)" t_bash_commit_no_pass
t "pre-bash: commit po check --quick PASS (aj zmazaný súbor) → allow" t_bash_commit_after_pass
t "pre-bash: commit po check PARTIAL → deny" t_bash_commit_after_partial
t "pre-bash: PARTIAL, nebežiaci kontajner (0 ok) → deny s únikom commitGate, ten commit pustí" t_bash_commit_partial_explained
t "pre-bash: PARTIAL s 1 ok krokom → únik step:<id>, ten dá PASS; partial.json > 24 h mlčí" t_bash_commit_partial_one_ok
t "pre-bash: PARTIAL so 7 blokovanými krokmi → 5 riadkov, únik so všetkými 7 id" t_bash_commit_partial_all_ids
t "pre-bash: git commit -am bez PASS → deny, po PASS → allow" t_bash_commit_all_flag
t "pre-bash: zmena a git add po PASS → deny" t_bash_commit_restaged
t "pre-bash: commit len .md → allow" t_bash_commit_docs_only
t "pre-bash: fullWhen súbor s quick pass.json → deny s --full" t_bash_commit_fullwhen
t "pre-bash: staged forbidFiles (.test-credentials) → deny" t_bash_commit_forbidden_file
t "pre-bash: tajomstvo na pridanom riadku → deny s file:line, bez hodnoty" t_bash_commit_secret
t "pre-bash: tajomstvo v secrets.allow (tests/fixtures/) → allow" t_bash_commit_secret_allow
t "pre-bash: 'cd sub && git commit' aj 'git -C sub commit' sú commit" t_bash_detect_cd_commit
t "pre-bash: 'git commit-tree' nie je commit" t_bash_detect_commit_tree
t "pre-bash: globálne prepínače gitu, env priradenia a obaly pred commit → deny (D17)" t_bash_detect_global_opts
t "pre-bash: 'git stage X && git commit' sa započíta ako add" t_bash_stage_alias
t "pre-bash: cd \"\$CLAUDE_PROJECT_DIR\" sa rozvinie" t_bash_cd_var_project
t "pre-bash: reťaz relatívnych cd sa skladá kumulatívne" t_bash_cd_chain_relative
t "pre-bash: nerozriešiteľné cd → cwd session (fail closed)" t_bash_cd_unresolvable_fallback
t "pre-bash: cd za commitom repo nemení" t_bash_cd_after_commit
t "pre-bash: cd na cestu s medzerou v úvodzovkách" t_bash_cd_quoted_space
t "pre-bash: git -C / cd --, -P na iné repo bez devkit.json → allow" t_bash_cd_other_repo_allow
t "pre-bash: nerozriešený cieľ cd / -C → cwd session a riadok „sa nedal určiť“ s úryvkom" t_bash_cd_unresolved_note
t "pre-bash: cd \"\$(pwd)\", \$PWD, \`pwd\` = aktuálna báza; cd v \$(…) s commitom" t_bash_cd_pwd_base
t "pre-bash: viacriadkový príkaz s dvoma commitmi → oba segmenty" t_bash_multiline_commits
t "pre-bash: git add -f / --force ignorovaného zakázaného súboru → deny s maskou" t_bash_add_force_forbidden
t "pre-bash: git add -A -f → deny" t_bash_add_force_all
t "pre-bash: git add -p v tom istom príkaze → deny aj po PASS" t_bash_add_patch_same_cmd
t "pre-bash: názov súboru v úvodzovkách gitu → deny" t_bash_quoted_name
t "pre-bash: zástupný text ukotvený na celú hodnotu (SEC-15)" t_bash_secret_placeholder_anchor
t "pre-bash: telo heredocu správy commitu sa nečíta ako príkazy" t_bash_heredoc_message
t "check.sh --quick: všetko PASS → exit 0, riadky krokov, log, pass.json s blobmi" t_check_quick_pass
t "check.sh: zlyhaný krok → exit 1, ≤ 20 riadkov, ✗ krok" t_check_fail
t "check.sh: chýbajúci requires → SKIP riadok" t_check_skip_missing
t "check.sh: všetky kroky SKIP → exit 4" t_check_all_skip
t "check.sh: krok sa nedá spustiť (exit 127) → PARTIAL, exit 4, bez pass.json" t_check_blocked_partial
t "check.sh: chyba prostredia v jednom kroku → PARTIAL" t_check_infra_partial
t "check.sh: knownFailures pokryje všetky zlyhania → PASS" t_check_known_failures
t "check.sh: changedLinesOnly ignoruje staré nálezy kroku" t_check_changed_lines_only
t "check.sh --auto: zmena vo fullWhen → full kroky" t_check_auto_full
t "check.sh: bez devkit.json → exit 3" t_check_no_config
t "stop-check: zlyhaný unit → decision block s dôvodom" t_stop_block
t "stop-check: guard v pridanom riadku (zmena cez Bash) → block" t_stop_guard
t "stop-check: po oprave bez bloku, nezmenený hash → bez kontroly" t_stop_fixed_then_fast
t "stop-check: 3× rovnaké zlyhanie → systemMessage namiesto bloku" t_stop_cap3
t "stop-check: opakovaný Stop s rovnakým obsahom blokuje z uloženého dôvodu bez behu kroku" t_stop_replay_same_fail
t "stop-check: stop.json bez reason, zmena mimo session alebo devkit.json → kontrola beží znova" t_stop_replay_needs_same_state
t "stop-check: PARTIAL → pripomienka s krokom, nezmenený hash bez kontroly" t_stop_partial_once
t "stop-check: zlyhanie inej session nevynuluje počítadlo blokov" t_stop_sessions_separate
t "stop-check: pripomienka pair raz za session" t_stop_pair_once
t "stop-check: pair so zmeneným testom (unless) → ticho" t_stop_pair_unless
t "stop-check: pair po commite v tom istom ťahu (.head) → ticho, bez testu pripomienka" t_stop_pair_after_commit
t "stop-check: bez súborov session → exit 0, ticho" t_stop_no_session
t "kontajner nebeží: on-edit bez lintu, Stop bez bloku, karta NEBEŽÍ" t_container_down
t "session-card: bez devkit.json → jeden riadok, v ten istý deň ticho" t_card_hint_once
t "session-card: 1. a 2. riadok, pripomienka údržby (chýba / > 30 dní)" t_card_stack_maintenance
t "session-card: údržba kitu len s tools/upstream.sh vedľa skriptov, cesta z umiestnenia" t_card_maintenance_checkout_only
t "session-card --record-handoff → posledný handoff (len < 24 h)" t_card_handoff
t "test-lock.sh: lock/status/unlock, karta aj pre-edit" t_test_lock_roundtrip
t "stats.sh: súhrn decisions.jsonl" t_stats
t "lib.sh dk_glob_match: vzory z SPEC §3" t_glob
t "lib.sh dk_workdir: worktree pod .claude/worktrees/x" t_worktree_workdir
t "check.sh v kontajneri: docker exec -w podľa worktree, mimo mountu SKIP" t_worktree_exec
t "worktree: check --project <hlavný> z worktree kontroluje worktree (D16)" t_worktree_check_project_main
t "worktree: test-lock --project <hlavný> z worktree, --project iného repa ostáva" t_worktree_lock_project_main
t "worktree: --record-handoff --project <hlavný> z worktree → karta worktree" t_worktree_handoff_project_main
t "on-edit: phpcs 'No files were checked' (exit 16) → SKIP" t_edit_phpcs_no_files_checked
t "check.sh: phpcs 'No files were checked' → chyba prostredia, nie FAIL" t_check_phpcs_no_files_checked
t "on-edit: latte chyba hlásená na nezmenenom riadku ostane" t_edit_latte_error_unchanged_line
t "check.sh: changedLinesOnly zahodí nález iného súboru" t_check_changed_lines_other_file
t "check.sh: pád nástroja (Fatal error) sa neodfiltruje" t_check_crash_not_filtered
t "check.sh: knownFailures ignoruje varovania PHPUnit runnera" t_check_known_failures_runner_warning
t "check.sh: ANSI farby PHPUnit sa odstránia z výstupu aj logu" t_check_strip_ansi
t "lib.sh dk_filter_changed: zaznamenané výstupy php -l, phpstan, phpcs, latte" t_filter_real_outputs
t "lib.sh dk_filter_changed: yaml/twig lint (ERROR in, >>) ostane" t_filter_yaml_twig_kept
t "check.sh: changedLinesOnly \"stop\" filtruje len v --stop" t_check_changed_lines_stop_only
t "check.sh: súbor začínajúci '-' ide nástroju ako ./-…" t_check_dash_filename
t "check.sh: nesledovaný worktree (koncové /) nie je v pass.json" t_check_ignores_nested_worktree
t "šablóna php-nette: krok latte skontroluje každý súbor, nielen prvý" t_check_template_latte_all_files
t "on-edit: hlavička s id pravidiel, guard riadok s [guard:id]" t_edit_rule_ids_in_message
t "on-edit: 25 nálezov guardu → počet 25, „… ďalšie nálezy: 10“" t_edit_guard_count_over_20
t "on-edit: tajomstvo v pridanom riadku → exit 2 s maskou" t_edit_secret_added_line
t "on-edit: tajomstvo v súbore ignorovanom gitom → ticho" t_edit_secret_ignored_file
t "pre-edit: zámok testu pri ./, .., // a inej veľkosti písmen" t_pre_edit_lock_path_variants
t "pre-edit: commitnutá migrácia s inou veľkosťou písmen → ask (case-insensitive FS)" t_pre_edit_migration_case
t "lib.sh: dátový adresár s právami 700" t_data_dir_mode
t "stop-check: pair v novej session, skratka nezmeneného hashu v rámci session (D8)" t_stop_pairs_after_pass_shortcut
t "stop-check: pair nad nekódovým súborom session" t_stop_pairs_non_code_only
t "stop-check: zmazaná test metóda → pripomienka raz" t_stop_removed_test_method
t "session-card: systemMessage len s upozorneniami" t_card_warning_system_message
t "session-card: bez jq → statický JSON so systemMessage" t_card_no_jq_json
t "session-card: container bez docker binárky → chýba docker" t_card_no_docker_binary
t "session-card: python worktree bez .venv/ → upozornenie (D20)" t_card_worktree_venv
t "session-card: stará verzia Claude Code, kontrola raz za deň" t_card_cc_version
t "devkit.json zmenený (R3): karta raz, on-edit a pre-bash systemMessage raz za session, hooky bežia ďalej" t_cfg_trust
t "šablóny: ukotvené deny, bez \\s/\\w v [...], vzorky tajomstiev, rules (paths, Pasce, ≤ 60), značky db:" t_templates_lint
t "stop-check: check.sh exit 3 / 2 → pripomienka „nedala spustiť“, skip namiesto pass, bez bloku" t_stop_check_not_run
t "lib.sh dk_blobs: nečitateľný súbor = - a errors.log, symlink .php vypadne" t_blobs_unreadable_symlink
t "pre-bash: symlink .php v stage aj cez git add → commit gate ho nežiada" t_bash_commit_symlink_code
t "lib.sh dk_err: errors.log nad 1 MB → posledných 500 riadkov" t_err_log_rotation
t "kontajner: on-edit číta container.state 30 s, check.sh vždy docker inspect" t_container_state_cache
t "check.sh: runFiles bez ext dostane do {files} len kódové súbory" t_check_runfiles_code_only
t "check.sh --auto: fullWhen bez krokov len pre full → riadok „– full: rovnaké kroky ako quick“" t_check_auto_full_same_steps
t "cesty so spätnou lomkou: on-edit, check.sh changedLinesOnly, dk_strip_paths (awk ENVIRON)" t_awk_backslash_paths
t "check.sh: knownFailures z pytest „FAILED <id>“ (aj [param]) → známe, neznáme id → FAIL" t_check_known_failures_pytest
t "on-edit: predvolené vzory AKIA… a BEGIN … PRIVATE KEY → exit 2 s maskou ****" t_edit_secret_defaults
t "pre-bash: predvolené vzory AKIA… a BEGIN … PRIVATE KEY → deny s maskou ****" t_bash_commit_secret_defaults
t "stop-check: zmazaný celý test súbor (rm aj git rm) → pripomienka raz, nový súbor ticho" t_stop_removed_test_file
t "pre-bash: commitGate enabled false / disabledRules → kód bez PASS prejde, tajomstvo deny" t_bash_gate_off_secrets_on
t "tools/upstream.sh: klon ECC predvolene <kit>/../ECC, ECC_DIR ho prebije" t_upstream_ecc_default
t "šablóny php: guardy die, debug-php a dql-concat (->exit(, \$this->dump( nie; die(, exit;, ->where('…' . \$x) áno)" t_templates_php_guards
t "stop-check: pairs when/unless ako zoznam globov (php-nette model-test)" t_stop_pair_glob_list
t "NotebookEdit: matcher v hooks.json, notebook_path v on-edit (guard python .ipynb) aj pre-edit" t_notebook_edit
t "project-init: tabuľka Zástupné symboly pokrýva všetky {{…}} šablón, bez mŕtvych symbolov" t_templates_symbols
t "runtime host pri nastavenom container: krok, Stop aj lint na hoste, docker vždy zlyhá; karta bez stavu kontajnera" t_runtime_host
t "runtime: container bez kontajnera = host, neznáma hodnota → ! krok / lint do errors.log, lint ako reťazec či objekt" t_runtime_values
t "šablóny php: guardy console-log a inner-html (console.error, innerHTML ===, .css nie)" t_templates_frontend_guards
t "šablóny php: kroky eslint a stylelint na hoste, len ich prípony, nález → FAIL, bez node_modules → chýba" t_templates_frontend_steps
t "stop-check: prípona len z kroku quick/full (.css) Stop nespustí, commit gate ju ráta; .php → kontrola beží" t_stop_ext_quick_full_only
t "check.sh: knownFailures z Nette Tester „-- FAILED:“ (id = cesta + method=/dataprovider=, bez titulku), nie chyba prostredia" t_check_known_failures_tester
t "šablóna php-nette: krok tester, .phpt v lint a commitGate.ext, guardy debug-php a test-skip (Environment::skip) pre .phpt" t_templates_tester
t "Phinx: _init, detekcia phinx.{php,json,yaml,yml}, db-dibi.md; migrations.paths s * (module/*/migrations) → ask len pri commitnutej" t_templates_phinx
t "check.sh: knownFailures zo zraniteľností composer audit a pip-audit (vzor na CVE alias pokryje záznam, ukotvenie platí)" t_check_known_failures_audit
t "check.sh: audit — abandoned ostáva FAIL, Ignore reason a blok bez id, tabuľka, sieť = PARTIAL, pytest bez hlavičky bez id" t_check_audit_edges
t "šablóny: krok audit len vo full so súhlasom v pláne initu; review a production-audit odkazujú na krok" t_templates_audit
t "check.sh --config / DEVKIT_CONFIG: kópia s container \"\" beží na hoste, bez pass.json a partial.json, Stop berie config projektu" t_check_config
t "check.sh --config: projekt bez devkit.json, neplatný JSON, chýbajúca hodnota, ten istý súbor a prázdne DEVKIT_CONFIG → markery" t_check_config_edges
t "eval suite: prompt.md a gradery, fixture shop zo scaffold.sh (PARTIAL, commit gate, zámok testu, diff), make eval mimo check" t_evals_suite
t "pre-compact: hooks.json PreCompact; bez devkit.json, bez jq, s neplatným configom a bez stavu session exit 0 bez výstupu" t_pre_compact_silent
t "pre-compact: plain text (nie JSON) — súbory session (8 + ďalšie), Stop len tejto session, pass.json, zámok a handoff < 24 h" t_pre_compact_facts

wait
for f in "$RES"/*; do
  [ -f "$f" ] || continue
  if LC_ALL=C grep -q '^ok - ' "$f"; then
    cat "$f"
  else
    NF=$((NF + 1))
    LC_ALL=C grep -q '^not ok - ' "$f" && cat "$f" || echo "not ok - prípad ${f##*/}: bez výsledku ($(flat "$(cat "$f")"))"
  fi
done

if [ -z "$FILTER" ]; then
  N=$((N + 1))
  if [ -e "$HOME/.claude" ]; then
    NF=$((NF + 1))
    echo "not ok - izolácia: skripty zapísali do \$HOME/.claude napriek DEVKIT_DATA ($(ls "$HOME/.claude" | head -3 | tr '\n' ' '))"
  else
    echo "ok - izolácia: nič mimo DEVKIT_DATA (\$HOME/.claude neexistuje)"
  fi
fi

echo "# čas: ${SECONDS} s"
[ "$SECONDS" -lt 20 ] || echo "# varovanie: selftest trval ${SECONDS} s (limit 20 s)"
if [ "$N" = 0 ]; then
  echo "FAIL 0/0 (filter '$FILTER' nevybral žiadny prípad)"
  exit 1
fi
if [ "$NF" = 0 ]; then
  echo "PASS $N/$N"
  exit 0
fi
echo "FAIL $NF/$N"
exit 1
