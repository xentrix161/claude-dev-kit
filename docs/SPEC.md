# dev-kit — build specification (v0.1.1)

Source of truth for every builder agent; this file wins on contracts.

## 0. Ground rules for all builders

- Kit repo: `~/Projects/_tools/claude-dev-kit` (KIT). Plugin root: `KIT/plugins/dev` (ROOT). Write ONLY
  inside KIT. Other projects and their containers are READ-ONLY reference — never write there, never
  run git commands that change those repos, never run docker commands that stop, restart or modify
  existing containers. Other Claude sessions work there.
- ECC source (read-only): `~/Projects/_tools/ECC` pinned at commit `b92f181` (2026-10-11), MIT.
- Claude Code docs (current for v2.1.308): `hooks.md`, `hooks-guide.md`, `plugins-reference.md`,
  `skills.md`, `sub-agents.md`, `settings.md`, `permissions.md`, `worktrees.md`, `plugin-evals.md`,
  `statusline.md`, `memory.md`, `plugins-loading.md`.
  When unsure about a frontmatter key, hook field or JSON output shape: check these docs, do not guess.
- Language: everything a human or Claude reads at runtime (hook messages, skill bodies, agent prompts,
  README, templates) is **Slovak with full diacritics**. Code identifiers, commands and paths stay as is.
- Style of user-facing output: the user's rule „Štýl odpovedí — stručne, ale úplne“ (`~/.claude/CLAUDE.md`):
  conclusion first, then evidence; short paragraphs of full sentences plus bullets as the content needs,
  no caps on list length; complete lists (findings, TODO, files) with ID/state/description; no intro
  phrases, no closing recap; `file:line` refs. Fixed formats stay: hook messages (≤ 20 lines, prefix
  `[dev-kit]`, each finding one line), check.sh lines, the review finding line, the one-line commit message.
- Shell: scripts must run on **macOS /bin/bash 3.2** and on Linux bash 5. Forbidden: `declare -A`,
  `mapfile`/`readarray`, `${x,,}`/`${x^^}`, `|&`, `&>>`, `coproc`, `grep -P`, `sed -i` (use temp file +
  mv), `date -d`, `stat -c/-f`, `readlink -f`, `realpath`, `timeout` (not on macOS). Hashing: use
  `git hash-object --stdin` (portable), not sha1sum/shasum/md5. Use `set -u` carefully (bash 3.2 empty
  arrays + `set -u` = error → avoid arrays or guard them). Always `#!/usr/bin/env bash`.
- Dependencies at runtime: bash, git, jq (required for hooks; if missing → hooks exit 0 silently except
  session-card which says so in static JSON, §4.7), docker (only when `container` is set).
- Hook discipline: consume stdin fully; stdout silent unless emitting the documented JSON; exit 0 when
  nothing to report; never crash the session — any internal error → log to `$DK_DATA/errors.log` and
  exit 0. Respect hook timeouts (see hooks.json).
- No comments that narrate history. Comments short, only for non-obvious things.

## 1. Repository layout

```
KIT/
  .claude-plugin/marketplace.json     # {"name":"dev-kit","owner":{"name":"dev-kit"},"plugins":[{"name":"dev","source":"./plugins/dev","description":"…"}]}
  plugins/dev/
    .claude-plugin/plugin.json        # {"name":"dev","version":"0.1.1","description":"…","author":{"name":"dev-kit"}}
    hooks/hooks.json
    scripts/   lib.sh check.sh on-edit.sh pre-edit.sh pre-bash.sh stop-check.sh session-card.sh test-lock.sh stats.sh
    skills/    <command skills> <reference skills>   (see §5)
    agents/    ecc-silent-failure-hunter.md ecc-pr-test-analyzer.md ecc-a11y-architect.md ecc-performance-optimizer.md
    templates/ common/ php-nette/ php-symfony/ python/ skills/   (see §7)
    LICENSES/ECC-MIT.txt
    PROVENANCE.md
  tests/selftest.sh  tests/fixtures/…   # deterministic, no docker, no network
  tools/upstream.sh                     # P3: diff of pinned ECC pieces vs upstream
  tools/details.sh                      # inventory + always-on budget (§5)
  Makefile  README.md  CHANGELOG.md  docs/SPEC.md
```
Version lives only in `plugin.json` (never in the marketplace entry). No LICENSE for the kit's own code
(the `LICENSE_MISSING` warning is accepted); the ECC MIT text stays in `plugins/dev/LICENSES/`.

## 2. Data directory

`DK_DATA="${DEVKIT_DATA:-$HOME/.claude/dev-kit}"` — one fixed location for hooks AND for scripts called
from skills via the Bash tool (the Bash tool does not get CLAUDE_PLUGIN_DATA). Tests set `DEVKIT_DATA`.
`$DK_DATA` is created with mode 700 (`mkdir -m 700`, no global `umask` change).
```
$DK_DATA/decisions.jsonl                          # V8 log, all projects
$DK_DATA/errors.log
$DK_DATA/maintenance.json                         # {"lastUpstreamCheck": <epoch>} written by tools/upstream.sh
$DK_DATA/projects/<phash>/pass.json               # commit-gate PASS marker
$DK_DATA/projects/<phash>/test-lock.json          # V3
$DK_DATA/projects/<phash>/sessions/<session_id>.files   # files edited in that session (repo-relative, one per line)
$DK_DATA/projects/<phash>/sessions/<session_id>.stop.json   # last stop-check state of that session
$DK_DATA/projects/<phash>/pairs-<session_id>.done # Stop reminders already given (pairs, testRemoved)
$DK_DATA/projects/<phash>/logs/check-<mode>-<epoch>.log  # full check output (keep last 20)
$DK_DATA/projects/<phash>/card-hint.<YYYYMMDD>    # "no devkit.json" hint shown today
$DK_DATA/projects/<phash>/last-handoff.json       # {"time":…, "title":"…", "path":"…"}
$DK_DATA/cc-version.<YYYYMMDD>                    # `claude --version` cached for the day (§4.7)
```
`<phash>` = first 12 chars of `printf %s "<project dir>" | git hash-object --stdin`.

## 3. Project config `.claude/devkit.json` (schema v1)

