# screen-to-tmux-translator 0.3.9

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

Two reproducible build drivers are included:

```sh
sh build_tmux_3.7d.sh
sh build_tmux_latest.sh
```

`build_tmux_3.7d.sh` downloads the official `release_3.7d` branch. `build_tmux_latest.sh` downloads the official `master` branch at the commit current when the script is run. Both scripts record the exact source commit in `BUILD-INFO`.

Before downloading, the shared builder checks for the normal tmux-from-Git prerequisites: a C compiler and make, Git, Autoconf/Automake, yacc or bison, `pkg-config`, libevent 2.x development files, ncurses/terminfo development files, `patch`, and standard shell utilities. If something is missing, the builder reports the missing commands/libraries, detects `apt-get`, `dnf`, `yum`, `apk`, or Homebrew, shows the package set, and asks `Install the missing build software automatically and continue? [y/N]`. `y`/`yes` installs and then rechecks dependencies before continuing; `n`, Enter, or any other answer cancels the build without installing anything. Set `SCREEN2TMUX_AUTO_INSTALL=yes` or `no` to pre-answer the prompt for automation.

Each driver downloads one source commit, creates two independent clean snapshots, then performs two complete Autotools/configure/make/install builds:

```text
build/tmux-3.7d/
├── original/
│   ├── source/
│   └── install/bin/tmux
└── patched/
    ├── source/
    └── install/bin/
        ├── tmux
        └── screen   # hardlink to tmux

build/tmux-latest/
└── ... same layout ...
```

The patch contract is deliberately narrow. Before `autogen.sh` runs, the builder verifies that the patched source differs from pristine upstream in exactly two filesystem entries:

```text
modified: tmux.c
added:    screen-to-tmux-translator
```

All compatibility code lives in `tmux-integration/screen-to-tmux-translator`. `tmux-integration/tmux.c-screen-compat.patch` only includes that file and calls `screen_to_tmux_translate(&argc, &argv)` at the start of tmux's `main()`. Patch application uses zero fuzz; if a future `master` moves those locations, the latest builder stops instead of guessing.

The build scripts accept a few useful overrides:

```sh
TMUX_BUILD_JOBS=8 sh build_tmux_3.7d.sh
SCREEN2TMUX_BUILD_ROOT=/var/tmp/screen2tmux-builds sh build_tmux_latest.sh
TMUX_GIT_URL=https://github.com/tmux/tmux.git sh build_tmux_latest.sh
SCREEN2TMUX_AUTO_INSTALL=yes sh build_tmux_3.7d.sh
```

`TMUX_SOURCE_DIR=/path/to/an/existing/tmux/tree` is also available as an offline/test override; normal use downloads from GitHub.

## Tests

Run everything:

```sh
sh run-tests.sh
```

The test system has four always-available layers plus an automatic built-binary layer:

1. A **Screen syntax oracle**, independent from the translator, built from GNU Screen 5.0.2 `comm.c` command metadata plus a separate top-level CLI parser.
2. Translator tests that insert `--dry-run` at first/middle/last positions and compare the resulting classification. `first` means immediately after `screen`, `middle` means after the first real Screen argument, and `last` means after all real Screen arguments. These placements prove the translator-only flag is accepted without changing Screen argument parsing. Successful placements are collapsed to one console PASS per case; the detailed log still records every placement, and failures name the exact placement.
3. An **interface-equivalence suite**: canonical source versus minified source across all 683 dry-run placements, plus three-way canonical/minified/standalone comparison across all 228 base Screen command cases and a normal-execution stub test.
4. An **optional live tmux behavioral suite** using an isolated `-L` server. It is skipped cleanly if no tmux executable is installed.
5. When `build/tmux-3.7d` and/or `build/tmux-latest` contains a completed patched build, a **built hardlink suite** automatically runs the actual hardlink named `screen` through all 683 dry-run placements, requiring byte-for-byte output and identical exit status versus the canonical translator. It also performs an isolated real-execution smoke test and reruns the live tmux behavioral suite against each patched tmux binary. Successful first/middle/last placements are shown as one PASS per Screen case; the underlying detailed log still contains all 683 comparisons.

Current packaged results:

```text
683/683 translation dry-run permutations PASS
228/228 independent Screen syntax oracle cases PASS
85/85 focused semantic regression tests PASS
683/683 canonical/minified source-placement comparisons PASS
228/228 three-way command-case comparisons PASS
1/1 three-way normal-execution stub comparison PASS
live tmux behavior tests run when a tmux executable is available
built hardlink matrix: automatically 683/683 per discovered patched build
```

Each `sh run-tests.sh` invocation creates one timestamped run set. For example:

```text
logs/test-screen-cli-20261004-211500.log
logs/test-regressions-20261004-211500.log
logs/test-interface-equivalence-20261004-211500.log
logs/test-tmux-behavior-20261004-211500.log
logs/test-run-console-20261004-211500.log
logs/screen-to-tmux-translator-0.3.9-test-logs-20261004-211500.zip
```

With no compiled build present, all five base `.log` files use the same timestamp and the ZIP contains exactly those five logs. When a 3.7d/latest patched build is discovered, the runner adds `test-built-tmux-screen-<timestamp>.log` plus one `test-tmux-behavior-<build>-<timestamp>.log` for each discovered build, and includes those additional logs in the same ZIP.

`test-screen-cli-<timestamp>.log` records the displayed input, exact argv bytes in hex, output, output bytes in hex, expected class, actual exit code, and PASS/FAIL for every invocation.

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
screen-to-tmux-translator-0.3.9/
├── VERSION
├── README.md
├── CHANGELOG.md
├── MANIFEST.sha256
├── build_tmux_3.7d.sh
├── build_tmux_latest.sh
├── bin/
│   ├── screen-function-source.sh
│   ├── screen-function-source-minified.sh
│   └── screen.sh
├── scripts/
│   └── build-tmux-variant.sh
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
│   ├── screen-syntax-oracle.sh
│   ├── test-built-tmux-screen.sh
│   ├── test-interface-equivalence.sh
│   ├── test-regressions.sh
│   ├── test-screen-cli.sh
│   └── test-tmux-behavior.sh
├── logs/                       # runtime timestamped logs + one ZIP per run
└── run-tests.sh
```

## Scope

This is intentionally not a promise that every Screen feature has a lossless tmux equivalent. GNU Screen and tmux have different object models, security models, configuration languages, terminal compatibility assumptions, and serial/network features. The translator's policy is to execute only mappings judged safe enough to call exact and to surface semantic differences explicitly everywhere else.
