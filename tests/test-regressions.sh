#!/bin/sh
# Focused regressions for semantic/scope false positives observed through 0.2.1.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$HERE/.." && pwd)
. "$PROJECT/bin/screen-to-tmux.sh"
RUN_TIMESTAMP=${SCREEN2TMUX_RUN_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}
REG_LOG=${REG_LOG:-$PROJECT/logs/test-regressions-$RUN_TIMESTAMP.log}
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

capture_in_tmux()
{
    _cit_had=${TMUX+x}
    _cit_old=${TMUX-}
    TMUX='/tmp/tmux-test/default,12345,0'
    export TMUX
    capture "$@"
    if [ "$_cit_had" = x ]; then TMUX=$_cit_old; export TMUX; else unset TMUX; fi
}

expect_exact_in_tmux()
{
    name=$1; expected=$2; shift 2
    CURRENT_NAME=$name
    capture_in_tmux "$@"
    if [ "$RC" -eq 0 ] && [ "$OUT" = "$expected" ]; then pass "$name"; else
        fail "$name (rc=$RC, output=$OUT)"
    fi
}

expect_class_contains_in_tmux()
{
    name=$1; rcwant=$2; needle=$3; shift 3
    CURRENT_NAME=$name
    capture_in_tmux "$@"
    if [ "$RC" -eq "$rcwant" ] && printf '%s\n' "$OUT" | grep -F -- "$needle" >/dev/null 2>&1; then pass "$name"; else
        fail "$name (wanted rc=$rcwant and '$needle'; rc=$RC output=$OUT)"
    fi
}

expect_exact_unique()
{
    name=$1; expected=$2; shift 2
    _eu_had=${SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES+x}
    _eu_old=${SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES-}
    SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES=1
    export SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES
    expect_exact "$name" "$expected" "$@"
    if [ "$_eu_had" = x ]; then SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES=$_eu_old; export SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES; else unset SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES; fi
}

expect_exact_unique_in_tmux()
{
    name=$1; expected=$2; shift 2
    _eui_had=${SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES+x}
    _eui_old=${SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES-}
    SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES=1
    export SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES
    expect_exact_in_tmux "$name" "$expected" "$@"
    if [ "$_eui_had" = x ]; then SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES=$_eui_old; export SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES; else unset SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES; fi
}