Located at `<project>/.claude/devkit.json`. Missing file ⇒ every hook is a no-op (except the one-line
hint in session-card). Unknown keys and keys starting with `_` (template notes such as `_init`) are
ignored. Example (typical Nette project):
```json
{
  "version": 1,
  "stack": "php-nette",
  "container": "app-php",
  "appRoot": "/application",
  "lint": {
    ".php":   ["php -l {file}", "php vendor/bin/phpcs -q -n --report=emacs --standard=PSR12 {file}"],
    ".latte": ["php vendor/bin/latte-lint {file}"]
  },
  "lintChangedLinesOnly": true,
  "check": {
    "steps": [
      {"id": "phpstan", "requires": "vendor/bin/phpstan",
       "run": "php vendor/bin/phpstan analyse -c app/config/phpstan.neon --no-progress --error-format=raw --memory-limit=1G",
       "runFiles": "php vendor/bin/phpstan analyse -c app/config/phpstan.neon --no-progress --error-format=raw --memory-limit=1G {files}",
       "ext": [".php"], "modes": ["stop", "quick", "full"], "changedLinesOnly": "stop"},
      {"id": "unit", "requires": "vendor/bin/phpunit", "run": "php vendor/bin/phpunit --testsuite unit", "modes": ["stop", "quick", "full"]},
      {"id": "phpcs", "requires": "vendor/bin/phpcs", "runFiles": "php vendor/bin/phpcs -q -n --report=emacs --standard=PSR12 {files}",
       "ext": [".php"], "modes": ["quick", "full"], "changedLinesOnly": true},
      {"id": "latte", "requires": "vendor/bin/latte-lint", "runFiles": "r=0; for f in {files}; do php vendor/bin/latte-lint \"$f\" || r=1; done; exit $r", "ext": [".latte"], "modes": ["quick", "full"]},
      {"id": "integration", "requires": "vendor/bin/phpunit", "run": "php vendor/bin/phpunit --testsuite integration", "modes": ["full"]}
    ],
    "fullWhen": ["app/models/**", "libs/**", "db/**", "app/presenters/**"],
    "knownFailures": [{"step": "integration", "pattern": "Tests\\\\Integration\\\\Example::testFlaky"}]
  },
  "guards": [
    {"id": "debug-php", "ext": [".php", ".latte"], "pattern": "\\b(dump|dd|bdump|var_dump|print_r)\\(", "message": "debug výpis v kóde"},
    {"id": "die", "ext": [".php"], "pattern": "\\b(die|exit)\\(", "message": "die()/exit() — použi throw alebo $this->terminate()"},
    {"id": "latte-raw", "ext": [".latte"], "pattern": "\\{!\\$", "message": "{!$var} vypína escapovanie — len s jasným dôvodom"},
    {"id": "error-suppress", "ext": [".php"], "pattern": "(^|[^[:alnum:]_])@\\$?[a-zA-Z_]+\\(", "message": "potlačenie chyby operátorom @"},
    {"id": "sql-concat", "ext": [".php"], "pattern": "(SELECT|UPDATE|DELETE|INSERT)[^;]*['\"]\\s*\\.\\s*\\$", "message": "SQL skladané reťazcom — použi parametre"}
  ],
  "pairs": [
    {"id": "validator-test", "when": "libs/Validator/**", "unless": "tests/**",
     "say": "Zmena validátora bez zmeny testu: navrhni používateľovi regresný test (pravidlo 11), nepridávaj ho sám."}
  ],
  "secrets": {
    "patterns": ["(?i)(password|passwd|heslo|secret|api[_-]?key|token)[\"']?[[:space:]]*(=>|[:=])[[:space:]]*[\"'][^\"'[:space:]]{6,}"],
    "allow": ["tests/fixtures/"],
    "forbidFiles": ["app/config/config.local.neon", ".test-credentials", "**/.env", "**/.env.local"]
  },
  "migrations": {"paths": ["db/migrations/**"]},
  "testLock": {"ttlHours": 6},
  "stopCheck": true,
  "commitGate": {"enabled": true, "ext": [".php", ".latte", ".neon", ".twig", ".yml", ".yaml", ".xml", ".sql", ".py"]},
  "handoffDoc": "docs/handoff.md",
  "disabledRules": []
}
```
Semantics:
- `container` empty/absent ⇒ commands run on the host: `cd <project> && sh -c "<cmd>"`.
- Path mapping (V6 worktrees): MAIN = main repo root (`git rev-parse --path-format=absolute
  --git-common-dir` → strip trailing `/.git`). The container mounts MAIN at `appRoot`. Container workdir
  for a project dir P = `appRoot + "/" + relpath(P, MAIN)` (just `appRoot` when P == MAIN). Commands
  execute as `docker exec -i -w <workdir> <container> sh -c "<cmd>"`; `{file}`/`{files}` are paths
  relative to P (shell-quoted). If P is not under MAIN ⇒ step SKIP with message
  `worktree mimo mountu kontajnera`.
- `requires`: path relative to P checked on the HOST; missing ⇒ step SKIP `chýba <path>`.
- Container not running (`docker inspect -f '{{.State.Running}}'` ≠ true) ⇒ container steps SKIP
  `kontajner <c> nebeží`.
- `changedLinesOnly` (per step): `true` = keep only output lines on added lines (same filter as on-edit,
  §4.2 step 3) in every mode; `"stop"` = filter only in stop mode (`/dev:check` still shows whole-file
  findings); `false`/absent = no filter. `lintChangedLinesOnly` does the same for the `lint` map.
