#!/bin/sh
# Focused regressions for semantic/scope false positives observed through 0.2.1.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$HERE/.." && pwd)
. "$PROJECT/bin/screen-function-source.sh"
RUN_TIMESTAMP=${SCREEN2TMUX_RUN_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}
REG_LOG=${REG_LOG:-$PROJECT/logs/test-regressions-$RUN_TIMESTAMP.log}
mkdir -p "$(dirname -- "$REG_LOG")"
: > "$REG_LOG"

_color_enabled=0
if [ -z "${NO_COLOR:-}" ]; then
    case "${SCREEN2TMUX_COLOR:-auto}" in
        always) _color_enabled=1 ;;
        auto|'') if [ -t 1 ] && [ "${TERM:-}" != dumb ]; then _color_enabled=1; fi ;;
        never) : ;;
    esac
fi
if [ "$_color_enabled" -eq 1 ]; then
    G='\033[32m'; R='\033[31m'; C='\033[36m'; Z='\033[0m'
else G=; R=; C=; Z=; fi
P=0; F=0
SHOW_PASS=${SCREEN2TMUX_SHOW_REGRESSION_TEST_PASS:-0}
case "$SHOW_PASS" in 0|1) : ;; *) SHOW_PASS=0 ;; esac

pass()
{
    P=$((P+1))
    printf 'RESULT\tPASS\t%s\n' "$1" >> "$REG_LOG"
    [ "$SHOW_PASS" -eq 0 ] || printf '%b[PASS]%b %s\n' "$G" "$Z" "$1"
}
fail()
{
    F=$((F+1))
    printf 'RESULT\tFAIL\t%s\n' "$1" >> "$REG_LOG"
    printf '%b[FAIL]%b %s\n' "$R" "$Z" "$1"
}

capture()
{
    INPUT=$( _s2t_display_quote screen; for a do printf ' '; _s2t_display_quote "$a"; done )
    OUT=$(NO_COLOR=1 screen "$@" 2>&1)
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


capture_forced_color()
{
    _cfc_no_had=${NO_COLOR+x}
    _cfc_no_old=${NO_COLOR-}
    _cfc_color_had=${SCREEN2TMUX_COLOR+x}
    _cfc_color_old=${SCREEN2TMUX_COLOR-}
    unset NO_COLOR
    SCREEN2TMUX_COLOR=always
    export SCREEN2TMUX_COLOR

    OUT=$(screen "$@" 2>&1)
    RC=$?
    OUT_HEX=$(printf '%s' "$OUT" | od -An -v -tx1 | tr -d ' \n')
    {
        printf '%s\n' '=============================================================================='
        printf 'TEST: %s\n' "${CURRENT_NAME:-unnamed}"
        printf 'COLOR_MODE: always\n'
        printf 'ACTUAL_EXIT: %s\n' "$RC"
        printf 'OUTPUT_HEX: %s\n' "$OUT_HEX"
    } >> "$REG_LOG"

    if [ "$_cfc_no_had" = x ]; then NO_COLOR=$_cfc_no_old; export NO_COLOR; else unset NO_COLOR; fi
    if [ "$_cfc_color_had" = x ]; then SCREEN2TMUX_COLOR=$_cfc_color_old; export SCREEN2TMUX_COLOR; else unset SCREEN2TMUX_COLOR; fi
}

expect_selective_color()
{
    name=$1; rcwant=$2; colored_token=$3; plain_prefix=$4; shift 4
    CURRENT_NAME=$name
    capture_forced_color "$@"
    case "$OUT" in
        "$plain_prefix"*"$colored_token"*) _esc_prefix_ok=1 ;;
        *) _esc_prefix_ok=0 ;;
    esac
    case "$OUT_HEX" in *1b*) _esc_present=1 ;; *) _esc_present=0 ;; esac
    if [ "$RC" -eq "$rcwant" ] && [ "$_esc_prefix_ok" -eq 1 ] && [ "$_esc_present" -eq 1 ]; then
        pass "$name"
    else
        fail "$name (rc=$RC prefix_ok=$_esc_prefix_ok ansi=$_esc_present hex=$OUT_HEX)"
    fi
}

expect_no_color_override()
{
    name=$1; rcwant=$2; shift 2
    CURRENT_NAME=$name
    _nco_color_had=${SCREEN2TMUX_COLOR+x}
    _nco_color_old=${SCREEN2TMUX_COLOR-}
    _nco_no_had=${NO_COLOR+x}
    _nco_no_old=${NO_COLOR-}
    SCREEN2TMUX_COLOR=always
    NO_COLOR=1
    export SCREEN2TMUX_COLOR NO_COLOR
    OUT=$(screen "$@" 2>&1)
    RC=$?
    OUT_HEX=$(printf '%s' "$OUT" | od -An -v -tx1 | tr -d ' \n')
    {
        printf '%s\n' '=============================================================================='
        printf 'TEST: %s\n' "${CURRENT_NAME:-unnamed}"
        printf 'COLOR_MODE: always + NO_COLOR\n'
        printf 'ACTUAL_EXIT: %s\n' "$RC"
        printf 'OUTPUT_HEX: %s\n' "$OUT_HEX"
    } >> "$REG_LOG"
    if [ "$_nco_color_had" = x ]; then SCREEN2TMUX_COLOR=$_nco_color_old; export SCREEN2TMUX_COLOR; else unset SCREEN2TMUX_COLOR; fi
    if [ "$_nco_no_had" = x ]; then NO_COLOR=$_nco_no_old; export NO_COLOR; else unset NO_COLOR; fi
    case "$OUT_HEX" in *1b*) _nco_clean=0 ;; *) _nco_clean=1 ;; esac
    if [ "$RC" -eq "$rcwant" ] && [ "$_nco_clean" -eq 1 ]; then pass "$name"; else
        fail "$name (rc=$RC ansi_free=$_nco_clean hex=$OUT_HEX)"
    fi
}

expect_exact "-d -m preserves command operand" "tmux new-session -d bash" --dry-run -d -m bash
expect_exact "-m alone does not detach" "tmux new-session" -m --dry-run
expect_class_contains "screenrc is not passed to tmux -f" 2 "Screen -c reads Screen configuration syntax" --dry-run -c /tmp/my-screenrc
expect_not_contains "screenrc rejection never emits tmux -f" 2 "tmux -f /tmp/my-screenrc" -c /tmp/my-screenrc --dry-run
expect_class_contains "Screen source is not tmux source-file" 2 "Screen 'source' reads Screen command syntax" -S work -X source /tmp/screen-extra --dry-run
expect_class_contains "-L is approximation, never silently dropped" 3 "APPROX" --dry-run -L
expect_class_contains "-Logfile without -L is unsupported" 2 "persistent logfile-name setting" -Logfile /tmp/screen.log --dry-run
expect_class_contains "-p window is preserved in attach execution" 0 "tmux attach-session -t work:2" -p 2 -r work --dry-run
expect_class_contains "compact -p window is preserved in attach execution" 0 "tmux attach-session -t work:2" -p2 -r work --dry-run
expect_class_contains "focus right is approximation with correct target" 0 "work:.{right-of}" -S work -X focus right --dry-run
expect_not_contains "resize +5 does not invent down direction" 3 "resize-pane -D" -S work -X resize +5 --dry-run
expect_class_contains "Screen layout next is not claimed exact" 0 "saved display-region layouts" -S work -X layout next --dry-run
expect_class_contains "ACL add warns about server-wide scope" 0 "server level" -S work -X acladd alice --dry-run
expect_class_contains "direct serial mapping is external" 0 "EXTERNAL" /dev/ttyUSB0 115200 --dry-run
expect_class_contains "direct serial dry-run shows picocom tmux command" 0 "tmux new-session picocom -b 115200 /dev/ttyUSB0" /dev/ttyUSB0 115200 --dry-run
expect_class_contains "telnet dry-run shows external-client tmux command" 0 "tmux new-session telnet example.com 23" //telnet example.com 23 --dry-run
expect_class_contains "IPv6 telnet dry-run preserves address-family selection" 0 "tmux new-session telnet -6 example.com" -6 //telnet example.com --dry-run
expect_class_contains "plain -r warns before executing closest attach" 0 "normally refuses an already attached session" -r work --dry-run
expect_class_contains "plain selectorless -r dry-run prints unquoted tmux command" 0 "tmux attach-session" -r --dry-run
expect_not_contains "plain selectorless -r dry-run omits unnecessary quotes" 0 "\'tmux\'" -r --dry-run
expect_exact "--strict leaves EXACT mappings available" "tmux new-session -d bash" --strict --dry-run -d -m bash
expect_class_contains "--strict makes executable APPROX advisory" 3 "--strict keeps APPROX mappings advisory" --strict --dry-run -r work
expect_class_contains "--strict dry-run still shows closest APPROX command" 3 "tmux attach-session -t work" -r work --strict --dry-run
expect_class_contains "--strict blocks notice-then-run approximations" 3 "tmux new-session -s work" --dry-run -S work --strict

