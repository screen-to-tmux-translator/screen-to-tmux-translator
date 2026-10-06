#!/bin/sh
# POSIX-shell test harness for screen-to-tmux-translator 0.3.9.
# 1. Validate base Screen syntax with an independent Screen 5.0.2 oracle.
# 2. Exercise translator --dry-run at first/middle/last argument positions.
# 3. Log escaped argv/output plus exact byte hex.

set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
TRANSLATOR=${TRANSLATOR:-$PROJECT_DIR/bin/screen-function-source.sh}
ORACLE=${ORACLE:-$TEST_DIR/screen-syntax-oracle.sh}
RUN_TIMESTAMP=${SCREEN2TMUX_RUN_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}
LOG_FILE=${LOG_FILE:-$PROJECT_DIR/logs/test-screen-cli-$RUN_TIMESTAMP.log}

[ -r "$TRANSLATOR" ] || { printf 'ERROR: cannot read translator: %s\n' "$TRANSLATOR" >&2; exit 2; }
[ -r "$ORACLE" ] || { printf 'ERROR: cannot read oracle: %s\n' "$ORACLE" >&2; exit 2; }

# shellcheck disable=SC1090
. "$TRANSLATOR"
# shellcheck disable=SC1090
. "$ORACLE"

mkdir -p "$(dirname -- "$LOG_FILE")"
: > "$LOG_FILE"

_color_enabled=0
if [ -z "${NO_COLOR:-}" ]; then
    case "${SCREEN2TMUX_COLOR:-auto}" in
        always) _color_enabled=1 ;;
        auto|'') if [ -t 1 ] && [ "${TERM:-}" != dumb ]; then _color_enabled=1; fi ;;
        never) : ;;
    esac
fi
if [ "$_color_enabled" -eq 1 ]; then
    C_GREEN='\033[32m'; C_RED='\033[31m'; C_YELLOW='\033[33m'; C_CYAN='\033[36m'; C_MAGENTA='\033[35m'; C_RESET='\033[0m'
else
    C_GREEN=; C_RED=; C_YELLOW=; C_CYAN=; C_MAGENTA=; C_RESET=
fi

PASS=0
FAIL=0
TOTAL=0
ORACLE_PASS=0
ORACLE_FAIL=0

print_input()
{
    _pi_sep=
    for _pi_arg do
        printf '%s' "$_pi_sep"
        _s2t_display_quote "$_pi_arg"
        _pi_sep=' '
    done
}

hex_bytes()
{
    printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n'
}

expected_rc()
{
    case "$1" in
        exact) printf '0' ;;
        unsupported) printf '2' ;;
        approx) printf '3' ;;
        moot) printf '4' ;;
        external) printf '5' ;;
        invalid) printf '64' ;;
        *) printf '255' ;;
    esac
}

log_argv_hex()
{
    _lah_i=0
    for _lah_arg do
        printf '  argv[%s]=%s\n' "$_lah_i" "$(hex_bytes "$_lah_arg")" >> "$LOG_FILE"
        _lah_i=$((_lah_i + 1))
    done
}

capture_translator_plain()
{
    # Keep diagnostic bytes in the detailed log deterministic/plain even when
    # the test harness itself is being displayed with forced ANSI color.
    NO_COLOR=1 screen "$@"
}

run_variant()
{
    _rv_id=$1; _rv_expected=$2; _rv_desc=$3; _rv_placement=$4
    shift 4

    case "$_rv_placement" in
        first)
            _rv_input=$(print_input screen --dry-run "$@")
            _rv_output=$(capture_translator_plain --dry-run "$@" 2>&1); _rv_rc=$?
            set -- screen --dry-run "$@"
            ;;
        middle)
            [ "$#" -gt 0 ] || return 0
            _rv_first=$1; shift
            _rv_input=$(print_input screen "$_rv_first" --dry-run "$@")
            _rv_output=$(capture_translator_plain "$_rv_first" --dry-run "$@" 2>&1); _rv_rc=$?
            set -- screen "$_rv_first" --dry-run "$@"
            ;;
        last)
            _rv_input=$(print_input screen "$@" --dry-run)
            _rv_output=$(capture_translator_plain "$@" --dry-run 2>&1); _rv_rc=$?
            set -- screen "$@" --dry-run
            ;;
        *) printf 'internal test error: unknown placement %s\n' "$_rv_placement" >&2; exit 2 ;;
    esac

    _rv_want=$(expected_rc "$_rv_expected")
    TOTAL=$((TOTAL + 1))
    case "$_rv_expected" in
        exact)       _rv_class_color=$C_GREEN ;;
        approx)      _rv_class_color=$C_YELLOW ;;
        unsupported) _rv_class_color=$C_RED ;;
        moot)        _rv_class_color=$C_CYAN ;;
        external)    _rv_class_color=$C_MAGENTA ;;
        invalid)     _rv_class_color=$C_RED ;;
        *)           _rv_class_color= ;;
    esac

    if [ "$_rv_rc" -eq "$_rv_want" ]; then
        PASS=$((PASS + 1)); _rv_result=PASS
        # Successful dry-run placements are intentionally silent here. case_()
        # emits one compact PASS line after every applicable placement succeeds.
    else
        FAIL=$((FAIL + 1)); _rv_result=FAIL
        printf '%b[FAIL]%b %s expected=%b%s%b(rc=%s) got=%s placement=%s %s\n' "$C_RED" "$C_RESET" "$_rv_id" "$_rv_class_color" "$_rv_expected" "$C_RESET" "$_rv_want" "$_rv_rc" "$_rv_placement" "$_rv_desc"
    fi

    {
        printf '%s\n' '=============================================================================='
        printf 'CASE: %s\n' "$_rv_id"
        printf 'DESCRIPTION: %s\n' "$_rv_desc"
        printf 'DRY_RUN_PLACEMENT: %s\n' "$_rv_placement"
        printf 'EXPECTED_CLASS: %s\n' "$_rv_expected"
        printf 'EXPECTED_EXIT: %s\n' "$_rv_want"
        printf 'INPUT_DISPLAY: %s\n' "$_rv_input"
        printf 'INPUT_ARGV_HEX_BEGIN\n'
    } >> "$LOG_FILE"
    log_argv_hex "$@"
    {
        printf 'INPUT_ARGV_HEX_END\n'
        printf 'ACTUAL_EXIT: %s\n' "$_rv_rc"
        printf '%s\n' 'OUTPUT_DISPLAY_BEGIN'
        printf '%s\n' "$_rv_output"
        printf '%s\n' 'OUTPUT_DISPLAY_END'
        printf 'OUTPUT_HEX: %s\n' "$(hex_bytes "$_rv_output")"
        printf 'RESULT: %s\n' "$_rv_result"
    } >> "$LOG_FILE"
}

