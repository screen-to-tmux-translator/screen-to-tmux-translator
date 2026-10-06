# screen-to-tmux-translator 0.4.1

A conservative POSIX-shell compatibility translator for GNU Screen 5.0.x command lines.

It defines:

- `screen2tmux ...` — explicit translator entry point.
- `screen ...` — optional drop-in shell function, unless `SCREEN2TMUX_NO_SCREEN_FUNCTION=1` is set before sourcing the file.

The translator executes only mappings classified as **EXACT**. When a tmux command is merely similar, broader in scope, depends on an external program, or the Screen operation is unnecessary under tmux's architecture, the translator explains that instead of silently executing a misleading substitute.

## Load it

For a standalone command that behaves like `screen`, use:

```sh
./bin/screen.sh [Screen arguments ...]
```

For shell-function use, source either function file with the POSIX dot command:

```sh
. ./bin/screen-function-source.sh
screen -r
```

A mechanically minified equivalent is also shipped:

```sh
. ./bin/screen-function-source-minified.sh
screen -r
```

The minified file removes comments and blank lines only; it is verified against the canonical source across the complete 683-placement dry-run matrix.

This defines a shell function named `screen` in the **current shell**, shadowing an installed GNU Screen executable there. Use `command screen ...` to invoke the native executable.

Do **not** use `sh ./bin/screen-function-source.sh` when you want the function to remain available afterward. POSIX `sh FILE` runs the file in a child shell, and a child cannot install a function into its parent. Direct execution of the source file therefore exits with status `2` and prints the correct `. ./bin/screen-function-source.sh` instruction.

To define only `screen2tmux`:

```sh
SCREEN2TMUX_NO_SCREEN_FUNCTION=1
export SCREEN2TMUX_NO_SCREEN_FUNCTION
. ./bin/screen-function-source.sh
```

## Dry run

`--dry-run` or `--dryrun` may appear anywhere in the Screen argument vector:

```sh
screen --dry-run -S work -X stuff hello
screen -S work --dryrun -X stuff hello
screen -S work -X stuff hello --dry-run
```

An exact mapping prints the tmux argv instead of executing it:

```text
'tmux' 'send-keys' '-l' '-t' 'work:0' 'hello'
```

Control bytes are escaped in dry-run output so they cannot corrupt the terminal or log. For example a carriage return is shown as `\r`.

## Compatibility help

`screen --help` is a translator-owned help page, not tmux's help and not a byte-for-byte copy of native GNU Screen help. It follows the GNU Screen 5.0.x option surface and annotates each option/command family with `EXACT`, `APPROX`, `UNSUPPORTED`, `MOOT`, `EXTERNAL`, or `VARIES`. It also explains the important differences introduced by tmux's session/client/pane model and documents translator extensions such as `--dry-run`/`--dryrun`.

Only semantic tokens and headings are colorized; descriptions remain in the normal terminal color. `SCREEN2TMUX_COLOR=never` or `NO_COLOR=1` disables color. The same help is produced by the canonical source function, minified source function, standalone `screen.sh`, and the patched tmux hardlink named `screen`.

## Translation classes and exit status

| Status | Class | Meaning |
| ---: | --- | --- |
| `0` | `EXACT` | Safe enough to execute automatically; under `--dry-run`, prints the tmux command. |
| `2` | `UNSUPPORTED` | Valid Screen operation, but no safe automatic tmux equivalent is implemented. |
| `3` | `APPROX` | A useful tmux substitute exists, but semantics differ materially; it is not executed. |
| `4` | `MOOT` | tmux architecture makes the Screen operation unnecessary. |
| `5` | `EXTERNAL` | Closest substitute requires a non-tmux program such as `picocom` or `telnet`. |
| `64` | `INVALID` | Invalid or unknown Screen syntax for this translator. |

Other statuses can come from tmux itself when an `EXACT` mapping is executed without `--dry-run`.

Example approximation:

```text
screen2tmux: APPROX: Screen focus moves among display regions; tmux select-pane moves among PTY panes, so the object model is different.
screen2tmux: suggestion: Closest substitute: tmux select-pane -t work:.{right-of}
```

Argument uncertainty uses the same non-executing exit status `3`, but is called out explicitly:

