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
APPROX       exit 0/3 semantics differ: executable one-command substitute / advisory only
MOOT         exit 4   tmux architecture removes the need for the operation
EXTERNAL     exit 0/5 concrete helper-backed substitute / advisory or missing helper
INVALID      exit 64  invalid/unknown Screen syntax
```

`EXACT` mappings execute tmux when `--dry-run` is absent. By default, concrete one-command `APPROX` mappings also execute after emitting their semantic warning. Concrete `EXTERNAL` mappings for startup endpoints may execute a tmux command that launches a required helper such as `telnet` or `picocom` when that helper is installed. With translator-owned `--strict`, every `APPROX` and `EXTERNAL` mapping is advisory and never executes tmux; `APPROX` returns 3 and `EXTERNAL` returns 5.

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

The combined aggregate matrix still executes every applicable placement. For successful cases the terminal/console output is intentionally compact: one PASS is printed after the oracle, reference-class checks, and all selected interface comparisons succeed. The display form is `result | description | screen command -> tmux command`; the two pipe columns and the `->` column are aligned. In color mode, the class token and the entire right-hand result use the same class color, so `UNSUPPORTED` placeholders are red, `MOOT` placeholders are cyan, and approximate tmux commands are yellow. Ordinary argv are shown bare; quoting is retained only where shell protection or single-line control-byte escaping is needed. `run-tests.sh --quiet` hides the mapping columns without suppressing ordinary PASS/FAIL progress. `tests/test-screen-cli.sh` remains available separately when the older per-invocation hex diagnostic log is desired.

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
test-regressions-YYYYMMDD-HHMMSS.log
test-interface-equivalence-YYYYMMDD-HHMMSS.log
test-tmux-behavior-YYYYMMDD-HHMMSS.log
test-run-console-YYYYMMDD-HHMMSS.log
screen-to-tmux-translator-<VERSION>-test-logs-YYYYMMDD-HHMMSS.zip
```

The ZIP is produced after all test layers finish. With no compiled tmux build present it contains those four base `.log` files. When patched builds are discovered, the system-tmux behavior log is replaced by one behavior log per patched version and the built-hardlink integration log is added. A `--build` run additionally includes `test-build-<timestamp>.log`. The standalone `test-screen-cli.sh` creates its own detailed CLI log only when invoked directly. `test-run-console-*` is produced by the runner itself and includes the shared run timestamp, start/finish timestamps, overall status, and paths of all run artifacts. The runner refuses to overwrite artifacts when a forced timestamp collides with an existing run.

`SCREEN2TMUX_RUN_TIMESTAMP` may be set for deterministic filenames; `SCREEN2TMUX_LOG_DIR` may be set to redirect all runtime artifacts. ZIP creation prefers the `zip` executable and falls back to Python 3 `zipfile`. Runtime log files are intentionally excluded from the static package checksum manifest.

## Console colorization

The runner's terminal stream is colorized only after the corresponding plain text has been appended to `test-run-console-*`. ANSI escapes therefore never become part of the normal log/archive contract. Only semantic tokens are colored; complete test lines are not.

The default `SCREEN2TMUX_COLOR=auto` enables color only for an interactive terminal. `always` forces it and `never` disables it. `NO_COLOR` disables all color and takes precedence. Test components launched by `run-tests.sh` receive `NO_COLOR=1`; the parent runner then selectively colors its terminal copy. Standalone test scripts honor the same console color policy directly while forcing translator output captured into their detailed log to plain text.

Terminal truncation is also terminal-only. `run-tests.sh` measures `/dev/tty` width once at startup and truncates displayed lines to that width. `--truncate-lines N` overrides the width; `--trunkate-lines N` is accepted as a typo-compatible alias. The full line is appended to `test-run-console-*` before truncation, so archived logs remain unabridged.

`logs/test-regressions-<YYYYMMDD-HHMMSS>.log` records the focused semantic regressions accumulated through 0.4.17.

`logs/test-interface-equivalence-<YYYYMMDD-HHMMSS>.log` is now the combined Screen/oracle/interface matrix log. `screen-function-source.sh` is always the reference. For each case the GNU Screen 5.0.2 oracle validates base syntax, the reference exit status is checked against the expected class on every first/middle/last placement, and the minified source, both one-line source variants, standalone self-contained `screen.sh`, plus every discovered patched tmux hardlink named `screen` are compared with the reference. Each Screen case prints one PASS only when all of those checks succeed. The resolved interfaces are printed one per line with the path on the same line in parentheses; paths inside the project are relative to the repository root. `run-tests.sh --equivalence NAME` (repeatable) restricts interface comparison, and `--list-equivalence-interfaces` prints accepted names. The standalone `tests/test-screen-cli.sh` harness remains available but is not duplicated inside `run-tests.sh`.

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
- sourceability/direct-execution behavior of canonical, minified, and both one-line function-source files;
- proof that `screen.sh` works after being copied alone with no sibling translator files;
- one-physical-line enforcement for both `.oneliner.sh` files;
- interactive build-dependency decline and automatic-install/recheck control paths without performing real package installation;
- selective compatibility-help color/status content;
- `--strict` preserving exact mappings while preventing every executable and delayed `APPROX` path from invoking tmux;
- concrete `EXTERNAL` dry-run mappings for serial/Telnet startup plus real helper-present execution and strict-mode suppression;
- class-matched mapping colors on both the class token and right-hand result, including the aggregate runner terminal repaint path;
- default tmux 3.7c release-tag pinning plus retained immutable tmux 3.7d source pinning;
- explicit `sh` invocation for internal `.sh` scripts so ZIP-extracted trees do not depend on Unix executable mode bits.