CURRENT_NAME='plain -r executes closest tmux attach after warning'
_s2t_approx_stub=${TMPDIR:-/tmp}/screen2tmux-approx-exec-$$
rm -rf "$_s2t_approx_stub"
mkdir -p "$_s2t_approx_stub"
cat > "$_s2t_approx_stub/tmux" <<'EOF_APPROX_STUB'
#!/bin/sh
printf 'APPROX_TMUX_EXEC'
for a do printf ' <%s>' "$a"; done
printf '\n'
EOF_APPROX_STUB
chmod 755 "$_s2t_approx_stub/tmux"
OUT=$(PATH="$_s2t_approx_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never screen -r work 2>&1)
RC=$?
rm -rf "$_s2t_approx_stub"
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'ACTUAL_EXIT: %s\n' "$RC"
    printf 'OUTPUT_DISPLAY_BEGIN\n%s\nOUTPUT_DISPLAY_END\n' "$OUT"
} >> "$REG_LOG"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -F 'screen2tmux: APPROX:' >/dev/null 2>&1 && \
   printf '%s\n' "$OUT" | grep -F 'APPROX_TMUX_EXEC <attach-session> <-t> <work>' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi

CURRENT_NAME='selectorless -r executes tmux attach-session after warning'
_s2t_approx_stub=${TMPDIR:-/tmp}/screen2tmux-approx-exec-$$
rm -rf "$_s2t_approx_stub"
mkdir -p "$_s2t_approx_stub"
cat > "$_s2t_approx_stub/tmux" <<'EOF_APPROX_STUB'
#!/bin/sh
printf 'APPROX_TMUX_EXEC'
for a do printf ' <%s>' "$a"; done
printf '\n'
EOF_APPROX_STUB
chmod 755 "$_s2t_approx_stub/tmux"
OUT=$(PATH="$_s2t_approx_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never screen -r 2>&1)
RC=$?
rm -rf "$_s2t_approx_stub"
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'ACTUAL_EXIT: %s\n' "$RC"
    printf 'OUTPUT_DISPLAY_BEGIN\n%s\nOUTPUT_DISPLAY_END\n' "$OUT"
} >> "$REG_LOG"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -F 'screen2tmux: APPROX:' >/dev/null 2>&1 && \
   printf '%s\n' "$OUT" | grep -F 'APPROX_TMUX_EXEC <attach-session>' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi

CURRENT_NAME='--strict never executes executable APPROX mapping'
_s2t_strict_stub=${TMPDIR:-/tmp}/screen2tmux-strict-exec-$$
rm -rf "$_s2t_strict_stub"
mkdir -p "$_s2t_strict_stub"
cat > "$_s2t_strict_stub/tmux" <<'EOF_STRICT_STUB'
#!/bin/sh
printf 'executed\n' > "${SCREEN2TMUX_STRICT_SENTINEL:?}"
exit 0
EOF_STRICT_STUB
chmod 755 "$_s2t_strict_stub/tmux"
_s2t_strict_sentinel=$_s2t_strict_stub/executed
OUT=$(PATH="$_s2t_strict_stub:$PATH" SCREEN2TMUX_STRICT_SENTINEL="$_s2t_strict_sentinel" NO_COLOR=1 SCREEN2TMUX_COLOR=never screen --strict -r work 2>&1)
RC=$?
if [ "$RC" -eq 3 ] && [ ! -e "$_s2t_strict_sentinel" ] && printf '%s\n' "$OUT" | grep -F -- '--strict keeps APPROX mappings advisory' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC sentinel=$([ -e "$_s2t_strict_sentinel" ] && printf yes || printf no) output=$OUT)"
fi
rm -rf "$_s2t_strict_stub"