- Regexes (`pattern`, `secrets.patterns`, `knownFailures.pattern`) are **POSIX ERE as understood by
  `grep -E`**; a leading `(?i)` means case-insensitive (strip it and use `grep -i`). `\b`, `\w`, `\s` only
  OUTSIDE `[...]`; inside brackets use `[:space:]` / `[:alnum:]_` (BSD grep reads `[^\s]` as "not
  backslash, not s"). Every pattern is passed to grep with `-e` (patterns may start with `-----BEGIN`).
  `secrets.patterns` EXTEND the lib defaults (union); one finding per `file:line`. Builders keep shipped
  default patterns compatible with BSD and GNU grep.
- Globs (`fullWhen`, `when`, `unless`, `allow` entries ending with `/` are prefixes, `forbidFiles`,
  `migrations.paths`): `**/` = zero or more directories (so `**/*.php` matches `a.php` and `x/y/a.php`),
  trailing `/**` = everything below, other `**` = any chars incl `/`, `*` = any chars except `/`, `?` = one
  char; matched against repo-relative paths (relative to P). Implement once in lib.sh (`dk_glob_match`).
- Rule ids usable in `disabledRules`: guard ids (`guard:<id>`, e.g. `guard:sql-concat`, the templates'
  `guard:test-skip`), `lint:<ext>` (e.g. `lint:.php`), `step:<id>`, `pair:<id>`, `secrets`, `migrations`,
  `testLock`, `stopCheck`, `commitGate`, `testRemoved`. Hook messages print these ids (§4.2, §4.6).
- `knownFailures`: when a step fails, extract failing identifiers from its output — only PHPUnit lines
  `^[0-9]+\) <Class>::<method>` and pytest `^FAILED <id>`; other numbered lines are not identifiers. If ≥1
  identifier was found and every one matches some pattern for that step ⇒ the step does not fail; its
  line gets the note `známe zlyhania: N` and the summary counts it as `známe`, not `ok` (§4.5).

## 4. Hooks (`ROOT/hooks/hooks.json`)

```json
{
  "hooks": {
    "SessionStart": [{"matcher": "startup|resume|clear|compact", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/session-card.sh\"", "timeout": 10}]}],
    "PreToolUse": [
      {"matcher": "Edit|Write|MultiEdit", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/pre-edit.sh\"", "timeout": 10}]},
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/pre-bash.sh\"", "timeout": 30}]}
    ],
    "PostToolUse": [{"matcher": "Edit|Write|MultiEdit", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/on-edit.sh\"", "timeout": 60}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/stop-check.sh\"", "timeout": 300}]}]
  }
}
```
Verify tool names and matcher syntax against `hooks.md` (current tool names for file edits). Hook input
fields used: `session_id`, `cwd`, `hook_event_name`, `tool_name`, `tool_input.file_path`,
`tool_input.command`, `stop_hook_active`, `source`. Project dir = `$CLAUDE_PROJECT_DIR`, fallback
`.cwd` from input, fallback `pwd`. A cwd inside a linked worktree of the same repo wins over
`--project`/`CLAUDE_PROJECT_DIR` (scripts called from skills and hooks); `--project` of another repo is
honoured. Skills keep passing `--project "${CLAUDE_PROJECT_DIR}"` and need no worktree workarounds.

### 4.1 `lib.sh` (sourced by all scripts)
Functions (names fixed, other scripts depend on them):
`dk_init` (reads stdin into `DK_INPUT` when stdin is not a tty; sets `DK_PROJECT`, `DK_DATA`, `DK_PDATA`
(per-project data dir, created), `DK_CFG` (path or empty), `DK_SESSION`), `dk_in <jq-filter>` (query
DK_INPUT), `dk_cfg <jq-filter> [default]`, `dk_rule_on <rule-id>` (false when listed in disabledRules),
`dk_main_root`, `dk_rel <abs-path>` (relative to DK_PROJECT; empty if outside), `dk_workdir`
(container workdir, empty+message if outside mount), `dk_exec <cmd>` (runs in container or host, returns
exit code, merges stderr into stdout), `dk_container_ok` (0 when container unset or running),
`dk_glob_match <path> <glob>`, `dk_added_lines <rel>` (newline list of added line numbers vs HEAD from
`git diff -U0 HEAD --`; untracked file ⇒ all lines; file new in index ⇒ all lines), `dk_hash_files
<rel>…` (combined content hash via git hash-object), `dk_log <hook> <rule> <decision> [file] [ms]`
(append one JSON line: ts, project, session, hook, rule, decision ∈ block|deny|ask|warn|pass|skip, file,
ms), `dk_err <msg>` (append to errors.log), `dk_now` (epoch seconds), `dk_ms` (best-effort ms: `perl
-MTime::HiRes` if available else seconds*1000), `dk_mask <match>` (always `****`, no character of the value;
returns 1 for a placeholder value; shared by on-edit and pre-bash), `dk_secret_scan <rel> <added-spec> <patterns>` (one `line<US>masked value`
per added line that matches; used by on-edit), `dk_data_dir` (creates `$DK_DATA` with mode 700, §2). Shared values: `DK_RE_GITPFX`, `DK_RE_COMMIT`, `DK_RE_ADD` (§4.4), `DK_RE_INFRA`
(infrastructure errors, §4.5), `DK_MIN_CC` (minimum Claude Code version, §4.7).

### 4.2 `on-edit.sh` — PostToolUse (edit/write)
1. No config / no jq / file outside project ⇒ exit 0.
2. Append rel path to `sessions/<session_id>.files` (dedupe).
3. Lint (`lint` map by extension, rule `lint:<ext>`): only when `dk_container_ok`. Run each command
   with `{file}`. Treat exit≠0 as failure; exit 126/127, `command not found` or docker errors ⇒ SKIP,
   never block. When `lintChangedLinesOnly` is true, keep only output lines whose line number is in
   `dk_added_lines` (the same filter serves `changedLinesOnly` in check.sh). Understood formats:
   `<path>:<line>:` with absolute container paths (appRoot/workdir prefix stripped → project-relative),
   `on line N`, latte-lint `[ERROR] file:line:col`, Symfony lint `ERROR in <file>` + `>> … at line N`
   and twig `(line N)`. Always kept: parse/syntax/compile error lines (php -l, latte `[ERROR]`, yaml/twig
   lint, Python `SyntaxError`/`IndentationError`) and tool crash lines (`Fatal error`, `Uncaught`,
   `Segmentation fault`, `Allowed memory size`).
   Numbered lines whose path is not a target are dropped; lines without any number are kept only when
   the output has no numbered line. Failure with empty filtered output ⇒ ignore (pre-existing legacy
   issue).
4. Guards (rule `guard:<id>`): for files matching `ext`, grep the ADDED lines only for `pattern`;
   finding = `<rel>:<line> — <message> [guard:<id>]`. Secrets (rule `secrets`): the added lines are also
   matched against the secrets patterns (lib defaults ∪ `secrets.patterns`); files matching
   `secrets.allow` or `forbidFiles` and files ignored by git are skipped; the value is masked
   (`dk_mask`).
5. Findings ⇒ print to **stderr**: header `[dev-kit] <rel>: N nálezov [<rule ids>] — oprav ich (1 nález → oprav ho); falošný
   poplach nahlás používateľovi s id pravidla (vypnutie: disabledRules …)` (declension 1 nález / 2 nálezy
   / 5 nálezov; rule ids e.g. `lint:.php, guard:die`), then up to 15 finding lines, then `… ďalšie
   nálezy: K` if truncated; exit 2. Otherwise exit 0. Log every finding rule (decision `block`) and a
   single `pass` per file when clean.
6. Budget: typical run < 0.5 s plus the lint commands themselves.

### 4.3 `pre-edit.sh` — PreToolUse (edit/write)
- Test lock (V3, rule `testLock`): if `test-lock.json` exists, not expired (`ttlHours`, default 6) and
  the target rel path (parent resolved physically, compared case-insensitively) is in its `files` ⇒ deny
  via JSON on stdout, exit 0:
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"[dev-kit] Test <rel> je zamknutý počas /dev:fix — oprav kód, nie test. Odomknúť môže používateľ: /dev:fix --unlock"}}`.
- Committed migration (V4, rule `migrations`): target matches `migrations.paths` AND exists in HEAD
  (`git cat-file -e HEAD:<rel>`; a path typed in another letter case that is the same file on a
  case-insensitive FS resolves to the indexed name first) ⇒ `permissionDecision":"ask"` with reason
  `[dev-kit] <rel> je už commitnutá migrácia — aplikované migrácie sa neupravujú, vytvor novú. Pokračovať?`.
