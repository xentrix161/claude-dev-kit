# dev-kit — build specification

Source of truth for every builder agent; this file wins on contracts. It describes the working copy; the
version is only in `plugins/dev/.claude-plugin/plugin.json`, changes per version are in `CHANGELOG.md`.

## 0. Ground rules for all builders

- Kit repo: a working copy of this repository (`<KIT>`, `KIT/` in §1). Plugin root: `<KIT>/plugins/dev`
  (ROOT). Write ONLY inside `<KIT>`. Other projects and their containers are READ-ONLY reference — never
  write there, never run git commands that change those repos, never run docker commands that stop,
  restart or modify existing containers. Other Claude sessions work there.
- ECC source (read-only): a clone in `ECC_DIR` (default `<KIT>/../ECC`, §9) pinned at commit `b92f181`
  (2026-10-11), MIT.
- Claude Code docs (current for v2.1.308): `hooks.md`, `hooks-guide.md`, `plugins-reference.md`,
  `skills.md`, `sub-agents.md`, `settings.md`, `permissions.md`, `tools-reference.md`, `worktrees.md`,
  `plugin-evals.md`, `statusline.md`, `memory.md`, `plugins-loading.md`.
  When unsure about a frontmatter key, hook field or JSON output shape: check these docs, do not guess.
- Assumptions about Claude Code the kit relies on (verified 2026-10-30 in code.claude.com/docs, CLI 2.1.308;
  re-check when a doc changes and fix the code, not this list):
  1. A plugin's `settings.json` (or `settings` in `plugin.json`) applies only `agent` and `subagentStatusLine`,
     other keys incl. `permissions` are dropped (`plugins-reference.md`) ⇒ permission templates stay in the
     project's `.claude/settings.json` (§6, §7).
  2. Plugin subagents ignore the `hooks`, `mcpServers` and `permissionMode` frontmatter (`sub-agents.md`) ⇒
     kit agents use none of them; read-only comes from `tools`/`disallowedTools` and `agentReadOnly` (§4.3, §8).
  3. Stop accepts `hookSpecificOutput.additionalContext` as non-error feedback; the conversation continues
     under the same loop protections as `decision: "block"` (`hooks.md`, Stop decision control) ⇒ §4.6.
  4. A handler's `if` holds exactly one permission rule (no `&&`, `||`, list; a `!` rule carves only out of
     earlier rules of a deny/ask list) and is evaluated only on `PreToolUse`, `PostToolUse`,
     `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`; on any other event (Stop, SessionStart,
     PreCompact) a handler with `if` never runs (`hooks.md`, Common fields) ⇒ no `if` in hooks.json (§4).
  5. `MultiEdit` is not a current tool (absent from `tools-reference.md`, "legacy" in `permissions.md`);
     file edits come as `Edit`, `Write`, `NotebookEdit`, and an `Edit(path)` rule covers all three ⇒
     matchers `Edit|Write|NotebookEdit`, agents `disallowedTools: Edit, Write, NotebookEdit`.
  6. `CLAUDE_PLUGIN_DATA` is exported to hook commands (and MCP/LSP processes) and substituted inline in
     plugin skill and agent Markdown, but is not in the environment of Bash tool commands
     (`plugins-reference.md`, Environment variables) ⇒ data dir `DEVKIT_DATA` / `$HOME/.claude/dev-kit` (§2).
  7. `additionalContext`, `systemMessage` and plain stdout of a hook are capped at 10 000 characters each;
     longer text is replaced by a file path and a 2 000-character preview, and `additionalContext` should be
     facts, not imperative instructions (`hooks.md`, JSON output and Add context for Claude) ⇒ `dk_cap`
     (§4) and factual card, reminder and PreCompact lines (§4.6, §4.7, §4.10).
  8. Up to 2.1.313, hooks with matcher `Bash` did not run for the Monitor tool, so a `git commit` started from
     Monitor bypassed `pre-bash.sh` (commit gate, secrets) ⇒ `DK_MIN_CC` = 2.1.314, the card warns on older (§4.7).
- Language: everything a human or Claude reads at runtime (hook messages, skill bodies, agent prompts,
  README, templates) is **Slovak with full diacritics**. Code identifiers, commands and paths stay as is.