CURRENT_NAME='external telnet mapping executes when telnet is installed'
_s2t_external_stub=${TMPDIR:-/tmp}/screen2tmux-external-exec-$$
rm -rf "$_s2t_external_stub"
mkdir -p "$_s2t_external_stub"
cat > "$_s2t_external_stub/telnet" <<'EOF_EXTERNAL_TELNET'
#!/bin/sh
exit 0
EOF_EXTERNAL_TELNET
cat > "$_s2t_external_stub/picocom" <<'EOF_EXTERNAL_PICOCOM'
#!/bin/sh
exit 0
EOF_EXTERNAL_PICOCOM
cat > "$_s2t_external_stub/tmux" <<'EOF_EXTERNAL_TMUX'
#!/bin/sh
printf 'EXTERNAL_TMUX_EXEC'
for a do printf ' <%s>' "$a"; done
printf '\n'
EOF_EXTERNAL_TMUX
chmod 755 "$_s2t_external_stub/telnet" "$_s2t_external_stub/picocom" "$_s2t_external_stub/tmux"
OUT=$(PATH="$_s2t_external_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never screen //telnet example.com 23 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -F 'screen2tmux: EXTERNAL:' >/dev/null 2>&1 && \
   printf '%s\n' "$OUT" | grep -F 'EXTERNAL_TMUX_EXEC <new-session> <telnet> <example.com> <23>' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi

CURRENT_NAME='external serial mapping executes when picocom is installed'
OUT=$(PATH="$_s2t_external_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never screen /dev/ttyUSB0 115200 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -F 'EXTERNAL_TMUX_EXEC <new-session> <picocom> <-b> <115200> </dev/ttyUSB0>' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi

CURRENT_NAME='--strict blocks executable EXTERNAL mapping'
_s2t_external_sentinel=$_s2t_external_stub/executed
cat > "$_s2t_external_stub/tmux" <<'EOF_EXTERNAL_STRICT_TMUX'
#!/bin/sh
printf 'executed\n' > "${SCREEN2TMUX_EXTERNAL_SENTINEL:?}"
exit 0
EOF_EXTERNAL_STRICT_TMUX
chmod 755 "$_s2t_external_stub/tmux"
OUT=$(PATH="$_s2t_external_stub:$PATH" SCREEN2TMUX_EXTERNAL_SENTINEL="$_s2t_external_sentinel" NO_COLOR=1 SCREEN2TMUX_COLOR=never screen --strict //telnet example.com 23 2>&1)
RC=$?
if [ "$RC" -eq 5 ] && [ ! -e "$_s2t_external_sentinel" ] && printf '%s\n' "$OUT" | grep -F -- '--strict keeps EXTERNAL mappings advisory' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC sentinel=$([ -e "$_s2t_external_sentinel" ] && printf yes || printf no) output=$OUT)"
fi

CURRENT_NAME='--strict dry-run shows EXTERNAL command but returns advisory status'
OUT=$(PATH="$_s2t_external_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never screen --strict --dry-run //telnet example.com 23 2>&1)
RC=$?
if [ "$RC" -eq 5 ] && printf '%s\n' "$OUT" | grep -F "tmux new-session telnet example.com 23" >/dev/null 2>&1 && printf '%s\n' "$OUT" | grep -F -- '--strict keeps EXTERNAL mappings advisory' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi
rm -rf "$_s2t_external_stub"

expect_class_contains "hardcopy explicit file is approximation" 3 "not byte-for-byte equivalent" -S work -p 0 -X hardcopy /tmp/window.txt --dry-run
expect_class_contains "removebuf does not delete tmux buffer" 2 "exchange file" -S work -X removebuf --dry-run
expect_not_contains "removebuf never emits delete-buffer" 2 "delete-buffer'" -S work -X removebuf --dry-run
expect_exact "query number reproduces Screen N (title) shape" "tmux display-message -p -t work '#{window_index} (#{window_name})'" -S work -Q number --dry-run
expect_class_contains "displays is session scoped" 0 "tmux list-clients -t work" -S work -X displays --dry-run
expect_class_contains "bind warns about tmux server-wide key tables" 0 "server-wide" -S work -X bind c screen --dry-run
expect_class_contains "unbindall warns about tmux server-wide key tables" 0 "server-wide" -S work -X unbindall --dry-run
expect_class_contains "redisplay requires a concrete client" 3 "particular attached Display" -S work -X redisplay --dry-run
expect_class_contains "suspend requires a concrete client" 3 "does not uniquely identify a tmux client" -S work -X suspend --dry-run
expect_class_contains "query info is not claimed output-compatible" 0 "fixed status summary" -S work -Q info --dry-run
expect_class_contains "query lastmsg is not claimed output-compatible" 0 "single most recent message" -S work -Q lastmsg --dry-run
expect_class_contains "Screen help is not claimed output-compatible" 0 "server-wide key tables" -S work -X help --dry-run
expect_exact_in_tmux "inside tmux plain screen bash creates a window" "tmux new-window bash" --dry-run bash
expect_exact_in_tmux "inside tmux plain screen creates a window" "tmux new-window" --dry-run
expect_exact_in_tmux "inside tmux -t title creates titled window" "tmux new-window -n editor vim" --dry-run -t editor vim
expect_class_contains_in_tmux "inside tmux -m warns about tmux nesting safeguard" 3 "normally rejects an attached nested new-session" --dry-run -m bash
expect_class_contains_in_tmux "inside tmux -S warns about duplicate Screen labels before execution" 0 "multiple sessions whose socket names share the same -S label" --dry-run -S work bash
expect_exact_unique_in_tmux "inside tmux -S can opt into unique-name policy" "tmux new-session -s work bash" --dry-run -S work bash

# 0.3.0 hardening: state, scope, and edge-condition semantics.
expect_class_contains "named session creation warns before closest execution" 0 "tmux requires each session name to be unique" --dry-run -S work
expect_exact_unique "unique-name policy restores direct named creation" "tmux new-session -s work" --dry-run -S work
expect_class_contains "session listing is not output-compatible" 0 "dead sockets" --dry-run -ls
expect_class_contains "quiet listing preserves Screen-specific exit-status warning" 0 "status codes" --dry-run -q -ls
expect_class_contains "Screen -R is state-sensitive approximation" 0 "only considers sockets suitable" --dry-run -R work
expect_class_contains "Screen -RR multiple-match rules are not tmux -A" 0 "multiple-match selection" --dry-run -RR work
expect_class_contains "detach-and-R remains state-sensitive" 0 "only considers sockets suitable" --dry-run -d -R work
expect_class_contains "number documents occupied-destination swap" 0 "use swap-window explicitly" --dry-run -S work -p 2 -X number 5
expect_class_contains "collapse documents base-index mismatch" 0 "base-index" --dry-run -S work -X collapse
expect_class_contains "internal detach is client-specific" 3 "Display only" --dry-run -S work -X detach
expect_class_contains "internal power detach is client-specific" 3 "one concrete Display" --dry-run -S work -X pow_detach
expect_class_contains "altscreen is backend-wide versus pane scoped" 0 "backend-wide use_altscreen" --dry-run -S work -X altscreen on
expect_class_contains "readbuf warns about server-wide tmux buffers" 0 "shared by the entire tmux server" --dry-run -S work -X readbuf /tmp/text
expect_class_contains "writebuf warns about server-wide tmux buffers" 0 "server-wide" --dry-run -S work -X writebuf /tmp/text
expect_class_contains "register warns about server-wide tmux buffers" 0 "server-wide" --dry-run -S work -X register a hello
expect_class_contains "paste with no register is not tmux paste-buffer" 2 "interactive register prompt" --dry-run -S work -p 0 -X paste

# 0.3.1 hardening: no invented feature emulation, literal tmux-format data, and
# explicit uncertainty warnings for target arguments with incompatible grammars.
expect_class_contains "-U is partial semantics, not tmux -u exact" 0 "two semantics" --dry-run -U
expect_class_contains "-U executes tmux -u after warning" 0 "tmux -u new-session" --dry-run -U
expect_class_contains "-A attach semantics do not silently disappear" 0 "no equivalent adapt-all-windows flag" --dry-run -A -x work
expect_exact "-A on new-session path is semantically inert" "tmux new-session" --dry-run -A
expect_exact "-U does not block unrelated remote X command" "tmux send-keys -l -t work:0 hello" --dry-run -U -S work -p 0 -X stuff hello
expect_class_contains "short Screen version is not tmux version" 2 "reports the GNU Screen version" --dry-run -v
expect_class_contains "long Screen version is not tmux version" 2 "reports the GNU Screen version" --dry-run --version
expect_class_contains "compatibility help is available" 0 "screen-to-tmux compatibility help" --dry-run --help
expect_class_contains "compatibility help identifies Screen 5.0.x syntax" 0 "GNU Screen 5.0.x-style command-line syntax" --dry-run --help
expect_class_contains "compatibility help explains tmux differences" 0 "Important tmux-underneath differences" --dry-run --help
expect_class_contains "compatibility help documents dryrun alias" 0 "--dry-run / --dryrun" --dry-run --help
expect_class_contains "compatibility help documents strict mode" 0 "Never execute APPROX or EXTERNAL mappings" --dry-run --help
expect_class_contains "internal Screen version is not tmux version" 2 "reports Screen's version/status text" --dry-run -S work -X version
expect_exact "query echo uses tmux literal mode" "tmux display-message -pl '#{session_name}'" --dry-run -S work -Q echo '#{session_name}'
expect_class_contains "query echo -p refuses Screen format reinterpretation" 2 "Screen echo -p expands Screen's own % status-format language" --dry-run -S work -Q echo -p '%n %t'
expect_exact_unique "named creation escapes tmux format hash" "tmux new-session -s 'work-##{host}'" --dry-run -S 'work-#{host}'
expect_exact "initial title escapes tmux format hash" "tmux new-session -n '##{session_name}' vim" --dry-run -t '#{session_name}' vim
expect_exact "runtime title escapes tmux format hash" "tmux rename-window -t work:2 '##{session_name}'" --dry-run -S work -p 2 -X title '#{session_name}'
expect_exact "runtime session rename escapes tmux format hash" "tmux rename-session -t work 'dev-##(printf pwn)'" --dry-run -S work -X sessionname 'dev-#(printf pwn)'
expect_class_contains "risky Screen session selector prints uncertainty warning" 3 "WARNING: uncertain translation of argument Screen session selector" --dry-run -S '$1' -X quit
expect_class_contains "numeric Screen session selector warns about PID ambiguity" 3 "may interpret leading digits as a PID" --dry-run -r 12345
expect_class_contains "risky Screen window selector prints uncertainty warning" 3 "WARNING: uncertain translation of argument Screen window selector" --dry-run -S work -p 'editor.1' -X stuff x

ESC=$(printf '\033')
YELLOW_APPROX="${ESC}[33mAPPROX${ESC}[0m"
RED_UNSUPPORTED="${ESC}[31mUNSUPPORTED${ESC}[0m"
expect_selective_color "APPROX diagnostic colorizes only its class token" 3 "$YELLOW_APPROX" "screen2tmux: " --dry-run -L
expect_selective_color "UNSUPPORTED diagnostic colorizes only its class token" 2 "$RED_UNSUPPORTED" "screen2tmux: " --dry-run -c /tmp/my-screenrc
expect_no_color_override "NO_COLOR overrides forced color without changing semantics" 3 --dry-run -L

CURRENT_NAME='help colorizes status tokens without coloring whole rows'
OUT=$(NO_COLOR= SCREEN2TMUX_COLOR=always screen --help 2>&1)
RC=$?
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'ACTUAL_EXIT: %s\n' "$RC"
    printf '%s\n' 'OUTPUT_DISPLAY_BEGIN'
    printf '%s\n' "$OUT"
    printf '%s\n' 'OUTPUT_DISPLAY_END'
} >> "$REG_LOG"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -F "${ESC}[32m[EXACT]${ESC}[0m" >/dev/null 2>&1 && \
   printf '%s' "$OUT" | grep -F 'Safe mapping; executes tmux automatically' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC)"
fi

CURRENT_NAME='build dependency decline exits without installing'
OUT=$(CC=definitely-missing-screen2tmux-cc SCREEN2TMUX_AUTO_INSTALL=no SCREEN2TMUX_DEPENDENCY_CHECK_ONLY=1 sh "$PROJECT/build_tmux_3.7d.sh" 2>&1)
RC=$?
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'ACTUAL_EXIT: %s\n' "$RC"
    printf '%s\n' 'OUTPUT_DISPLAY_BEGIN'
    printf '%s\n' "$OUT"
    printf '%s\n' 'OUTPUT_DISPLAY_END'
} >> "$REG_LOG"
if [ "$RC" -eq 2 ] && \
   printf '%s\n' "$OUT" | grep -F 'Dependency installation declined; build cancelled.' >/dev/null 2>&1 && \
   printf '%s\n' "$OUT" | grep -F 'If you do not have administrator rights, ask an administrator to run:' >/dev/null 2>&1 && \
   printf '%s\n' "$OUT" | grep -F 'sudo apt-get update && sudo apt-get install -y' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi

CURRENT_NAME='build dependency yes path invokes installer and rechecks'
_DEP_TMP="$PROJECT/logs/.dep-install-test-$$"
rm -rf "$_DEP_TMP"
mkdir -p "$_DEP_TMP/bin"
cat > "$_DEP_TMP/bin/apt-get" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${SCREEN2TMUX_FAKE_APT_LOG:?}"
exit 0
EOF
cat > "$_DEP_TMP/bin/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${SCREEN2TMUX_FAKE_SUDO_LOG:?}"
exec "$@"
EOF
chmod +x "$_DEP_TMP/bin/apt-get" "$_DEP_TMP/bin/sudo"
: > "$_DEP_TMP/apt.log"
: > "$_DEP_TMP/sudo.log"
OUT=$(PATH="$_DEP_TMP/bin:$PATH" SCREEN2TMUX_FAKE_APT_LOG="$_DEP_TMP/apt.log" \
    SCREEN2TMUX_FAKE_SUDO_LOG="$_DEP_TMP/sudo.log" \
    CC=definitely-missing-screen2tmux-cc SCREEN2TMUX_PACKAGE_MANAGER=apt-get \
    SCREEN2TMUX_AUTO_INSTALL=yes SCREEN2TMUX_DEPENDENCY_CHECK_ONLY=1 \
    sh "$PROJECT/build_tmux_3.7d.sh" 2>&1)
RC=$?
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'ACTUAL_EXIT: %s\n' "$RC"
    printf '%s\n' 'OUTPUT_DISPLAY_BEGIN'
    printf '%s\n' "$OUT"
    printf '%s\n' 'OUTPUT_DISPLAY_END'
    printf '%s\n' 'FAKE_APT_BEGIN'
    cat "$_DEP_TMP/apt.log"
    printf '%s\n' 'FAKE_APT_END'
    printf '%s\n' 'FAKE_SUDO_BEGIN'
    cat "$_DEP_TMP/sudo.log"
    printf '%s\n' 'FAKE_SUDO_END'
} >> "$REG_LOG"
if [ "$RC" -eq 2 ] && grep -F 'update' "$_DEP_TMP/apt.log" >/dev/null 2>&1 && \
   grep -F 'install -y' "$_DEP_TMP/apt.log" >/dev/null 2>&1 && \
   printf '%s\n' "$OUT" | grep -F 'If you do not have administrator rights, ask an administrator to run:' >/dev/null 2>&1 && \
   printf '%s\n' "$OUT" | grep -F 'sudo apt-get update && sudo apt-get install -y' >/dev/null 2>&1 && \
   printf '%s\n' "$OUT" | grep -F 'Rechecking build dependencies after installation' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi
rm -rf "$_DEP_TMP"

CURRENT_NAME='invalid syntax rejection is strict-only'
OUT=$(NO_COLOR=1 SCREEN2TMUX_COLOR=never sh -c '. "$1"; screen -Z --dry-run' sh "$PROJECT/bin/screen-function-source.sh" 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then pass "$CURRENT_NAME"; else fail "$CURRENT_NAME"; fi

CURRENT_NAME='strict mode still rejects invalid syntax'
OUT=$(NO_COLOR=1 SCREEN2TMUX_COLOR=never sh -c '. "$1"; screen -Z --dry-run --strict' sh "$PROJECT/bin/screen-function-source.sh" 2>&1)
RC=$?
if [ "$RC" -eq 64 ] && printf '%s\n' "$OUT" | grep -F 'invalid/unknown Screen syntax' >/dev/null 2>&1; then pass "$CURRENT_NAME"; else fail "$CURRENT_NAME"; fi

CURRENT_NAME='invalid equivalence cases enable strict validation internally'
if grep -F '[ "$_iw_expected" = invalid ] && set -- "$@" --strict' "$PROJECT/tests/interface-equivalence-worker.sh" >/dev/null 2>&1; then pass "$CURRENT_NAME"; else fail "$CURRENT_NAME"; fi

CURRENT_NAME='built integration formatter aligns both pipe columns'
_BUILT_FMT=$(NO_COLOR=1 SCREEN2TMUX_MAP_LEFT_WIDTH=32 SCREEN2TMUX_MAP_DESC_WIDTH=60 SCREEN2TMUX_MAP_SCREEN_WIDTH=70 sh -c '
. "$1"
_s2t_test_print_case "[PASS] tmux-3.7c DRYRUN" "compiled screen hardlink translation smoke test" "screen -d -m bash" "tmux new-session -d bash"
_s2t_test_print_case "[PASS] tmux-3.7c STRICT-EXTERNAL" "compiled strict mode blocks helper-backed EXTERNAL execution" "screen --strict -d -m //telnet example.com 23" "<EXTERNAL: advisory only>"
' sh "$PROJECT/tests/output-format.sh")
_BUILT_POS=$(printf '%s\n' "$_BUILT_FMT" | awk '''{ first=index($0,"|"); rest=substr($0,first+1); second=first+index(rest,"|"); print first ":" second }''')
if [ "$_BUILT_POS" = "34:97
34:97" ] && \
   grep -F 'SCREEN2TMUX_MAP_LEFT_WIDTH=${SCREEN2TMUX_BUILT_LEFT_WIDTH:-32}' "$PROJECT/tests/test-built-tmux-screen.sh" >/dev/null 2>&1; then pass "$CURRENT_NAME"; else fail "$CURRENT_NAME ($_BUILT_POS)"; fi

CURRENT_NAME='standalone screen.sh accepts --dryrun alias'
OUT=$(NO_COLOR=1 sh "$PROJECT/bin/screen.sh" --dryrun -d -m bash 2>&1)
RC=$?
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'ACTUAL_EXIT: %s\n' "$RC"
    printf 'OUTPUT_DISPLAY_BEGIN\n%s\nOUTPUT_DISPLAY_END\n' "$OUT"
} >> "$REG_LOG"
if [ "$RC" -eq 0 ] && [ "$OUT" = "tmux new-session -d bash" ]; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi

CURRENT_NAME='standalone screen.sh has no sibling-file dependency'
_s2t_solo_dir=${TMPDIR:-/tmp}/screen2tmux-standalone-$$
rm -rf "$_s2t_solo_dir"
mkdir -p "$_s2t_solo_dir"
cp "$PROJECT/bin/screen.sh" "$_s2t_solo_dir/screen.sh"
chmod 644 "$_s2t_solo_dir/screen.sh"
OUT=$(NO_COLOR=1 sh "$_s2t_solo_dir/screen.sh" --dryrun -d -m bash 2>&1)
RC=$?
cat > "$_s2t_solo_dir/tmux" <<'EOF_SOLO_TMUX'
#!/bin/sh
printf 'SOLO_TMUX_EXEC'
for a do printf ' <%s>' "$a"; done
printf '\n'
EOF_SOLO_TMUX
chmod 755 "$_s2t_solo_dir/tmux"
_EXEC_OUT=$(PATH="$_s2t_solo_dir:$PATH" NO_COLOR=1 sh "$_s2t_solo_dir/screen.sh" -d -m bash 2>&1)
_EXEC_RC=$?
rm -rf "$_s2t_solo_dir"
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'DRYRUN_EXIT: %s\n' "$RC"
    printf 'DRYRUN_OUTPUT_BEGIN\n%s\nDRYRUN_OUTPUT_END\n' "$OUT"
    printf 'EXEC_EXIT: %s\n' "$_EXEC_RC"
    printf 'EXEC_OUTPUT_BEGIN\n%s\nEXEC_OUTPUT_END\n' "$_EXEC_OUT"
} >> "$REG_LOG"
if [ "$RC" -eq 0 ] && [ "$OUT" = "tmux new-session -d bash" ] && \
   [ "$_EXEC_RC" -eq 0 ] && [ "$_EXEC_OUT" = 'SOLO_TMUX_EXEC <new-session> <-d> <bash>' ] && \
   ! grep -F '. "$_s2t_front_dir/' "$PROJECT/bin/screen.sh" >/dev/null 2>&1 && \
   ! grep -F 'screen-function-source.sh" || exit' "$PROJECT/bin/screen.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi

CURRENT_NAME='screen-function-source.sh defines callable screen function when sourced'
OUT=$(NO_COLOR=1 sh -c '. "$1"; screen --dryrun -d -m bash' sh "$PROJECT/bin/screen-function-source.sh" 2>&1)
RC=$?
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'ACTUAL_EXIT: %s\n' "$RC"
    printf 'OUTPUT_DISPLAY_BEGIN\n%s\nOUTPUT_DISPLAY_END\n' "$OUT"
} >> "$REG_LOG"
if [ "$RC" -eq 0 ] && [ "$OUT" = "tmux new-session -d bash" ]; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi

CURRENT_NAME='direct sh execution of screen-function-source.sh explains POSIX sourcing requirement'
OUT=$(NO_COLOR=1 sh "$PROJECT/bin/screen-function-source.sh" 2>&1)
RC=$?
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'ACTUAL_EXIT: %s\n' "$RC"
    printf 'OUTPUT_DISPLAY_BEGIN\n%s\nOUTPUT_DISPLAY_END\n' "$OUT"
} >> "$REG_LOG"
if [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | grep -F '. ./bin/screen-function-source.sh' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi

CURRENT_NAME='screen-function-source-minified.sh defines callable screen function when sourced'
OUT=$(NO_COLOR=1 sh -c '. "$1"; screen --dryrun -d -m bash' sh "$PROJECT/bin/screen-function-source-minified.sh" 2>&1)
RC=$?
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'ACTUAL_EXIT: %s\n' "$RC"
    printf 'OUTPUT_DISPLAY_BEGIN\n%s\nOUTPUT_DISPLAY_END\n' "$OUT"
} >> "$REG_LOG"
if [ "$RC" -eq 0 ] && [ "$OUT" = "tmux new-session -d bash" ]; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi

CURRENT_NAME='direct sh execution of minified source explains POSIX sourcing requirement'
OUT=$(NO_COLOR=1 sh "$PROJECT/bin/screen-function-source-minified.sh" 2>&1)
RC=$?
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'ACTUAL_EXIT: %s\n' "$RC"
    printf 'OUTPUT_DISPLAY_BEGIN\n%s\nOUTPUT_DISPLAY_END\n' "$OUT"
} >> "$REG_LOG"
if [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | grep -F '. ./bin/screen-function-source-minified.sh' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi

for _s2t_one in screen-function-source.oneliner.sh screen-function-source-minified.oneliner.sh; do
    CURRENT_NAME="$_s2t_one is one physical line and defines callable screen function"
    _s2t_one_path=$PROJECT/bin/$_s2t_one
    _s2t_lines=$(wc -l < "$_s2t_one_path" | tr -d ' ')
    OUT=$(NO_COLOR=1 sh -c '. "$1"; screen --dryrun -d -m bash' sh "$_s2t_one_path" 2>&1)
    RC=$?
    {
        printf '%s\n' '=============================================================================='
        printf 'TEST: %s\n' "$CURRENT_NAME"
        printf 'PHYSICAL_LINES: %s\n' "$_s2t_lines"
        printf 'ACTUAL_EXIT: %s\n' "$RC"
        printf 'OUTPUT_DISPLAY_BEGIN\n%s\nOUTPUT_DISPLAY_END\n' "$OUT"
    } >> "$REG_LOG"
    if [ "$_s2t_lines" -eq 1 ] && [ "$RC" -eq 0 ] && [ "$OUT" = "tmux new-session -d bash" ]; then
        pass "$CURRENT_NAME"
    else
        fail "$CURRENT_NAME (lines=$_s2t_lines rc=$RC output=$OUT)"
    fi

    CURRENT_NAME="direct sh execution of $_s2t_one explains POSIX sourcing requirement"
    OUT=$(NO_COLOR=1 sh "$_s2t_one_path" 2>&1)
    RC=$?
    {
        printf '%s\n' '=============================================================================='
        printf 'TEST: %s\n' "$CURRENT_NAME"
        printf 'ACTUAL_EXIT: %s\n' "$RC"
        printf 'OUTPUT_DISPLAY_BEGIN\n%s\nOUTPUT_DISPLAY_END\n' "$OUT"
    } >> "$REG_LOG"
    if [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | grep -F ". ./bin/$_s2t_one" >/dev/null 2>&1; then
        pass "$CURRENT_NAME"
    else
        fail "$CURRENT_NAME (rc=$RC output=$OUT)"
    fi
done

CURRENT_NAME='minified one-liner starts with the primary screen function body'
_s2t_literal_one=$PROJECT/bin/screen-function-source-minified.oneliner.sh
_s2t_literal_prefix=$(head -c 240 "$_s2t_literal_one")
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'PREFIX: %s\n' "$_s2t_literal_prefix"
} >> "$REG_LOG"
case "$_s2t_literal_prefix" in
    'screen () { _s2t_dry_run=0;'*)
        if ! printf '%s\n' "$_s2t_literal_prefix" | grep -F 'screen2tmux "$@"' >/dev/null 2>&1; then
            pass "$CURRENT_NAME"
        else
            fail "$CURRENT_NAME (screen is still only a wrapper)"
        fi
        ;;
    *) fail "$CURRENT_NAME (prefix=$_s2t_literal_prefix)" ;;
esac

CURRENT_NAME='minified one-liner is a literal POSIX function definition without shell eval reconstruction'
_s2t_literal_one=$PROJECT/bin/screen-function-source-minified.oneliner.sh
OUT=$(NO_COLOR=1 sh -c '. "$1"; screen2tmux --dryrun -d -m bash; screen --dryrun -d -m bash' sh "$_s2t_literal_one" 2>&1)
RC=$?
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'ACTUAL_EXIT: %s\n' "$RC"
    printf 'OUTPUT_DISPLAY_BEGIN\n%s\nOUTPUT_DISPLAY_END\n' "$OUT"
} >> "$REG_LOG"
if [ "$RC" -eq 0 ] && \
   grep -F 'screen () {' "$_s2t_literal_one" >/dev/null 2>&1 && \
   ! grep -F 'eval "$(printf' "$_s2t_literal_one" >/dev/null 2>&1 && \
   ! grep -F 'eval "set --' "$_s2t_literal_one" >/dev/null 2>&1 && \
   [ "$OUT" = "tmux new-session -d bash
tmux new-session -d bash" ]; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi

CURRENT_NAME='standalone screen.sh executes tmux by default'
_s2t_stub_dir=${TMPDIR:-/tmp}/screen2tmux-wrapper-$$
rm -rf "$_s2t_stub_dir"
mkdir -p "$_s2t_stub_dir"
cat > "$_s2t_stub_dir/tmux" <<'EOF_STUB'
#!/bin/sh
printf 'TMUX_EXEC'
for a do printf ' <%s>' "$a"; done
printf '\n'
EOF_STUB
chmod 755 "$_s2t_stub_dir/tmux"
OUT=$(PATH="$_s2t_stub_dir:$PATH" NO_COLOR=1 sh "$PROJECT/bin/screen.sh" -d -m bash 2>&1)
RC=$?
rm -rf "$_s2t_stub_dir"
{
    printf '%s\n' '=============================================================================='
    printf 'TEST: %s\n' "$CURRENT_NAME"
    printf 'ACTUAL_EXIT: %s\n' "$RC"
    printf 'OUTPUT_DISPLAY_BEGIN\n%s\nOUTPUT_DISPLAY_END\n' "$OUT"
} >> "$REG_LOG"
if [ "$RC" -eq 0 ] && [ "$OUT" = 'TMUX_EXEC <new-session> <-d> <bash>' ]; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$RC output=$OUT)"
fi