- Log decisions. Otherwise exit 0 silently.

### 4.4 `pre-bash.sh` — PreToolUse (Bash)
Fast path: if `tool_input.command` does not contain a `git … commit` invocation ⇒ exit 0. Here-doc bodies
(e.g. a commit message via `<<'EOF'`) are blanked before analysis, line numbers kept. Detection uses
the EREs `DK_RE_GITPFX` (command start + `git` with its global options), `DK_RE_COMMIT` and `DK_RE_ADD`
(`add`/`stage`) from lib.sh; other scripts and this SPEC reference them, never copy them. They contain `/`, so
every `sed` using them takes the `\001` delimiter. Recognised before `commit`: leading env assignments
(`VAR=x git commit`, quoted values too), wrappers (`command`, `builtin`, `exec`, `env`, `time`, `nice`,
`nohup`, after `then`/`do`/`else`, `{`, `(`, `!`), `git` by absolute path or as `\git`, and the git
global options `-C <dir>` (also quoted with spaces), `-c k=v`, `-p`/`-P`, `--no-pager`, `--git-dir` and
`--work-tree` (with `=` or a space). Must match `cd x && git commit -m …`; must not match
`git commit-tree`, `git log --grep commit` or `echo "git commit"`. The only documented limitation:
`sh -c '…git commit…'` / `bash -c '…'` is not seen.
Repo: start from the session cwd, apply every `cd` before the commit cumulatively (`$HOME`, `$PWD`,
`$CLAUDE_PROJECT_DIR` and `~` expanded; an unresolvable `cd` ⇒ session cwd, fail closed), then
`git -C <dir>`. A multi-line command is evaluated over all its commit segments; their to-be-committed
sets are united.
Determine TO-BE-COMMITTED files: staged (`git diff --cached --name-only --diff-filter=ACMRD`) ∪ (when
`-a`/`--all`/combined short flags containing `a`: tracked modified files) ∪ (explicit pathspecs after
`--` or existing paths among trailing args: best effort) ∪ (`git add`/`git stage` earlier in the same
command: `-A`/`.`/`-u` widen like `-a`, paths count as pathspecs, `-f` includes ignored files). Denied
with a hint: `git add -p/-i/-e` in the same command (partial staging cannot be checked before it runs —
stage in a separate command, then commit), `git add -A -f`, and file names git prints only C-quoted.
Content of each file: staged blob (`git ls-files -s`) or, for -a/paths/add, `git hash-object <file>`;
deleted = `-`.
1. Secrets (V5, rule `secrets`): any to-be-committed file matching `forbidFiles` ⇒ deny. Added lines of
   the to-be-committed diff matched against the lib defaults ∪ `secrets.patterns` (defaults: generic
   password/token assignment, `-----BEGIN [A-Z ]*PRIVATE KEY-----`, `AKIA[0-9A-Z]{16}`,
   `[A-Z0-9_]*TEST_PASS(WORD)?=[^[:space:]]+`), one finding per `file:line`; skip files whose path matches an `allow`
   prefix/glob ⇒ deny listing `file:line` with the secret value masked (`****`, `dk_mask`). The deny
   text tells Claude to report the finding to the user, not to remove the value on its own, and names
   `secrets.allow` for a false positive. Never print the full secret.
2. Gate (rule `commitGate`, enabled default true when config exists): code files = to-be-committed
   files with extension in `commitGate.ext`, or, when it is absent, in the `lint` keys ∪
   `check.steps[].ext`. None ⇒ allow (docs-only commit). Else require `pass.json` whose `blobs[rel]`
   equals the to-be-committed blob for EVERY code file (deleted files must be recorded as `"-"`). Also if
   any code file matches `check.fullWhen` and `pass.json.mode` ≠ `full` ⇒ deny `zmena v <glob> vyžaduje
   /dev:check --full`. Deny reason lists up to 8 files and ends with `Spusti kontrolu: bash "<scripts>/check.sh"
   --auto|--full --project "<P>" (to isté robí /dev:check), pri PASS commit zopakuj.` — command skills
   have `disable-model-invocation`, so Claude must get a command it can run itself.
   What the gate proves: the content of every committed code file passed `check.sh` in the working tree
   (together with the other uncommitted changes present at that time) — not that the resulting commit tree
   passes. A commit hidden in `sh -c '…'` / `bash -c '…'` is not recognised (§4.4 header).
3. Deny ⇒ JSON `permissionDecision":"deny"` with reason, exit 0. Allow ⇒ exit 0 silently. Log;
   `commitGate` entries carry a content key (hash of the to-be-committed code blobs) so `/dev:stats` can
   group attempts on the same content (§4.9).
Never block `git commit --amend --no-edit` differently — same rules apply. Do not attempt to
intercept `--no-verify` (irrelevant to Claude hooks).

### 4.5 `check.sh` — the single source of truth (`/dev:check`, Stop, commit, CI)
Usage: `check.sh [--quick|--full|--auto|--stop] [--session <id>] [--project <dir>] [--files <rel>…]` —
flags in any order; `--files` consumes paths until the next `--` flag.
- Without hook stdin (called from Bash tool or CI). Reads config of `--project` (default `pwd`'s git
  toplevel; worktree rule in §4). No config ⇒ print `[dev-kit] chýba .claude/devkit.json — spusti
  /dev:project-init` exit 3.
