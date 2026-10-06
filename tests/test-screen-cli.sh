#!/bin/sh
# POSIX-shell test harness for the screen-to-tmux translator.
# Calls the drop-in screen() function with --dry-run in multiple positions.

set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
TRANSLATOR=${TRANSLATOR:-$PROJECT_DIR/bin/screen-to-tmux.sh}
LOG_FILE=${LOG_FILE:-$PROJECT_DIR/logs/test-screen-cli.log}

if [ ! -r "$TRANSLATOR" ]; then
    printf '%s\n' "ERROR: cannot read translator: $TRANSLATOR" >&2
    exit 2
fi

# shellcheck disable=SC1090
. "$TRANSLATOR"

mkdir -p "$(dirname -- "$LOG_FILE")"
: > "$LOG_FILE"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_GREEN='\033[32m'
    C_RED='\033[31m'
    C_YELLOW='\033[33m'
    C_CYAN='\033[36m'
    C_RESET='\033[0m'
else
    C_GREEN=
    C_RED=
    C_YELLOW=
    C_CYAN=
    C_RESET=
fi

PASS=0
FAIL=0
TOTAL=0

quote_word()
{
    q=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
    printf "'%s'" "$q"
}

print_input()
{
    sep=
    for arg do
        printf '%s' "$sep"
        quote_word "$arg"
        sep=' '
    done
}

expected_rc()
{
    case "$1" in
        mapped) printf '0' ;;
        unsupported) printf '2' ;;
        invalid) printf '64' ;;
        *) printf '255' ;;
    esac
}

run_variant()
{
    id=$1
    expected=$2
    desc=$3
    placement=$4
    shift 4

    case "$placement" in
        first)
            input_text=$(print_input screen --dry-run "$@")
            output=$(screen --dry-run "$@" 2>&1)
            rc=$?
            ;;
        middle)
            if [ "$#" -eq 0 ]; then return 0; fi
            first_arg=$1
            shift
            input_text=$(print_input screen "$first_arg" --dry-run "$@")
            output=$(screen "$first_arg" --dry-run "$@" 2>&1)
            rc=$?
            ;;
        last)
            input_text=$(print_input screen "$@" --dry-run)
            output=$(screen "$@" --dry-run 2>&1)
            rc=$?
            ;;
        *)
            printf 'internal test error: unknown placement %s\n' "$placement" >&2
            exit 2
            ;;
    esac

    want=$(expected_rc "$expected")
    TOTAL=$((TOTAL + 1))
    if [ "$rc" -eq "$want" ]; then
        PASS=$((PASS + 1))
        result=PASS
        printf '%b[PASS]%b %s %-11s %-6s %s\n' "$C_GREEN" "$C_RESET" "$id" "$expected" "$placement" "$desc"
    else
        FAIL=$((FAIL + 1))
        result=FAIL
        printf '%b[FAIL]%b %s expected=%s(rc=%s) got=%s placement=%s %s\n' "$C_RED" "$C_RESET" "$id" "$expected" "$want" "$rc" "$placement" "$desc"
    fi

    {
        printf '%s\n' '=============================================================================='
        printf 'CASE: %s\n' "$id"
        printf 'DESCRIPTION: %s\n' "$desc"
        printf 'DRY_RUN_PLACEMENT: %s\n' "$placement"
        printf 'EXPECTED_CLASS: %s\n' "$expected"
        printf 'EXPECTED_EXIT: %s\n' "$want"
        printf 'INPUT: %s\n' "$input_text"
        printf 'ACTUAL_EXIT: %s\n' "$rc"
        printf '%s\n' 'OUTPUT_BEGIN'
        printf '%s\n' "$output"
        printf '%s\n' 'OUTPUT_END'
        printf 'RESULT: %s\n' "$result"
    } >> "$LOG_FILE"
}

case_()
{
    id=$1
    expected=$2
    desc=$3
    shift 3

    # Requirement: --dry-run may appear anywhere in the Screen argument vector.
    # Exercise first argument position, one interior position, and final position.
    run_variant "$id" "$expected" "$desc" first "$@"
    if [ "$#" -gt 0 ]; then
        run_variant "$id" "$expected" "$desc" middle "$@"
    fi
    run_variant "$id" "$expected" "$desc" last "$@"
}

printf '%s\n' "screen-to-tmux-translator test run" >> "$LOG_FILE"
printf 'VERSION: %s\n' "${SCREEN2TMUX_VERSION:-unknown}" >> "$LOG_FILE"
printf 'TRANSLATOR: %s\n' "$TRANSLATOR" >> "$LOG_FILE"
printf 'NOTE: GNU Screen has no native --dry-run. These tests call the translator\047s drop-in screen() function.\n' >> "$LOG_FILE"
printf '%s\n' '==============================================================================' >> "$LOG_FILE"

# shellcheck disable=SC1090
. "$TEST_DIR/cases.sh"

printf '%s\n' '==============================================================================' >> "$LOG_FILE"
printf 'SUMMARY: total=%s pass=%s fail=%s\n' "$TOTAL" "$PASS" "$FAIL" >> "$LOG_FILE"

printf '\n%bSummary:%b %b%s PASS%b, %b%s FAIL%b, %s total\n' \
    "$C_CYAN" "$C_RESET" "$C_GREEN" "$PASS" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET" "$TOTAL"
printf '%bLog:%b %s\n' "$C_YELLOW" "$C_RESET" "$LOG_FILE"

[ "$FAIL" -eq 0 ]