```text
screen2tmux: WARNING: uncertain translation of argument Screen window selector 'editor.1': tmux window/pane targets have a different selector grammar from Screen window names and numbers.
```

This is intentionally a stop condition rather than a best-effort rewrite.

## Important 0.3.1 correctness changes

0.3.1 follows a stricter rule: when tmux does not actually implement the Screen feature, the translator does not build an emulation layer. It returns `UNSUPPORTED`/`APPROX` with a concrete explanation. When a Screen argument cannot be interpreted safely under tmux target syntax, it emits a specific `WARNING: uncertain translation of argument ...` message and does not execute tmux.

- `screen -U` is now `APPROX`, not `tmux -u` `EXACT`. Screen `-U` both declares the display UTF-8 capable and sets UTF-8 as the default encoding for new Screen windows; tmux `-u` only forces its client UTF-8 assumption. No automatic command is executed.
- Screen `-A` is treated as `APPROX` when it actually participates in an attach operation: Screen explicitly adapts all windows to the attaching terminal and tmux has no equivalent adapt-all-windows flag. On non-attach paths, where Screen does not use `adaptflag`, the option is semantically inert and does not force an approximation.
- `screen -v`, `screen --version`, and internal `version` remain `UNSUPPORTED` because a tmux-backed binary cannot truthfully report itself as native GNU Screen. `screen --help` is now translator-owned and returns a compatibility-aware Screen 5.0.x help page instead of tmux help.
- Attached nested `screen -m` inside tmux is now `APPROX`. tmux deliberately rejects an attached nested `new-session` while `$TMUX` is set unless the operator explicitly unsets it; the translator no longer tries to bypass that safeguard.
- `screen ... -X screen N` and `N:title` are now `APPROX`: Screen treats `N` as a `StartAt` lower bound and searches for the first free slot at or above it, whereas tmux `new-window -t :N` addresses the exact index. The translator does not emulate Screen's free-slot search.
- tmux-format expansion is neutralized where source-confirmed name arguments are format-expanded. Literal `#` in Screen session/window names and titles becomes tmux `##` for `new-session -s/-n`, `new-window -n`, `rename-session`, and `rename-window`.
- `screen -Q echo` uses `tmux display-message -pl` so literal text such as `#{session_name}` is not expanded by tmux. Screen `echo -p`, which uses Screen's `%` format language, is `UNSUPPORTED` rather than being reinterpreted as tmux format syntax.
- Session/window selectors containing tmux-significant target syntax (for example `$`, `@`, `:`, `.`, braces, or glob metacharacters) stop with an explicit uncertain-argument warning instead of being guessed.

## Important 0.3.0 correctness changes

0.3.0 tightens state-dependent and namespace semantics that remained after 0.2.1:

- `screen -R/-RR` and the `-d/-D` variants are now `APPROX`, not `EXACT`. Screen filters sockets by attached/detached state and `-RR` has its own multiple-match behavior; `tmux new-session -A` does not preserve those rules.
- `screen -ls/-list` is now `APPROX` because Screen reports socket names, attached/detached/dead state, and socket-directory information that `tmux list-sessions` does not reproduce. `-q -ls` is also `APPROX` because Screen returns special socket-count-derived exit statuses while suppressing output.
- `screen ... -X number N` is now `APPROX`. Screen swaps window numbers when `N` is already occupied; tmux `move-window` fails in that situation. The translator now suggests `swap-window` for an occupied destination and `move-window` for an empty one.
- `collapse` is now `APPROX`: Screen always renumbers from 0, while tmux `move-window -r` starts at the session's `base-index`.
- Internal `detach` and `pow_detach` are now client/display-scoped approximations. They no longer expand a single Screen Display operation into a tmux session-wide detach.
- `altscreen` is now `APPROX`: Screen changes one backend-wide `use_altscreen` switch, while tmux's `alternate-screen` setting is window/pane scoped.
- `readbuf`, `writebuf`, and `register` are now `APPROX` because Screen copy/register state belongs to a Screen backend/user while tmux buffers are server-wide. Suggestions use explicit session-style buffer namespaces.
- `paste` with no register argument is now `UNSUPPORTED`; Screen opens its interactive register prompt, which is not equivalent to immediate `tmux paste-buffer`.
- Named session creation with `-S NAME` is conservative by default because Screen permits multiple `PID.NAME` sessions sharing the same user label while tmux session names are unique. Set `SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES=1` only when your environment enforces unique Screen labels; then the direct `tmux new-session -s NAME` mapping is enabled.
- The regression suite now covers the above state/scope issues and an optional live tmux behavior suite verifies duplicate-name rejection, occupied-index move/swap behavior, `base-index` renumbering, server-wide buffer scope, and pane-scoped `alternate-screen` on an isolated tmux server.