- Mode: default `--quick`; `--auto` = full when any CHANGED file matches `fullWhen`, else quick.
- CHANGED files (quick/full/auto) = `git diff --name-only HEAD` ∪ untracked (`git ls-files --others
  --exclude-standard`) ∪ staged, deduped, existing files only (deleted tracked → recorded "-" in marker).
  Stop mode files = session files list (existing only).
- `--files` narrows the file set in every mode (quick/full/auto/stop); `pass.json` then records exactly
  those blobs, so `/dev:commit` can check only its group.
- Steps = config steps whose `modes` contain the mode (stop/quick/full; auto resolves first), and whose
  rule `step:<id>` is enabled. For each: `requires`/container checks (SKIP with reason); if `run` exists
  and mode ≠ stop ⇒ run whole; else if `runFiles` exists ⇒ files filtered by `ext` (none ⇒ SKIP
  `žiadne zmenené súbory`), substitute `{files}`; in stop mode prefer `runFiles` when files exist, else
  `run` (for steps without ext, e.g. unit tests, always `run`). `changedLinesOnly` (`true` | `"stop"`,
  §3) filters like on-edit.
- Two kinds of skipped step. **Not applicable** (line `– <id>: <reason>`, verdict unaffected): missing
  `requires`, no changed files for its `ext`, tool output `No files were checked` without any numbered
  line (`nástroj nič neskontroloval (No files were checked)`). **Blocked** — the step should run but could
  not (line `! <id>: <reason>`, verdict at most PARTIAL): container not running or worktree outside its
  mount, no `run`/`runFiles`, exit 125–127, output without any numbered line that matches `DK_RE_INFRA`
  (`chyba prostredia, nie kódu (<match>)`). Both count in `<n> skip`.
- Each step: elapsed time, exit code, output (ANSI sequences stripped) appended to the full log file.
  Result PASS/FAIL/skip; knownFailures may turn FAIL into a non-failing step with note. Blocked steps are
  never FAIL.
- Output (stdout, ≤ 20 lines): `[dev-kit] check <mode>: PASS|FAIL|PARTIAL|SKIP · <n> ok[ · <n> známe] · <n> fail · <n> skip · <s> s`
  (`známe` only when > 0), one line per step `✓ phpstan 2,1 s` / `✗ unit 0,4 s` / `– phpcs: chýba
  vendor/bin/phpcs` / `! unit: príkaz sa nedá spustiť (exit 127)`, then for failing steps up to 8 most
  relevant output lines each (total cap 20), then `log: <path>`.
- Verdict and exit: some FAIL ⇒ FAIL, 1; else some blocked step ⇒ PARTIAL, 4; else ≥1 `ok` or `známe`
  ⇒ PASS, 0; else (nothing ran) ⇒ SKIP, 4. 3 = config error. Exit 4 = incomplete verification — never
  report it as PASS.
- On exit 0 in quick/full: write `pass.json` = `{"time":…,"mode":"quick|full","head":"<sha>","blobs":{"<rel>":"<blob sha or ->"}}`
  for the checked file set (CHANGED files, or exactly the `--files` set); PARTIAL never writes it. Stop
  mode on PASS or PARTIAL writes `sessions/<session_id>.stop.json` (`{"hash": <dk_hash_files of session
  files>, "time":…, "fails":0, "result":"PASS|PARTIAL"}`). Markers are written via a per-process temp
  file and `mv`.
- Prune logs to the newest 20 per project.

### 4.6 `stop-check.sh` — Stop
1. No config / `stopCheck` false / rule `stopCheck` disabled ⇒ exit 0.
2. Reminders first, once per session (`pairs-<session_id>.done`), over the session file list incl.
   non-code files:
   - Pairs (N, rule `pair:<id>`): a session file matches `when` and none of the CHANGED files matches
     `unless` ⇒ add its `say`.
   - Removed tests (rule `testRemoved`): a test method/function removed in a session file (diff vs HEAD,
     e.g. `function test…` in PHP, `def test_…` in Python) ⇒ reminder naming file and test.
3. Session code files = session files with extension in any `lint` key or any step `ext`. Shortcuts that
   skip the check (reminders from step 2 are still emitted): no code files; hash (`dk_hash_files`) equal
   to `hash` in the session's `stop.json` with last result PASS or PARTIAL; the same failing hash already
   reached the 3× cap. State is per session, so another session's result never resets this one's counter.
4. Run `check.sh --stop --session <id> --project <P>` (+ guards over those files' added lines,
   because files may have been changed via Bash).
5. Output on stdout, exit 0:
   - Failure (check FAIL or guard finding) ⇒ `{"decision":"block","reason":"<≤20 lines>"}`; the reason
     says what failed and that it must be fixed before the turn ends, lists failing lines, guard findings
     (`[guard:<id>]`), reminders (`[pair:<id>]`, `[testRemoved]`) and `log: <path>`.
   - Reminders only ⇒ `{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"<reminders>"}}`
     (non-error feedback, no hook error shown to the user).
   - Check PARTIAL (exit 4, verdict PARTIAL) ⇒ never block; add reminder `[partial] tieto kroky sa nedali
     spustiť — netvrď, že sú overené:` followed by up to 5 `!` lines.
   - Track consecutive blocks for the same failure hash in the session's `stop.json` (`fails`); when it reaches 3 ⇒ do not
     block, instead `{"systemMessage":"[dev-kit] kontrola stále padá (3×) — blokovanie vypnuté pre tento stav, pozri <log>"}`
     plus `hookSpecificOutput.additionalContext` when there are reminders.
   - `stop_hook_active` true is allowed (we cap ourselves).
6. Container down / blocked step / nothing ran ⇒ never block on infrastructure; reminders still go out as in step 5.

### 4.7 `session-card.sh` — SessionStart (one JSON object on stdout, card ≤ 10 lines, < 1 s)
- stdout = one JSON object: `hookSpecificOutput.additionalContext` (`hookEventName` `SessionStart`) =
  the card (context for Claude); top-level `systemMessage` = user-facing warnings only (jq, docker,
  container down, maintenance, worktree, Claude Code version), omitted when there are none.
- No jq ⇒ print a static JSON object (built without jq) whose message says `[dev-kit] chýba jq → hooky
  kitu nebežia (brew install jq)`, exit 0.
