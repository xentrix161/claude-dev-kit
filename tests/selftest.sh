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
unset CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA CLAUDE_ENV_FILE DEVKIT_DATA \
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
t "stop-check: PARTIAL → pripomienka s krokom, nezmenený hash bez kontroly" t_stop_partial_once
t "stop-check: zlyhanie inej session nevynuluje počítadlo blokov" t_stop_sessions_separate
t "stop-check: pripomienka pair raz za session" t_stop_pair_once
t "stop-check: pair so zmeneným testom (unless) → ticho" t_stop_pair_unless
t "stop-check: bez súborov session → exit 0, ticho" t_stop_no_session
t "kontajner nebeží: on-edit bez lintu, Stop bez bloku, karta NEBEŽÍ" t_container_down
t "session-card: bez devkit.json → jeden riadok, v ten istý deň ticho" t_card_hint_once
t "session-card: 1. a 2. riadok, pripomienka údržby (chýba / > 30 dní)" t_card_stack_maintenance
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
t "šablóny: ukotvené deny, bez \\s/\\w v [...], vzorky tajomstiev, rules (paths, Pasce, ≤ 60), značky db:" t_templates_lint

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
