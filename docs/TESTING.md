# Testing model

## Goals

The suite separately answers two questions:

1. Is the tested argv a valid GNU Screen 5.0.2 command-line form?
2. If valid, does the translator classify and handle it as intended?

This separation fixes the main weakness in 0.1.0, where translator expectations and syntax validity came from the same manifest and could therefore agree on the same mistake.

## Screen syntax oracle

`tests/screen-syntax-oracle.sh` does not source or call the translator. It uses:

- a separate top-level Screen option parser for the tested CLI grammar;
- `docs/screen-5.0.2-command-manifest.tsv`, generated from Screen 5.0.2 `comm.c`;
- `CAN_QUERY` metadata to distinguish commands allowed through `-Q`;
- command arity expressions such as `ARGS_0`, `ARGS_12`, `ARGS_1234`, and `ARGS_ORMORE`;
- narrow semantic checks used by negative controls, such as valid `focus` directions.

GNU Screen has no native side-effect-free dry-run mode, so invoking the real binary is not a safe general syntax validator: valid commands can create persistent processes, detach terminals, touch utmp, open serial devices, kill sessions, and so on.

## Translator classes

```text
EXACT        exit 0   safe automatic translation
UNSUPPORTED  exit 2   valid Screen operation, no safe automatic translation
APPROX       exit 3   useful substitute exists but semantics differ
MOOT         exit 4   tmux architecture removes the need for the operation
EXTERNAL     exit 5   substitute requires a non-tmux program
INVALID      exit 64  invalid/unknown Screen syntax
```

Only `EXACT` mappings execute tmux when `--dry-run` is absent.

## Dry-run placement

Every nonempty case is tested with `--dry-run` inserted at three positions:

```text
screen --dry-run <args...>
screen <first-arg> --dry-run <remaining-args...>
screen <args...> --dry-run
```

The zero-argument Screen invocation has first/last placements, which are equivalent after insertion.

The three names describe only where the translator-specific dry-run flag is inserted:

```text
first:  screen --dry-run ARG1 ARG2 ...
middle: screen ARG1 --dry-run ARG2 ...
last:   screen ARG1 ARG2 ... --dry-run
```

The suite still executes and logs every applicable placement. For successful cases the terminal/console output is intentionally compact: one PASS is printed after every placement succeeds. If any placement fails, that failing placement is printed explicitly. The detailed `test-screen-cli-*.log` retains the complete per-placement records.

## Logs

`logs/test-screen-cli-<YYYYMMDD-HHMMSS>.log` records for every concrete invocation:

```text
CASE
DESCRIPTION
DRY_RUN_PLACEMENT
EXPECTED_CLASS
EXPECTED_EXIT
INPUT_DISPLAY
INPUT_ARGV_HEX_BEGIN ... INPUT_ARGV_HEX_END
ACTUAL_EXIT
OUTPUT_DISPLAY_BEGIN ... OUTPUT_DISPLAY_END
OUTPUT_HEX
RESULT
```

Control characters are rendered visibly in `INPUT_DISPLAY`/dry-run output and preserved exactly in the hex fields.

`run-tests.sh` chooses one timestamp once and uses it for every artifact from that invocation:

```text
test-screen-cli-YYYYMMDD-HHMMSS.log
test-regressions-YYYYMMDD-HHMMSS.log
test-interface-equivalence-YYYYMMDD-HHMMSS.log
test-tmux-behavior-YYYYMMDD-HHMMSS.log
test-run-console-YYYYMMDD-HHMMSS.log
screen-to-tmux-translator-<VERSION>-test-logs-YYYYMMDD-HHMMSS.zip
```

The ZIP is produced after all test layers finish. With no compiled tmux build present it contains the five base `.log` files; when patched 3.7d/latest builds are discovered it also contains the generated built-hardlink and per-build behavior logs. `test-run-console-*` is produced by the runner itself and includes the shared run timestamp, start/finish timestamps, overall status, and paths of all run artifacts. The runner refuses to overwrite artifacts when a forced timestamp collides with an existing run.

`SCREEN2TMUX_RUN_TIMESTAMP` may be set for deterministic filenames; `SCREEN2TMUX_LOG_DIR` may be set to redirect all runtime artifacts. ZIP creation prefers the `zip` executable and falls back to Python 3 `zipfile`. Runtime log files are intentionally excluded from the static package checksum manifest.

## Console colorization

The runner's terminal stream is colorized only after the corresponding plain text has been appended to `test-run-console-*`. ANSI escapes therefore never become part of the normal log/archive contract. Only semantic tokens are colored; complete test lines are not.

The default `SCREEN2TMUX_COLOR=auto` enables color only for an interactive terminal. `always` forces it and `never` disables it. `NO_COLOR` disables all color and takes precedence. Test components launched by `run-tests.sh` receive `NO_COLOR=1`; the parent runner then selectively colors its terminal copy. Standalone test scripts honor the same console color policy directly while forcing translator output captured into their detailed log to plain text.

`logs/test-regressions-<YYYYMMDD-HHMMSS>.log` records the focused semantic regressions accumulated through 0.3.9.

`logs/test-interface-equivalence-<YYYYMMDD-HHMMSS>.log` records interface parity. The canonical and minified source files are compared byte-for-byte with identical exit status across all 683 first/middle/last dry-run placements. All 228 base Screen command cases are then compared three ways against the standalone `bin/screen.sh` executable, and one normal-execution path is compared using a private stub `tmux`.

## Focused regressions

`tests/test-regressions.sh` checks the bugs observed through the 0.2.0 package runs, including:

- `-d -m <program>` operand handling;
- `-m` not implying detach;
- screenrc/tmux.conf incompatibility;
- Screen `source` incompatibility;
- logging not being silently dropped;
- attach preselection preservation;
- region/pane focus target correctness;
- no invented resize direction;
- layout abstraction mismatch;
- ACL scope mismatch;
- serial mappings being external;
- safe rendering of carriage-return bytes;
- Screen `$STY`-style nested invocation behavior using `$TMUX`;
- `removebuf` exchange-file semantics;
- Screen-compatible `-Q number` output shape;
- session scoping for `displays`;
- server-wide tmux key-binding scope;
- client targeting for redisplay/suspend;
- non-compatible informational/query output;
- hardcopy/capture-pane approximation;
- plain `-r` attach/resume semantic differences;
- `-R/-RR` attached/detached and multiple-match selection differences;
- `-q -ls` output/exit-status semantics;
- occupied-destination `number` swap semantics;
- `collapse` versus tmux `base-index`;
- client-specific internal detach/power-detach;
- backend-wide Screen `altscreen` versus pane/window-scoped tmux settings;
- Screen copy/register state versus server-wide tmux buffers;
- interactive no-argument `paste`;
- duplicate Screen `-S` labels versus unique tmux session names and the explicit unique-name opt-in;
- Screen `-U` versus tmux `-u` partial semantics;
- Screen `-A` versus tmux client/window sizing;
- native version output non-equivalence and translator-owned compatibility `--help`;
- nested attached `-m` and tmux's `$TMUX` safeguard;
- literal tmux-format escaping in names/titles and literal `-Q echo`;
- Screen `screen N` StartAt semantics;
- explicit uncertain-argument warnings for incompatible target syntax;
- selective diagnostic color tokens and `NO_COLOR` precedence;
- sourceability/direct-execution behavior of both canonical and minified function-source files;
- interactive build-dependency decline and automatic-install/recheck control paths without performing real package installation;
- selective compatibility-help color/status content.

## Current packaged result

```text
translation permutations: 683 PASS, 0 FAIL
syntax oracle base cases: 228 PASS, 0 FAIL
focused regressions:       85 PASS, 0 FAIL
source/minified parity:     683 PASS, 0 FAIL
three-way base cases:       228 PASS, 0 FAIL
three-way execution stub:     1 PASS, 0 FAIL
live tmux behavior:         optional; skipped if tmux is unavailable
```

## Optional live tmux behavioral layer

`tests/test-tmux-behavior.sh` starts an isolated tmux server using `tmux -L screen2tmux-behavior-$$ -f /dev/null`. It never connects to the user's normal tmux server. When tmux is installed, it checks properties that cannot be established by argv inspection alone:

- duplicate literal tmux session names are rejected;
- `move-window` rejects an occupied destination while `swap-window` exchanges it;
- `move-window -r` honors nonzero `base-index`;
- tmux named buffers are server-wide;
- `alternate-screen` can differ between panes.

If tmux is not installed, this layer reports `SKIP` and exits successfully; the source-derived syntax oracle and translator regressions still run.

## Built tmux hardlink layer (0.3.9)

The repository includes two build drivers:

```sh
sh build_tmux_3.7d.sh
sh build_tmux_latest.sh
```

A completed build is recognized from either of these standard paths:

```text
build/tmux-3.7d/patched/install/bin/screen
build/tmux-latest/patched/install/bin/screen
```

The build driver creates `screen` with `ln` from the patched `tmux` binary; it is a hardlink, not a wrapper or copied executable.

When `run-tests.sh` discovers one or both completed builds, it automatically adds `tests/test-built-tmux-screen.sh`. For each patched build this test:

1. verifies that sibling `screen` and `tmux` have the same inode;
2. invokes the actual hardlink whose basename is `screen` over all 683 first/middle/last dry-run placements from `tests/cases.sh`; successful placements are collapsed to one console PASS per Screen case while failures name the exact placement;
3. compares exit status and raw output bytes with the canonical `screen-function-source.sh` translator using `cmp`;
4. performs one non-dry-run detached-session smoke test under an isolated `TMUX_TMPDIR` and confirms that the sibling patched `tmux` can see the resulting session;
5. leaves the user's normal tmux socket untouched.

The existing live behavior suite is then rerun with `TMUX_BIN` set to each patched tmux binary. This means the same duplicate-session, occupied-index, `base-index`, buffer-scope, format-literal, StartAt, and alternate-screen checks are exercised against the actual build rather than only a system-installed tmux.

Additional timestamped logs are created only when builds are discovered:

```text
test-built-tmux-screen-YYYYMMDD-HHMMSS.log
test-tmux-behavior-tmux-3.7d-YYYYMMDD-HHMMSS.log
test-tmux-behavior-tmux-latest-YYYYMMDD-HHMMSS.log
```

Every additional log is added to the same per-run ZIP as the five base logs.

## Build dependency and patch-safety checks

The shared build driver performs dependency checks before downloading source. It requires the normal tmux-from-Git toolchain and mandatory libraries: compiler, make, Git, Autoconf/Automake, yacc/bison, `pkg-config`, libevent 2.x development files, ncurses/terminfo development files, `patch`, and standard shell utilities. If requirements are missing, it detects a supported package manager, shows the proposed package set, and asks before installing. `SCREEN2TMUX_AUTO_INSTALL=yes|no` can pre-answer the prompt; after a successful install the complete dependency probe is rerun before any download/build begins.

The patch is intentionally non-adaptive. `patch --fuzz=0` must find the two known `tmux.c` integration locations. If a future master changes enough that this no longer applies, the build stops and reports the branch/commit rather than inserting code heuristically.

Before `autogen.sh`, the pristine and patched snapshots are compared recursively. A build is rejected unless there are exactly two source differences: modified `tmux.c` and added `screen-to-tmux-translator`.
