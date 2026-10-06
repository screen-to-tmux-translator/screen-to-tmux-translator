#!/bin/sh
# Run the complete test suite using one shared timestamp for every artifact.
# Console color is applied after plain-text logging so archived logs never
# contain ANSI escapes.
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION=$(cat "$HERE/VERSION" 2>/dev/null || printf unknown)
LOG_DIR=${SCREEN2TMUX_LOG_DIR:-$HERE/logs}
RUN_TIMESTAMP=${SCREEN2TMUX_RUN_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}

case "$RUN_TIMESTAMP" in
    *[!0-9A-Za-z._-]*|'')
        printf 'ERROR: invalid SCREEN2TMUX_RUN_TIMESTAMP: %s\n' "$RUN_TIMESTAMP" >&2
        exit 64
        ;;
esac

case "${SCREEN2TMUX_COLOR:-auto}" in
    auto|'') COLOR_MODE=auto ;;
    always) COLOR_MODE=always ;;
    never) COLOR_MODE=never ;;
    *)
        printf 'ERROR: SCREEN2TMUX_COLOR must be auto, always, or never (got: %s)\n' "${SCREEN2TMUX_COLOR}" >&2
        exit 64
        ;;
esac

COLOR_ENABLED=0
if [ -z "${NO_COLOR:-}" ]; then
    case "$COLOR_MODE" in
        always) COLOR_ENABLED=1 ;;
        auto)
            if [ -t 1 ] && [ "${TERM:-}" != dumb ]; then COLOR_ENABLED=1; fi
            ;;
    esac
fi

# Color only semantic tokens on the terminal. The input to this filter has
# already passed through tee into the plain-text console log.
colorize_stream()
{
    if [ "$COLOR_ENABLED" -ne 1 ]; then
        cat
        return
    fi

    awk \
        -v G="$(printf '\033[32m')" \
        -v R="$(printf '\033[31m')" \
        -v Y="$(printf '\033[33m')" \
        -v C="$(printf '\033[36m')" \
        -v M="$(printf '\033[35m')" \
        -v Z="$(printf '\033[0m')" '
    {
        line = $0

        # Fixed-column CLI test rows: color only the translation class token.
        if (line ~ /^\[(PASS|FAIL)\] [A-Z][0-9][0-9][0-9] /) {
            sub(/ exact/,       " " G "exact" Z, line)
            sub(/ approx/,      " " Y "approx" Z, line)
            sub(/ unsupported/, " " R "unsupported" Z, line)
            sub(/ moot/,        " " C "moot" Z, line)
            sub(/ external/,    " " M "external" Z, line)
            sub(/ invalid/,     " " R "invalid" Z, line)
        }

        # Result markers.
        gsub(/\[PASS\]/, G "[PASS]" Z, line)
        gsub(/\[FAIL\]/, R "[FAIL]" Z, line)
        gsub(/\[SKIP\]/, Y "[SKIP]" Z, line)

        # Translator diagnostics: only the class/label, never the full text.
        gsub(/: EXACT:/,       ": " G "EXACT" Z ":", line)
        gsub(/: APPROX:/,      ": " Y "APPROX" Z ":", line)
        gsub(/: UNSUPPORTED:/, ": " R "UNSUPPORTED" Z ":", line)
        gsub(/: MOOT:/,        ": " C "MOOT" Z ":", line)
        gsub(/: EXTERNAL:/,    ": " M "EXTERNAL" Z ":", line)
        gsub(/: INVALID:/,     ": " R "INVALID" Z ":", line)
        gsub(/: WARNING:/,     ": " Y "WARNING" Z ":", line)
        gsub(/: suggestion:/,  ": " C "suggestion" Z ":", line)
        gsub(/: note:/,        ": " C "note" Z ":", line)

        # Run-level labels and summaries.
        if (line ~ /^(Summary|Regression summary|Interface equivalence summary|Behavior summary|Built screen summary):/) {
            gsub(/ PASS/, " " G "PASS" Z, line)
            gsub(/ FAIL/, " " R "FAIL" Z, line)
        }
        sub(/^ERROR:/, R "ERROR" Z ":", line)
        sub(/^WARNING:/, Y "WARNING" Z ":", line)
        sub(/^Summary:/, C "Summary" Z ":", line)
        sub(/^Regression summary:/, C "Regression summary" Z ":", line)
        sub(/^Interface equivalence summary:/, C "Interface equivalence summary" Z ":", line)
        sub(/^Behavior summary:/, C "Behavior summary" Z ":", line)
        sub(/^Built screen summary:/, C "Built screen summary" Z ":", line)
        sub(/^Log:/, C "Log" Z ":", line)
        sub(/^Regression log:/, C "Regression log" Z ":", line)
        sub(/^Equivalence log:/, C "Equivalence log" Z ":", line)
        sub(/^Behavior log:/, C "Behavior log" Z ":", line)
        sub(/^Built screen log:/, C "Built screen log" Z ":", line)
        sub(/^Log archive:/, C "Log archive" Z ":", line)
        sub(/^RUN_TIMESTAMP:/, C "RUN_TIMESTAMP" Z ":", line)
        sub(/^RUN_STARTED:/, C "RUN_STARTED" Z ":", line)
        sub(/^RUN_FINISHED:/, C "RUN_FINISHED" Z ":", line)
        sub(/^PROJECT:/, C "PROJECT" Z ":", line)
        sub(/^LOG_SCREEN_CLI:/, C "LOG_SCREEN_CLI" Z ":", line)
        sub(/^LOG_REGRESSIONS:/, C "LOG_REGRESSIONS" Z ":", line)
        sub(/^LOG_EQUIVALENCE:/, C "LOG_EQUIVALENCE" Z ":", line)
        sub(/^LOG_TMUX_BEHAVIOR:/, C "LOG_TMUX_BEHAVIOR" Z ":", line)
        sub(/^LOG_BUILT_SCREEN:/, C "LOG_BUILT_SCREEN" Z ":", line)
        sub(/^LOG_TMUX_3_7D_BEHAVIOR:/, C "LOG_TMUX_3_7D_BEHAVIOR" Z ":", line)
        sub(/^LOG_TMUX_LATEST_BEHAVIOR:/, C "LOG_TMUX_LATEST_BEHAVIOR" Z ":", line)
        sub(/^LOG_CONSOLE:/, C "LOG_CONSOLE" Z ":", line)
        sub(/^LOG_ARCHIVE:/, C "LOG_ARCHIVE" Z ":", line)
        sub(/^RUN_STATUS: PASS$/, "RUN_STATUS: " G "PASS" Z, line)
        sub(/^RUN_STATUS: FAIL$/, "RUN_STATUS: " R "FAIL" Z, line)

        # Section titles: leave the separator characters uncolored.
        if (line ~ /^===== .* =====$/) {
            sub(/^===== /, "===== " C, line)
            sub(/ =====$/, Z " =====", line)
        }

        print line
    }'
}

