#!/bin/sh
# Run the complete test suite using one shared timestamp for every artifact.
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOG_DIR=${SCREEN2TMUX_LOG_DIR:-$HERE/logs}
RUN_TIMESTAMP=${SCREEN2TMUX_RUN_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}

case "$RUN_TIMESTAMP" in
    *[!0-9A-Za-z._-]*|'')
        printf 'ERROR: invalid SCREEN2TMUX_RUN_TIMESTAMP: %s\n' "$RUN_TIMESTAMP" >&2
        exit 64
        ;;
esac

mkdir -p "$LOG_DIR"
LOG_DIR=$(CDPATH= cd -- "$LOG_DIR" && pwd)

CLI_LOG=$LOG_DIR/test-screen-cli-$RUN_TIMESTAMP.log
REG_LOG=$LOG_DIR/test-regressions-$RUN_TIMESTAMP.log
BEHAVIOR_LOG=$LOG_DIR/test-tmux-behavior-$RUN_TIMESTAMP.log
CONSOLE_LOG=$LOG_DIR/test-run-console-$RUN_TIMESTAMP.log
ARCHIVE=$LOG_DIR/screen-to-tmux-translator-test-logs-$RUN_TIMESTAMP.zip

# Do not append to artifacts from an earlier run using the same forced timestamp.
for _f in "$CLI_LOG" "$REG_LOG" "$BEHAVIOR_LOG" "$CONSOLE_LOG" "$ARCHIVE"; do
    [ ! -e "$_f" ] || {
        printf 'ERROR: test-run artifact already exists: %s\n' "$_f" >&2
        printf 'Use a new timestamp or remove the existing artifact.\n' >&2
        exit 73
    }
done

: > "$CLI_LOG"
: > "$REG_LOG"
: > "$BEHAVIOR_LOG"
: > "$CONSOLE_LOG"

{
    printf 'screen-to-tmux-translator test run\n'
    printf 'RUN_TIMESTAMP: %s\n' "$RUN_TIMESTAMP"
    printf 'RUN_STARTED: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf 'PROJECT: %s\n' "$HERE"
    printf '%s\n' '=============================================================================='
} | tee -a "$CONSOLE_LOG"

run_component()
{
    _name=$1
    shift
    _rc_file=$LOG_DIR/.run-tests-$RUN_TIMESTAMP-$$.rc
    rm -f "$_rc_file"

    printf '\n===== %s =====\n' "$_name" | tee -a "$CONSOLE_LOG"

    # POSIX sh has no pipefail. Record the component status out-of-band while
    # tee mirrors its output to both the terminal and the timestamped console log.
    (
        "$@"
        _rc=$?
        printf '%s\n' "$_rc" > "$_rc_file"
        exit 0
    ) 2>&1 | tee -a "$CONSOLE_LOG"

    if [ ! -r "$_rc_file" ]; then
        printf 'ERROR: could not recover status for %s\n' "$_name" | tee -a "$CONSOLE_LOG" >&2
        return 125
    fi
    _rc=$(cat "$_rc_file")
    rm -f "$_rc_file"
    return "$_rc"
}

suite_rc=0

if run_component 'screen CLI/oracle tests' env LOG_FILE="$CLI_LOG" "$HERE/tests/test-screen-cli.sh" "$@"; then :; else suite_rc=1; fi
if run_component 'focused regressions' env REG_LOG="$REG_LOG" "$HERE/tests/test-regressions.sh" "$@"; then :; else suite_rc=1; fi
if run_component 'live tmux behavior tests' env BEHAVIOR_LOG="$BEHAVIOR_LOG" "$HERE/tests/test-tmux-behavior.sh" "$@"; then :; else suite_rc=1; fi

printf '\n%s\n' '==============================================================================' | tee -a "$CONSOLE_LOG"
printf 'RUN_FINISHED: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" | tee -a "$CONSOLE_LOG"
printf 'RUN_STATUS: %s\n' "$(if [ "$suite_rc" -eq 0 ]; then printf PASS; else printf FAIL; fi)" | tee -a "$CONSOLE_LOG"
printf 'LOG_SCREEN_CLI: %s\n' "$CLI_LOG" | tee -a "$CONSOLE_LOG"
printf 'LOG_REGRESSIONS: %s\n' "$REG_LOG" | tee -a "$CONSOLE_LOG"
printf 'LOG_TMUX_BEHAVIOR: %s\n' "$BEHAVIOR_LOG" | tee -a "$CONSOLE_LOG"
printf 'LOG_CONSOLE: %s\n' "$CONSOLE_LOG" | tee -a "$CONSOLE_LOG"
printf 'LOG_ARCHIVE: %s\n' "$ARCHIVE" | tee -a "$CONSOLE_LOG"

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
    "$(basename -- "$BEHAVIOR_LOG")" \
    "$(basename -- "$CONSOLE_LOG")"

if archive_logs "$ARCHIVE" "$@"; then
    printf 'Log archive: %s\n' "$ARCHIVE"
else
    suite_rc=1
    printf 'ERROR: failed to create log archive: %s\n' "$ARCHIVE" | tee -a "$CONSOLE_LOG" >&2
fi

exit "$suite_rc"
