# screen-to-tmux-translator 0.3.2

A conservative POSIX-shell compatibility translator for GNU Screen 5.0.x command lines.

It defines:

- `screen2tmux ...` — explicit translator entry point.
- `screen ...` — optional drop-in shell function, unless `SCREEN2TMUX_NO_SCREEN_FUNCTION=1` is set before sourcing the file.

The translator executes only mappings classified as **EXACT**. When a tmux command is merely similar, broader in scope, depends on an external program, or the Screen operation is unnecessary under tmux's architecture, the translator explains that instead of silently executing a misleading substitute.

## Load it

```sh
. ./bin/screen-to-tmux.sh
```

This defines a shell function named `screen`, shadowing an installed GNU Screen executable in that shell. Use `command screen ...` to invoke the native executable.

To define only `screen2tmux`:

```sh
SCREEN2TMUX_NO_SCREEN_FUNCTION=1
export SCREEN2TMUX_NO_SCREEN_FUNCTION
. ./bin/screen-to-tmux.sh
```

## Dry run

`--dry-run` may appear anywhere in the Screen argument vector:

```sh
screen --dry-run -S work -X stuff hello
screen -S work --dry-run -X stuff hello
screen -S work -X stuff hello --dry-run
```

An exact mapping prints the tmux argv instead of executing it:

```text
'tmux' 'send-keys' '-l' '-t' 'work:0' 'hello'
```

Control bytes are escaped in dry-run output so they cannot corrupt the terminal or log. For example a carriage return is shown as `\r`.

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
- `screen -v`, `screen --version`, `screen --help`, and internal `version` are `UNSUPPORTED` as compatibility translations because tmux would report tmux help/version text, not Screen output.
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
. ./bin/screen-to-tmux.sh
```

then named creation is permitted as an `EXACT` mapping within that explicit policy.

## Tests

Run everything:

```sh
sh run-tests.sh
```

The test system has three layers:

1. A **Screen syntax oracle**, independent from the translator, built from GNU Screen 5.0.2 `comm.c` command metadata plus a separate top-level CLI parser.
2. Translator tests that insert `--dry-run` at first/middle/last positions and compare the resulting classification.
3. An **optional live tmux behavioral suite** using an isolated `-L` server. It is skipped cleanly if no tmux executable is installed.

Current packaged results:

```text
683/683 translation dry-run permutations PASS
228/228 independent Screen syntax oracle cases PASS
68/68 focused semantic regression tests PASS
live tmux behavior tests run when a tmux executable is available
```

Each `sh run-tests.sh` invocation creates one timestamped run set. For example:

```text
logs/test-screen-cli-20261004-211500.log
logs/test-regressions-20261004-211500.log
logs/test-tmux-behavior-20261004-211500.log
logs/test-run-console-20261004-211500.log
logs/screen-to-tmux-translator-test-logs-20261004-211500.zip
```

All four `.log` files use the same timestamp and the ZIP is created automatically after the test layers finish. The ZIP contains exactly those four logs from that run.

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

## Source basis

The bundled command manifest was generated from the GNU Screen 5.0.2 source supplied with this project work. The tmux mappings were audited against the supplied tmux `next-3.9` development source snapshot. See `docs/SOURCE-BASIS.md`.

## Project files

```text
screen-to-tmux-translator-0.3.2/
├── VERSION
├── README.md
├── CHANGELOG.md
├── MANIFEST.sha256
├── bin/
│   └── screen-to-tmux.sh
├── docs/
│   ├── SOURCE-BASIS.md
│   ├── TESTING.md
│   └── screen-5.0.2-command-manifest.tsv
├── tests/
│   ├── cases.sh
│   ├── screen-syntax-oracle.sh
│   ├── test-regressions.sh
│   ├── test-screen-cli.sh
│   └── test-tmux-behavior.sh
├── logs/                       # runtime timestamped logs + one ZIP per run
└── run-tests.sh
```

## Scope

This is intentionally not a promise that every Screen feature has a lossless tmux equivalent. GNU Screen and tmux have different object models, security models, configuration languages, terminal compatibility assumptions, and serial/network features. The translator's policy is to execute only mappings judged safe enough to call exact and to surface semantic differences explicitly everywhere else.