mkdir -p "$LOG_DIR"
LOG_DIR=$(CDPATH= cd -- "$LOG_DIR" && pwd)

BUILD_BASE=${SCREEN2TMUX_BUILD_ROOT:-$HERE/build}
BUILD37_ROOT=$BUILD_BASE/tmux-3.7d
BUILDLATEST_ROOT=$BUILD_BASE/tmux-latest
BUILD37_TMUX=$BUILD37_ROOT/patched/install/bin/tmux
BUILD37_SCREEN=$BUILD37_ROOT/patched/install/bin/screen
BUILDLATEST_TMUX=$BUILDLATEST_ROOT/patched/install/bin/tmux
BUILDLATEST_SCREEN=$BUILDLATEST_ROOT/patched/install/bin/screen
HAS_BUILD37=0
HAS_BUILDLATEST=0
if [ -f "$BUILD37_ROOT/BUILD-INFO" ] || [ -x "$BUILD37_SCREEN" ]; then HAS_BUILD37=1; fi
if [ -f "$BUILDLATEST_ROOT/BUILD-INFO" ] || [ -x "$BUILDLATEST_SCREEN" ]; then HAS_BUILDLATEST=1; fi

CLI_LOG=$LOG_DIR/test-screen-cli-$RUN_TIMESTAMP.log
REG_LOG=$LOG_DIR/test-regressions-$RUN_TIMESTAMP.log
EQUIV_LOG=$LOG_DIR/test-interface-equivalence-$RUN_TIMESTAMP.log
BEHAVIOR_LOG=$LOG_DIR/test-tmux-behavior-$RUN_TIMESTAMP.log
BUILT_SCREEN_LOG=$LOG_DIR/test-built-tmux-screen-$RUN_TIMESTAMP.log
BUILD37_BEHAVIOR_LOG=$LOG_DIR/test-tmux-behavior-tmux-3.7d-$RUN_TIMESTAMP.log
BUILDLATEST_BEHAVIOR_LOG=$LOG_DIR/test-tmux-behavior-tmux-latest-$RUN_TIMESTAMP.log
CONSOLE_LOG=$LOG_DIR/test-run-console-$RUN_TIMESTAMP.log
ARCHIVE=$LOG_DIR/screen-to-tmux-translator-$VERSION-test-logs-$RUN_TIMESTAMP.zip

