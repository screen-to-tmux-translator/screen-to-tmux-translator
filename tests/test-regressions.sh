#!/bin/sh
# Focused regressions for semantic false positives observed in 0.1.0.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$HERE/.." && pwd)
. "$PROJECT/bin/screen-to-tmux.sh"
REG_LOG=${REG_LOG:-$PROJECT/logs/test-regressions.log}
mkdir -p "$(dirname -- "$REG_LOG")"
: > "$REG_LOG"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    G='\033[32m'; R='\033[31m'; C='\033[36m'; Z='\033[0m'
else G=; R=; C=; Z=; fi
P=0; F=0

pass(){ P=$((P+1)); printf '%b[PASS]%b %s\n' "$G" "$Z" "$1"; }
fail(){ F=$((F+1)); printf '%b[FAIL]%b %s\n' "$R" "$Z" "$1"; }

capture()
{
    INPUT=$( _s2t_display_quote screen; for a do printf ' '; _s2t_display_quote "$a"; done )
    OUT=$(screen "$@" 2>&1)
    RC=$?
    {
        printf '%s\n' '=============================================================================='
        printf 'TEST: %s\n' "${CURRENT_NAME:-unnamed}"
        printf 'INPUT_DISPLAY: %s\n' "$INPUT"
        printf 'ACTUAL_EXIT: %s\n' "$RC"
        printf '%s\n' 'OUTPUT_DISPLAY_BEGIN'
        printf '%s\n' "$OUT"
        printf '%s\n' 'OUTPUT_DISPLAY_END'
        printf 'OUTPUT_HEX: %s\n' "$(printf '%s' "$OUT" | od -An -v -tx1 | tr -d ' \n')"
    } >> "$REG_LOG"
}

expect_exact()
{
    name=$1; expected=$2; shift 2
    CURRENT_NAME=$name
    capture "$@"
    if [ "$RC" -eq 0 ] && [ "$OUT" = "$expected" ]; then pass "$name"; else
        fail "$name (rc=$RC, output=$OUT)"
    fi
}

expect_class_contains()
{
    name=$1; rcwant=$2; needle=$3; shift 3
    CURRENT_NAME=$name
    capture "$@"
    if [ "$RC" -eq "$rcwant" ] && printf '%s\n' "$OUT" | grep -F -- "$needle" >/dev/null 2>&1; then pass "$name"; else
        fail "$name (wanted rc=$rcwant and '$needle'; rc=$RC output=$OUT)"
    fi
}

expect_not_contains()
{
    name=$1; rcwant=$2; needle=$3; shift 3
    CURRENT_NAME=$name
    capture "$@"
    if [ "$RC" -eq "$rcwant" ] && ! printf '%s\n' "$OUT" | grep -F -- "$needle" >/dev/null 2>&1; then pass "$name"; else
        fail "$name (unexpected '$needle'; rc=$RC output=$OUT)"
    fi
}

expect_exact "-d -m preserves command operand" "'tmux' 'new-session' '-d' 'bash'" --dry-run -d -m bash
expect_exact "-m alone does not detach" "'tmux' 'new-session'" -m --dry-run
expect_class_contains "screenrc is not passed to tmux -f" 2 "Screen -c reads Screen configuration syntax" --dry-run -c /tmp/my-screenrc
expect_not_contains "screenrc rejection never emits tmux -f" 2 "'tmux' '-f'" -c /tmp/my-screenrc --dry-run
expect_class_contains "Screen source is not tmux source-file" 2 "Screen 'source' reads Screen command syntax" -S work -X source /tmp/screen-extra --dry-run
expect_class_contains "-L is approximation, never silently dropped" 3 "APPROX" --dry-run -L
expect_class_contains "-Logfile without -L is unsupported" 2 "persistent logfile-name setting" -Logfile /tmp/screen.log --dry-run
expect_exact "-p window is preserved when attaching" "'tmux' 'attach-session' '-t' 'work:2'" -p 2 -r work --dry-run
expect_exact "compact -p window is preserved when attaching" "'tmux' 'attach-session' '-t' 'work:2'" -p2 -r work --dry-run
expect_class_contains "focus right is approximation with correct target" 3 "work:.{right-of}" -S work -X focus right --dry-run
expect_not_contains "resize +5 does not invent down direction" 3 "resize-pane -D" -S work -X resize +5 --dry-run
expect_class_contains "Screen layout next is not claimed exact" 3 "saved display-region layouts" -S work -X layout next --dry-run
expect_class_contains "ACL add warns about server-wide scope" 3 "server level" -S work -X acladd alice --dry-run
expect_class_contains "direct serial mapping is external" 5 "EXTERNAL" /dev/ttyUSB0 115200 --dry-run

CR=$(printf '\r')
CURRENT_NAME='dry-run renders carriage return safely'
capture -S work -p 0 -X stuff "hello${CR}" --dry-run
HEX=$(printf '%s' "$OUT" | od -An -v -tx1 | tr -d ' \n')
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -F 'hello\r' >/dev/null 2>&1 && ! printf '%s' "$HEX" | grep -F '0d' >/dev/null 2>&1; then
    pass "dry-run renders carriage return safely"
else
    fail "dry-run carriage-return rendering (rc=$RC hex=$HEX output=$OUT)"
fi

printf '\n%bRegression summary:%b %s PASS, %s FAIL\n' "$C" "$Z" "$P" "$F"
printf 'SUMMARY: pass=%s fail=%s\n' "$P" "$F" >> "$REG_LOG"
printf 'Regression log: %s\n' "$REG_LOG"
[ "$F" -eq 0 ]