CURRENT_NAME='generic tmux builders and legacy front-ends are readable shell scripts'
if [ -r "$PROJECT/build_tmux.sh" ] && [ -r "$PROJECT/build_tmux_patched.sh" ] && \
   [ -r "$PROJECT/build_tmux_3.7c.sh" ] && [ -r "$PROJECT/build_tmux_3.7c_patched.sh" ] && \
   [ -r "$PROJECT/build_tmux_3.7d.sh" ] && [ -r "$PROJECT/build_tmux_3.7d_patched.sh" ] && \
   [ -r "$PROJECT/build_tmux_latest.sh" ] && [ -r "$PROJECT/build_tmux_latest_patched.sh" ]; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='internal shell-script calls use explicit sh'
if grep -F 'exec sh "$HERE/build_tmux.sh" "$@"' "$PROJECT/build_tmux_patched.sh" >/dev/null 2>&1 && \
   grep -F 'exec sh "$HERE/scripts/build-tmux-one.sh" 3.7c 3.7c 1' "$PROJECT/build_tmux_3.7c_patched.sh" >/dev/null 2>&1 && \
   grep -F 'sh "$HERE/tests/test-interface-equivalence.sh"' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F 'sh "$HERE/tests/test-regressions.sh"' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F '*.sh) NO_COLOR=1 SCREEN2TMUX_COLOR=never sh "$INTERFACE"' "$PROJECT/tests/interface-equivalence-worker.sh" >/dev/null 2>&1 && \
   grep -F 'screen-script) _exec_count=$((_exec_count + 1)); PATH="$_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never sh "$_path"' "$PROJECT/tests/test-interface-equivalence.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='tmux integration uses native C module layout'
if [ -r "$PROJECT/tmux-integration/screen-compat.c" ] && \
   [ -r "$PROJECT/tmux-integration/tmux-screen-compat.patch" ] && \
   grep -F 'screen-compat.c' "$PROJECT/tmux-integration/tmux-screen-compat.patch" >/dev/null 2>&1 && \
   grep -F 'screen_compat_translate(int *, char ***)' "$PROJECT/tmux-integration/tmux-screen-compat.patch" >/dev/null 2>&1 && \
   grep -F 'screen_compat_translate(&argc, &argv);' "$PROJECT/tmux-integration/tmux-screen-compat.patch" >/dev/null 2>&1 && \
   ! grep -F '#include "screen-to-tmux-translator"' "$PROJECT/tmux-integration/tmux-screen-compat.patch" >/dev/null 2>&1 && \
   grep -F 'INTEGRATION=$PROJECT/tmux-integration/screen-compat.c' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'TMUX_PATCH=$PROJECT/tmux-integration/tmux-screen-compat.patch' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F '[ -r "$TMUX_PATCH" ]' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   ! grep -F 'TMUX_C_PATCH' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'if [ "$_diff_count" -ne 4 ]' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='native C integration uses tmux printflike annotation'
_CFILE=$PROJECT/tmux-integration/screen-compat.c
if grep -F 'static void printflike(2, 3)' "$_CFILE" >/dev/null 2>&1 && \
   ! grep -F '__printflike' "$_CFILE" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi
unset _CFILE

CURRENT_NAME='native executable mappings terminate parser branch after argv install'
_CFILE=$PROJECT/tmux-integration/screen-compat.c
if awk '
BEGIN { in_call = 0; need_stop = 0; bad = 0 }
{
    if (need_stop) {
        if ($0 ~ /^[[:space:]]*$/)
            next
        if ($0 !~ /^[[:space:]]*return;[[:space:]]*$/ &&
            $0 !~ /^[[:space:]]*}[[:space:]]*$/)
            bad = 1
        need_stop = 0
    }
    if ($0 ~ /^[[:space:]]+screen_compat_(approx_exec|external_exec)\(sc,/) {
        in_call = 1
        if ($0 ~ /\);[[:space:]]*$/) {
            in_call = 0
            need_stop = 1
        }
        next
    }
    if (in_call && $0 ~ /\);[[:space:]]*$/) {
        in_call = 0
        need_stop = 1
    }
}
END { exit (bad || in_call || need_stop) ? 1 : 0 }
' "$_CFILE"; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi
unset _CFILE

CURRENT_NAME='README ZIP build command removes stale extraction first'
if grep -F 'rm -rf screen-to-tmux-translator-main && unzip -q stt.zip' "$PROJECT/README.md" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='focused regressions hide PASS rows unless explicitly requested'
if grep -F 'SHOW_PASS=${SCREEN2TMUX_SHOW_REGRESSION_TEST_PASS:-0}' "$PROJECT/tests/test-regressions.sh" >/dev/null 2>&1 && \
   grep -F '[ "$SHOW_PASS" -eq 0 ] || printf' "$PROJECT/tests/test-regressions.sh" >/dev/null 2>&1 && \
   grep -F 'RESULT\tPASS\t%s' "$PROJECT/tests/test-regressions.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='run-tests exposes show-regression-test-pass option'
if grep -F -- '--show-regression-test-pass' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F 'SCREEN2TMUX_SHOW_REGRESSION_TEST_PASS="$SHOW_REGRESSION_PASS"' "$PROJECT/run-tests.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='console and build formatters flush progress incrementally'
if grep -F 'function emit(s) { print s; fflush() }' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F 'function add_compile(item,' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'function emit(s) { print s; fflush() }' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='compiled tmux integration contains no embedded shell bridge'
_CFILE=$PROJECT/tmux-integration/screen-compat.c
_CINCLUDES=$(grep '^#include ' "$_CFILE" || :)
_EXPECTED_INCLUDES='#include <sys/types.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "tmux.h"'
if [ "$_CINCLUDES" = "$_EXPECTED_INCLUDES" ] && \
   grep -F 'screen_compat_parse(struct screen_compat *)' "$_CFILE" >/dev/null 2>&1 && \
   grep -F 'screen_compat_translate(int *argcp, char ***argvp)' "$_CFILE" >/dev/null 2>&1 && \
   ! grep -E 'screen_compat_shell_source|_PATH_BSHELL|/bin/sh|(^|[^A-Za-z0-9_])(fork|pipe|execv?|waitpid)\(' "$_CFILE" >/dev/null 2>&1 && \
   ! grep -E '^[[:space:]]*#[[:space:]]*include[[:space:]]+<(sys/wait|signal|errno|fcntl|paths)\.h>' "$_CFILE" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi
unset _CFILE _CINCLUDES _EXPECTED_INCLUDES

CURRENT_NAME='3.7c default builder uses pinned release tag'
if grep -F 'TMUX_3_7C_PIN=${SCREEN2TMUX_TMUX_3_7C_PIN:-refs/tags/3.7c}' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F '3.7c|release_3.7c)' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'rev-parse --verify "$TMUX_3_7C_PIN^{commit}"' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'exec sh "$HERE/scripts/build-tmux-one.sh" 3.7c 3.7c 0' "$PROJECT/build_tmux_3.7c.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='3.7d builder uses immutable project pin'
if grep -F 'e9634d40749a5ae330aabf5aa46a81505b094a6b' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F '3.7d|release_3.7d)' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'exec sh "$HERE/scripts/build-tmux-one.sh" 3.7d 3.7d 0' "$PROJECT/build_tmux_3.7d.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='tmux build layout uses src and build roots'
if grep -F 'SCREEN2TMUX_SOURCE_ROOT:-$PROJECT/src' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'SCREEN2TMUX_BUILD_ROOT:-$PROJECT/build' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'SOURCE_DIR=$SOURCE_PARENT/tmux-$NAME$SUFFIX' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'BUILD_DIR=$BUILD_PARENT/tmux-$NAME$SUFFIX' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='generic tmux builder defaults to both 3.7c variants'
_BTMP=${TMPDIR:-/tmp}/screen2tmux-build-driver-$$
rm -rf "$_BTMP"; mkdir -p "$_BTMP"
cat > "$_BTMP/driver" <<'EOF_BUILD_STUB'
#!/bin/sh
printf '%s %s %s\n' "$1" "$2" "$3" >> "$SCREEN2TMUX_BUILD_STUB_LOG"
exit 0
EOF_BUILD_STUB
chmod 755 "$_BTMP/driver"
: > "$_BTMP/calls"
SCREEN2TMUX_BUILD_ONE="$_BTMP/driver" SCREEN2TMUX_BUILD_STUB_LOG="$_BTMP/calls" NO_COLOR=1 sh "$PROJECT/build_tmux.sh" --verbosity quiet >/dev/null 2>&1
_RC=$?
_BCALLS=$(cat "$_BTMP/calls")
if [ "$_RC" -eq 0 ] && [ "$_BCALLS" = "3.7c 3.7c 0
3.7c 3.7c 1" ]; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$_RC calls=$_BCALLS)"
fi

CURRENT_NAME='patched tmux builder defaults to patched 3.7c only'
: > "$_BTMP/calls"
SCREEN2TMUX_BUILD_ONE="$_BTMP/driver" SCREEN2TMUX_BUILD_STUB_LOG="$_BTMP/calls" NO_COLOR=1 sh "$PROJECT/build_tmux_patched.sh" --verbosity quiet >/dev/null 2>&1
_RC=$?
_BCALLS=$(cat "$_BTMP/calls")
if [ "$_RC" -eq 0 ] && [ "$_BCALLS" = "3.7c 3.7c 1" ]; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$_RC calls=$_BCALLS)"
fi