- Style of user-facing output „stručne, ale úplne“ (the user's global response-style rule, restated here):
  conclusion first, then evidence; short paragraphs of full sentences plus bullets as the content needs,
  no caps on list length; complete lists (findings, TODO, files) with ID/state/description; no intro
  phrases, no closing recap; `file:line` refs. Fixed formats stay: hook messages (≤ 20 lines, prefix
  `[dev-kit]`, each finding one line), check.sh lines, the review finding line, the one-line commit message.
- Shell: scripts must run on **macOS /bin/bash 3.2** and on Linux bash 5. Forbidden: `declare -A`,
  `mapfile`/`readarray`, `${x,,}`/`${x^^}`, `|&`, `&>>`, `coproc`, `grep -P`, `sed -i` (use temp file +
  mv), `date -d`, `stat -c/-f`, `readlink -f`, `realpath`, `timeout` (not on macOS). Hashing: use
  `git hash-object --stdin` (portable), not sha1sum/shasum/md5. Use `set -u` carefully (bash 3.2 empty
  arrays + `set -u` = error → avoid arrays or guard them). Always `#!/usr/bin/env bash`. Paths and other
  data go to `awk` via `ENVIRON`, never `-v` (it expands backslash escapes: `\t` in a path becomes a TAB).
- Dependencies at runtime: bash, git, jq (required for hooks; if missing → hooks exit 0 silently except
  session-card which says so in static JSON, §4.7), docker (only when `container` is set).
- Hook discipline: consume stdin fully; stdout silent unless emitting the documented JSON (PreCompact: the
  documented plain text, §4.10); exit 0 when
  nothing to report; never crash the session — any internal error → log to `$DK_DATA/errors.log` and
  exit 0. Respect hook timeouts (see hooks.json).
- No comments that narrate history. Comments short, only for non-obvious things.

## 1. Repository layout

```
KIT/
  .claude-plugin/marketplace.json     # {"name":"dev-kit","owner":{"name":"dev-kit"},"plugins":[{"name":"dev","source":"./plugins/dev","description":"…"}]}
  plugins/dev/
    .claude-plugin/plugin.json        # {"name":"dev","version":"x.y.z","description":"…","author":{"name":"dev-kit"}}
    hooks/hooks.json
    scripts/   lib.sh check.sh on-edit.sh pre-edit.sh pre-bash.sh cmd-parse.sh stop-check.sh session-card.sh pre-compact.sh test-lock.sh stats.sh
    skills/    <command skills> <reference skills>   (see §5)
    agents/    ecc-silent-failure-hunter.md ecc-pr-test-analyzer.md ecc-a11y-architect.md ecc-performance-optimizer.md
    templates/ common/ php-nette/ php-symfony/ python/ skills/   (see §7)
    evals/     <case>/ (prompt.md case.yaml scaffold.sh graders/)  fixtures/   (see §9, make eval)
    LICENSES/ECC-MIT.txt
    PROVENANCE.md
  tests/selftest.sh  tests/fixtures/…   # deterministic, no docker, no network
  tools/upstream.sh                     # P3: diff of pinned ECC pieces vs upstream
  tools/details.sh                      # inventory + always-on budget (§5)
  Makefile  README.md  CHANGELOG.md  LICENSE  docs/SPEC.md
  .github/workflows/check.yml           # kit CI: validate + selftest on Linux and macOS (§9)
```
Version lives only in `plugin.json` (never in the marketplace entry). The kit's own code is MIT (`LICENSE`);
the ECC MIT text stays in `plugins/dev/LICENSES/`.

## 2. Data directory

`DK_DATA="${DEVKIT_DATA:-$HOME/.claude/dev-kit}"` — one fixed location for hooks AND for scripts called
from skills via the Bash tool (the Bash tool does not get CLAUDE_PLUGIN_DATA). Tests set `DEVKIT_DATA`.
`$DK_DATA` is created with mode 700 (`(umask 077; mkdir -p …)` in a subshell, no global `umask` change); an
existing one owned by the user is set to 700 once per process.
```
$DK_DATA/decisions.jsonl                          # V8 log, all projects
$DK_DATA/errors.log                               # dk_err; over 1 MB trimmed to the last 500 lines
$DK_DATA/maintenance.json                         # {"lastUpstreamCheck": <epoch>} written by tools/upstream.sh
$DK_DATA/projects/<phash>/pass.json               # commit-gate PASS marker
$DK_DATA/projects/<phash>/partial.json            # last quick/full check ended PARTIAL (§4.5), explained by the commit gate (§4.4)
$DK_DATA/projects/<phash>/test-lock.json          # V3
$DK_DATA/projects/<phash>/container.state         # "<epoch> <running|down> <container>", dk_container_ok cache (30 s)
$DK_DATA/projects/<phash>/config.hash             # blob hash of the devkit.json last seen by the card, on-edit or pre-bash (dk_cfg_trust, §4.1)
$DK_DATA/projects/<phash>/config.cmds.json        # its commands as a sorted JSON array of labelled strings (DK_JQ_CMDS, §4.1)
$DK_DATA/projects/<phash>/sessions/<session_id>.files   # files edited in that session (repo-relative, one per line)
$DK_DATA/projects/<phash>/sessions/<session_id>.head    # HEAD at the session's first .files write (empty without HEAD)
$DK_DATA/projects/<phash>/sessions/<session_id>.t0      # empty, mtime = session start (card on startup|resume|clear, §4.7)
$DK_DATA/projects/<phash>/sessions/<session_id>.stop.json   # last stop-check state of that session
$DK_DATA/projects/<phash>/sessions/<session_id>.cfgnote     # on-edit or pre-bash reported a devkit.json change in that session
$DK_DATA/projects/<phash>/sessions/<session_id>.tplnote     # the card compared the template headers in that session (§4.7 item 10)
$DK_DATA/projects/<phash>/pairs-<session_id>.done # Stop reminders already given (pairs, testRemoved)
$DK_DATA/projects/<phash>/logs/check-<mode>-<epoch>.log  # full check output (keep last 20)
$DK_DATA/projects/<phash>/card-hint.<YYYYMMDD>    # "no devkit.json" hint shown today
$DK_DATA/projects/<phash>/last-handoff.json       # {"time":…, "title":"…", "path":"…"}
$DK_DATA/cc-version.<YYYYMMDD>                    # `claude --version` cached for the day (§4.7)
```
`<phash>` = first 12 chars of `printf %s "<project dir>" | git hash-object --stdin`. On `startup` the card
deletes `sessions/*.files|.head|.t0|.stop.json|.cfgnote|.tplnote` and `pairs-*.done` older than 14 days (§4.7).

## 3. Project config `.claude/devkit.json` (schema v1)

Located at `<project>/.claude/devkit.json`. Missing file ⇒ every hook is a no-op (except the one-line
hint in session-card and the `agentReadOnly` deny of the kit's agents in pre-edit, §4.3). Only `check.sh`
can read another file of this schema instead (`--config`/`DEVKIT_CONFIG`, CI, §4.5). Unknown keys
and keys starting with `_` (template notes such as `_init`) are ignored. Example (typical Nette project):
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
    {"id": "debug-php", "ext": [".php", ".latte"], "pattern": "(^|[^>:$_[:alnum:]])(dump|dd|bdump|var_dump|print_r)\\(", "message": "debug výpis v kóde"},
    {"id": "die", "ext": [".php"], "pattern": "(^|[^>:$_[:alnum:]])(die|exit)[[:space:]]*(\\(|;)", "message": "die()/exit() — použi throw alebo $this->terminate()"},
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
- `lint`: `"<ext>": [<command>, …]`; a command is a string or an object `{"run": "<cmd>", "runtime":
  "host"|"container"}` (a single string or object instead of the list is accepted). Steps take the same
  optional `runtime`.
- `runtime` (per step, per lint command): `"host"` ⇒ the command runs on the host (`cd <P> && sh -c
  "<cmd>"`) even when `container` is set, without the container state check and the workdir mapping;
  `"container"` or absent ⇒ in the container when `container` is set, otherwise on the host (so a CI
  copy with `container: ""` runs everything on the host). Any other value ⇒ the step is blocked
  `! <id>: neznámy runtime "<x>" (host|container)` (§4.5); a lint command is skipped (`errors.log`,
  decision `skip`). `{file}`/`{files}` are relative to P in both runtimes.
- Trust (R3): hooks run the `lint` and `check.steps[]` commands as written. A change of the file is reported,
  never blocked: the card once after the change (§4.7 item 9), on-edit and pre-bash once per session (§4.2,
  §4.4); the first sight of a config is trusted silently (`dk_cfg_trust`, §4.1). An allowlist of commands
  is out of scope.
- Path mapping (V6 worktrees): MAIN = main repo root (`git rev-parse --path-format=absolute
  --git-common-dir` → strip trailing `/.git`). The container mounts MAIN at `appRoot`. Container workdir
  for a project dir P = `appRoot + "/" + relpath(P, MAIN)` (just `appRoot` when P == MAIN). Container
  commands execute as `docker exec -i -w <workdir> <container> sh -c "<cmd>"`; `{file}`/`{files}` are paths
  relative to P (shell-quoted). If P is not under MAIN ⇒ step SKIP with message
  `worktree mimo mountu kontajnera`.
- `requires`: path relative to P checked on the HOST (in both runtimes); missing ⇒ step SKIP `chýba <path>`.
- Container not running (`docker inspect -f '{{.State.Running}}'` ≠ true) ⇒ container steps SKIP
  `kontajner <c> nebeží`; `runtime: host` steps and lint commands run regardless.
- `changedLinesOnly` (per step): `true` = keep only output lines on added lines (same filter as on-edit,
  §4.2 step 3) in every mode; `"stop"` = filter only in stop mode (`/dev:check` still shows whole-file
  findings); `false`/absent = no filter. `lintChangedLinesOnly` does the same for the `lint` map.
- Regexes (`pattern`, `secrets.patterns`, `knownFailures.pattern`) are **POSIX ERE as understood by
  `grep -E`**; a leading `(?i)` means case-insensitive (strip it and use `grep -i`). `\b`, `\w`, `\s` only
  OUTSIDE `[...]`; inside brackets use `[:space:]` / `[:alnum:]_` (BSD grep reads `[^\s]` as "not
  backslash, not s"). Every pattern is passed to grep with `-e` (patterns may start with `-----BEGIN`).
  `secrets.patterns` EXTEND the lib defaults (union); one finding per `file:line`. Builders keep shipped
  default patterns compatible with BSD and GNU grep.
- `pairs[].when` and `pairs[].unless` are one glob or a list of globs (a path matching any of them counts).
- Globs (`fullWhen`, `when`, `unless`, `allow` entries ending with `/` are prefixes, `forbidFiles`,
  `migrations.paths`): `**/` = zero or more directories (so `**/*.php` matches `a.php` and `x/y/a.php`),
  trailing `/**` = everything below, other `**` = any chars incl `/`, `*` = any chars except `/`, `?` = one
  char; matched against repo-relative paths (relative to P). Implement once in lib.sh (`dk_glob_match`).
- Rule ids usable in `disabledRules`: guard ids (`guard:<id>`, e.g. `guard:sql-concat`, the templates'
  `guard:test-skip`), `lint:<ext>` (e.g. `lint:.php`), `step:<id>`, `pair:<id>`, `secrets`, `migrations`,
  `testLock`, `stopCheck`, `commitGate`, `testRemoved`. Hook messages print these ids (§4.2, §4.6).
- `knownFailures`: when a step fails, extract failing identifiers from its output — only PHPUnit lines
  `^[0-9]+\) <Class>::<method>`, pytest `^FAILED <id>` and `^ERROR <id>` (short summary; `<id>` is
  `<path>::<test>` or, for a collection error, the path; an `ERROR` line whose first word is not a `.py` path
  is not an identifier) and Nette Tester `^-- FAILED: [<title> | ]<path>[ <args>]`;
  other numbered lines are not identifiers. A Tester id is the path as Tester prints it (relative to the common
  directory of the tests that ran) plus the variant arguments (`method=<m>`, `dataprovider=<item>|<file>`); the
  title before the last ` | ` that is followed by a `.php`/`.phpt` path is dropped, otherwise the whole text
  after `-- FAILED: ` is the id. A path-only pattern (`^Model/FooTest\.phpt$`) does not cover a method
  variant. Vulnerability records (step `audit`, §7) are identifiers too. `composer audit` (plain or table):
  after a header `Found <n> [ignored ]security vulnerability advisor…` each block from `Package:` is one
  record whose ids are the values of `Advisory ID:` and `CVE:` (`NO CVE` is none; Composer before 2.8 prints
  no Advisory ID, 2.8 only without a CVE); a block without any id is the package name; a block with `Ignore
  reason:` (Composer's own `audit.ignore`) is skipped; every other `Found <n> …` line of that output
  (abandoned packages, filters) is a record of its own, so a known CVE never hides it. `pip-audit` (columns):
  each row under the header `Name Version ID …` and its dash line is a record, ids = the `ID` column
  (`PYSEC-…`, `GHSA-…`) plus the aliases (`--aliases on`: `CVE-…`). A record matches when a pattern matches
  any of its ids (`^CVE-2026-12345$` covers `PKSA-… CVE-2026-12345`); without those headers nothing is read
  as a record (a test printing `Package: x` adds no identifier). If ≥1
  identifier was found and every one matches some pattern for that step ⇒ the step does not fail; its
  line gets the note `známe zlyhania: N` and the summary counts it as `známe`, not `ok` (§4.5).

## 4. Hooks (`ROOT/hooks/hooks.json`)

```json
{
  "hooks": {
    "SessionStart": [{"matcher": "startup|resume|clear|compact", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/session-card.sh\"", "timeout": 10}]}],
    "PreToolUse": [
      {"matcher": "Edit|Write|NotebookEdit", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/pre-edit.sh\"", "timeout": 10}]},
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/pre-bash.sh\"", "timeout": 30}]}
    ],
    "PostToolUse": [{"matcher": "Edit|Write|NotebookEdit", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/on-edit.sh\"", "timeout": 60}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/stop-check.sh\"", "timeout": 600}]}],
    "PreCompact": [{"hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/pre-compact.sh\"", "timeout": 10}]}]
  }
}
```
Verify tool names and matcher syntax against `hooks.md` (current tool names for file edits). Hook input
fields used: `session_id`, `cwd`, `hook_event_name`, `tool_name`, `tool_input.file_path` (NotebookEdit:
`tool_input.notebook_path`; pre-edit and on-edit treat both the same),
`tool_input.command`, `stop_hook_active`, `source`, `agent_type` (set when a subagent calls the tool).
Project dir = `$CLAUDE_PROJECT_DIR`, fallback `.cwd` from input, fallback `pwd`. A cwd inside a linked
worktree of the same repo wins over `--project`/`CLAUDE_PROJECT_DIR` (scripts called from skills and
hooks); `--project` of another repo is honoured. Skills keep passing `--project "${CLAUDE_PROJECT_DIR}"` and need no worktree workarounds.
No handler has an `if` field: one permission rule without negation cannot express a filter that is safe for
every project (pre-edit guards any Edit/Write target, not reads — `agentReadOnly`, `forbidFiles`, locks — and on-edit scans every
file for secrets, while the `lint` map is per project), and on Stop, SessionStart or PreCompact a handler with
`if` would never run (§0 assumption 4). Text for Claude and the user — `additionalContext`, `systemMessage`
of session-card and stop-check, the PreCompact stdout — goes through jq `dk_cap` (`DK_JQ_CAP`, §4.1): at most
9 000 UTF-16 code units (a character outside the BMP counts 2), a longer text is cut and ends with `…`. Scripts
hand text to jq only via `--arg` or `--rawfile` (hook text above, `partial.json` and `pass.json` §4.5,
`test-lock.json` §4.8, the decision log in `stats.sh` §4.9), never `jq -R` from a pipe (jq 1.7.1 breaks a
multibyte character at a read-chunk boundary into U+FFFD).

### 4.1 `lib.sh` (sourced by all scripts)
Functions (names fixed, other scripts depend on them):
`dk_init` (reads stdin into `DK_INPUT` when stdin is not a tty; sets `DK_PROJECT`, `DK_DATA`, `DK_PDATA`
(per-project data dir, created), `DK_CFG` (path or empty), `DK_SESSION`), `dk_in <jq-filter>` (query
DK_INPUT), `dk_cfg <jq-filter> [default]`, `dk_rule_on <rule-id>` (false when listed in disabledRules),
`dk_cfg_trust [note]` (R3: `git hash-object --no-filters` of `DK_CFG` vs `config.hash` (§2); on a difference the
config's commands (`DK_JQ_CMDS`: each `lint` command as `lint <ext>[ (<runtime>)]: <cmd>`, each step's `run` and
`runFiles` as `krok <id> run|runFiles[ (<runtime>)]: <cmd>`) are compared with `config.cmds.json`,
`DK_CFG_CMDS` = the commands that are new or changed (one per line; removed ones are not listed),
`DK_CFG_CHANGED=1`, both files are rewritten and it returns 0; no `config.hash` yet ⇒ writes the snapshot
silently and returns 1; JSON jq cannot read ⇒ 1 without writing. `note` (on-edit, pre-bash): an existing
`sessions/<id>.cfgnote` ⇒ 1 without comparing, so a later change in that session waits in the snapshot for the
next card; a reported change creates the marker. Only session-card, on-edit and pre-bash call it — check.sh,
stop-check and skills run changed commands without consuming the change), `dk_cfg_note` (one line
`[dev-kit] devkit.json sa zmenil — príkazy: <a> · <b>` from `DK_CFG_CMDS`, at most 5 then `· … ďalšie: K`;
none ⇒ `príkazy: žiadny nový ani zmenený`),
`dk_main_root`, `dk_rel <abs-path>` (relative to DK_PROJECT; empty if outside), `dk_workdir`
(container workdir, empty+message if outside mount), `dk_exec <cmd> [runtime]` (runs in container or host,
returns exit code, merges stderr into stdout; runtime `host` ⇒ host even when `container` is set),
`dk_runtime <value>` (effective runtime of a step or lint command into `DK_RT`: `host`, or `container`
when `container` is set and the value is empty or `container`, else `host`; any other value returns 1), `dk_container_ok` (0 when container unset or running; reuses
`container.state` (§2) younger than 30 s for the same container, otherwise asks `docker inspect` and writes
it; `check.sh` sets `DK_NO_CONTAINER_CACHE`, so it always asks and only writes the fresh state),
`dk_glob_match <path> <glob>`, `dk_added_lines <rel>` (newline list of added line numbers vs HEAD from
`git diff -U0 HEAD --`; untracked file ⇒ all lines; file new in index ⇒ all lines; a path the repo does not know — a
file in a submodule or a nested repo — ⇒ the same diff in the root of that repo, `git -C <dir of rel> rev-parse
--show-toplevel`, with the path relative to it; only a root strictly below the project counts), `dk_blobs <rel>…`
(`rel<TAB>blob` sorted by path; missing or unreadable file = `-`; when the batch `git hash-object
--stdin-paths` fails, files are hashed one by one and each unreadable one is logged via `dk_err`; a symlink
with a code extension (`dk_is_code`: `lint` keys ∪ every step's `ext`) is left out — git commits its link
target, not the content hashed here), `dk_is_code <rel> [stop]` (`stop` ⇒ only the Stop code extensions,
§4.6 step 3), `dk_hash_files <rel>…` (combined content hash over `dk_blobs`), `dk_session_newer` (Stop code files, §4.6 step 3,
among `dk_changed_files` that exist and are newer than `sessions/<id>.t0` — `find -newer` via `xargs -0`, never the
whole tree; nothing without `.t0`), `dk_log <hook> <rule> <decision>
[file] [ms]` (append one JSON line: ts, project, session, hook, rule, decision ∈
block|deny|ask|warn|pass|skip, file, ms), `dk_err <msg>` (append to errors.log; over 1 MB the log keeps its
last 500 lines), `dk_now` (epoch seconds), `dk_ms` (best-effort ms: `perl -MTime::HiRes` if available else
seconds*1000), `dk_mask <match>` (always `****`, no character of the value;
returns 1 for a placeholder value; shared by on-edit and pre-bash), `dk_secret_scan <rel> <added-spec> <patterns>` (one `line<US>masked value`
per added line that matches; used by on-edit), `dk_data_dir` (creates `$DK_DATA` with mode 700, §2). Shared values: `DK_JQ_CAP` (jq `def dk_cap`, §4), `DK_RE_GITPFX`, `DK_RE_COMMIT`, `DK_RE_COMMIT_CONT`, `DK_RE_ADD` (§4.4), `DK_RE_INFRA`
(infrastructure errors incl. network errors of package registries, §4.5), `DK_MIN_CC` (minimum Claude Code version, §4.7).

### 4.2 `on-edit.sh` — PostToolUse (edit/write)
1. No config / no jq / file outside project ⇒ exit 0.
2. Append rel path to `sessions/<session_id>.files` (dedupe); the first write also stores
   `git rev-parse HEAD` in `sessions/<session_id>.head` (empty file when the repo has no HEAD).
   devkit.json changed (`dk_cfg_trust note`, §4.1) ⇒ stdout `{"systemMessage": "<dk_cfg_note>"}` once per
   session, with exit 0 and with exit 2 alike (Claude Code reads JSON fields on exit 2 too, the block message
   stays stderr); stderr on exit 0 would reach nobody. Lint and guards run as usual.
3. Lint (`lint` map by extension, rule `lint:<ext>`): a container command (effective runtime, §3) only
   when `dk_container_ok` (state cached 30 s, §4.1) and the workdir resolves, otherwise it is skipped
   silently; a `runtime: host` command always runs on the host. Run each command
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
- Read-only agents (rule `agentReadOnly`): checked first, before the config is read, so it applies in
  projects without `devkit.json` too (jq is still required). Input `agent_type` matching `dev:ecc-*` (the
  kit's agents, §8) and a target outside `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agent-memory/` (or one
  containing `..`) ⇒ deny, reason `[dev-kit] agent <agent_type> je len na čítanie — zapisovať smie iba do
  svojej pamäte v <dir>. Opravu navrhni v odpovedi.`, logged as `agentReadOnly deny`. Not switchable via
  `disabledRules`. Other agents and the main session are not affected.
- Forbidden files (rule `secrets`, the same id as the commit check §4.4, so `disabledRules secrets` turns off both):
  the target rel path matches a `secrets.forbidFiles` glob (`dk_first_glob`, compared case-insensitively like the test
  lock) ⇒ deny, reason `[dev-kit] <rel> je v secrets.forbidFiles — tajomstvá sa needitujú cez Claude`, logged as
  `forbidFiles deny`. Checked before the test lock. Only Edit/Write/NotebookEdit; reading the file is not guarded.
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
Fast path: if `tool_input.command` does not contain a `git … commit` invocation nor a `git rebase|merge|cherry-pick|
revert|am … --continue` ⇒ exit 0. Here-doc bodies
(e.g. a commit message via `<<'EOF'`) are blanked before analysis, line numbers kept. Detection uses
the EREs `DK_RE_GITPFX` (command start + `git` with its global options), `DK_RE_COMMIT`, `DK_RE_COMMIT_CONT`
(`rebase|merge|cherry-pick|revert|am` with `--continue` before the next `;`, `&` or `|`) and `DK_RE_ADD`
(`add`/`stage`) from lib.sh; other scripts and this SPEC reference them, never copy them. They contain `/`, so
every `sed` using them takes the `\001` delimiter. Recognised before `commit`: leading env assignments
(`VAR=x git commit`, quoted values too), wrappers (`command`, `builtin`, `exec`, `env`, `time`, `nice`,
`nohup`, after `then`/`do`/`else`, `{`, `(`, `!`), `git` by absolute path or as `\git`, and the git
global options `-C <dir>` (also quoted with spaces), `-c k=v`, `-p`/`-P`, `--no-pager`, `--git-dir` and
`--work-tree` (with `=` or a space). Must match `cd x && git commit -m …`; must not match
`git commit-tree`, `git log --grep commit` or `echo "git commit"`. Limitations: see Known limitations below.
A `--continue` matching `DK_RE_COMMIT_CONT` commits the staged files, so it is a commit for everything below: same
báza and kandidáti (§4.4.1), both checks; its to-be-committed files are the staged ones (plus a `git add` earlier
in the same command), never `-a` or pathspecs, and its words are not read as commit flags. When the command has
one, the deny names the first such command: `commit zablokovaný pred git <op> --continue — …`,
`commit gate pred git <op> --continue: …` and the final line ends `pri PASS zopakuj git <op> --continue.`
Repo: `dk_cmd_parse` (`cmd-parse.sh`, §4.4.1) returns for every `git commit` and `git add`/`git stage` of the
command its báza (the directory it runs in: session cwd, then every `cd` that certainly runs before it, then the
command's own `-C` / `--work-tree` / `GIT_WORK_TREE` / `--git-dir` / `GIT_DIR`) and its kandidáti (directories it may
run in instead: targets of a `cd` that is not certain to run, literal operands and variable values of an unknown
target, the previous báza). The checks below run in the repo (`dk_set_project`) of every báza and every kandidát,
each once; repos without config are skipped. A deny starts with the lines of §4.4.1 (`U`, `N`, `R`) and, when more
than one repo denies, each block is headed by `[dev-kit] repo <path>:`.
Known limitations (§4.4.1 lists what the parser models): the structure inside strings (`sh -c`, `bash -c`, `eval`,
`xargs`, `source` / `.`) is not seen beyond the fallback `R` (session cwd plus every directory named after a word
`cd`, `pushd` or `-C` anywhere in the text); aliases and functions from the user's shell startup files, which Claude
Code applies to every Bash command (docs: tools reference, Bash tool behavior), including a function or alias named
`cd` or `git`; `CDPATH` from the environment, zsh `AUTO_CD` / `CDABLE_VARS`, bash `cdable_vars`; `GIT_INDEX_FILE`;
`$(…)` inside an unquoted here-doc body; functions defined by an earlier Bash call; a `git commit` that git or
an editor runs on its own (`GIT_EDITOR` / `GIT_SEQUENCE_EDITOR` script, `exec` line of `rebase -i`, `rebase -x`).
Determine TO-BE-COMMITTED files: staged (`git diff --cached --name-only --diff-filter=ACMRD`) ∪ (when
`-a`/`--all`/combined short flags containing `a`: tracked modified files) ∪ (explicit pathspecs after
`--` or existing paths among trailing args: best effort) ∪ (`git add`/`git stage` earlier in the same
command: `-A`/`.`/`-u` widen like `-a`, paths count as pathspecs, `-f` includes ignored files). Denied
with a hint: `git add -p/-i/-e` in the same command (partial staging cannot be checked before it runs —
stage in a separate command, then commit), `git add -A -f`, and file names git prints only C-quoted.
Content of each file: staged blob (`git ls-files -s`) or, for -a/paths/add, `git hash-object <file>`;
deleted = `-`. A symlink with a code extension is left out of the set (working tree: `dk_blobs`, §4.1;
staged only: mode `120000` with an extension in `commitGate.ext` or the code extensions): git stores its link
target, which never equals the content `check.sh` hashed, so the gate would deny it forever.
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
   --auto|--full --project "<P>"[ --files <f>…] (to isté robí /dev:check), pri PASS commit zopakuj.` — command
   skills have `disable-model-invocation`, so Claude must get a command it can run itself. `--files` lists the
   code files of the commit when there are at most 8 (a name with a character outside `A-Za-z0-9._/@+=,:-` in
   single quotes), so an unrelated work-in-progress file does not fail the check; `pass.json` then holds exactly
   those blobs (§4.5).
   PARTIAL still blocks; the deny must say why and how to proceed: when it asks for a check (files without
   PASS or `--full`) and `partial.json` (§4.5) has `time` less than 24 h old, the reason adds before that
   final line `Posledná kontrola skončila PARTIAL:`, its `!` lines (≤ 5) and one escape line chosen by
   `ok`. `ok` ≥ 1: `Únik: navrhni používateľovi <príčina> a kontrolu zopakuj, alebo mu navrhni dočasné
   vypnutie kroku|krokov: disabledRules step:<id>[, step:<id>…] v .claude/devkit.json (config nemeň sám,
   počkaj na jeho rozhodnutie).` with every id from `steps` (`kroku` for one id, `krokov` for more).
   `ok` = 0 (always when the container is down — disabling the blocked steps would give SKIP, never PASS):
   `Únik: vypnutie krokov by dalo SKIP, nie PASS — navrhni používateľovi <príčina> a kontrolu zopakuj,
   alebo mu navrhni dočasné vypnutie gate: disabledRules commitGate v .claude/devkit.json (kontrola
   tajomstiev aj Stop bežia ďalej; config nemeň sám).` The text never tells Claude to change the config,
   only to propose disabling to the user — the same as `commit/SKILL.md:97` (Claude itself never turns
   off `commitGate` nor adds `disabledRules`). `<príčina>` = `spustiť kontajner <c>` when a
   line reads `kontajner <c> nebeží` for the configured container, else `odstrániť príčinu`. Never the
   imperative `spusti kontajner` — the `check` and `commit` skills forbid Claude to start containers.
   What the gate proves: the content of every committed code file passed `check.sh` in the working tree
   (together with the other uncommitted changes present at that time) — not that the resulting commit tree
   passes. A commit hidden in `sh -c '…'` / `bash -c '…'` is not recognised (§4.4 Known limitations).
3. Length and order of the deny text: the `U`/`N`/`R` lines (§4.4.1), then per repo the header (more than one
   repo), the block (secrets, then gate) and last the `Spusti kontrolu: …` line, which is added after the block
   is cut and never cut itself. A block has at most 12 lines; when more repos deny, fewer, so the whole text stays
   ≤ 20 lines (`(20 − U/N/R lines) / repos`, minus the header and the `Spusti` line, at least 1). Lists keep
   their cap (secret findings 8, files 8, `!` lines 5) and the longest one is shortened first (on a tie the later
   one), each with `… ďalšie nálezy|súbory|riadky: N`; only when no list can shrink below 1 item is the block cut
   at the end, dropping a trailing list heading (a line ending with `:`).
4. Deny ⇒ JSON `permissionDecision":"deny"` with reason, exit 0. Allow ⇒ exit 0 silently. Exception (R3):
   when the commit's repo has a config, `dk_cfg_trust note` (§4.1) reports its change once per session — the
   deny JSON gets a top-level `systemMessage` (`dk_cfg_note`), an allow prints `{"systemMessage": …}` alone
   (no decision, the normal permission flow continues); the gate and the secrets check are unchanged. Log;
   `commitGate` entries carry a content key (hash of the to-be-committed code blobs) so `/dev:stats` can
   group attempts on the same content (§4.9).
Never block `git commit --amend --no-edit` differently — same rules apply. Do not attempt to
intercept `--no-verify` (irrelevant to Claude hooks).

### 4.4.1 Commit command parser (`cmd-parse.sh`)
`cmd-parse.sh` is sourced by `pre-bash.sh` after `lib.sh`; the lexer, the parser and the certainty rules are one
POSIX awk program (BSD awk, mawk, gawk) in `DK_AWK_CMD`, `bash cmd-parse.sh --dump '<command>'` prints its records
for one command. The tables of this section are the fixtures `tests/fixtures/cmd-parse.tsv` (62 rows) and
`tests/fixtures/cmd-parse-closed.tsv` (41 rows); the selftest runs every row end to end through `pre-bash.sh`.

**Output.** `dk_cmd_parse <command> <fb>` (`fb` = session cwd, as in §4.4) returns one record per `git commit` and per
`git add`/`git stage` of the command: `báza` (the directory that command runs in) and `nerozriešené` — a list of
items, each with a snippet, a kind (`U` target unknown, `N` not certain that the `cd` runs, `R` fallback) and
`kandidáti` (directories where the command may run instead). Here-doc bodies are blanked first (§4.4).

**Masking.** Literal, without structure: `'…'`, `$'…'`, `"…"` except `$(…)` and `` `…` `` inside it, the character
after `\` (`\;` is a word character, `\cd` is the word `cd`), `#` at the start of a word up to the end of the line,
`$((…))`, `((…))`, `${…}` and the inside of `[[ … ]]` (`&&`, `||`, `<`, `(` there are not operators). `\` + newline
is removed. `$(…)`, `` `…` ``, `<(…)` and `>(…)` are nested command lists parsed by the same rules. Redirections
(`[n]<`, `>`, `>>`, `>|`, `<>`, `<&`, `>&`, `&>`, `&>>`, `<<`, `<<-`, `<<<` with their word) are not operators and
belong to their simple command.

**Structure.** list = and-or lists separated by `;`, `&` or newline; and-or list = pipelines joined by `&&` / `||`
(a newline after `&&`, `||` or `|`, also after a comment, continues it); pipeline = commands joined by `|`, with
optional `!` / `time` in front; command = simple command, `( … )`, `{ …; }`, `if`, `while`, `until`, `for`,
`select`, `case` or a function definition (`name() …`, `function name …`, zsh `() { … }`). Reserved words count only
in command position (`echo then cd /x` is one simple command `echo`).

**Commands.** A simple command is a commit / add when its masked text matches `DK_RE_COMMIT` or `DK_RE_COMMIT_CONT` / `DK_RE_ADD`
(wrappers, prefix assignments and git options as in §4.4). It changes the directory when its command word — after
prefix assignments, redirections and `builtin` / `command` — is `cd` (also `\cd`, `"cd"`), `pushd`, `popd` or
`chdir`:
- `cd` / `pushd` skip `-L` / `-P` (also combined) and one `--` after them (A4); one operand = target; no operand =
  `~`, with a prefix `HOME=<literal>` on that `cd` = the literal. Unknown target: `cd -`, any other option (also after
  `--`; zsh `-q`/`-s`, bash ≥ 4.3 `-e`/`-@`), two or more operands (zsh `cd old new`), `pushd` with an option,
  `+N`/`-N` or without an operand, a prefix `CDPATH=…`, and `popd`.
- `chdir` exists only in zsh, so it is never certain (kind `N`).
- Other prefix assignments (`X=1 cd /x`) do not change the target.

**Targets.** Expanded as `dk_expand_dir` (§4.4): `~`, `~/…`, `$HOME`, `$PWD`, `$(pwd)`, `` `pwd` ``,
`$CLAUDE_PROJECT_DIR`, plus variables of leading assignments. Anything else (`$(…)`, other variables, `~user`) is an
unknown target.

**Leading assignments.** A simple command made only of `NAME=value` words (optionally after `export`) at the very start
of the command, preceded only by other such commands joined by `;`, newline or `&&`, whose value is literal or built
from the expansions above. Its variable expands in later targets when the command assigns `NAME` nowhere else (no
other `NAME=`, `NAME+=`, `export|readonly|declare|typeset|local|unset|read NAME`, `for NAME`). A leading `HOME` applies
to `~`, `$HOME` and a bare `cd`; a leading `export GIT_DIR=…` / `GIT_WORK_TREE=…` acts as a prefix of every later
commit. Every other assignment leaves the variable unknown; each literal value the command assigns to it (also the
words of `for NAME in …`, and the hook's `$HOME` for `HOME`) becomes a kandidát of a target that uses it.

**Certainty of a `cd` D before a commit C.** When C is inside `( … )`, `$(…)`, `` `…` ``, `<(…)`, `>(…)`, a
`then` / `else` / `do` body or a `case` branch, apply the rules inside it first, then treat the whole construct as C in
the enclosing list.
- certain: D is the first pipeline of its and-or list, not in a pipe, without `!` / `time`, and that list ends with
  `;` or newline before C's list; or D is in C's and-or list with only `&&` between the start of the list and C. A
  group `{ …; }` is transparent: D inside it is certain when it is certain within the group and the group is certain
  for C.
- not certain (kind `N`): every other D that may run in the current shell before C — after `&&` / `||` in an earlier
  and-or list; in C's and-or list when `||` precedes C; in any pipe element (zsh runs the last one in the current
  shell); in a list ended by `&`; in `( … )` without C; in a function body (the function may be called later); in an
  `if` / `elif` condition or body, a loop body or a `case` branch without C; after `!` or `time`; and any D in a loop
  body that contains C, also after C.
- no effect: D inside `$(…)`, `` `…` ``, `<(…)`, `>(…)` without C; D after C outside a loop around C.

**Result per commit.** báza starts at `fb`. Certain D in text order: a known target ⇒ báza = target resolved against
báza when it is an existing directory, else báza stays (the `cd` fails, the shell stays where it was); an unknown
target ⇒ báza = `fb` and item `U` with kandidáti = its literal operands that are directories, values from
assignments, and the previous báza. Not certain D ⇒ item `N` (`U` when the target is unknown) with kandidáti = the
target resolved against the báza at that point when it is a directory, otherwise `fb` and values from assignments;
báza does not change. A later certain D whose target does not depend on báza (`/…`, `~`, `$HOME`,
`$CLAUDE_PROJECT_DIR`) drops the items collected so far; a relative one is applied to the kandidáti as well (when the
result is a directory). Then C's own `-C` / `--work-tree` / `--git-dir` / `GIT_WORK_TREE` / `GIT_DIR` as in §4.4
(unknown ⇒ báza `fb`, item `U`). `git add` / `git stage` records get their báza the same way.

**Fallback (fail closed).** A parse error (unterminated quote, unbalanced `(`, `{`, `$(` or backtick, `fi` / `done` /
`esac` / `}` without its opener, `case` without `esac`, a zsh short form such as `if … { }`), a commit inside a
function body, or `DK_RE_COMMIT` and `DK_RE_COMMIT_CONT` finding more commits in the raw text than the parser found in the structure (a
commit inside a string — `sh -c`, `bash -c`, `eval`, `xargs` — or behind `\;`) adds one record: báza `fb`, item `R`
with the reason (`neuzavretá úvodzovka`, `neuzavretá zátvorka`, `neočakávané slovo <w>`, `commit v tele funkcie`,
`commit mimo štruktúry`), kandidáti = every word after a word `cd`, `pushd` or `-C` anywhere in the text with quotes
and backslashes removed that expands to an existing directory.

**Use in the hook.** Checked repos = the repo (`dk_set_project`) of every báza and every kandidát of all records, each
once; repos without config are skipped (§4.4 no-op). The to-be-committed set is built in each repo from all commits
and adds of the command (union of flags and pathspecs, as today), both checks (secrets, gate) run in each repo, the
deny lists findings per repo with `[dev-kit] repo <path>:` before each block when more than one repo denies, and the
instruction line for secret findings appears once. Before the findings, only in a deny, in this order (each with at
most 3 snippets joined by `; `; a snippet = the simple command as written, or `-C|--work-tree|--git-dir <target>`,
at most 60 chars, longer 59 + `…`):
- `U` (text of §4.4 unchanged): ``[dev-kit] cieľ `cd`/`git -C` sa nedal určiť (<úryvky>) — použi doslovnú cestu``
- `N`, only when one of the item's kandidáti lies in another repo than báza: ``[dev-kit] nie je isté, či `cd` pred
  commitom prebehne (<úryvky>) — kontrola zahŕňa aj jeho cieľ; spoj cd s commitom cez && alebo použi git -C <cesta>``
- `R`: ``[dev-kit] príkaz s commitom sa nedal rozložiť (<dôvod>) — spusti git commit samostatným príkazom``

**Fixtures.** UTF-8, LF; lines starting with `#` (the first one names the columns) and empty lines are skipped;
columns separated by exactly one TAB; `-` = empty. In `vstup` and `riadky`: `\n` = newline, `\t` = TAB, `\\` =
backslash, any other `\` is a fixture error (decoded in awk, not `printf %b`). Placeholders = `@` + one capital letter
not followed by a letter, substituted after decoding; expected snippets are truncated after substitution like the
hook does (59 + `…`).
- `tests/fixtures/cmd-parse.tsv`: `vstup`, `báza` (one per commit in order, space separated; `-` = no commit ⇒ allow),
  `kandidáti` (space separated, order free), `riadky` (`U:<úryvky>`, `N:<úryvky>`, `R:<dôvod>`, joined by ` ¦ `),
  `pozn.` (free text). Placeholders: `@R` session cwd and `CLAUDE_PROJECT_DIR` (repo with config), `@R/app` a plain
  directory in it, `@R/sub` a nested repo, `@O` another repo, `@H` the hook's `HOME` (repo), `@Q` repo `sp ace`, `@X`
  nonexistent; every repo has config and one staged secret `<letter>.ini`.
- `tests/fixtures/cmd-parse-closed.tsv`: `cwd`, `vstup`, `pozn.`. `@R` repo with config and a staged secret, `@O`
  repo without config, `@N` repo without config (also the hook's `HOME`), `@S` repo with config and a staged secret.
- Runner: end to end through `pre-bash.sh` (so the mutation test also runs against an older `pre-bash.sh` via
  `DK_SELFTEST_SCRIPTS`). Main table: the set of `<letter>.ini:1` findings = repos of báza ∪ kandidáti (`@R` and
  `@R/app` → `R`, `@R/sub` → `B`, `@O`, `@H`, `@Q`), the `U` / `N` / `R` lines exactly as `riadky` (none for `-`).
  Closed table: every row is a deny listing `R.ini` (cwd `@R`) or `S.ini` (cwd `@N`).

**Tables.** `cmd-parse.tsv` row `n` is checked by case `t_cmd_parse_<1–6>` (`n` mod 6), `cmd-parse-closed.tsv` by
`t_cmd_parse_closed_<1–3>` (`n` mod 3); the fixture column `pozn.` records where the commit really ran (`/bin/bash`
3.2.57 and zsh 5.9 with a `git` stub) and what `pre-bash.sh` of 0.3.1 checked. Mutation criterion of B15: with the
scripts of 0.3.1, 41 of the 62 main rows differ in báza ∪ kandidáti and 29 of the 41 closed rows are fail open.

### 4.5 `check.sh` — the single source of truth (`/dev:check`, Stop, commit, CI)
Usage: `check.sh [--quick|--full|--auto|--stop] [--session <id>] [--project <dir>] [--config <file>] [--files <rel>…]` —
flags in any order; `--files` consumes paths until the next `--` flag.
- Without hook stdin (called from Bash tool or CI). Reads config of `--project` (default `pwd`'s git
  toplevel; worktree rule in §4). No config ⇒ print `[dev-kit] chýba .claude/devkit.json — spusti
  /dev:project-init` exit 3; invalid JSON ⇒ `[dev-kit] <config> nie je platný JSON → jq . <config>` exit 3.
- Config override (CI, e.g. a copy with `"container": ""` when the runner has no compose): `--config <file>`
  (or `--config=<file>`), else env `DEVKIT_CONFIG` (empty = unset), replaces the project's config for this
  run; the project needs none of its own. A relative path is resolved against the caller's cwd, `--project`
  still sets the project. Missing file ⇒ `[dev-kit] config <path> neexistuje (--config, DEVKIT_CONFIG)` exit 3;
  `--config` without a value ⇒ `[dev-kit] --config bez súboru` + usage, exit 3. A file other than the project's
  config (`[ -ef ]`; the same file is no override) writes and removes no marker (`pass.json`, `partial.json`,
  `stop.json`): the commit gate and Stop vouch only for the project's config. Such a run prints `config: <path>
  (namiesto .claude/devkit.json; výsledok neodomkne commit)` before `log:` (within the 20 lines) and the log
  has `# config: <path>` after `# súbory:`. Stop (§4.6 step 4) clears `DEVKIT_CONFIG`.
- Mode: default `--quick`; `--auto` = full when any CHANGED file matches `fullWhen`, else quick. When
  `--auto` switches to full and no enabled step runs in only one of quick/full, the step lines start with
  `– full: rovnaké kroky ako quick` (not counted as skip).
- CHANGED files (quick/full/auto) = `git diff --name-only HEAD` ∪ untracked (`git ls-files --others
  --exclude-standard`) ∪ staged, deduped, existing files only (deleted tracked → recorded "-" in marker).
  Stop mode files = session files list ∪ `dk_session_newer` (§4.1; code changed outside on-edit since the session
  started), existing only.
- `--files` narrows the file set in every mode (quick/full/auto/stop); `pass.json` then records exactly
  those blobs, so `/dev:commit` can check only its group.
- Steps = config steps whose `modes` contain the mode (stop/quick/full; auto resolves first), and whose
  rule `step:<id>` is enabled. For each: `requires` (on the host), unknown `runtime` (blocked), then for a
  container step (effective runtime, §3) the container checks (with reason); a `runtime: host` step
  skips them and calls neither `docker` nor `dk_workdir`; if `run` exists
  and mode ≠ stop ⇒ run whole; else if `runFiles` exists ⇒ files filtered by `ext` (none ⇒ SKIP
  `žiadne zmenené súbory`; a step without `ext` gets only code files, `dk_is_code`, in stop mode only the
  Stop code files of §4.6 step 3), substitute
  `{files}`; in stop mode prefer `runFiles` when files exist, else
  `run` (for steps without ext, e.g. unit tests, always `run`). `changedLinesOnly` (`true` | `"stop"`,
  §3) filters like on-edit.
- Two kinds of skipped step. **Not applicable** (line `– <id>: <reason>`, verdict unaffected): missing
  `requires`, no changed files for its `ext`, tool output `No files were checked` without any finding
  line (`nástroj nič neskontroloval (No files were checked)`). **Blocked** — the step should run but could
  not (line `! <id>: <reason>`, verdict at most PARTIAL): container not running or worktree outside its
  mount, unknown `runtime`, no `run`/`runFiles`, exit 125–127, output without any finding line that matches `DK_RE_INFRA`
  (`chyba prostredia, nie kódu (<match>)`; Docker, missing files and the network errors of `composer`/`pip-audit`:
  `curl error <n> while downloading`, `could not be downloaded`, `Max retries exceeded`, `network may be blocking
  this service`). A finding line (`DK_RE_FINDING`) is a numbered line (`:<n>`, `on line <n>`), a Nette Tester
  `-- FAILED: ` line (Tester prints `file.phpt(<n>)`, so a failing test whose message says `No such file or
  directory` stays FAIL) or an audit header `Found <n> security vulnerability advisor…` / `known vulnerabilit…` /
  `abandoned package`. Both count in `<n> skip`.
- Each step: elapsed time, exit code, output (ANSI sequences stripped) appended to the full log file.
  Result PASS/FAIL/skip; knownFailures may turn FAIL into a non-failing step with note. Blocked steps are
  never FAIL.
- Output (stdout, ≤ 20 lines): `[dev-kit] check <mode>: PASS|FAIL|PARTIAL|SKIP · <n> ok[ · <n> známe] · <n> fail · <n> skip · <s> s`
  (`známe` only when > 0), one line per step `✓ phpstan 2,1 s` / `✗ unit 0,4 s` / `– phpcs: chýba
  vendor/bin/phpcs` / `! unit: príkaz sa nedá spustiť (exit 127)`, then for failing steps up to 8 most
  relevant output lines each (`DK_EXCERPT_RE`: PHPUnit, pytest, Tester `-- FAILED:` and its `Failed:` lines,
  `file:line` findings, errors, audit `Found <n> …`, `Package:`/`Advisory ID:`/`CVE:`/`Title:` and `pip-audit`
  rows; total cap 20), then the `config:` line of an override run, then `log: <path>`.
- Verdict and exit: some FAIL ⇒ FAIL, 1; else some blocked step ⇒ PARTIAL, 4; else ≥1 `ok` or `známe`
  ⇒ PASS, 0; else (nothing ran) ⇒ SKIP, 4. 3 = config error. Exit 4 = incomplete verification — never
  report it as PASS. CI treats every exit other than 0 as a failed job.
- On exit 0 in quick/full: write `pass.json` = `{"time":…,"mode":"quick|full","head":"<sha>","blobs":{"<rel>":"<blob sha or ->"}}`
  for the checked file set (CHANGED files, or exactly the `--files` set); PARTIAL never writes it.
  On PARTIAL in quick/full write `partial.json` = `{"time":…,"mode":"quick|full","ok":<n>,"steps":["<id>",…],"lines":["! <id>: <reason>",…]}`
  for the commit gate (§4.4): `ok` = steps `ok` + `známe` (what would still PASS with the blocked steps
  disabled), `steps` = ids of all blocked steps, `lines` = the first ≤ 5 `!` lines for display; any other
  quick/full verdict removes it, stop mode leaves it alone. Stop mode on PASS or PARTIAL writes `sessions/<session_id>.stop.json` (`{"hash":
  <dk_hash_files of the session code files, §4.6 step 3>, "time":…, "fails":0, "result":"PASS|PARTIAL"}`); the FAIL shape is
  written by `stop-check.sh` (§4.6 step 5). Markers are written
  via a per-process temp file and `mv`; an override run (`--config`/`DEVKIT_CONFIG`) neither writes nor removes them.
- Prune logs to the newest 20 per project.

### 4.6 `stop-check.sh` — Stop
1. No config / `stopCheck` false / rule `stopCheck` disabled ⇒ exit 0.
2. Reminders first, once per session (`pairs-<session_id>.done`), over the session file list incl.
   non-code files:
   - Pairs (N, rule `pair:<id>`): a session file matches `when` and no file of the `unless` set matches
     `unless` (each one glob or a list, §3) ⇒ add its `say`. The `unless` set = changed files (`dk_changed_files`) ∪ session files ∪
     `git diff --name-only <.head> HEAD` (only when `.head` holds a commit different from HEAD), so a
     test committed in the same turn still counts.
   - Removed tests (rule `testRemoved`): a test method/function removed in a session file (diff vs HEAD,
     e.g. `function test…` in PHP, `def test_…` in Python) ⇒ reminder naming file and test,
     `[testRemoved] <file>: zmazaná test metóda <name> — zámer s používateľom nie je overený`; a removed
     committed test file ⇒ `[testRemoved] <file>: zmazaný testovací súbor — zámer s používateľom nie je overený`.
3. Session code files = session files with extension in any `lint` key or in the `ext` of a step whose
   `modes` contain `stop` (absent `modes` = quick/full), plus such files changed outside on-edit since the session
   started (`dk_session_newer`, §4.1: changed vs HEAD and newer than `sessions/<id>.t0`), so a change made via Bash
   (`sed`, `git checkout`, a generator) starts the check, the guard scan and the hash below. Without `.t0` (a
   session older than the card that writes it) only the session files count. Known limitation: a file changed in
   that time by the user's editor or by another session in the same project counts too. A file checked only by quick/full steps (the
   templates' `eslint`/`stylelint` extensions `.js`, `.ts`, `.css`, `.scss`) does not start the check, and
   the guard scan of step 4 skips it (on-edit still scans it); the commit gate (§4.4) and `dk_blobs` still
   count every step's `ext`. Known limitation: a project's own quick/full-only step for an extension
   outside `lint` (e.g. `.twig` without a lint entry) does not trigger Stop either — add a `lint` entry or
   `stop` to the step's `modes`. `check.sh --stop` hashes and passes to steps without `ext` the same set. Shortcuts that
   skip the check (reminders from step 2 are still emitted): no code files; hash (`dk_hash_files`) equal
   to `hash` in the session's `stop.json` with last result PASS or PARTIAL; the same failing hash already
   reached the 3× cap. State is per session, so another session's result never resets this one's counter.
   Replay: the same failing hash with `fails` 1–2, a non-empty stored `reason` and an unchanged `ctx`
   (git blob hash over `devkit.json`, HEAD and the blobs of `dk_changed_files`, so a fix outside the
   session files or a new `knownFailures`/`disabledRules` entry runs the check again) ⇒ step 4 (check
   and guards) is skipped and step 5 blocks again from the stored `reason`; the header says
   `výsledok predošlej kontroly — súbory session sa nezmenili`. A `stop.json` without `reason` or `ctx`
   (older version) runs the check.
4. Run `check.sh --stop --session <id> --project <P>` with `DEVKIT_CONFIG` cleared (the project's config,
   like steps 1–3; §4.5) (+ guards over those files' added lines, because files may have been changed via Bash).
5. Output on stdout, exit 0:
   - Failure (check FAIL or guard finding) ⇒ `{"decision":"block","reason":"<≤20 lines>"}`; the reason
     says what failed and that it must be fixed before the turn ends, lists failing lines, guard findings
     (`[guard:<id>]`), reminders (`[pair:<id>]`, `[testRemoved]`) and `log: <path>`.
   - Reminders only ⇒ `{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"<reminders>"}}`
     (non-error feedback, no hook error shown to the user). The kit's reminder texts are facts, not
     instructions (§0 assumption 7); a pair's `say` is project text and passes as written. Capped by `dk_cap`.
   - Check PARTIAL (exit 4, verdict PARTIAL) ⇒ never block; add reminder `[partial] tieto kroky sa nedali
     spustiť, nie sú overené:` followed by up to 5 `!` lines.
   - Track consecutive failures for the same failure hash in the session's `stop.json` (`fails`), so the same
     failure blocks at most 2× (`blok 1/2`, `blok 2/2`); when it reaches 3 (the 3× cap) ⇒ do not block, instead `{"systemMessage":"[dev-kit] kontrola stále padá (3×) — blokovanie vypnuté pre tento stav, pozri <log>; vypnutie: disabledRules stopCheck"}`
     plus `hookSpecificOutput.additionalContext` when there are reminders.
   - Every failure (blocked, replayed or capped) writes `stop.json` = `{"hash":<session hash>,"time":…,
     "fails":<n>,"failHash":<session hash>,"result":"FAIL","reason":"<≤ 18 lines: failing check lines,
     guard findings, reminders — the block reason without its header and log line>","log":"<path>",
     "ctx":"<sha>"}`. A replay puts reminders that are new in this Stop in front of the stored `reason`.
   - `stop_hook_active` true is allowed (we cap ourselves).
6. Container down / blocked step / nothing ran ⇒ never block on infrastructure; reminders still go out as in step 5.
   `check.sh` exit outside 0/1/4 (3 = config or arguments, 2 or ≥ 5 = the script itself failed) ⇒ no block,
   `errors.log` entry, decision `skip` (never `pass`) and reminder `[check] kontrola sa nedala spustiť (exit N),
   dôvod je v <DK_DATA>/errors.log`.

### 4.7 `session-card.sh` — SessionStart (one JSON object on stdout, card ≤ 10 lines, < 1 s)
- stdout = one JSON object: `hookSpecificOutput.additionalContext` (`hookEventName` `SessionStart`) =
  the card (context for Claude, facts without imperatives, §0 assumption 7); top-level `systemMessage` =
  user-facing warnings only (jq, docker, container down, maintenance, worktree, Claude Code version,
  devkit.json change, outdated templates), omitted when there are none. Both go through `dk_cap` (§4).
- No jq ⇒ print a static JSON object (built without jq) whose message says `[dev-kit] chýba jq → hooky
  kitu nebežia (brew install jq)`, exit 0.
- No config: if P has composer.json|pyproject.toml|package.json and `card-hint.<today>` absent ⇒ hint
  `[dev-kit] projekt nemá .claude/devkit.json — /dev:project-init ho nastaví` and create the marker.
- With config and `source` `startup`, `resume` or `clear` (empty = `startup`), the card first creates
  `sessions/<id>.t0` when it does not exist (§2; `compact` keeps it, so its mtime stays the session start).
- With config, the card:
  1. `[dev-kit] <stack> · kontajner <c> (beží|NEBEŽÍ — kontroly sa preskočia) · Stop kontrola on|off · commit gate on|off`;
     `container` set but no `docker` on PATH ⇒ `chýba docker → kontroly v kontajneri sa preskočia` in the
     container slot of this line (also a `systemMessage` warning); `container` set but no step and no lint
     command runs in it (all `runtime: host`, §3) ⇒ `kontroly na hoste (kontajner <c> sa nepoužíva)`,
     without a docker call or warning
  2. `kontroly: /dev:check (quick) · /dev:check --full · /dev:commit`
  3. `git: <branch> · <N> zmenených súborov` + up to 3 lines of `git status --short`
  4. last handoff if < 24 h: `posledný handoff: <title> (pred <h> h) → <path>`
  5. worktree without `vendor/` while MAIN has it ⇒ `worktree nemá vendor/ → rieši ho .worktreeinclude alebo composer install`;
     stack python: worktree without `.venv/` while MAIN has it ⇒ `worktree nemá .venv/ → nový venv: uv sync alebo …`
  6. maintenance, only when `<kit>/tools/upstream.sh` exists, `<kit>` = `$DK_SCRIPTS/../../..` resolved
     physically (`cd -P … && pwd`), i.e. the plugin runs in place from a kit checkout; a marketplace
     install never shows it:
     `$DK_DATA/maintenance.json` missing (or without a numeric `lastUpstreamCheck`) ⇒
     `údržba kitu: kontrola upstreamu ešte nebežala → make -C <kit> upstream`;
     older than 30 days ⇒ `údržba kitu: posledná kontrola upstreamu pred <d> dňami → make -C <kit> upstream`
  7. test lock active ⇒ `zamknutý test: <files> (do <time>)`
  8. Claude Code version older than `DK_MIN_CC` ⇒ warning line; the version check runs at most once a
     day (result cached in `$DK_DATA`)
  9. devkit.json changed since the snapshot (`dk_cfg_trust` without `note`, §4.1; any source, the card
     neither reads nor writes `.cfgnote`) ⇒ `devkit.json sa zmenil od poslednej session: <N> príkaz|príkazy|príkazov
     (lint/kroky)`, N = new or changed commands (0 when only other keys changed); the `systemMessage` warning
     adds ` — skontroluj diff` for the user. The next start without a change prints nothing.
  10. templates copied from an older kit, once per session (marker `sessions/<id>.tplnote` written when the
     comparison runs): the oldest `@ <VER>` (a leading `v` dropped) of the header lines `<!-- dev-kit: <path> @ <VER> -->`
     in `.claude/rules/*.md` and `REVIEW.md` and `# dev-kit: <path> @ <VER>` in `.worktreeinclude` (§6) is older than
     `version` in `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` (x.y.z compared numerically) ⇒ `šablóny z kitu
     <oldest> (aktuálna <version>): /dev:project-init --sync`, also as a `systemMessage` warning. No header ⇒ nothing.
  Optional lines 4–10 are one line each and take precedence over the `git status` lines, so all of them fit in 10.
- Subcommand outside the hook (used by `/dev:handoff`): `session-card.sh --record-handoff <path> <title>
  [--project P]` (P defaults to `pwd`, stdin is not read) writes `last-handoff.json`
  `{"time":<epoch>,"title":"…","path":"…"}` for card line 4; an absolute path inside P is stored relative,
  `./` is stripped, an empty title becomes the file name. Prints one line `[dev-kit] handoff zaznamenaný:
  <title> → <path> (úvodná karta ho ukáže 24 h)`, exit 0; no path ⇒ usage line, exit 2; no jq or a failed
  write ⇒ one `[dev-kit]` line, exit 1.

### 4.8 `test-lock.sh` (called by /dev:fix)
`test-lock.sh lock <rel>… [--project P]` | `unlock [--project P]` | `status [--project P]`. Writes
`test-lock.json` `{"files":[…],"time":…,"ttlHours":…}`. Prints one Slovak line. Exit 0.

### 4.9 `stats.sh` (V8, called by /dev:stats)
`stats.sh [--days 30] [--project P|--all]` → scope = project from `pwd` (or `--project`) by default,
`--all` = every project; reads decisions.jsonl, prints ≤ 20 lines: `obdobie: N dní`, counts per hook+rule
(block/deny/ask/warn/pass), top 5 noisiest rules, stop-check block rate, commit-gate denials and the
`PASS na prvý raz` share (commit gate attempts grouped by the content key from §4.4), average ms per
hook. Exit 0.

### 4.10 `pre-compact.sh` — PreCompact (no matcher: `manual` and `auto`)
- Output channel. `hooks.md` lists no `additionalContext` for PreCompact (only SessionStart, SubagentStart,
  UserPromptSubmit/Expansion, the tool events, Stop/SubagentStop and PostModelSwitch take it) and says Claude Code
  discards a PreCompact hook's `systemMessage` and `continue`; exit 2 or `decision: "block"` would block the
  compaction, which the kit never does. The stdout of a successful, non-blocking run is plain text that Claude
  Code appends to the compaction's custom instructions (after the user's `/compact <instructions>`) and, on a
  manual `/compact`, shows to the user as `PreCompact [<command>] completed successfully: <output>` (CLI
  2.1.308; the 2.1.314 changelog caps each PreCompact hook's output at 10 000 characters). A compaction inside
  a subagent ignores it. So the script prints plain text, never JSON — a JSON object would land in the
  instructions verbatim. The facts reach Claude through the summary; the card after compaction (SessionStart
  `compact`, §4.7) still runs.
- No jq, no config or config jq cannot read ⇒ exit 0, no output. No fact below ⇒ no output.
- Otherwise ≤ 10 lines, facts only (no imperatives, `hooks.md` "Add context for Claude"): the header
  `[dev-kit] stav session pred kompakciou (fakty pre súhrn):`, then each line only when its source exists:
  - `- súbory session (<N>): <a>, <b>, …` — the first 8 of `sessions/<session_id>.files`, then ` · … ďalšie: <K>`
  - `- posledná Stop kontrola: PASS|PARTIAL|FAIL, <time>` — `sessions/<session_id>.stop.json` of this session only
  - `- posledný PASS /dev:check: quick|full, <time>` — `pass.json` (§4.5)
  - `- zamknutý test (/dev:fix): <files> (do <time>)` — an active lock (`dk_lock_read`, ttl `testLock.ttlHours`)
  - `- posledný handoff: <title>, <time> → <path>` — `last-handoff.json` younger than 24 h (card line 4, §4.7)
  `<time>` = local `dd.mm. HH:MM` (the summary may be read on another day). The text goes through `dk_cap`
  (`jq --arg`, §4). Reads only, writes no marker, exit 0 always.

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
| `commit` | the user's original command `commit` (keep ALL its rules: `[#XX] type: výstih`, one confirmation, explicit `git add <files>`, never push, never `--no-verify`, never amend unless asked, NO Co-Authored-By / AI attribution) | step 0: `check.sh --auto` must PASS (the hook gate enforces it anyway); show grouping+message+check result in ONE message; secrets reminder |
| `review` | the user's original commands `review` (format with 🔴🟡🔵, numbering, verification, `.review-notes.md` only on request) and `security` (as `--security` pass) + ECC `agents/code-reviewer.md`, `skills/security-review` | scopes: none = uncommitted, `branch [base]`; passes Bugs · Security · Súlad s `docs/plans/*.md` (V1) · stale CLAUDE.md/rules (V9); read project `REVIEW.md` if present (V2: Important vs Nit, max 5 nits, do-not-report list); confidence > 80 %, merge similar, security first; Nette/Symfony/Python checklists; optional delegation to agents `dev:ecc-silent-failure-hunter`, `dev:ecc-performance-optimizer` for large diffs |
| `test` | the user's original command `test` + ECC `skills/tdd-workflow` | RED→GREEN→REFACTOR with evidence, AAA, naming, mirror structure, run via `check.sh`-configured command or `dk`-style docker exec from devkit.json; PHPUnit + pytest branches |
| `debug` | plan §5 Debugging row | Nette: Tracy `log/exception*.html`, `log/*.log`, docker logs, mail catcher (e.g. Mailpit) and search server (e.g. Typesense) health when compose has them, login via the project's gitignored test login file when it has one (named in its `CLAUDE.md`), `EXPLAIN`; Symfony: `var/log`, profiler, `bin/console debug:*`; Python: traceback/pytest -x; hypothesis → minimal repro → fix suggestion; never guess |
| `fix` | ECC `commands/orch-fix-defect.md` | facts first (where, who calls, data); write failing repro test; run, confirm it fails for the expected reason; `test-lock.sh lock <test>`; fix code without touching the test; `check.sh --auto`; on PASS `test-lock.sh unlock`; offer `/dev:review` and `/dev:commit`. `--unlock` argument ⇒ only unlock and report |
| `plan` | plan §18 V1 | write `docs/plans/<task>-<slug>.md` (no `#`) (Úloha+zdroj, Súbory, Poradie, Riziká, Dôkaz, Mimo rozsahu) from the agreed plan; task number from branch; small tasks (≤ 3 files, no risky paths) ⇒ tell the user it is not needed; local mode (`docs/plans/` ignored) ⇒ the plan stays on disk, never committed; team mode ⇒ committed with the first change, deviations in the same commit |
| `learn` | ECC `commands/learn.md` + `learn-eval.md`, plan §13 | scan session for user corrections, resolved errors, discovered conventions ⇒ propose each as: native memory entry (feedback/project), project `.claude/rules/*.md` line, or new `guards`/`pairs` entry in devkit.json; user approves one by one; write only approved |
| `handoff` | plan §14 Kontext row | write state (hotové, rozpracované, ďalší krok, rozhodnutia, zmenené súbory, príkazy na overenie) to `handoffDoc` from devkit.json (append dated section) or `docs/handoff.md`; record it with `session-card.sh --record-handoff <path> <title> --project "${CLAUDE_PROJECT_DIR}"` (§4.7); then suggest `/clear` |
| `explain` | the user's original command `explain` | same structure (Čo to robí / Ako to funguje / Závislosti / Riziká pri zmene), Slovak, depth by request |
| `stats` | §4.9 | run `stats.sh $ARGUMENTS`, interpret: which rules are noisy, propose `disabledRules`/pattern tweaks, never change config without approval |
| `project-init` | ECC `skills/codebase-onboarding`, `commands/project-init.md`, plan §4.4, §14 PHP prax (infer-conventions), §16 P5, §17, §18 V2/V4/V6/V9 | see §6 |

Reference skills — model-invocable, short descriptions (always-on budget for the whole plugin ≤ 3k
tokens, measured by `tools/details.sh` by the docs rule: `disable-model-invocation` skills count 0;
the `claude plugin details` estimate depends on login and model, so the budget is checked logged in):
| name | from ECC | `paths` | notes |
|---|---|---|---|
| `ecc-mysql-patterns` | `skills/mysql-patterns` | `db/**`, `migrations/**`, `**/*Model.php`, `**/*.sql`, `**/Entity/**`, `**/Repository/**` | MySQL 5.7/8, Dibi + Doctrine parametrization, EXPLAIN, indexes, N+1 |
| `ecc-e2e-testing` | `skills/e2e-testing` | `tests/e2e/**`, `**/*.spec.js`, `**/*.spec.ts`, `playwright.config.*` | Playwright POM, flaky handling; drop Vercel/npm-specific bits |
| `ecc-change-impact` | `skills/change-impact` | — | before risky changes in core (validators, triggers, public API) |
| `ecc-accessibility` | `skills/accessibility` | `**/*.latte`, `**/*.twig`, `www/css/**`, `assets/**/*.css`, `templates/**` | WCAG 2.2, server-rendered templates (no React) |
| `ecc-production-audit` | `skills/production-audit` | — | `disable-model-invocation: true` (user runs before deploy) |
| `ecc-python-patterns` | `skills/python-patterns` | `**/*.py` | F7 |
| `ecc-python-testing` | `skills/python-testing` | `tests/**/*.py`, `**/test_*.py`, `**/*_test.py` | F7, pytest |
| `task-tldr` | the user's original skill `task-tldr`, example rewritten to a generic domain (e-shop) | — | user's own skill; its 399-char description is accepted; the installer moves the original to a backup |
Adaptation rules for every `ecc-*` piece: dir AND frontmatter `name` = `ecc-<original>`; keep the
original description meaning; translate body to Slovak and trim (output stručne, ale úplne (§0), no "80 % coverage" mandates, no
conventional-commit rules, no npm/Node assumptions, `docker exec` instead), keep the best checklists; add
a first line comment `<!-- prevzaté z ECC <path> @ b92f181, upravené -->` after frontmatter.

## 6. `project-init` skill (most complex)

Arguments: none | `--sync` | `--dry-run`.
Consent is asked in four named phases only, each with one message: (1) plan — the dry-run incl. the exact
`permissions` block before → after and the local/team choice with its exact `info/exclude` and
`.worktreeinclude` lines or `.gitignore` diff; (2) write + `check.sh --quick` — nothing new, consent only to
resolve check findings (`knownFailures`, baseline, `changedLinesOnly`, dropping a step, `--full`);
(3) conventions, one by one; (4) `CLAUDE.md`/`AGENTS.md`/`CLAUDE.local.md` diff with the move map. At most
4 questions per init, all in the plan message (an unclear stack is asked first and counts).
1. Detect: stack (composer.json → nette/symfony; pyproject/requirements → python); for php-nette the DB layer
   from `require` only (`dibi/dibi` → dibi, `doctrine/orm`/`nettrine/orm` → doctrine; several ⇒ show evidence and
   ask) and Doctrine console command names; `AGENTS.md` and whether `CLAUDE.md` imports it (`@AGENTS.md`);
   the project's verification rules (PHPStan config, baseline policy, test runner); container (docker
   compose files: container_name + mounts → appRoot), tools present in `vendor/bin` / venv, phpstan
   config path, phpunit suites, phpcs ruleset, existing CLAUDE.md size, `.claude/` contents, git remote,
   the gitignored test login file (`{{testCredentialsFile}}`; content never read, none ⇒ its template line is deleted).
   No compose (or a mount of a subdirectory only) ⇒ `container: ""`, `appRoot: ""`; the plan says that lint
   and steps run on the host and `appRoot` is unused, and shows each tool checked on the host
   (`command -v`, `vendor/bin/<tool>`, `.venv/bin/<tool>`); a missing tool drops its step. Question 1 also
   covers compose that mounts only a subdirectory (the kit cannot run steps there from the repo root: host, or
   the user changes the mount to the repo root).
   No step with `run` and mode `quick` whose tool init found ⇒ `/dev:check` ends SKIP (exit 4, neither
   `pass.json` nor `partial.json`) and the commit gate blocks such a commit with no escape — every commit with
   no steps; with `runFiles`-only steps every commit without an existing file of their extensions, a commit
   that only deletes files included (steps get existing files only, the gate counts deleted ones too). The plan
   says so, its `devkit.json` draft has `commitGate.enabled: false` also with `runFiles`-only steps (a narrowed
   `commitGate.ext` does not cover deletion; secrets, guards, lint and Stop keep running) and question 1 offers
   a container or host tools instead (an answer that brings such a step back sets `enabled: true`).
   Frontend (php-nette, php-symfony): `package.json` with `eslint`/`stylelint` in `dependencies` or
   `devDependencies` plus its config ⇒ step `eslint`/`stylelint` and its extensions in `commitGate.ext`;
   otherwise both are dropped without a question (a missing `node_modules` only keeps the step, `requires`
   skips it until the user installs the dependencies; init never runs `npm install`).
   Dependency audit: step `audit` (full only) for php when `composer` exists in the container (`docker exec <c>
   sh -c 'command -v composer'`, the only `docker exec` of point 1) — no `runtime` — or only on the host
   (`command -v composer`) — `runtime: host`; for python when `pip-audit` is in the project's tool directory
   (`{{bin}}`; `--aliases` needs 2.7+). No tool ⇒ the step is dropped and listed.
   Nette Tester (php-nette): executable `vendor/bin/tester` and `*.phpt` files under `tests/` ⇒ step `tester`
   (`php vendor/bin/tester tests -s -C`) instead of `unit`/`integration` when the project has no PHPUnit;
   with PHPUnit both, `tester` only over the directory of the `.phpt` tests (Tester runs `*Test.php` too);
   without Tester the step and the `.phpt` lint key are dropped.
   Phinx (php-nette): executable `vendor/bin/phinx` and a config in the root, in Phinx's lookup order
   `phinx.php`, `phinx.json`, `phinx.yaml`, `phinx.yml` (another file only from `-c`/`--configuration` in the
   `Makefile` or composer scripts) ⇒ `migrations.paths` = `<path>/**` for every path of `paths.migrations` (a
   string, a list, or a namespace ⇒ path map; `%%PHINX_CONFIG_DIR%%` and `__DIR__` = the config's directory,
   other relative paths are from the directory phinx runs in, the repo root; a Phinx `*` stays, `{a,b}` becomes
   several entries), a path outside `db/` and `migrations/` also goes to `fullWhen`, `{{migrationsDir}}` = the
   first path, and a config outside the root adds `-c <config>` to the migrate command in `CLAUDE.md`.
   `phinx.php` is read as text (grep), never executed — neither `php phinx.php` nor any `phinx` command
   (Phinx loads it with `include`: project autoload, possibly a DB connection); a value built from a
   variable, function, constant or `getenv` is undetected ⇒ question 4 with a candidate (the directory of
   `<14 digits>_*.php` files). Without Phinx the template's `migrations.paths` stays.
   Doctrine migrations (php-nette, config read, never run): `migrations_paths` (namespace ⇒ path) of Doctrine
   Migrations (`migrations.php`, `.yml`, `.xml`, `.json` in the root or the `--configuration` file); for
   nettrine/migrations the neon section that `extensions:` registers as `Nettrine\Migrations\DI\MigrationsExtension`
   (usually `nettrine.migrations`) with `directories:` (namespace ⇒ path; older `directory:`), where `%appDir%` =
   the directory of `Bootstrap.php` (usually `app/`), `%rootDir%` = the project root, `%wwwDir%` = the directory
   of `index.php` (another parameter ⇒ undetected); without a config the directory of `Version<14 digits>.php`
   files ⇒ `migrations.paths` = `<path>/**` for every path, `{{migrationsDir}}` = the first. Undetected ⇒ pair
   `doctrine-entity-migration` is dropped and the plan says the template's `migrations.paths` stays.
   Placeholders: the skill's table „Zástupné symboly“ lists every `{{name}}` of the stack templates with
   its detection source and what to do when undetected; undetected ⇒ deleted without a question (the line,
   or the smallest part of it that needs the symbol; a version keeps the name; a `devkit.json` step or pair
   that needs it is dropped and listed). A tool whose step or lint init dropped loses its lines and mentions in
   `CLAUDE.md.tmpl` the same way, placeholder or not (Príkazy row, Kvalita/Stack, Overovanie práce sentence).
   Questions only for `{{projectDescription}}`, `{{commitStyle}}`
   (no usable git history), `{{container}}` (no compose) and `{{migrationsDir}}` when a Phinx config exists
   but `paths.migrations` cannot be read without running it. `{{dbContainer}}` is text in `CLAUDE.md`, not
   a `devkit.json` field. Selftest `t_templates_symbols` keeps the table complete.
2. Dry-run plan shown to the user BEFORE writing anything: files to create/modify, devkit.json draft,
   which template rules, `permissions` block before → after, local-only vs team (commit) choice with its
   exact lines, layer-B skills offered (`templates/skills/*`). The plan says next to step `audit` that
   `/dev:check --full` sends the project's package list (names and versions) to Packagist (`composer audit`) or
   PyPI (`pip-audit`); approving the plan is the consent to it (no separate question), an answer that declines
   it drops the step. Approving the plan covers new files and the changes it showed exactly; any other
   existing file is never overwritten without explicit consent (diff).
   Project rules win over the template: conflicts are listed as `template:line ↔ file:line`, a conflicting
   template rule is not copied without consent, and baseline/`changedLinesOnly` are not offered when the
   project rules exclude them.
3. Verify every check step by running it once (via the same exec logic as check.sh — call
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh" --quick --project "${CLAUDE_PROJECT_DIR}"` after writing devkit.json) and
   record baseline failures as `knownFailures` only with user consent. SKIP with the commit gate on and no
   `quick` step with `run` that runs ⇒ the same proposal as in point 1 (`commitGate.enabled: false`, also with
   `runFiles`-only steps), consent of phase 2.
4. Copy template files with a header: markdown → `<!-- dev-kit: <template>/<file> @ <plugin version> -->`
   (YAML-frontmatter files get it right after the frontmatter); `.worktreeinclude` → `# dev-kit:
   <template>/<file> @ <plugin version>`; JSON (`devkit.json`, `settings.json`) → no header (`--sync`
   compares by id/keys). Rules are copied, never symlinked.
5. infer-conventions: list well-evidenced, non-default conventions found in code (with evidence
   file:line), skip what phpcs/PHPStan/rector enforce; user approves each; write approved into
   `.claude/rules/conventions.md`.
6. AGENTS.md present ⇒ project content goes to `AGENTS.md` (diff, consent; never split into rules) and
   `CLAUDE.md` = `@AGENTS.md` import + Claude-only parts; a textual mention is replaced by the import; never
   create `CLAUDE.md` without the import (Claude Code reads `AGENTS.md` itself only when no `CLAUDE.md`
   or `CLAUDE.local.md` exists); local mode ⇒ import and Claude-only parts go to `CLAUDE.local.md`.
   CLAUDE.md: propose a skeleton ≤ 120 lines (Projekt, Stack, Príkazy with healthy-output examples
   (V9), Architektúra, Pravidlá, Pasce, `## Compact instructions`) built from the existing CLAUDE.md, moving
   topic sections into `rules/*.md` with `paths:`. Large rewrite only with consent; preserve every
   rule that would cause a regression if lost (list what moved where).
7. Team vs local (decided in the plan, phase 1): local ⇒ add `.claude/rules/`, `.claude/devkit.json` etc., `CLAUDE.local.md`, `.claude/worktrees/`, an
   untracked `handoffDoc` and `docs/plans/` to `.git/info/exclude` (local mode puts nothing from the kit into git), and `.claude/rules/`, `CLAUDE.local.md`, `REVIEW.md`, `docs/plans/` to `.worktreeinclude` (so
   new worktrees get the untracked files); local mode never creates a new `CLAUDE.md` — the filled skeleton
   goes to `CLAUDE.local.md`; team ⇒ leave for commit (do not commit yourself) and propose
   `.claude/worktrees/` for `.gitignore`.
8. `--sync` (P5): for each project file with a `dev-kit:` header (JSON files: by template id/keys),
   compare with current template version; show per-file diff and propose update keeping local edits;
   update header version. A JSON item with an existing id gets the new template value (with consent) only
   when the project still holds the value of the template version it came from; an item the project
   changed is listed with its difference, never overwritten. A new `eslint`/`stylelint` step is proposed only
   when the frontend detection of point 1 finds the tool, together with its extensions for `commitGate.ext`;
   a new `tester` step only when point 1 finds Nette Tester, together with `.phpt` for `lint` and `commitGate.ext`;
   Phinx or Doctrine migration paths of point 1 that `migrations.paths` does not cover are proposed as `<path>/**` (outside `db/`
   and `migrations/` also for `fullWhen`); a new `audit` step follows the detection of point 1 and is written
   only after consent to sending the package list.
   A renamed placeholder keeps its old name in the table (`entityGlob` = `{{entityDir}}**`), so the old
   template version is filled from the project too.
9. Final report stručne, ale úplne (§0): what was created, what to commit, how to undo.

## 7. Templates (`ROOT/templates/`)

```
common/REVIEW.md                 # V2: passes Bugs · Security · Súlad s plan.md; Important vs Nit; max 5 nits; do-not-report placeholders
common/plan.md                   # V1 template
php-nette/CLAUDE.md.tmpl         # skeleton with {{placeholders}}, ≤ 120 lines incl. verification block (V9) and `## Compact instructions`;
                                 # commands use `{{run}}` like php-symfony (`docker exec <c> ` or empty for `container: ""`);
                                 # DB-dependent lines end with `<!-- db:dibi -->` / `<!-- db:doctrine -->`, table rows carry it before the
                                 # last `|` (init keeps one variant, strips the marker with the space before it)
php-nette/devkit.json            # like §3 example with {{container}}, {{appRoot}}, {{phpstanConfig}} placeholders; `_init` notes;
                                 # items with id `doctrine-*` (step doctrine-schema, guard doctrine-dql-concat, pair doctrine-entity-migration) only for Doctrine;
                                 # guards debug-php (+ bdump) and die use the php-symfony patterns: `->exit(`, `::dump(`, `$exit` are not findings;
                                 # pair model-test `when` = app/models/**, app/model/**, app/Model/** (like fullWhen);
                                 # pair doctrine-entity-migration `when`/`unless` = `{{entityDir}}**` / `{{migrationsDir}}**`;
                                 # optional frontend steps `eslint` (.js, .ts) and `stylelint` (.css, .scss; `--allow-empty-input
                                 # --formatter unix`): `runtime: host`, `requires: node_modules/.bin/<tool>`, quick/full, no changedLinesOnly
                                 # on eslint (stylish output has no path on the finding line); their extensions are in `commitGate.ext`,
                                 # not in the Stop code files (a .js/.css-only turn does not start Stop, §4.6 step 3)
                                 # and init keeps both only with the tool (§6); guards `console-log` (`console.(log|debug)(`) and
                                 # `inner-html` (assignment incl. `+=`, not `==`/`===`) on .js/.ts are kept always;
                                 # optional step `tester` (Nette Tester, `php vendor/bin/tester tests -s -C`, `requires:
                                 # vendor/bin/tester`, stop/quick/full) instead of `unit`/`integration` without PHPUnit; `.phpt` has
                                 # lint `php -l` (a Stop code extension) and is in `commitGate.ext`; guards `debug-php` and `test-skip`
                                 # (also `Environment::skip(`) cover `.phpt`;
                                 # step `audit` (`composer audit --no-interaction --format=plain`, `requires: composer.json`, full only,
                                 # no changedLinesOnly — no line numbers; `runtime: host` when only the host has composer); init adds it
                                 # only with the plan's consent to sending the package list to Packagist (§6)
php-nette/settings.json          # permissions.ask (V4: make db-import*, docker stop/restart/rm * (any container), git push*, git checkout*/git switch*, Doctrine commands that change the DB, migration history or files (`*migrations:migrate*` incl. `--dry-run`, `*migrations:diff*`, `*schema:update*`, `*schema-tool:*`, `*dbal:run-sql*`, …; inert in Dibi projects), Phinx commands that change the DB (`*phinx migrate*`, `*phinx rollback*`, `*phinx seed:run*`, `*phinx breakpoint*`, right after the Doctrine rules; `phinx status`, `create`, `seed:create` stay free; inert in Doctrine projects); project-init adds existing Makefile targets that stop/rebuild containers or change the DB/index) + permissions.deny (O: Edit(/vendor/**), Edit(/node_modules/**) …, anchored to the project root)
php-nette/.worktreeinclude       # V6: vendor/, app/config/config.local.neon, .test-credentials
php-nette/rules/php-core.md      # paths: **/*.php — PHP 8.x, PSR-12, strict types where project uses them, no die(), no @
php-nette/rules/nette.md         # paths: app/**, libs/** — presenters, DI, forms CSRF, ACL isAllowed
php-nette/rules/latte-frontend.md# paths: **/*.latte, www/css/**, www/js/** — escaping, {!$} policy, data-bs-*, JS anchors, frontend guards and steps
php-nette/rules/db-dibi.md       # paths: db/**, **/*Model.php, phinx.{php,json,yaml,yml} — Dibi 4+ fetch null, params, no begin/commit in models, Phinx (directory from `paths.migrations`)
php-nette/rules/db-doctrine.md   # paths: **/Entity/**, **/Repository/**, **/migrations/**, app/config/*doctrine*.neon — Doctrine ORM + Migrations in Nette; copied instead of db-dibi.md
php-nette/rules/tests.md         # paths: tests/** — suites, rollback tests, credentials, verification output (PHPUnit and Nette Tester)
php-symfony/…                    # same shape: CLAUDE.md.tmpl, devkit.json, settings.json, .worktreeinclude, rules/{php-core,symfony,twig-frontend,doctrine,api-platform,tests}.md;
                                 # devkit.json has the same frontend steps, guards, `commitGate.ext` extensions and `audit` step as php-nette
python/…                         # CLAUDE.md.tmpl, devkit.json (pytest, ruff, mypy; host or container; {{bin}} placeholder, _init note key), settings.json, .worktreeinclude, rules/{python-core,tests}.md;
                                 # guards also cover `.ipynb` (cell source lines in the notebook JSON, NotebookEdit); no `.ipynb` lint —
                                 # ruff reports notebook findings as `cell N:<line>`, which the changed-lines filter (§4.2) cannot map;
                                 # step `audit` (`{{bin}}pip-audit --progress-spinner off --aliases on`, `requires: {{bin}}pip-audit`, full
                                 # only; audits the environment it runs in, sends the package list to PyPI — plan consent like php)
skills/ecc-design-system/  skills/ecc-api-design/  skills/ecc-inherit-legacy-style/  skills/ecc-seo/   # layer B, copied into <project>/.claude/skills/ on request
```
Template content is GENERIC for the stack (no project specifics, no project names, no data).
All templates use the same placeholder name for the same thing (`{{projectDescription}}`, `{{run}}`, …)
and the same compaction heading `## Compact instructions`. A directory placeholder (`{{entityDir}}`,
`{{repositoryDir}}`, `{{migrationsDir}}`) ends with `/` and is the only name for that directory: a glob in
`devkit.json` is written as `{{entityDir}}**`. A placeholder named like a `devkit.json` key means that key
(`{{container}}`, `{{appRoot}}`); python's environment line uses `{{pythonEnv}}`, because `runtime` is reserved
for the step field. Every placeholder has a row in the project-init table (§6), checked by `t_templates_symbols`.
Deny rules in `settings.json` start with `/`
(relative to the settings source = project root, permissions.md). `changedLinesOnly: "stop"` on phpstan
(php-nette, php-symfony) and mypy (python). Stop mode runs only fast steps: tests without the slow ones
(php-nette `--testsuite unit`, php-symfony `--exclude-group integration` or the fast `<testsuite>` that
init picks from `phpunit.xml`, python `-m 'not slow and not integration'`); slow tests are a separate
step with `modes: ["full"]` (`integration`; python the whole `pytest`). php-symfony `settings.json` has the
same `ask` rules as php-nette (`migrations:migrate` is not in the template's command list, it runs only on
request); its broader deny is intended. The PHPStan baseline wording is the same in both PHP templates:
„nový nález oprav v kóde; baseline sa regeneruje len na pokyn používateľa“.
Source material: `CLAUDE.md` of real Nette and Symfony projects — read-only — plus the
user's global `CLAUDE.md` rules. Each rule file ≤ 60 lines, with a `## Pasce` section.

## 8. Agents (`ROOT/agents/*.md`)

From ECC `agents/<name>.md`, renamed `ecc-<name>`, Slovak, trimmed. Frontmatter: `name`, `description`
(≤ 200 chars), `tools: Read, Grep, Glob, Bash`, `disallowedTools: Edit, Write, NotebookEdit`, `model`
(`sonnet` for pr-test-analyzer and a11y-architect; `inherit` for silent-failure-hunter and
performance-optimizer), `maxTurns: 30`. No `memory` (it would enable Write/Edit and create
`.claude/agent-memory-local/` in projects); agents stay read-only, and silent-failure-hunter and
pr-test-analyzer may end with an optional line `Na zapamätanie: <poznatok → .claude/rules/<súbor>.md>`,
a suggestion that `/dev:learn` writes to project rules after approval (subagents load project rules).
Revisit `memory: user` in F6 if agents keep repeating the same false positives; the pre-edit guard
(`agentReadOnly`, §4.3: writes only under the user's `agent-memory/`) is already in place for that. No `isolation`. Body: read-only analysis; Bash only for read-only commands (git
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
  VERSION=x.y.z` (bump plugin.json, remind CHANGELOG, `claude plugin tag --dry-run plugins/dev`), `eval`
  (= `claude plugin eval plugins/dev --ablation with-without --scaffold --allow-tools Bash Edit Write
  $(EVAL_ARGS)`; not part of `check` — every agent run and every `llm` judge call costs tokens).
- `plugins/dev/evals/` — eval suite of the command skills for `claude plugin eval` (docs `plugin-evals.md`).
  A case = `<case>/prompt.md` (frontmatter: `description`, `expected_outcome`, `max_turns`,
  `timeout_seconds`, `allowed_tools`; body: the `/dev:*` command, expanded by `claude -p`), `case.yaml`
  (`schema_version: "1.1"`, `name`, `context.scaffold_script: scaffold.sh`), `scaffold.sh` (must live in
  the case dir; calls `../fixtures/scaffold.sh` with its variant) and `graders/*.md` (one grader per file,
  options in frontmatter, `llm` criteria in the body). The command skills are `disable-model-invocation`,
  so no `tool_used: Skill`; graders on kit mechanics (`check.sh`, `test-lock.sh`, their order) are
  `arm: with-only`:
  | case | prompt | graded |
  |---|---|---|
  | `check-partial` | `/dev:check` | `check.sh` ran; reply has `PARTIAL`, no `check <mode>: PASS`; no `docker (compose) start/restart/run/up`; llm: step `integration` named, container start only proposed |
  | `commit-no-attribution` | `/dev:commit` with the approval given in the argument | `.git/COMMIT_EDITMSG` is one line `[#12] <type>: …` (number from branch `feature/12-pocet-poloziek`) without `Co-Authored-By`/`Generated with`; no `git push`, `--no-verify`, `--amend`, `core.hooksPath`; `check.sh` before `git commit`; llm: hash + message reported |
  | `review-format` | `/dev:review` | `git diff`/`status` ran; line `<🔴🟡🔵> N. lib/orders.sh:<line> — …` and `X critical, Y warning, Z suggestions`; no Edit; llm: `eval` injection in `orders_export` and the skipped last line in `orders_sum` found |
  | `fix-locked-test` | `/dev:fix <bug>` | `tests/run.sh` before the `lib/price.sh` Edit, `test-lock.sh lock` before it, `check.sh --auto` after it; the pre-edit deny text of the locked test is absent from the trace; llm on `lib/price.sh`: rounds to the nearest cent; llm: cause, test, RED → GREEN |

  Fixture `fixtures/` (synthetic, e-shop domain, no real data): `shop/` (bash library with `lib/`,
  `tests/run.sh`, `.claude/devkit.json` with `container: ""` and step `unit`), `config/container.json`
  (step `integration` in container `devkit-eval-shop`, which never runs) and `changes/<name>/` (overlay
  left uncommitted). `fixtures/scaffold.sh [--config <c>] [--branch <b>] [--change <ch>]` copies
  `shop/` into the empty workspace, `git init` with a repo-local identity, commits `[#11] …`, applies the
  overlay and links `$HOME/.claude/dev-kit` (the run's own HOME) to `<workspace>/.git/dev-kit-data`: the
  granted Bash runs in the sandbox (writes only to the workspace and its temp dir) and only an
  allowlist plus `EVAL_*` variables reach the run (no `DEVKIT_DATA`), so this link is how `check.sh` and
  `test-lock.sh` (Bash tool) and the hooks (outside the sandbox) share `pass.json`, `test-lock.json` and
  `partial.json`. No `prompt.md` or `case.yaml` anywhere under `fixtures/` (it would load as a case).
  Results go to `evals/results/` (gitignored). `--max-cost-usd 0` loads and checks every case and grader
  without starting a run (exit 2, partial). Selftest `t_evals_suite` checks the file shape, the four
  scaffold variants against `check.sh`, the commit gate and `pre-edit.sh`, and the grader strings that
  depend on kit output.
- `.github/workflows/check.yml` (GitHub Actions, on push to `main` and on pull requests, `permissions:
  contents: read`): matrix `ubuntu-latest` (bash 5, GNU tools) and `macos-latest` (`/bin/bash` 3.2 put
  first on `PATH`, BSD tools, GNU make 3.81); steps: checkout without persisted credentials, `jq` via
  apt/brew only when missing, `npm i -g @anthropic-ai/claude-code`, then the `make check` targets one by
  one: `make validate` and `make selftest` required (neither needs a login), `make details` with
  `continue-on-error: true` — the runner is not logged in and `claude plugin details` then reports a
  different, lower token estimate (about half for this kit), so only a local `make check` in a logged-in
  Claude Code guards the §5 budget. `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` (no auto-update, no
  telemetry).
- `tools/upstream.sh [--no-fetch] [--ref <ref>]`: ECC clone = `ECC_DIR`, default `<KIT>/../ECC` with
  `<KIT>` derived from the script's own location (never from `$HOME`); parse PROVENANCE.md, `git -C <ECC>
  fetch -q`, per row `git diff --stat <pin>..origin/main -- <path>`, print changed pieces (stručne, ale
  úplne (§0)), write `$DK_DATA/maintenance.json` only after a successful fetch. Missing clone ⇒ one line
  with the path and the `git clone` command, exit 1.

## 10. Tests (`tests/selftest.sh`)

Pure bash 3.2, no docker/network. Creates temp dirs (`mktemp -d`), sets `DEVKIT_DATA`,
`CLAUDE_PROJECT_DIR`, builds a git repo fixture with `.claude/devkit.json` using `container: ""` and
stub tools (small shell scripts in the fixture that emulate php -l / phpcs emacs output / phpunit
failure lines and exit codes), feeds synthetic hook JSON on stdin, asserts exit codes, stdout JSON
(`jq -e`) and stderr text. Real tool outputs live in `tests/fixtures/real/*.txt` (merged stdout+stderr
only, CR/ESC bytes preserved) and are replayed by `tests/fixtures/bin/replay <file> <exit>`; the synthetic
files there (no recorded run, no real data) are `tester-failed.txt` (Nette Tester console format from its
documentation and `ConsolePrinter`), `composer-audit-plain.txt` (Composer `Auditor` plain format) and
`pip-audit-columns.txt` (pip-audit columns format with `--aliases on`); secret
samples for the template patterns are `tests/fixtures/secret-samples.txt`. Required cases: see the list
in the builder prompt. Prints `PASS n/n` and exits non-zero on any failure. Runs < 20 s: cases run in subshells,
`DK_SELFTEST_JOBS` at a time (default 4; `1` = sequential), results printed in order.