case_()
{
    _c_id=$1; _c_expected=$2; _c_desc=$3
    shift 3
    _c_fail_before=$FAIL

    # Independent Screen syntax check on the base argv, before adding --dry-run.
    screen_syntax_oracle "$@" >/dev/null 2>&1
    _c_oracle_rc=$?
    if [ "$_c_expected" = invalid ]; then _c_oracle_want=64; else _c_oracle_want=0; fi
    if [ "$_c_oracle_rc" -eq "$_c_oracle_want" ]; then
        ORACLE_PASS=$((ORACLE_PASS + 1))
    else
        ORACLE_FAIL=$((ORACLE_FAIL + 1))
        FAIL=$((FAIL + 1))
        printf '%b[FAIL]%b %s oracle expected=%s got=%s: %s\n' "$C_RED" "$C_RESET" "$_c_id" "$_c_oracle_want" "$_c_oracle_rc" "${SCREEN_ORACLE_REASON:-unknown oracle failure}"
        {
            printf '%s\n' '=============================================================================='
            printf 'CASE: %s\n' "$_c_id"
            printf 'ORACLE_RESULT: FAIL\n'
            printf 'ORACLE_EXPECTED_EXIT: %s\n' "$_c_oracle_want"
            printf 'ORACLE_ACTUAL_EXIT: %s\n' "$_c_oracle_rc"
            printf 'ORACLE_REASON: %s\n' "${SCREEN_ORACLE_REASON:-}"
        } >> "$LOG_FILE"
    fi

    run_variant "$_c_id" "$_c_expected" "$_c_desc" first "$@"
    if [ "$#" -gt 0 ]; then run_variant "$_c_id" "$_c_expected" "$_c_desc" middle "$@"; fi
    run_variant "$_c_id" "$_c_expected" "$_c_desc" last "$@"

    # Keep the console concise: when the oracle and every applicable placement
    # pass, print one line for the Screen case instead of first/middle/last.
    if [ "$FAIL" -eq "$_c_fail_before" ]; then
        case "$_c_expected" in
            exact)       _c_class_color=$C_GREEN ;;
            approx)      _c_class_color=$C_YELLOW ;;
            unsupported) _c_class_color=$C_RED ;;
            moot)        _c_class_color=$C_CYAN ;;
            external)    _c_class_color=$C_MAGENTA ;;
            invalid)     _c_class_color=$C_RED ;;
            *)           _c_class_color= ;;
        esac
        printf '%b[PASS]%b %s %b%-11s%b %s\n' "$C_GREEN" "$C_RESET" "$_c_id" "$_c_class_color" "$_c_expected" "$C_RESET" "$_c_desc"
    fi
}

{
    printf '%s\n' 'screen-to-tmux-translator test run'
    printf 'VERSION: %s\n' "${SCREEN2TMUX_VERSION:-unknown}"
    printf 'TRANSLATOR: %s\n' "$TRANSLATOR"
    printf 'ORACLE: %s\n' "$ORACLE"
    printf '%s\n' 'NOTE: GNU Screen has no native --dry-run. Syntax is checked independently by the Screen 5.0.2 source-derived oracle; translation is then tested through the drop-in screen() function.'
    printf '%s\n' '=============================================================================='
} >> "$LOG_FILE"

# shellcheck disable=SC1090
. "$TEST_DIR/cases.sh"

{
    printf '%s\n' '=============================================================================='
    printf 'SUMMARY: translation_total=%s pass=%s fail=%s oracle_pass=%s oracle_fail=%s\n' "$TOTAL" "$PASS" "$FAIL" "$ORACLE_PASS" "$ORACLE_FAIL"
} >> "$LOG_FILE"

printf '\n%bSummary:%b %s %bPASS%b, %s %bFAIL%b, %s translation invocations; oracle %s %bPASS%b/%s %bFAIL%b\n' \
    "$C_CYAN" "$C_RESET" "$PASS" "$C_GREEN" "$C_RESET" "$FAIL" "$C_RED" "$C_RESET" "$TOTAL" "$ORACLE_PASS" "$C_GREEN" "$C_RESET" "$ORACLE_FAIL" "$C_RED" "$C_RESET"
printf '%bLog:%b %s\n' "$C_YELLOW" "$C_RESET" "$LOG_FILE"

[ "$FAIL" -eq 0 ] && [ "$ORACLE_FAIL" -eq 0 ]