CURRENT_NAME='generic tmux builder accepts comma-separated versions'
: > "$_BTMP/calls"
SCREEN2TMUX_BUILD_ONE="$_BTMP/driver" SCREEN2TMUX_BUILD_STUB_LOG="$_BTMP/calls" NO_COLOR=1 sh "$PROJECT/build_tmux.sh" --verbosity quiet 3.7d,latest >/dev/null 2>&1
_RC=$?
_BCOUNT=$(wc -l < "$_BTMP/calls" | tr -d ' ')
if [ "$_RC" -eq 0 ] && [ "$_BCOUNT" -eq 4 ] && grep -F 'latest latest 0' "$_BTMP/calls" >/dev/null 2>&1 && grep -F 'latest latest 1' "$_BTMP/calls" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$_RC calls=$_BCALLS)"
fi
rm -rf "$_BTMP"

CURRENT_NAME='normal build verbosity summarizes coherent configure and compile results'
if grep -F 'emit_items("Configure yes", yes, ny, "  ")' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'emit_items("Configure no", no, nn, "  ")' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'emit_items("Configure values", values, nv, ", ")' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'sub(/ usability$/, "", name)' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'sub(/ presence$/, "", name)' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'function emit_compile' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'prefix = "Compiling "' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'add_compile($0 " ... [OK]")' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='configure yes/no color is token scoped'
if grep -F 'Configure yes:' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'G substr(line,p+1) Z' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'R substr(line,p+1) Z' "$PROJECT/scripts/build-tmux-one.sh" >/dev/null 2>&1 && \
   grep -F 'SCREEN2TMUX_CONSOLE_WIDTH="$CONSOLE_WIDTH"' "$PROJECT/run-tests.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='run-tests builds patched only by default and exposes compile-original'
if grep -F -- '--build [VERSION ...]' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F -- '--compile-original' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F 'BUILD_VERSIONS=3.7c' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F '_builder=$HERE/build_tmux_patched.sh' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F '[ "$COMPILE_ORIGINAL" -eq 0 ] || _builder=$HERE/build_tmux.sh' "$PROJECT/run-tests.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='compile-original is rejected without build'
_CO_OUT=$(NO_COLOR=1 sh "$PROJECT/run-tests.sh" --compile-original 2>&1)
_CO_RC=$?
if [ "$_CO_RC" -eq 64 ] && printf '%s\n' "$_CO_OUT" | grep -F -- '--compile-original requires --build' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (rc=$_CO_RC output=$_CO_OUT)"
fi

CURRENT_NAME='run-tests discovers arbitrary successful builds dynamically'
if grep -F 'for _dir in "$BUILD_ROOT"/tmux-*' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F 'SCREEN2TMUX_EQUIV_BUILT_REGISTRY="$EQUIV_BUILT_REGISTRY"' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F 'while IFS="$TAB" read -r _bn _bp _bl' "$PROJECT/tests/test-interface-equivalence.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='mapping formatter aligns pipes and arrows'
_FMT_OUT=$(SCREEN2TMUX_TEST_QUIET=0 SCREEN2TMUX_MAP_LEFT_WIDTH=26 SCREEN2TMUX_MAP_DESC_WIDTH=52 SCREEN2TMUX_MAP_SCREEN_WIDTH=49 sh -c '. "$1"; _s2t_test_print_case "[PASS] C001 exact" "one" "screen" "tmux new-session"; _s2t_test_print_case "[PASS] Z008 invalid" "a much longer description" "screen -S work -X definitely-not-a-screen-command" "<INVALID Screen syntax>"' sh "$PROJECT/tests/output-format.sh")
_FMT_POS=$(printf '%s
' "$_FMT_OUT" | awk 'NR==1 {p1=index($0,"|"); a1=index($0,"->")} NR==2 {p2=index($0,"|"); a2=index($0,"->")} END {print p1 ":" a1 ":" p2 ":" a2}')
if [ "$_FMT_POS" = '28:135:28:135' ]; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (columns $_FMT_POS)"
fi

CURRENT_NAME='mapping formatter colorizes class result with class color'
_FMT_OUT=$(NO_COLOR= SCREEN2TMUX_COLOR=always SCREEN2TMUX_TEST_QUIET=0 SCREEN2TMUX_MAP_LEFT_WIDTH=26 SCREEN2TMUX_MAP_DESC_WIDTH=52 SCREEN2TMUX_MAP_SCREEN_WIDTH=49 sh -c '. "$1"; _s2t_test_print_case "[PASS] P013 unsupported" "flow off form" "screen -fn" "<UNSUPPORTED>" unsupported; _s2t_test_print_case "[PASS] C027 moot" "wipe stale sessions" "screen -wipe" "<MOOT: no tmux action>" moot; _s2t_test_print_case "[PASS] C007 approx" "start named editor session" "screen -S editor vim file.txt" "tmux new-session -s editor vim file.txt" approx-run' sh "$PROJECT/tests/output-format.sh")
_FMT_HEX=$(printf '%s' "$_FMT_OUT" | od -An -v -tx1 | tr -d ' \n')
_ESC=$(printf '\033')
if printf '%s\n' "$_FMT_OUT" | grep -F "${_ESC}[31m<UNSUPPORTED>${_ESC}[0m" >/dev/null 2>&1 && \
   printf '%s\n' "$_FMT_OUT" | grep -F "${_ESC}[36m<MOOT: no tmux action>${_ESC}[0m" >/dev/null 2>&1 && \
   printf '%s\n' "$_FMT_OUT" | grep -F "${_ESC}[33mtmux new-session -s editor vim file.txt${_ESC}[0m" >/dev/null 2>&1 && \
   printf '%s\n' "$_FMT_OUT" | grep -F "${_ESC}[31munsupported${_ESC}[0m" >/dev/null 2>&1 && \
   printf '%s\n' "$_FMT_OUT" | grep -F "${_ESC}[36mmoot${_ESC}[0m" >/dev/null 2>&1 && \
   printf '%s\n' "$_FMT_OUT" | grep -F "${_ESC}[33mapprox${_ESC}[0m" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (hex=$_FMT_HEX)"
fi

CURRENT_NAME='aggregate terminal colorizer colorizes complete result by class'
_COLOR_FUNC=${TMPDIR:-/tmp}/screen2tmux-colorize-$$.sh
sed -n '/^colorize_stream()$/,/^terminal_stream()/p' "$PROJECT/run-tests.sh" | sed '$d' > "$_COLOR_FUNC"
_AGG_FMT_OUT=$(sh -c 'COLOR_ENABLED=1; . "$1"; printf "%s\n" \
    "[PASS] C001 exact          | one | screen -> tmux new-session" \
    "[PASS] C002 approx         | two | screen -S work -> tmux new-session -s work" \
    "[PASS] P013 unsupported    | three | screen -fn -> <UNSUPPORTED>" \
    "[PASS] C027 moot           | four | screen -wipe -> <MOOT: no tmux action>" \
    "[PASS] X009 external       | five | screen //telnet example.com -> tmux new-session telnet example.com" \
    "[PASS] Z001 invalid        | six | screen -Z -> <INVALID Screen syntax>" | colorize_stream' sh "$_COLOR_FUNC")
rm -f "$_COLOR_FUNC"
_ESC=$(printf '\033')
if printf '%s\n' "$_AGG_FMT_OUT" | grep -F "${_ESC}[32mtmux new-session${_ESC}[0m" >/dev/null 2>&1 && \
   printf '%s\n' "$_AGG_FMT_OUT" | grep -F "${_ESC}[33mtmux new-session -s work${_ESC}[0m" >/dev/null 2>&1 && \
   printf '%s\n' "$_AGG_FMT_OUT" | grep -F "${_ESC}[31m<UNSUPPORTED>${_ESC}[0m" >/dev/null 2>&1 && \
   printf '%s\n' "$_AGG_FMT_OUT" | grep -F "${_ESC}[36m<MOOT: no tmux action>${_ESC}[0m" >/dev/null 2>&1 && \
   printf '%s\n' "$_AGG_FMT_OUT" | grep -F "${_ESC}[35mtmux new-session telnet example.com${_ESC}[0m" >/dev/null 2>&1 && \
   printf '%s\n' "$_AGG_FMT_OUT" | grep -F "${_ESC}[31m<INVALID Screen syntax>${_ESC}[0m" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='mapping formatter puts description before command mapping'
_FMT_OUT=$(SCREEN2TMUX_TEST_QUIET=0 SCREEN2TMUX_MAP_LEFT_WIDTH=26 SCREEN2TMUX_MAP_DESC_WIDTH=52 SCREEN2TMUX_MAP_SCREEN_WIDTH=49 sh -c '. "$1"; _s2t_test_print_case "[PASS] C001 exact" "start a new session" "screen" "tmux new-session"' sh "$PROJECT/tests/output-format.sh")
case "$_FMT_OUT" in
    *'| start a new session'*'| screen'*'-> tmux new-session') pass "$CURRENT_NAME" ;;
    *) fail "$CURRENT_NAME (output=$_FMT_OUT)" ;;