### Unique-name compatibility policy

By default:

```sh
screen --dry-run -S work
```

returns `APPROX` rather than silently assuming Screen's label namespace is identical to tmux's. If your operational convention already guarantees that Screen `-S` labels are unique:

```sh
SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES=1
export SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES
. ./bin/screen-function-source.sh
```

then named creation is permitted as an `EXACT` mapping within that explicit policy.

## Build original and patched tmux

Four independent build drivers are included. Each one creates and leaves behind one complete source tree plus one separate build/install tree:

```sh
sh build_tmux_3.7d.sh
sh build_tmux_3.7d_patched.sh
sh build_tmux_latest.sh
sh build_tmux_latest_patched.sh
```

The default layout is intentionally flat and explicit:

```text
source-tmux-3.7d/
build-tmux-3.7d/
source-tmux-3.7d-patched/
build-tmux-3.7d-patched/
source-tmux-latest/
build-tmux-latest/
source-tmux-latest-patched/
build-tmux-latest-patched/
```

The original build folders install `tmux` under `install/bin/tmux`. The patched build folders install both `tmux` and a true filesystem hardlink named `screen`:

```text
build-tmux-3.7d-patched/install/bin/tmux
build-tmux-3.7d-patched/install/bin/screen

build-tmux-latest-patched/install/bin/tmux
build-tmux-latest-patched/install/bin/screen
```

The 3.7d scripts use Git branch `release_3.7d`. The latest scripts use `master`. To make original-versus-patched comparisons meaningful on moving `master`, whichever latest tree is built second automatically reuses the first latest tree's exact commit. `TMUX_LATEST_COMMIT=<commit>` can pin a specific commit explicitly.

Before downloading, the shared builder checks for the normal tmux-from-Git prerequisites: a C compiler and make, Git, Autoconf/Automake, yacc or bison, `pkg-config`, libevent 2.x development files, ncurses/terminfo development files, `patch`, and standard shell utilities. If something is missing, the builder reports the missing commands/libraries, detects `apt-get`, `dnf`, `yum`, `apk`, or Homebrew, shows the package set, and asks `Install the missing build software automatically and continue? [y/N]`. `y`/`yes` installs and then rechecks dependencies before continuing; `n`, Enter, or any other answer cancels without installing anything. Set `SCREEN2TMUX_AUTO_INSTALL=yes` or `no` to pre-answer the prompt.

Each script removes and rebuilds only its own `source-tmux-*` and `build-tmux-*` pair. The full downloaded source directory is preserved after the build. Autotools generates `configure` in the source tree, while configure/make/install output lives in the separate `build-tmux-*` directory.

For patched builds, the source-footprint contract is checked before Autotools generation:

```text
modified: tmux.c
added:    screen-to-tmux-translator
```

Patch application uses zero fuzz; if a future `master` moves the two integration points enough that the patch no longer applies exactly, the patched-latest build stops instead of guessing.

Useful overrides:

```sh
TMUX_BUILD_JOBS=8 sh build_tmux_3.7d_patched.sh
SCREEN2TMUX_SOURCE_ROOT=/var/tmp/src SCREEN2TMUX_BUILD_ROOT=/var/tmp/build sh build_tmux_latest.sh
TMUX_GIT_URL=https://github.com/tmux/tmux.git sh build_tmux_latest_patched.sh
SCREEN2TMUX_AUTO_INSTALL=yes sh build_tmux_3.7d.sh
TMUX_LATEST_COMMIT=<commit> sh build_tmux_latest_patched.sh
```

