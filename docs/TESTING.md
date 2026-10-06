# Testing model

## Purpose

The test suite checks that the translator recognizes the Screen command-line forms catalogued from GNU Screen 5.0.2 and classifies each as either:

- `mapped`: a safe tmux command can be emitted;
- `unsupported`: the Screen operation is valid/recognized but cannot be translated faithfully;
- `invalid`: negative-control syntax which must be rejected.

## Why the tests do not execute native GNU Screen

GNU Screen has no native dry-run facility. Many valid commands have unavoidable effects: starting persistent processes, attaching/detaching terminals, manipulating session sockets, touching login accounting, opening serial devices, or terminating sessions. The project therefore performs parser-level validation against its source-derived case manifest through the replacement `screen()` function.

## Dry-run placement test

Every nonempty case is invoked three ways:

```text
screen --dry-run <args...>
screen <first-arg> --dry-run <remaining-args...>
screen <args...> --dry-run
```

The zero-argument Screen invocation has two distinct placements.

This directly tests the project's guarantee that `--dry-run` is recognized anywhere in the Screen argument vector.

## Result log

Each invocation appends a record containing:

```text
CASE
DESCRIPTION
DRY_RUN_PLACEMENT
EXPECTED_CLASS
EXPECTED_EXIT
INPUT
ACTUAL_EXIT
OUTPUT_BEGIN ... OUTPUT_END
RESULT
```

The default log is `logs/test-screen-cli.log`.

## Exit expectations

```text
mapped       -> 0
unsupported  -> 2
invalid      -> 64
```

Any mismatch is a test failure.