esac

CURRENT_NAME='command formatter omits unnecessary single quotes'
_FMT_OUT=$(sh -c '. "$1"; _s2t_test_format_argv screen -S work -X screen top' sh "$PROJECT/tests/output-format.sh")
if [ "$_FMT_OUT" = 'screen -S work -X screen top' ]; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (output=$_FMT_OUT)"
fi

CURRENT_NAME='command formatter keeps quotes only when shell protection is needed'
_FMT_OUT=$(sh -c '. "$1"; _s2t_test_format_argv tmux display-message -p -t work "#{window_index} (#{window_name})"' sh "$PROJECT/tests/output-format.sh")
if [ "$_FMT_OUT" = "tmux display-message -p -t work '#{window_index} (#{window_name})'" ]; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (output=$_FMT_OUT)"
fi

CURRENT_NAME='quiet mapping formatter suppresses screen-to-tmux column'
_FMT_OUT=$(SCREEN2TMUX_TEST_QUIET=1 SCREEN2TMUX_MAP_LEFT_WIDTH=26 sh -c '. "$1"; _s2t_test_print_case "[PASS] C001 exact" "one" "screen" "tmux new-session"' sh "$PROJECT/tests/output-format.sh")
if ! printf '%s
' "$_FMT_OUT" | grep -F ' | ' >/dev/null 2>&1 && printf '%s
' "$_FMT_OUT" | grep -F 'one' >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (output=$_FMT_OUT)"
fi

CURRENT_NAME='run-tests exposes individual equivalence interface selection'
if grep -F -- '--equivalence|--equivalence-only' "$PROJECT/run-tests.sh" >/dev/null 2>&1 &&    grep -F -- '--list-equivalence-interfaces' "$PROJECT/run-tests.sh" >/dev/null 2>&1 &&    grep -F 'SCREEN2TMUX_EQUIV_INTERFACES="$EQUIV_REQUEST"' "$PROJECT/run-tests.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='equivalence harness combines oracle and all selected interfaces per case'
if grep -F 'Equivalence interfaces (' "$PROJECT/tests/test-interface-equivalence.sh" >/dev/null 2>&1 && \
   grep -F 'screen_syntax_oracle "$@"' "$PROJECT/tests/test-interface-equivalence.sh" >/dev/null 2>&1 && \
   grep -F "printf '  %s (%s)\\n' \"\$_ilabel\" \"\$_idisplay_path\"" "$PROJECT/tests/test-interface-equivalence.sh" >/dev/null 2>&1 && \
   grep -F '_idisplay_path=${_ipath#"$PROJECT"/}' "$PROJECT/tests/test-interface-equivalence.sh" >/dev/null 2>&1 && \
   grep -F 'screen-function-source.oneliner.sh' "$PROJECT/tests/test-interface-equivalence.sh" >/dev/null 2>&1 && \
   grep -F 'screen-function-source-minified.oneliner.sh' "$PROJECT/tests/test-interface-equivalence.sh" >/dev/null 2>&1 && \
   grep -F '[DIVERGED]' "$PROJECT/tests/test-interface-equivalence.sh" >/dev/null 2>&1 && \
   ! grep -F '_way="${INTERFACE_COUNT}-way"' "$PROJECT/tests/test-interface-equivalence.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='aggregate runner prints the Screen matrix only once'
if grep -F "Screen CLI/oracle + interface equivalence tests" "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   ! grep -F "run_component 'screen CLI/oracle tests'" "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   ! grep -F "run_component 'interface equivalence tests'" "$PROJECT/run-tests.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='built live behavior runs only against patched tmux'
if grep -F '[ "$_variant" = patched ] || continue' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F 'tmux $_name patched behavior tests' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F 'The pristine originals are build baselines' "$PROJECT/run-tests.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='build registry preserves original build directory field'
if grep -F '_screen=-' "$PROJECT/run-tests.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='run-tests supports explicit and misspelled truncate-lines options'
if grep -F -- '--truncate-lines|--trunkate-lines' "$PROJECT/run-tests.sh" >/dev/null 2>&1 &&    grep -F -- '--truncate-lines=*|--trunkate-lines=*' "$PROJECT/run-tests.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='run-tests measures terminal width once before components'
if grep -F 'stty size </dev/tty' "$PROJECT/run-tests.sh" >/dev/null 2>&1 &&    grep -F 'CONSOLE_WIDTH:' "$PROJECT/run-tests.sh" >/dev/null 2>&1 &&    grep -F 'tee -a "$CONSOLE_LOG" | terminal_stream' "$PROJECT/run-tests.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='run-tests exposes normal build verbosity by default'
if grep -F 'VERBOSITY=normal' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F -- '--verbosity LEVEL' "$PROJECT/run-tests.sh" >/dev/null 2>&1 && \
   grep -F 'sh "$_builder"' "$PROJECT/run-tests.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='run-test archive filename includes translator version'
if grep -F 'screen-to-tmux-translator-$VERSION-test-logs-$RUN_TIMESTAMP.zip' "$PROJECT/run-tests.sh" >/dev/null 2>&1; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME"
fi

CURRENT_NAME='alternate-screen live test reads effective inherited pane value'
_A_COUNT=$(grep -F -c 'show-options -p -A -v -t altcase:' "$PROJECT/tests/test-tmux-behavior.sh" 2>/dev/null || printf '0')
if [ "$_A_COUNT" -eq 2 ]; then
    pass "$CURRENT_NAME"
else
    fail "$CURRENT_NAME (expected 2 inherited-value queries, found $_A_COUNT)"
fi

CR=$(printf '\r')
CURRENT_NAME='dry-run renders carriage return safely'
capture -S work -p 0 -X stuff "hello${CR}" --dry-run
HEX=$(printf '%s' "$OUT" | od -An -v -tx1 | tr -d ' \n')
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -F 'hello\r' >/dev/null 2>&1 && ! printf '%s' "$HEX" | grep -F '0d' >/dev/null 2>&1; then
    pass "dry-run renders carriage return safely"
else
    fail "dry-run carriage-return rendering (rc=$RC hex=$HEX output=$OUT)"
fi

printf '\n%bRegression summary:%b %s %bPASS%b, %s %bFAIL%b\n' "$C" "$Z" "$P" "$G" "$Z" "$F" "$R" "$Z"
printf 'SUMMARY: pass=%s fail=%s\n' "$P" "$F" >> "$REG_LOG"
printf 'Regression log: %s\n' "$REG_LOG"
[ "$F" -eq 0 ]