## Current packaged result

```text
translation permutations:       683 PASS, 0 FAIL
syntax oracle base cases:       228 PASS, 0 FAIL
focused regressions:            137 PASS, 0 FAIL
packaged equivalence interfaces: 5 (canonical, minified, two one-line sources, screen.sh)
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

## Generic tmux build and compiled-interface layer (0.4.4)

The patched-only build entry point is:

```sh
sh build_tmux_patched.sh         # patched 3.7c only
sh build_tmux_patched.sh latest
sh build_tmux_patched.sh 3.7c,latest
```

`build_tmux.sh` remains the explicit original+patched builder. `run-tests.sh --build` now uses `build_tmux_patched.sh` by default; `--compile-original` switches that build phase back to `build_tmux.sh` so both variants are compiled. `latest` resolves master/main; other values are accepted as exact refs and also tried as `release_VERSION`. Generated sources are kept under `src/tmux-*`; build/install output is kept under `build/tmux-*`. A successful build is identified by its `BUILD-INFO` file plus executable installed tmux binary.

Normal build verbosity is deliberately compact:

```text
Generating build system ...
[OK] Generating build system
Configuring tmux ...
Configure yes: build environment sane  make sets $(MAKE)  C compiler works  GNU C compiler  stdlib.h  libevent_core >= 2
Configure no: cross compiling  bitstring.h  libproc.h  closefrom  strlcpy
Configure values: install=/usr/bin/install -c, mkdir -p=/bin/mkdir -p, C compiler=cc, build system type=x86_64-pc-linux-gnu
[OK] Configuring tmux
Compiling alerts.c ... [OK] cfg.c ... [OK] cmd-new-session.c ... [OK] cmd-send-keys.c ... [OK]
          window.c ... [OK] tty.c ... [OK]
[OK] Compiling tmux
[OK] Installing tmux
```

`--verbosity quiet|normal|verbose` is supported by both generic builders and `run-tests.sh`, with `normal` as the default. In normal mode Autoconf results are normalized and de-duplicated before display: header usability/presence/final triples collapse to one header token, `whether`/`working` boilerplate is removed, common compiler names are shortened, cached booleans join the yes/no groups, and the internal `.screen2tmux-cc` wrapper path is replaced with the real compiler. `yes` names are grouped in green, `no` names in red, and all other results are comma-separated `name=value` entries. Each group wraps at the measured console width. Compiler success markers are collected into one width-wrapped `Compiling ...` stream. Full raw build diagnostics remain in each build directory's `build.log`; selective color follows `SCREEN2TMUX_COLOR` / `NO_COLOR`.

`run-tests.sh --build` builds patched 3.7c before testing. Versions following `--build` may be comma- or space-separated. `--compile-original` additionally compiles the pristine original for each requested version. Build failures set the eventual run status to FAIL but do not prevent discovery/testing of other variants that completed successfully.

Every discovered patched build contributes its `screen` hardlink to the unified 683-variant equivalence matrix. The interface name is dynamic (`tmux-3.7c`, `tmux-3.7d`, `tmux-latest`, `tmux-<other-version>`), so the suite is no longer limited to two hardcoded versions. Every patched build additionally receives inode-identity, compiled dry-run, and real-execution smoke checks. The isolated live behavior suite runs once per version against the patched tmux only; original binaries are retained as pristine build baselines.

Individual equivalence selection examples:

```sh
sh run-tests.sh --equivalence screen-script
sh run-tests.sh --equivalence tmux-3.7c
sh run-tests.sh --equivalence tmux-3.7d
sh run-tests.sh --equivalence tmux-latest
sh run-tests.sh --equivalence tmux-3.8
```

If an explicitly requested compiled interface is absent, the equivalence component fails with a specific unavailable-interface error rather than silently skipping it.

## Build dependency and patch-safety checks

The shared build driver performs dependency checks before downloading source. It requires the normal tmux-from-Git toolchain and mandatory libraries: compiler, make, Git, Autoconf/Automake, yacc/bison, `pkg-config`, libevent 2.x development files, ncurses/terminfo development files, `patch`, and standard shell utilities. If requirements are missing, it names the missing commands/libraries, detects a supported package manager, prints the complete package set, and prints a copyable administrator command (`sudo apt-get ...`, `sudo dnf ...`, `sudo yum ...`, or `sudo apk ...`; Homebrew is unprivileged). It then asks before attempting automatic installation, with an explicit warning that a system package manager may invoke `sudo`. `SCREEN2TMUX_AUTO_INSTALL=yes|no` can pre-answer the prompt; after a successful install the complete dependency probe is rerun before any download/build begins.

The automatic-install regression is fully isolated: it supplies both a fake package manager and a fake `sudo` wrapper, so `sh run-tests.sh` never contacts the real package manager or asks the person running the tests for a sudo password.

The patch is intentionally non-adaptive. `patch --fuzz=0` must find the two known `tmux.c` integration locations. If a future master changes enough that this no longer applies, the build stops and reports the branch/commit rather than inserting code heuristically.

Before `autogen.sh`, the pristine and patched snapshots are compared recursively. A build is rejected unless there are exactly four source differences: modified `Makefile.am`, `tmux.h`, and `tmux.c`, plus added `screen-compat.c`. This keeps the compatibility layer in a normal tmux translation unit instead of directly including a large implementation file from `tmux.c`. The added module is native C: regressions reject an embedded shell payload or runtime shell bridge, and the compiled-hardlink equivalence interface compares its argv/status/diagnostic behavior with the canonical shell interface across the same 683-variant matrix.