# Do not append to artifacts from an earlier run using the same forced timestamp.
check_new_artifact()
{
    [ ! -e "$1" ] || {
        printf 'ERROR: test-run artifact already exists: %s\n' "$1" >&2
        printf 'Use a new timestamp or remove the existing artifact.\n' >&2
        exit 73
    }
}
for _f in "$CLI_LOG" "$REG_LOG" "$EQUIV_LOG" "$BEHAVIOR_LOG" "$CONSOLE_LOG" "$ARCHIVE"; do check_new_artifact "$_f"; done
if [ "$HAS_BUILD37" -eq 1 ] || [ "$HAS_BUILDLATEST" -eq 1 ]; then check_new_artifact "$BUILT_SCREEN_LOG"; fi
if [ "$HAS_BUILD37" -eq 1 ]; then check_new_artifact "$BUILD37_BEHAVIOR_LOG"; fi
if [ "$HAS_BUILDLATEST" -eq 1 ]; then check_new_artifact "$BUILDLATEST_BEHAVIOR_LOG"; fi

: > "$CLI_LOG"
: > "$REG_LOG"
: > "$EQUIV_LOG"
: > "$BEHAVIOR_LOG"
: > "$CONSOLE_LOG"
if [ "$HAS_BUILD37" -eq 1 ] || [ "$HAS_BUILDLATEST" -eq 1 ]; then : > "$BUILT_SCREEN_LOG"; fi
if [ "$HAS_BUILD37" -eq 1 ]; then : > "$BUILD37_BEHAVIOR_LOG"; fi
if [ "$HAS_BUILDLATEST" -eq 1 ]; then : > "$BUILDLATEST_BEHAVIOR_LOG"; fi

{
    printf 'screen-to-tmux-translator test run\n'
    printf 'RUN_TIMESTAMP: %s\n' "$RUN_TIMESTAMP"
    printf 'RUN_STARTED: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf 'PROJECT: %s\n' "$HERE"
    printf 'DISCOVERED_BUILD_3_7D: %s\n' "$HAS_BUILD37"
    printf 'DISCOVERED_BUILD_LATEST: %s\n' "$HAS_BUILDLATEST"
    printf '%s\n' '=============================================================================='
} | tee -a "$CONSOLE_LOG" | colorize_stream

run_component()
{
    _name=$1
    shift
    _rc_file=$LOG_DIR/.run-tests-$RUN_TIMESTAMP-$$.rc
    rm -f "$_rc_file"

    printf '\n===== %s =====\n' "$_name" | tee -a "$CONSOLE_LOG" | colorize_stream

    # POSIX sh has no pipefail. Record the component status out-of-band while
    # tee stores plain output. NO_COLOR=1 guarantees that child test programs
    # cannot inject ANSI escapes into either their own logs or the console log.
    (
        NO_COLOR=1 "$@"
        _rc=$?
        printf '%s\n' "$_rc" > "$_rc_file"
        exit 0
    ) 2>&1 | tee -a "$CONSOLE_LOG" | colorize_stream

    if [ ! -r "$_rc_file" ]; then
        printf 'ERROR: could not recover status for %s\n' "$_name" | tee -a "$CONSOLE_LOG" | colorize_stream >&2
        return 125
    fi
    _rc=$(cat "$_rc_file")
    rm -f "$_rc_file"
    return "$_rc"
}

suite_rc=0

if run_component 'screen CLI/oracle tests' env LOG_FILE="$CLI_LOG" "$HERE/tests/test-screen-cli.sh" "$@"; then :; else suite_rc=1; fi
if run_component 'focused regressions' env REG_LOG="$REG_LOG" "$HERE/tests/test-regressions.sh" "$@"; then :; else suite_rc=1; fi
if run_component 'interface equivalence tests' env EQUIV_LOG="$EQUIV_LOG" "$HERE/tests/test-interface-equivalence.sh" "$@"; then :; else suite_rc=1; fi
if run_component 'live tmux behavior tests' env BEHAVIOR_LOG="$BEHAVIOR_LOG" "$HERE/tests/test-tmux-behavior.sh" "$@"; then :; else suite_rc=1; fi

if [ "$HAS_BUILD37" -eq 1 ] || [ "$HAS_BUILDLATEST" -eq 1 ]; then
    if [ "$HAS_BUILD37" -eq 1 ] && [ "$HAS_BUILDLATEST" -eq 1 ]; then
        if run_component 'built patched tmux screen hardlink tests' env BUILT_SCREEN_LOG="$BUILT_SCREEN_LOG" "$HERE/tests/test-built-tmux-screen.sh" "$BUILD37_SCREEN" "$BUILDLATEST_SCREEN"; then :; else suite_rc=1; fi
    elif [ "$HAS_BUILD37" -eq 1 ]; then
        if run_component 'built patched tmux screen hardlink tests' env BUILT_SCREEN_LOG="$BUILT_SCREEN_LOG" "$HERE/tests/test-built-tmux-screen.sh" "$BUILD37_SCREEN"; then :; else suite_rc=1; fi
    else
        if run_component 'built patched tmux screen hardlink tests' env BUILT_SCREEN_LOG="$BUILT_SCREEN_LOG" "$HERE/tests/test-built-tmux-screen.sh" "$BUILDLATEST_SCREEN"; then :; else suite_rc=1; fi
    fi
