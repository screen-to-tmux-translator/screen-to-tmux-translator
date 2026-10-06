# screen-to-tmux-translator 0.2.0

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

## Important 0.2.0 correctness changes

0.2.0 fixes semantic false positives found by running the 0.1.0 test suite on a real system:

- `screen -d -m bash` now keeps `bash` as the initial program instead of misreading it as a session name.
- `screen -m` no longer translates to a detached tmux session; Screen `-m` means “force a new Screen session despite `$STY`”, not “detach”.
- `screen -c FILE` never becomes `tmux -f FILE`; Screen and tmux configuration languages are different.
- `screen ... -X source FILE` never becomes `tmux source-file FILE` without translation of the file contents.
- `screen -L` and `-Logfile` are no longer silently discarded.
- `screen -p 2 -r work` now preserves the selected window as `tmux attach-session -t work:2`.
- Screen region operations (`split`, `focus`, `only`, `resize`) are classified as approximations instead of exact pane operations.
- Screen saved layouts are no longer conflated with tmux pane-layout objects.
- Screen ACL add/delete operations are no longer executed automatically as tmux `server-access`, because that would broaden scope from one Screen session to the entire tmux server.
- Direct serial/Telnet substitutions are classified as `EXTERNAL`, not exact tmux mappings.
- Dry-run/log rendering escapes control bytes, fixing carriage-return corruption in test logs.

## Tests

Run everything:

```sh
sh run-tests.sh
```

The test system has two layers:

1. A **Screen syntax oracle**, independent from the translator, built from GNU Screen 5.0.2 `comm.c` command metadata plus a separate top-level CLI parser.
2. Translator tests that insert `--dry-run` at first/middle/last positions and compare the resulting classification.

Current packaged results:

```text
683/683 translation dry-run permutations PASS
228/228 independent Screen syntax oracle cases PASS
15/15 focused semantic regression tests PASS
```

Logs:

```text
logs/test-screen-cli.log
logs/test-regressions.log
```

`test-screen-cli.log` records the displayed input, exact argv bytes in hex, output, output bytes in hex, expected class, actual exit code, and PASS/FAIL for every invocation.

## Source basis

The bundled command manifest was generated from the GNU Screen 5.0.2 source supplied with this project work. The tmux mappings were audited against the supplied tmux `next-3.9` development source snapshot. See `docs/SOURCE-BASIS.md`.

## Project files

```text
screen-to-tmux-translator-0.2.0/
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
│   └── test-screen-cli.sh
├── logs/
│   ├── test-regressions.log
│   └── test-screen-cli.log
└── run-tests.sh
```

## Scope

This is intentionally not a promise that every Screen feature has a lossless tmux equivalent. GNU Screen and tmux have different object models, security models, configuration languages, terminal compatibility assumptions, and serial/network features. The translator's policy is to execute only mappings judged safe enough to call exact and to surface semantic differences explicitly everywhere else.