expect_exact "-d -m preserves command operand" "'tmux' 'new-session' '-d' 'bash'" --dry-run -d -m bash
expect_exact "-m alone does not detach" "'tmux' 'new-session'" -m --dry-run
expect_class_contains "screenrc is not passed to tmux -f" 2 "Screen -c reads Screen configuration syntax" --dry-run -c /tmp/my-screenrc
expect_not_contains "screenrc rejection never emits tmux -f" 2 "'tmux' '-f'" -c /tmp/my-screenrc --dry-run
expect_class_contains "Screen source is not tmux source-file" 2 "Screen 'source' reads Screen command syntax" -S work -X source /tmp/screen-extra --dry-run
expect_class_contains "-L is approximation, never silently dropped" 3 "APPROX" --dry-run -L
expect_class_contains "-Logfile without -L is unsupported" 2 "persistent logfile-name setting" -Logfile /tmp/screen.log --dry-run
expect_class_contains "-p window is preserved in attach suggestion" 3 "tmux attach-session -t work:2" -p 2 -r work --dry-run
expect_class_contains "compact -p window is preserved in attach suggestion" 3 "tmux attach-session -t work:2" -p2 -r work --dry-run
expect_class_contains "focus right is approximation with correct target" 3 "work:.{right-of}" -S work -X focus right --dry-run
expect_not_contains "resize +5 does not invent down direction" 3 "resize-pane -D" -S work -X resize +5 --dry-run
expect_class_contains "Screen layout next is not claimed exact" 3 "saved display-region layouts" -S work -X layout next --dry-run
expect_class_contains "ACL add warns about server-wide scope" 3 "server level" -S work -X acladd alice --dry-run
expect_class_contains "direct serial mapping is external" 5 "EXTERNAL" /dev/ttyUSB0 115200 --dry-run
expect_class_contains "plain -r is approximation because tmux allows extra clients" 3 "normally refuses an already attached session" -r work --dry-run
expect_class_contains "hardcopy explicit file is approximation" 3 "not byte-for-byte equivalent" -S work -p 0 -X hardcopy /tmp/window.txt --dry-run
expect_class_contains "removebuf does not delete tmux buffer" 2 "exchange file" -S work -X removebuf --dry-run
expect_not_contains "removebuf never emits delete-buffer" 2 "delete-buffer'" -S work -X removebuf --dry-run
expect_exact "query number reproduces Screen N (title) shape" "'tmux' 'display-message' '-p' '-t' 'work' '#{window_index} (#{window_name})'" -S work -Q number --dry-run
expect_class_contains "displays is session scoped" 3 "tmux list-clients -t work" -S work -X displays --dry-run
expect_class_contains "bind warns about tmux server-wide key tables" 3 "server-wide" -S work -X bind c screen --dry-run
expect_class_contains "unbindall warns about tmux server-wide key tables" 3 "server-wide" -S work -X unbindall --dry-run
expect_class_contains "redisplay requires a concrete client" 3 "particular attached Display" -S work -X redisplay --dry-run
expect_class_contains "suspend requires a concrete client" 3 "does not uniquely identify a tmux client" -S work -X suspend --dry-run
expect_class_contains "query info is not claimed output-compatible" 3 "fixed status summary" -S work -Q info --dry-run
expect_class_contains "query lastmsg is not claimed output-compatible" 3 "single most recent message" -S work -Q lastmsg --dry-run
expect_class_contains "Screen help is not claimed output-compatible" 3 "server-wide key tables" -S work -X help --dry-run
expect_exact_in_tmux "inside tmux plain screen bash creates a window" "'tmux' 'new-window' 'bash'" --dry-run bash
expect_exact_in_tmux "inside tmux plain screen creates a window" "'tmux' 'new-window'" --dry-run
expect_exact_in_tmux "inside tmux -t title creates titled window" "'tmux' 'new-window' '-n' 'editor' 'vim'" --dry-run -t editor vim
expect_class_contains_in_tmux "inside tmux -m warns about tmux nesting safeguard" 3 "normally rejects an attached nested new-session" --dry-run -m bash
expect_class_contains_in_tmux "inside tmux -S warns about duplicate Screen labels" 3 "multiple sessions whose socket names share the same -S label" --dry-run -S work bash
expect_exact_unique_in_tmux "inside tmux -S can opt into unique-name policy" "'tmux' 'new-session' '-s' 'work' 'bash'" --dry-run -S work bash

