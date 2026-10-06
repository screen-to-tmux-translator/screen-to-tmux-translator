# screen-to-tmux-translator 0.1.0

A POSIX-shell compatibility translator for GNU Screen 5.0.x command lines.

The project defines two shell functions:

- `screen2tmux ...` — explicit translator entry point.
- `screen ...` — drop-in Screen-compatible entry point, unless `SCREEN2TMUX_NO_SCREEN_FUNCTION=1` is set before sourcing the script.

The translator maps Screen operations to tmux where the semantics are sufficiently close. When Screen exposes functionality tmux does not have, or where a superficially similar tmux command would change the semantics materially, it refuses the translation and prints the reason plus a suggested alternative.

## Load it

```sh
. ./bin/screen-to-tmux.sh
```

This intentionally defines a shell function named `screen`, so it shadows an installed GNU Screen executable in that shell. To invoke the native executable anyway, use `command screen ...`.

To load only `screen2tmux` without defining the `screen` function:

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

A mapped command prints the shell-quoted tmux command instead of executing it:

```text
'tmux' 'send-keys' '-l' '-t' 'work' 'hello'
```

A valid Screen operation that cannot be represented faithfully prints a reason and suggestion:

```text
screen2tmux: cannot translate exactly: Screen removes a display region without killing its window; tmux has no separate region object because a pane is both the PTY and the layout object.
screen2tmux: suggestion: Use resize-pane -Z to zoom, or break-pane before kill-pane if you need to preserve the process.
```

## Exit status

| Status | Meaning |
| ---: | --- |
| `0` | Screen command was translated; tmux was executed, or printed under `--dry-run`. |
| `2` | Screen syntax/operation is recognized, but there is no faithful automatic tmux equivalent. |
| `64` | Invalid or unknown Screen syntax for the translator. |
| other | When not using `--dry-run`, tmux's own exit status may be returned. |

## Tests

Run:

```sh
./tests/test-screen-cli.sh
```

The harness sources the translator and **calls the drop-in `screen()` function**, always with `--dry-run`. For each source-derived Screen command-line case it tests dry-run in the first argument position, an interior position where one exists, and the last position.

Current project test inventory:

- 218 source-derived valid Screen command-line cases.
- 10 negative controls.
- 683 concrete dry-run invocations after placement permutations.
- Current packaged result: **683 PASS, 0 FAIL**.

Console PASS/FAIL results use ANSI colors when stdout is a terminal. Set `NO_COLOR=1` to disable colors.

The complete input/output transcript is written to:

```text
logs/test-screen-cli.log
```

You may choose another path:

```sh
LOG_FILE=/tmp/screen2tmux.log ./tests/test-screen-cli.sh
```

## What "syntax validation" means here

GNU Screen itself does **not** provide a native `--dry-run` option. The test suite therefore does not execute a real Screen process for each case. Instead:

1. The case manifest is derived from the GNU Screen 5.0.2 command-line/parser behavior and the valid command forms catalogued while inspecting that source tree.
2. The harness calls this project's replacement `screen()` function with `--dry-run`.
3. A valid mapped command must return `0`.
4. A valid but deliberately unsupported Screen operation must return `2` with an explanation.
5. Negative controls must return `64`.

This validates the translator's Screen parser and classification without creating sessions, detaching terminals, touching utmp, opening serial devices, or otherwise causing the side effects that native Screen command validation would entail.

Some Screen facilities are build/platform dependent, especially built-in Telnet and utmp support. Their syntactic forms remain represented in the manifest because they are valid forms in configurations where those features are compiled.

## Files

```text
screen-to-tmux-translator-0.1.0/
├── VERSION
├── README.md
├── CHANGELOG.md
├── bin/
│   └── screen-to-tmux.sh
├── docs/
│   └── TESTING.md
├── tests/
│   ├── cases.sh
│   └── test-screen-cli.sh
└── logs/
    └── test-screen-cli.log
```

## Scope and safety

The translator is intentionally conservative. It does not silently replace a Screen operation with a tmux operation that would destroy a process, weaken access controls, or otherwise alter important semantics. Examples include Screen display-region removal, detailed Screen ACLs/writelock, native serial BREAK, ZMODEM handling, and legacy character-set translation.