- No config: if P has composer.json|pyproject.toml|package.json and `card-hint.<today>` absent ⇒ hint
  `[dev-kit] projekt nemá .claude/devkit.json — /dev:project-init ho nastaví` and create the marker.
- With config, the card:
  1. `[dev-kit] <stack> · kontajner <c> (beží|NEBEŽÍ — kontroly sa preskočia) · Stop kontrola on|off · commit gate on|off`;
     `container` set but no `docker` on PATH ⇒ `chýba docker → kontroly v kontajneri sa preskočia` in the
     container slot of this line (also a `systemMessage` warning)
  2. `kontroly: /dev:check (quick) · /dev:check --full · /dev:commit`
  3. `git: <branch> · <N> zmenených súborov` + up to 3 lines of `git status --short`
  4. last handoff if < 24 h: `posledný handoff: <title> (pred <h> h) → <path>`
  5. worktree without `vendor/` while MAIN has it ⇒ `worktree nemá vendor/ → doplň .worktreeinclude alebo composer install`;
     stack python: worktree without `.venv/` while MAIN has it ⇒ `worktree nemá .venv/ → vytvor nový venv (…)`
  6. maintenance: `$DK_DATA/maintenance.json` missing or older than 30 days ⇒
     `údržba kitu: posledná kontrola upstreamu pred <d> dňami → make -C ~/Projects/_tools/claude-dev-kit upstream`
  7. test lock active ⇒ `zamknutý test: <files> (do <time>)`
  8. Claude Code version older than `DK_MIN_CC` ⇒ warning line; the version check runs at most once a
     day (result cached in `$DK_DATA`)

### 4.8 `test-lock.sh` (called by /dev:fix)
`test-lock.sh lock <rel>… [--project P]` | `unlock [--project P]` | `status [--project P]`. Writes
`test-lock.json` `{"files":[…],"time":…,"ttlHours":…}`. Prints one Slovak line. Exit 0.

### 4.9 `stats.sh` (V8, called by /dev:stats)
`stats.sh [--days 30] [--project P|--all]` → scope = project from `pwd` (or `--project`) by default,
`--all` = every project; reads decisions.jsonl, prints ≤ 20 lines: `obdobie: N dní`, counts per hook+rule
(block/deny/ask/warn/pass), top 5 noisiest rules, stop-check block rate, commit-gate denials and the
`PASS na prvý raz` share (commit gate attempts grouped by the content key from §4.4), average ms per
hook. Exit 0.

## 5. Skills (`ROOT/skills/<name>/SKILL.md`)

Frontmatter: `name`, `description` (≤ 250 chars, key use first), optional `when_to_use`,
`argument-hint`, `disable-model-invocation`, `paths`, `allowed-tools`. Verify key names in `skills.md`.
Bodies in Slovak, < 300 lines, output stručne, ale úplne (§0). Scripts are referenced as
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh"` (substituted inline by Claude Code). Never rely on
CLAUDE_PLUGIN_DATA inside skills. Stack branches: detect from `.claude/devkit.json` `stack`, else
composer.json (nette/symfony) / pyproject.toml.

Command skills — all `disable-model-invocation: true` (0 always-on tokens):
| name | source material | essence |
|---|---|---|
| `check` | plan §15.3 D, ECC `skills/verification-loop` | run `check.sh $ARGUMENTS` (only known flags pass through; default quick), report stručne, ale úplne (§0); exit 4 ⇒ PARTIAL or SKIP, not PASS (list `!`/`–` reasons); FAIL ⇒ list failures with file:line and propose fix order; never claim PASS without the script output |
| `commit` | `~/.claude/commands/commit.md` (keep ALL its rules: `[#XX] type: výstih`, one confirmation, explicit `git add <files>`, never push, never `--no-verify`, never amend unless asked, NO Co-Authored-By / AI attribution) | step 0: `check.sh --auto` must PASS (the hook gate enforces it anyway); show grouping+message+check result in ONE message; secrets reminder |
| `review` | `~/.claude/commands/review.md` (format with 🔴🟡🔵, numbering, verification, `.review-notes.md` only on request) + `~/.claude/commands/security.md` (as `--security` pass) + ECC `agents/code-reviewer.md`, `skills/security-review` | scopes: none = uncommitted, `branch [base]`; passes Bugs · Security · Súlad s `docs/plans/*.md` (V1) · stale CLAUDE.md/rules (V9); read project `REVIEW.md` if present (V2: Important vs Nit, max 5 nits, do-not-report list); confidence > 80 %, merge similar, security first; Nette/Symfony/Python checklists; optional delegation to agents `dev:ecc-silent-failure-hunter`, `dev:ecc-performance-optimizer` for large diffs |
| `test` | `~/.claude/commands/test.md` + ECC `skills/tdd-workflow` | RED→GREEN→REFACTOR with evidence, AAA, naming, mirror structure, run via `check.sh`-configured command or `dk`-style docker exec from devkit.json; PHPUnit + pytest branches |
| `debug` | plan §5 Debugging row | Nette: Tracy `log/exception*.html`, `log/*.log`, docker logs, Mailpit, Typesense health, login via `.test-credentials`, `EXPLAIN`; Symfony: `var/log`, profiler, `bin/console debug:*`; Python: traceback/pytest -x; hypothesis → minimal repro → fix suggestion; never guess |
| `fix` | ECC `commands/orch-fix-defect.md` | facts first (where, who calls, data); write failing repro test; run, confirm it fails for the expected reason; `test-lock.sh lock <test>`; fix code without touching the test; `check.sh --auto`; on PASS `test-lock.sh unlock`; offer `/dev:review` and `/dev:commit`. `--unlock` argument ⇒ only unlock and report |
| `plan` | plan §18 V1 | write `docs/plans/<task>-<slug>.md` (no `#`) (Úloha+zdroj, Súbory, Poradie, Riziká, Dôkaz, Mimo rozsahu) from the agreed plan; task number from branch; small tasks (≤ 3 files, no risky paths) ⇒ tell the user it is not needed; local mode (`docs/plans/` ignored) ⇒ the plan stays on disk, never committed; team mode ⇒ committed with the first change, deviations in the same commit |
| `learn` | ECC `commands/learn.md` + `learn-eval.md`, plan §13 | scan session for user corrections, resolved errors, discovered conventions ⇒ propose each as: native memory entry (feedback/project), project `.claude/rules/*.md` line, or new `guards`/`pairs` entry in devkit.json; user approves one by one; write only approved |
| `handoff` | plan §14 Kontext row | write state (hotové, rozpracované, ďalší krok, rozhodnutia, zmenené súbory, príkazy na overenie) to `handoffDoc` from devkit.json (append dated section) or `docs/handoff.md`; update `last-handoff.json` via `jq` in `${HOME}/.claude/dev-kit/projects/<phash>/` using `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"` helper or a tiny dedicated subcommand (add `session-card.sh --record-handoff <path> <title>`); then suggest `/clear` |
| `explain` | `~/.claude/commands/explain.md` | same structure (Čo to robí / Ako to funguje / Závislosti / Riziká pri zmene), Slovak, depth by request |
| `stats` | §4.9 | run `stats.sh $ARGUMENTS`, interpret: which rules are noisy, propose `disabledRules`/pattern tweaks, never change config without approval |
| `project-init` | ECC `skills/codebase-onboarding`, `commands/project-init.md`, plan §4.4, §14 PHP prax (infer-conventions), §16 P5, §17, §18 V2/V4/V6/V9 | see §6 |