`TMUX_SOURCE_DIR=/path/to/an/existing/tmux/tree` is also available as an offline/test override.

## Tests

Run everything:

```sh
sh run-tests.sh
```

Translation-oriented PASS rows show one canonical mapping per Screen case, even though the first/middle/last dry-run placements are all still exercised internally. Both pipe columns are fixed: result, then description, then the Screen-to-tmux mapping. Ordinary command arguments are shown without unnecessary quotes; quoting is retained only when needed to represent a shell argument safely.

```text
[PASS] C001 exact                    | start a new session                                                  | screen -> tmux new-session
[PASS] W004 exact                    | create vim window                                                    | screen -S work -X screen vim file.txt -> tmux new-window -t work vim file.txt
[PASS] Q004 exact                    | query window number                                                  | screen -S work -Q number -> tmux display-message -p -t work '#{window_index} (#{window_name})'
```

For `APPROX`, `UNSUPPORTED`, `MOOT`, `EXTERNAL`, and `INVALID` cases the right side intentionally states that there is no automatically executed tmux command rather than presenting a suggestion as though it were exact. Detailed logs still contain every first/middle/last invocation and its raw output.

To hide only the mapping columns while keeping normal PASS/FAIL progress:

```sh
sh run-tests.sh --quiet
```

Terminal lines are truncated only for display. At startup `run-tests.sh` measures the terminal width once and uses that width for the entire run. Full individual logs and the full console transcript are written before truncation and remain unabridged. Override the display width with:

```sh
sh run-tests.sh --truncate-lines 120
```

The typo-compatible alias `--trunkate-lines 120` is also accepted.

The test system has four always-available layers plus automatic compiled-binary layers:

1. A **Screen syntax oracle**, independent from the translator, built from GNU Screen 5.0.2 `comm.c` command metadata plus a separate top-level CLI parser.
2. Translator tests that insert `--dry-run` at first/middle/last positions. `first` means immediately after `screen`, `middle` means after the first real Screen argument, and `last` means after all real Screen arguments. Successful placements collapse to one console case row; a failure still names the exact placement.
3. A unified **interface-equivalence suite**. `screen-function-source.sh` is the reference. By default the suite also checks `screen-function-source-minified.sh`, `screen.sh`, and every discovered patched tmux hardlink named `screen` across the full 683-placement matrix. If every selected interface agrees for a Screen case, one PASS row is printed. On a mismatch, only the interfaces/placements that diverged are listed after that case.
4. An **optional live tmux behavioral suite** using an isolated server. It skips cleanly when no tmux executable is available.
5. Discovered patched tmux builds also receive hardlink-identity, compiled dry-run smoke, real-execution smoke, and per-version live tmux behavior checks. Their 683-way translation matrix is not printed a second time because it is already part of the unified equivalence layer.

The default equivalence interfaces are named at the beginning of the run. With both patched builds present they are:

```text
screen-function-source.sh (reference)
screen-function-source-minified.sh
screen.sh
tmux-3.7d screen hardlink
tmux-latest screen hardlink
```

To test one interface individually against the canonical reference:

```sh
sh run-tests.sh --equivalence screen-script
sh run-tests.sh --equivalence screen-function-source-minified
sh run-tests.sh --equivalence tmux-3.7d
sh run-tests.sh --equivalence tmux-latest
```

Repeat `--equivalence NAME` to choose several interfaces, or use the default with no equivalence option to test all available interfaces. `sh run-tests.sh --list-equivalence-interfaces` prints the accepted names.

Current packaged verification:

```text
683/683 translation dry-run permutations PASS
228/228 independent Screen syntax oracle cases PASS
97/97 focused semantic regression tests PASS
683 placement variants per selected equivalence interface
228/228 aggregated equivalence command cases PASS (three packaged interfaces)
0 equivalence divergences in the packaged source/script set
C integration harness: -std=c99 -Wall -Wextra -Werror PASS
```

Each `sh run-tests.sh` invocation creates one timestamped run set. With no compiled build present, the base set is:

```text
logs/test-screen-cli-<timestamp>.log
logs/test-regressions-<timestamp>.log
logs/test-interface-equivalence-<timestamp>.log
logs/test-tmux-behavior-<timestamp>.log
logs/test-run-console-<timestamp>.log
logs/screen-to-tmux-translator-0.4.1-test-logs-<timestamp>.zip
```

When patched builds are discovered, the runner adds `test-built-tmux-screen-<timestamp>.log` and one build-specific tmux behavior log for each patched build to the same ZIP.

## Test-run artifact naming

By default the runner chooses the timestamp once at startup with `date +%Y%m%d-%H%M%S`. It will not overwrite an existing artifact with the same timestamp. For deterministic automation you can supply the timestamp explicitly:

```sh
SCREEN2TMUX_RUN_TIMESTAMP=20261004-211500 sh run-tests.sh
```

To place all logs and the ZIP elsewhere:

```sh
SCREEN2TMUX_LOG_DIR=/tmp/screen2tmux-logs sh run-tests.sh
```

The static package manifest intentionally excludes `logs/`, since those files are runtime artifacts and change on every test run.

## Console color

Interactive output uses selective ANSI colorization: only semantic elements such as `[PASS]`, `[FAIL]`, `[SKIP]`, translation classes (`exact`, `approx`, `unsupported`, `moot`, `external`, `invalid`), diagnostic labels (`APPROX`, `UNSUPPORTED`, `WARNING`, `suggestion`), section titles, and run-summary labels/statuses are colored. Descriptions, commands, arguments, paths, and whole lines are left in the terminal's normal color.

`run-tests.sh` applies color **after** `tee` writes the console transcript, so all timestamped `.log` files and the ZIP contents remain plain text with no ANSI escape bytes. Child test scripts are explicitly run with `NO_COLOR=1` for the same reason. When a test script is run standalone with forced console color, translator output captured into its detailed log is still forced plain, so the log remains ANSI-free.

Color policy is controlled with:

```sh
SCREEN2TMUX_COLOR=auto    # default: color only when the relevant fd is a terminal
SCREEN2TMUX_COLOR=always  # force terminal color; useful for testing/pagers that support ANSI
SCREEN2TMUX_COLOR=never   # disable color
NO_COLOR=1                # standard hard disable; overrides SCREEN2TMUX_COLOR=always
```

The translator itself uses the same policy for diagnostic labels on stderr. Exact dry-run command text remains uncolored and copy/paste safe.

## Source basis

The bundled command manifest was generated from the GNU Screen 5.0.2 source supplied with this project work. The tmux mappings were audited against the supplied tmux `next-3.9` development source snapshot. See `docs/SOURCE-BASIS.md`.

## Project files

```text
screen-to-tmux-translator-0.4.1/
├── VERSION
├── README.md
├── CHANGELOG.md
├── MANIFEST.sha256
├── build_tmux_3.7d.sh
├── build_tmux_3.7d_patched.sh
├── build_tmux_latest.sh
├── build_tmux_latest_patched.sh
├── bin/
│   ├── screen-function-source.sh
│   ├── screen-function-source-minified.sh
│   └── screen.sh
├── scripts/
│   └── build-tmux-one.sh
├── tmux-integration/
│   ├── screen-to-tmux-translator
│   └── tmux.c-screen-compat.patch
├── docs/
│   ├── SOURCE-BASIS.md
│   ├── TESTING.md
│   └── screen-5.0.2-command-manifest.tsv
├── tests/
│   ├── cases.sh
│   ├── interface-equivalence-worker.sh
│   ├── output-format.sh
│   ├── screen-syntax-oracle.sh
│   ├── test-built-tmux-screen.sh
│   ├── test-interface-equivalence.sh
│   ├── test-regressions.sh
│   ├── test-screen-cli.sh
│   └── test-tmux-behavior.sh
├── logs/
└── run-tests.sh
```

Build scripts create the eight `source-tmux-*` / `build-tmux-*` directories beside these project files at runtime; they are not part of the release ZIP or static manifest.

## Scope

This is intentionally not a promise that every Screen feature has a lossless tmux equivalent. GNU Screen and tmux have different object models, security models, configuration languages, terminal compatibility assumptions, and serial/network features. The translator's policy is to execute only mappings judged safe enough to call exact and to surface semantic differences explicitly everywhere else.
