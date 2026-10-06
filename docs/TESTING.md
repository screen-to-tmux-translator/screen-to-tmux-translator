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

The suite still executes and logs every applicable placement. For successful cases the terminal/console output is intentionally compact: one PASS is printed after every placement succeeds, together with one canonical mapping in the form `result | description | screen command -> tmux command`. Both pipe columns are fixed. Ordinary argv are shown bare; quoting is retained only where shell protection or single-line control-byte escaping is needed. If any placement fails, that failing placement is printed explicitly. The detailed `test-screen-cli-*.log` retains the complete per-placement records. `run-tests.sh --quiet` hides the mapping columns without suppressing ordinary PASS/FAIL progress.

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

The ZIP is produced after all test layers finish. With no compiled tmux build present it contains the five base `.log` files; when successful compiled builds are discovered it also contains the generated built-hardlink and per-build behavior logs. A `--build` run additionally includes `test-build-<timestamp>.log`. `test-run-console-*` is produced by the runner itself and includes the shared run timestamp, start/finish timestamps, overall status, and paths of all run artifacts. The runner refuses to overwrite artifacts when a forced timestamp collides with an existing run.

`SCREEN2TMUX_RUN_TIMESTAMP` may be set for deterministic filenames; `SCREEN2TMUX_LOG_DIR` may be set to redirect all runtime artifacts. ZIP creation prefers the `zip` executable and falls back to Python 3 `zipfile`. Runtime log files are intentionally excluded from the static package checksum manifest.

## Console colorization

The runner's terminal stream is colorized only after the corresponding plain text has been appended to `test-run-console-*`. ANSI escapes therefore never become part of the normal log/archive contract. Only semantic tokens are colored; complete test lines are not.

The default `SCREEN2TMUX_COLOR=auto` enables color only for an interactive terminal. `always` forces it and `never` disables it. `NO_COLOR` disables all color and takes precedence. Test components launched by `run-tests.sh` receive `NO_COLOR=1`; the parent runner then selectively colors its terminal copy. Standalone test scripts honor the same console color policy directly while forcing translator output captured into their detailed log to plain text.

Terminal truncation is also terminal-only. `run-tests.sh` measures `/dev/tty` width once at startup and truncates displayed lines to that width. `--truncate-lines N` overrides the width; `--trunkate-lines N` is accepted as a typo-compatible alias. The full line is appended to `test-run-console-*` before truncation, so archived logs remain unabridged.

`logs/test-regressions-<YYYYMMDD-HHMMSS>.log` records the focused semantic regressions accumulated through 0.4.2.

`logs/test-interface-equivalence-<YYYYMMDD-HHMMSS>.log` records unified interface parity. `screen-function-source.sh` is always the reference. By default the minified source, standalone `screen.sh`, and every discovered patched tmux hardlink named `screen` are each run over the complete 683 first/middle/last placement matrix. Each Screen case prints one PASS only when every selected interface agrees with the reference for every placement. On failure the console lists only the interface/placement combinations that diverged; the log retains each comparison record. `run-tests.sh --equivalence NAME` (repeatable) restricts this layer to named interfaces, and `--list-equivalence-interfaces` prints accepted names.

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
translation permutations:       683 PASS, 0 FAIL
syntax oracle base cases:       228 PASS, 0 FAIL
focused regressions:            102 PASS, 0 FAIL
packaged equivalence interfaces: 3 (canonical source, minified source, screen.sh)
equivalence variants/interface: 683
equivalence command cases:      228 PASS, 0 FAIL
equivalence divergences:          0
live tmux behavior:             optional; skipped if tmux is unavailable
```

With patched builds present, each discovered `screen` hardlink becomes an additional equivalence interface automatically; the same 683-placement matrix is not printed again in the build-integration section.

## Optional live tmux behavioral layer

`tests/test-tmux-behavior.sh` starts an isolated tmux server using `tmux -L screen2tmux-behavior-$$ -f /dev/null`. It never connects to the user's normal tmux server. When tmux is installed, it checks properties that cannot be established by argv inspection alone:

- duplicate literal tmux session names are rejected;
- `move-window` rejects an occupied destination while `swap-window` exchanges it;
- `move-window -r` honors nonzero `base-index`;
- tmux named buffers are server-wide;
- `alternate-screen` can differ between panes.

If tmux is not installed, this layer reports `SKIP` and exits successfully; the source-derived syntax oracle and translator regressions still run.

## Generic tmux build and compiled-interface layer (0.4.2)

The preferred build entry point is:

```sh
sh build_tmux.sh                 # 3.7d original + patched
sh build_tmux.sh 3.7d,latest
sh build_tmux.sh 3.7d 3.8 latest
```

For every requested version/ref, the generic builder invokes the shared single-build driver twice: once untouched and once with the Screen compatibility integration. `latest` resolves master/main; other values are accepted as exact refs and also tried as `release_VERSION`. Generated sources are kept under `src/tmux-*`; build/install output is kept under `build/tmux-*`. A successful build is identified by its `BUILD-INFO` file plus executable installed tmux binary.

Normal build verbosity is deliberately compact:

```text
Generating build system ...
[OK] Generating build system
Configuring tmux ...
[OK] Configuring tmux
Compiling alerts.c ... [OK]
Compiling cmd-new-session.c ... [OK]
...
[OK] Compiling tmux
[OK] Installing tmux
```

`--verbosity quiet|normal|verbose` is supported by both `build_tmux.sh` and `run-tests.sh`, with `normal` as the default. Full raw build diagnostics remain in each build directory's `build.log`; normal console rendering suppresses repeated compiler command lines. Selective color follows `SCREEN2TMUX_COLOR` / `NO_COLOR`.

`run-tests.sh --build` builds 3.7d before testing. Versions following `--build` may be comma- or space-separated. Build failures set the eventual run status to FAIL but do not prevent discovery/testing of other variants that completed successfully.

Every discovered patched build contributes its `screen` hardlink to the unified 683-variant equivalence matrix. The interface name is dynamic (`tmux-3.7d`, `tmux-latest`, `tmux-<other-version>`), so the suite is no longer limited to two hardcoded versions. Every patched build additionally receives inode-identity, compiled dry-run, and real-execution smoke checks. Every successful original **and** patched tmux binary receives the isolated live behavior suite.

Individual equivalence selection examples:

```sh
sh run-tests.sh --equivalence screen-script
sh run-tests.sh --equivalence tmux-3.7d
sh run-tests.sh --equivalence tmux-latest
sh run-tests.sh --equivalence tmux-3.8
```

If an explicitly requested compiled interface is absent, the equivalence component fails with a specific unavailable-interface error rather than silently skipping it.

## Build dependency and patch-safety checks

The shared build driver performs dependency checks before downloading source. It requires the normal tmux-from-Git toolchain and mandatory libraries: compiler, make, Git, Autoconf/Automake, yacc/bison, `pkg-config`, libevent 2.x development files, ncurses/terminfo development files, `patch`, and standard shell utilities. If requirements are missing, it detects a supported package manager, shows the proposed package set, and asks before installing. `SCREEN2TMUX_AUTO_INSTALL=yes|no` can pre-answer the prompt; after a successful install the complete dependency probe is rerun before any download/build begins.

The patch is intentionally non-adaptive. `patch --fuzz=0` must find the two known `tmux.c` integration locations. If a future master changes enough that this no longer applies, the build stops and reports the branch/commit rather than inserting code heuristically.

Before `autogen.sh`, the pristine and patched snapshots are compared recursively. A build is rejected unless there are exactly two source differences: modified `tmux.c` and added `screen-to-tmux-translator`.