Reference skills — model-invocable, short descriptions (always-on budget for the whole plugin ≤ 3k
tokens, measured by `tools/details.sh` by the docs rule: `disable-model-invocation` skills count 0):
| name | from ECC | `paths` | notes |
|---|---|---|---|
| `ecc-mysql-patterns` | `skills/mysql-patterns` | `db/**`, `migrations/**`, `**/*Model.php`, `**/*.sql`, `src/Repository/**` | MySQL 5.7/8, Dibi + Doctrine parametrization, EXPLAIN, indexes, N+1 |
| `ecc-e2e-testing` | `skills/e2e-testing` | `tests/e2e/**`, `**/*.spec.js`, `**/*.spec.ts`, `playwright.config.*` | Playwright POM, flaky handling; drop Vercel/npm-specific bits |
| `ecc-change-impact` | `skills/change-impact` | — | before risky changes in core (validators, triggers, public API) |
| `ecc-accessibility` | `skills/accessibility` | `**/*.latte`, `**/*.twig`, `www/css/**`, `assets/**/*.css`, `templates/**` | WCAG 2.2, server-rendered templates (no React) |
| `ecc-production-audit` | `skills/production-audit` | — | `disable-model-invocation: true` (user runs before deploy) |
| `ecc-python-patterns` | `skills/python-patterns` | `**/*.py` | F7 |
| `ecc-python-testing` | `skills/python-testing` | `tests/**/*.py`, `**/test_*.py`, `**/*_test.py` | F7, pytest |
| `task-tldr` | byte-identical copy of `~/.claude/skills/task-tldr/SKILL.md` | — | user's own skill; its 399-char description is accepted; the installer moves the original to a backup |
Adaptation rules for every `ecc-*` piece: dir AND frontmatter `name` = `ecc-<original>`; keep the
original description meaning; translate body to Slovak and trim (output stručne, ale úplne (§0), no "80 % coverage" mandates, no
conventional-commit rules, no npm/Node assumptions, `docker exec` instead), keep the best checklists; add
a first line comment `<!-- prevzaté z ECC <path> @ b92f181, upravené -->` after frontmatter.

## 6. `project-init` skill (most complex)

Arguments: none | `--sync` | `--dry-run`.
1. Detect: stack (composer.json → nette/symfony; pyproject/requirements → python), container (docker
   compose files: container_name + mounts → appRoot), tools present in `vendor/bin` / venv, phpstan
   config path, phpunit suites, phpcs ruleset, existing CLAUDE.md size, `.claude/` contents, git remote.
2. Dry-run plan shown to the user BEFORE writing anything: files to create/modify, devkit.json draft,
   which template rules, local-only vs team (commit) choice, layer-B skills offered
   (`templates/skills/*`). Never overwrite an existing file without explicit consent; show diffs.