fi
if [ "$HAS_BUILD37" -eq 1 ]; then
    if run_component 'live tmux behavior tests (patched 3.7d)' env TMUX_BIN="$BUILD37_TMUX" BEHAVIOR_LOG="$BUILD37_BEHAVIOR_LOG" "$HERE/tests/test-tmux-behavior.sh"; then :; else suite_rc=1; fi
fi
if [ "$HAS_BUILDLATEST" -eq 1 ]; then
    if run_component 'live tmux behavior tests (patched latest)' env TMUX_BIN="$BUILDLATEST_TMUX" BEHAVIOR_LOG="$BUILDLATEST_BEHAVIOR_LOG" "$HERE/tests/test-tmux-behavior.sh"; then :; else suite_rc=1; fi
fi

{
    printf '\n%s\n' '=============================================================================='
    printf 'RUN_FINISHED: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf 'RUN_STATUS: %s\n' "$(if [ "$suite_rc" -eq 0 ]; then printf PASS; else printf FAIL; fi)"
    printf 'LOG_SCREEN_CLI: %s\n' "$CLI_LOG"
    printf 'LOG_REGRESSIONS: %s\n' "$REG_LOG"
    printf 'LOG_EQUIVALENCE: %s\n' "$EQUIV_LOG"
    printf 'LOG_TMUX_BEHAVIOR: %s\n' "$BEHAVIOR_LOG"
    if [ "$HAS_BUILD37" -eq 1 ] || [ "$HAS_BUILDLATEST" -eq 1 ]; then printf 'LOG_BUILT_SCREEN: %s\n' "$BUILT_SCREEN_LOG"; fi
    if [ "$HAS_BUILD37" -eq 1 ]; then printf 'LOG_TMUX_3_7D_BEHAVIOR: %s\n' "$BUILD37_BEHAVIOR_LOG"; fi
    if [ "$HAS_BUILDLATEST" -eq 1 ]; then printf 'LOG_TMUX_LATEST_BEHAVIOR: %s\n' "$BUILDLATEST_BEHAVIOR_LOG"; fi
    printf 'LOG_CONSOLE: %s\n' "$CONSOLE_LOG"
    printf 'LOG_ARCHIVE: %s\n' "$ARCHIVE"
} | tee -a "$CONSOLE_LOG" | colorize_stream

archive_logs()
{
    _archive=$1
    shift

    if command -v zip >/dev/null 2>&1; then
        (
            cd "$LOG_DIR" || exit 1
            zip -q "$(basename -- "$_archive")" "$@"
        )
        return $?
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$LOG_DIR" "$_archive" "$@" <<'PY'
import os
import sys
import zipfile

log_dir, archive, *names = sys.argv[1:]
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for name in names:
        zf.write(os.path.join(log_dir, name), arcname=name)
PY
        return $?
    fi

    printf 'ERROR: cannot create requested ZIP: neither zip nor python3 is installed.\n' >&2
    return 127
}

set -- \
    "$(basename -- "$CLI_LOG")" \
    "$(basename -- "$REG_LOG")" \
    "$(basename -- "$EQUIV_LOG")" \
    "$(basename -- "$BEHAVIOR_LOG")" \
    "$(basename -- "$CONSOLE_LOG")"
if [ "$HAS_BUILD37" -eq 1 ] || [ "$HAS_BUILDLATEST" -eq 1 ]; then set -- "$@" "$(basename -- "$BUILT_SCREEN_LOG")"; fi
if [ "$HAS_BUILD37" -eq 1 ]; then set -- "$@" "$(basename -- "$BUILD37_BEHAVIOR_LOG")"; fi
if [ "$HAS_BUILDLATEST" -eq 1 ]; then set -- "$@" "$(basename -- "$BUILDLATEST_BEHAVIOR_LOG")"; fi

if archive_logs "$ARCHIVE" "$@"; then
    printf 'Log archive: %s\n' "$ARCHIVE" | colorize_stream
else
    suite_rc=1
    printf 'ERROR: failed to create log archive: %s\n' "$ARCHIVE" | tee -a "$CONSOLE_LOG" | colorize_stream >&2
fi

exit "$suite_rc"