# 0.3.0 hardening: state, scope, and edge-condition semantics.
expect_class_contains "named session creation is approximate by default" 3 "tmux requires each session name to be unique" --dry-run -S work
expect_exact_unique "unique-name policy restores direct named creation" "'tmux' 'new-session' '-s' 'work'" --dry-run -S work
expect_class_contains "session listing is not output-compatible" 3 "dead sockets" --dry-run -ls
expect_class_contains "quiet listing preserves Screen-specific exit-status warning" 3 "status codes" --dry-run -q -ls
expect_class_contains "Screen -R is state-sensitive approximation" 3 "only considers sockets suitable" --dry-run -R work
expect_class_contains "Screen -RR multiple-match rules are not tmux -A" 3 "multiple-match selection" --dry-run -RR work
expect_class_contains "detach-and-R remains state-sensitive" 3 "only considers sockets suitable" --dry-run -d -R work
expect_class_contains "number documents occupied-destination swap" 3 "tmux swap-window" --dry-run -S work -p 2 -X number 5
expect_class_contains "collapse documents base-index mismatch" 3 "base-index" --dry-run -S work -X collapse
expect_class_contains "internal detach is client-specific" 3 "Display only" --dry-run -S work -X detach
expect_class_contains "internal power detach is client-specific" 3 "one concrete Display" --dry-run -S work -X pow_detach
expect_class_contains "altscreen is backend-wide versus pane scoped" 3 "backend-wide use_altscreen" --dry-run -S work -X altscreen on
expect_class_contains "readbuf warns about server-wide tmux buffers" 3 "shared by the entire tmux server" --dry-run -S work -X readbuf /tmp/text
expect_class_contains "writebuf warns about server-wide tmux buffers" 3 "server-wide" --dry-run -S work -X writebuf /tmp/text
expect_class_contains "register warns about server-wide tmux buffers" 3 "server-wide" --dry-run -S work -X register a hello
expect_class_contains "paste with no register is not tmux paste-buffer" 2 "interactive register prompt" --dry-run -S work -p 0 -X paste

# 0.3.1 hardening: no invented feature emulation, literal tmux-format data, and
# explicit uncertainty warnings for target arguments with incompatible grammars.
expect_class_contains "-U is partial semantics, not tmux -u exact" 3 "two semantics" --dry-run -U
expect_not_contains "-U never auto-emits tmux -u" 3 "'tmux' '-u'" --dry-run -U
expect_class_contains "-A attach semantics do not silently disappear" 3 "no equivalent adapt-all-windows flag" --dry-run -A -x work
expect_exact "-A on new-session path is semantically inert" "'tmux' 'new-session'" --dry-run -A
expect_exact "-U does not block unrelated remote X command" "'tmux' 'send-keys' '-l' '-t' 'work:0' 'hello'" --dry-run -U -S work -p 0 -X stuff hello
expect_class_contains "short Screen version is not tmux version" 2 "reports the GNU Screen version" --dry-run -v
expect_class_contains "long Screen version is not tmux version" 2 "reports the GNU Screen version" --dry-run --version
expect_class_contains "Screen help is not tmux help" 2 "describes Screen's CLI" --dry-run --help
expect_class_contains "internal Screen version is not tmux version" 2 "reports Screen's version/status text" --dry-run -S work -X version
expect_exact "query echo uses tmux literal mode" "'tmux' 'display-message' '-pl' '#{session_name}'" --dry-run -S work -Q echo '#{session_name}'
expect_class_contains "query echo -p refuses Screen format reinterpretation" 2 "Screen echo -p expands Screen's own % status-format language" --dry-run -S work -Q echo -p '%n %t'
expect_exact_unique "named creation escapes tmux format hash" "'tmux' 'new-session' '-s' 'work-##{host}'" --dry-run -S 'work-#{host}'
expect_exact "initial title escapes tmux format hash" "'tmux' 'new-session' '-n' '##{session_name}' 'vim'" --dry-run -t '#{session_name}' vim
expect_exact "runtime title escapes tmux format hash" "'tmux' 'rename-window' '-t' 'work:2' '##{session_name}'" --dry-run -S work -p 2 -X title '#{session_name}'
expect_exact "runtime session rename escapes tmux format hash" "'tmux' 'rename-session' '-t' 'work' 'dev-##(printf pwn)'" --dry-run -S work -X sessionname 'dev-#(printf pwn)'
expect_class_contains "risky Screen session selector prints uncertainty warning" 3 "WARNING: uncertain translation of argument Screen session selector" --dry-run -S '$1' -X quit
expect_class_contains "numeric Screen session selector warns about PID ambiguity" 3 "may interpret leading digits as a PID" --dry-run -r 12345
expect_class_contains "risky Screen window selector prints uncertainty warning" 3 "WARNING: uncertain translation of argument Screen window selector" --dry-run -S work -p 'editor.1' -X stuff x

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