3. Verify every check step by running it once (via the same exec logic as check.sh — call
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" --quick --project .` after writing devkit.json) and
   record baseline failures as `knownFailures` only with user consent.
4. Copy template files with a header: markdown → `<!-- dev-kit: <template>/<file> @ <plugin version> -->`
   (YAML-frontmatter files get it right after the frontmatter); `.worktreeinclude` → `# dev-kit:
   <template>/<file> @ <plugin version>`; JSON (`devkit.json`, `settings.json`) → no header (`--sync`
   compares by id/keys). Rules are copied, never symlinked.
5. infer-conventions: list well-evidenced, non-default conventions found in code (with evidence
   file:line), skip what phpcs/PHPStan/rector enforce; user approves each; write approved into
   `.claude/rules/conventions.md`.
6. CLAUDE.md: propose a skeleton ≤ 120 lines (Projekt, Stack, Príkazy with healthy-output examples
   (V9), Architektúra, Pravidlá, Pasce, `## Compact instructions`) built from the existing CLAUDE.md, moving
   topic sections into `rules/*.md` with `paths:`. Large rewrite only with consent; preserve every
   rule that would cause a regression if lost (list what moved where).
7. Team vs local: local ⇒ add `.claude/rules/`, `.claude/devkit.json` etc., `.claude/worktrees/`, an
   untracked `handoffDoc` and `docs/plans/` to `.git/info/exclude` (local mode puts nothing from the kit into git), and `.claude/rules/`, `CLAUDE.local.md`, `REVIEW.md`, `docs/plans/` to `.worktreeinclude` (so
   new worktrees get the untracked files); team ⇒ leave for commit (do not commit yourself) and propose
   `.claude/worktrees/` for `.gitignore`.
8. `--sync` (P5): for each project file with a `dev-kit:` header (JSON files: by template id/keys),
   compare with current template version; show per-file diff and propose update keeping local edits;
   update header version.
9. Final report stručne, ale úplne (§0): what was created, what to commit, how to undo.

## 7. Templates (`ROOT/templates/`)

```
common/REVIEW.md                 # V2: passes Bugs · Security · Súlad s plan.md; Important vs Nit; max 5 nits; do-not-report placeholders
common/plan.md                   # V1 template
php-nette/CLAUDE.md.tmpl         # skeleton with {{placeholders}}, ≤ 120 lines incl. verification block (V9) and `## Compact instructions`
php-nette/devkit.json            # like §3 example with {{container}}, {{appRoot}}, {{phpstanConfig}} placeholders
php-nette/settings.json          # permissions.ask (V4: make db-import*, docker stop/restart/rm * (any container), git push*, git checkout*/git switch*; project-init adds existing Makefile targets that stop/rebuild containers or change the DB/index) + permissions.deny (O: Edit(/vendor/**), Edit(/node_modules/**) …, anchored to the project root)
php-nette/.worktreeinclude       # V6: vendor/, app/config/config.local.neon, .test-credentials
php-nette/rules/php-core.md      # paths: **/*.php — PHP 8.x, PSR-12, strict types where project uses them, no die(), no @
php-nette/rules/nette.md         # paths: app/**, libs/** — presenters, DI, forms CSRF, ACL isAllowed
php-nette/rules/latte-frontend.md# paths: **/*.latte, www/css/**, www/js/** — escaping, {!$} policy, data-bs-*, JS anchors
php-nette/rules/db-dibi.md       # paths: db/**, **/*Model.php — Dibi 5 fetch null, params, no begin/commit in models, Phinx
php-nette/rules/tests.md         # paths: tests/** — suites, rollback tests, credentials, verification output
php-symfony/…                    # same shape: CLAUDE.md.tmpl, devkit.json, settings.json, .worktreeinclude, rules/{php-core,symfony,twig-frontend,doctrine,api-platform,tests}.md
python/…                         # CLAUDE.md.tmpl, devkit.json (pytest, ruff, mypy; host or container; {{bin}} placeholder, _init note key), settings.json, .worktreeinclude, rules/{python-core,tests}.md
skills/ecc-design-system/  skills/ecc-api-design/  skills/ecc-inherit-legacy-style/  skills/ecc-seo/   # layer B, copied into <project>/.claude/skills/ on request
```
Template content is GENERIC for the stack (no project specifics, no project names, no data).
All templates use the same placeholder name for the same thing (`{{projectDescription}}`, `{{run}}`, …)
and the same compaction heading `## Compact instructions`. Deny rules in `settings.json` start with `/`
(relative to the settings source = project root, permissions.md). `changedLinesOnly: "stop"` on phpstan
(php-nette, php-symfony) and mypy (python). The symfony template's 12 ask rules and broader deny are
intended.
Source material: `CLAUDE.md` of real Nette and Symfony projects — read-only — plus the
user's global `~/.claude/CLAUDE.md` rules. Each rule file ≤ 60 lines, with a `## Pasce` section.

## 8. Agents (`ROOT/agents/*.md`)

From ECC `agents/<name>.md`, renamed `ecc-<name>`, Slovak, trimmed. Frontmatter: `name`, `description`
(≤ 200 chars), `tools: Read, Grep, Glob, Bash`, `disallowedTools: Edit, Write, MultiEdit`, `model`
(`sonnet` for pr-test-analyzer and a11y-architect; `inherit` for silent-failure-hunter and
performance-optimizer), `maxTurns: 30`. No `memory` (it would enable Write/Edit and create
`.claude/agent-memory-local/` in projects); agents stay read-only, and silent-failure-hunter and
pr-test-analyzer may end with an optional line `Na zapamätanie: <poznatok → .claude/rules/<súbor>.md>`,
a suggestion that `/dev:learn` writes to project rules after approval (subagents load project rules).
Revisit `memory: user` in F6 if agents keep repeating the same false positives; the pre-edit guard
(`agentReadOnly`, writes only under `~/.claude/agent-memory/`) is already in place for that. No `isolation`. Body: read-only analysis; Bash only for read-only commands (git
log/diff/grep, `docker exec <container> php vendor/bin/phpstan|phpunit --list-tests …` per devkit.json);
return contract = numbered findings `N. <file>:<line> — <výstih>` with severity, max 15, then one
summary line. Verify frontmatter keys in `sub-agents.md`.

## 9. Repo meta

- `PROVENANCE.md`: table `kit path | ECC source path | ECC commit | date adopted | changes` — one row per
  adopted ECC piece (incl. python skills, layer-B template skills and review sources) and per kit file
  whose content was derived from ECC (fix, learn, check, project-init); ECC commit `b92f181`, date
  adopted `2026-10-27`. `tools/upstream.sh` reads the columns by position.
- `README.md` (Slovak, stručne, ale úplne (§0)), written for a colleague first: what it is, install from
  the GitHub marketplace + requirements, project setup (`/dev:project-init`), what the hooks do,
  commands table, noisy hook and disabling (`/dev:stats`, `disabledRules`, `claude plugin disable`), then
  kit development (clone, `make check`, maintenance, release flow with version bump +
  `claude plugin tag --push`) and license.
- `CHANGELOG.md`: `## 0.1.0 — 2026-10-27` initial.
- `Makefile`: `check` (= `claude plugin validate --strict plugins/dev` + `claude plugin validate
  --strict .` + `selftest` + `details` when installed), `selftest`, `upstream`, `release
  VERSION=x.y.z` (bump plugin.json, remind CHANGELOG, `claude plugin tag --dry-run plugins/dev`).
- `tools/upstream.sh`: parse PROVENANCE.md, `git -C ~/Projects/_tools/ECC fetch -q`, per row `git diff
  --stat <pin>..origin/main -- <path>`, print changed pieces (stručne, ale úplne (§0)), write
  `$DK_DATA/maintenance.json`.

## 10. Tests (`tests/selftest.sh`)

Pure bash 3.2, no docker/network. Creates temp dirs (`mktemp -d`), sets `DEVKIT_DATA`,
`CLAUDE_PROJECT_DIR`, builds a git repo fixture with `.claude/devkit.json` using `container: ""` and
stub tools (small shell scripts in the fixture that emulate php -l / phpcs emacs output / phpunit
failure lines and exit codes), feeds synthetic hook JSON on stdin, asserts exit codes, stdout JSON
(`jq -e`) and stderr text. Real tool outputs live in `tests/fixtures/real/*.txt` (merged stdout+stderr
only, CR/ESC bytes preserved) and are replayed by `tests/fixtures/bin/replay <file> <exit>`; secret
samples for the template patterns are `tests/fixtures/secret-samples.txt`. Required cases: see the list
in the builder prompt. Prints `PASS n/n` and exits non-zero on any failure. Runs < 20 s: cases run in subshells,
`DK_SELFTEST_JOBS` at a time (default 4; `1` = sequential), results printed in order.
