#!/bin/sh
# Structural/runtime smoke checks for compiled patched tmux binaries whose
# hardlink is named screen. Full translation equivalence is handled centrally
# by test-interface-equivalence.sh so successful cases are printed only once.
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$HERE/.." && pwd)
CANONICAL=${CANONICAL:-$PROJECT/bin/screen-function-source.sh}
RUN_TIMESTAMP=${SCREEN2TMUX_RUN_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}
LOG=${BUILT_SCREEN_LOG:-$PROJECT/logs/test-built-tmux-screen-$RUN_TIMESTAMP.log}

if [ "$#" -lt 1 ]; then
    printf '[SKIP] built tmux screen hardlink checks: no built screen binary supplied\n'
    mkdir -p "$(dirname -- "$LOG")"
    printf 'SKIP: no built screen binary supplied\n' > "$LOG"
    exit 0
fi

[ -r "$CANONICAL" ] || { printf 'ERROR: canonical translator missing: %s\n' "$CANONICAL" >&2; exit 2; }
# shellcheck disable=SC1090
. "$CANONICAL"
# These checks use longer labels than the main mapping matrix. Reserve enough
# width so both pipe columns stay fixed, including STRICT-EXTERNAL.
SCREEN2TMUX_MAP_LEFT_WIDTH=${SCREEN2TMUX_BUILT_LEFT_WIDTH:-32}
SCREEN2TMUX_MAP_DESC_WIDTH=${SCREEN2TMUX_BUILT_DESC_WIDTH:-60}
SCREEN2TMUX_MAP_SCREEN_WIDTH=${SCREEN2TMUX_BUILT_SCREEN_WIDTH:-70}
# shellcheck disable=SC1090
. "$HERE/output-format.sh"

mkdir -p "$(dirname -- "$LOG")"
: > "$LOG"
TMPBASE=${TMPDIR:-/tmp}/screen2tmux-built-screen-$$
rm -rf "$TMPBASE"
mkdir -p "$TMPBASE"
trap 'rm -rf "$TMPBASE"' EXIT HUP INT TERM
PASS=0
FAIL=0
TOTAL=0

color=0
if [ -z "${NO_COLOR:-}" ]; then
    case "${SCREEN2TMUX_COLOR:-auto}" in
        always) color=1 ;;
        auto|'') [ -t 1 ] && [ "${TERM:-}" != dumb ] && color=1 ;;
    esac
fi
if [ "$color" -eq 1 ]; then G='\033[32m'; R='\033[31m'; C='\033[36m'; Z='\033[0m'; else G=; R=; C=; Z=; fi

printf 'built tmux screen hardlink integration checks\n' >> "$LOG"
printf 'NOTE: full 683-variant translation comparison is performed by test-interface-equivalence.sh.\n' >> "$LOG"

for SCREEN_BIN do
    if [ ! -x "$SCREEN_BIN" ]; then
        FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
        printf '%b[FAIL]%b built screen missing/not executable: %s\n' "$R" "$Z" "$SCREEN_BIN"
        printf 'BUILD\tFAIL\tmissing\t%s\n' "$SCREEN_BIN" >> "$LOG"
        continue
    fi
    case "$SCREEN_BIN" in
        */screen) : ;;
        *)
            FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
            printf '%b[FAIL]%b built binary basename is not screen: %s\n' "$R" "$Z" "$SCREEN_BIN"
            printf 'BUILD\tFAIL\tbasename\t%s\n' "$SCREEN_BIN" >> "$LOG"
            continue
            ;;
    esac

    BIN_DIR=$(CDPATH= cd -- "$(dirname -- "$SCREEN_BIN")" && pwd)
    SCREEN_BIN=$BIN_DIR/screen
    TMUX_BIN=$BIN_DIR/tmux
    BUILD_DIR=$(CDPATH= cd -- "$BIN_DIR/../.." && pwd)
    _build_base=$(basename -- "$BUILD_DIR")
    case "$_build_base" in
        tmux-*-patched) LABEL=${_build_base%-patched} ;;
        build-tmux-*-patched) LABEL=${_build_base#build-}; LABEL=${LABEL%-patched} ;;
        *) LABEL=$_build_base ;;
    esac

    TOTAL=$((TOTAL + 1))
    if [ ! -x "$TMUX_BIN" ]; then
        FAIL=$((FAIL + 1))
        printf '%b[FAIL]%b %s sibling patched tmux missing: %s\n' "$R" "$Z" "$LABEL" "$TMUX_BIN"
        printf 'HARDLINK\tFAIL\t%s\tmissing-tmux\n' "$LABEL" >> "$LOG"
        continue
    fi
    _it=$(ls -di "$TMUX_BIN" | awk '{print $1}')
    _is=$(ls -di "$SCREEN_BIN" | awk '{print $1}')
    if [ "$_it" = "$_is" ]; then
        PASS=$((PASS + 1))
        printf '%b[PASS]%b %s screen is a hardlink to patched tmux\n' "$G" "$Z" "$LABEL"
        printf 'HARDLINK\tPASS\t%s\t%s\n' "$LABEL" "$SCREEN_BIN" >> "$LOG"
    else
        FAIL=$((FAIL + 1))
        printf '%b[FAIL]%b %s screen is not a hardlink to sibling tmux\n' "$R" "$Z" "$LABEL"
        printf 'HARDLINK\tFAIL\t%s\t%s\n' "$LABEL" "$SCREEN_BIN" >> "$LOG"
        continue
    fi

    # A direct dry-run smoke check, independent of the central full-matrix run.
    TOTAL=$((TOTAL + 1))
    _dry=$($SCREEN_BIN -d -m bash --dry-run 2>&1); _dry_rc=$?
    _ref=$(NO_COLOR=1 SCREEN2TMUX_COLOR=never sh -c '. "$1"; screen -d -m bash --dry-run' sh "$CANONICAL" 2>&1); _ref_rc=$?
    if [ "$_dry_rc" -eq "$_ref_rc" ] && [ "$_dry" = "$_ref" ]; then
        PASS=$((PASS + 1))
        _s2t_test_print_case "[PASS] $LABEL DRYRUN" 'compiled screen hardlink translation smoke test' \
            "$(_s2t_test_format_argv screen -d -m bash)" "$(_s2t_test_format_argv tmux new-session -d bash)"
        printf 'DRYRUN\tPASS\t%s\n' "$LABEL" >> "$LOG"
    else
        FAIL=$((FAIL + 1))
        printf '%b[FAIL]%b %s compiled screen hardlink dry-run differs from canonical translator\n' "$R" "$Z" "$LABEL"
        printf 'DRYRUN\tFAIL\t%s\tref_rc=%s\tactual_rc=%s\n' "$LABEL" "$_ref_rc" "$_dry_rc" >> "$LOG"
    fi

    # One real execution smoke test against an isolated tmux socket.
    RUNTIME=$TMPBASE/runtime-$LABEL
    mkdir -p "$RUNTIME/home" "$RUNTIME/tmux"
    chmod 700 "$RUNTIME/tmux"
    TOTAL=$((TOTAL + 1))
    if HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" NO_COLOR=1 SCREEN2TMUX_COLOR=never \
       "$SCREEN_BIN" -d -m >/dev/null 2>"$RUNTIME/screen.err" && \
       HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" list-sessions >/dev/null 2>"$RUNTIME/list.err"; then
        PASS=$((PASS + 1))
        _s2t_test_print_case "[PASS] $LABEL EXEC" 'real screen hardlink created an isolated tmux session' \
            "$(_s2t_test_format_argv screen -d -m)" "$(_s2t_test_format_argv tmux new-session -d)"
        printf 'EXEC\tPASS\t%s\n' "$LABEL" >> "$LOG"
    else
        FAIL=$((FAIL + 1))
        printf '%b[FAIL]%b %s real screen hardlink execution smoke test failed\n' "$R" "$Z" "$LABEL"
        printf 'EXEC\tFAIL\t%s\n' "$LABEL" >> "$LOG"
    fi

    # A real executable-APPROX check. The compatibility layer must emit its
    # warning and still hand the translated command back to this patched tmux
    # process for execution.
    TOTAL=$((TOTAL + 1))
    _approx_session=screen2tmux_approx_$$
    HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" kill-session -t "$_approx_session" >/dev/null 2>&1 || :
    if HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" new-session -d -s "$_approx_session" >/dev/null 2>"$RUNTIME/approx-create.err" && \
       HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" NO_COLOR=1 SCREEN2TMUX_COLOR=never \
       "$SCREEN_BIN" -S "$_approx_session" -X hardstatus off >"$RUNTIME/approx.out" 2>"$RUNTIME/approx.err" && \
       grep -F 'screen2tmux: APPROX:' "$RUNTIME/approx.err" >/dev/null 2>&1 && \
       ! grep -F 'screen2tmux: UNSUPPORTED:' "$RUNTIME/approx.err" >/dev/null 2>&1 && \
       _approx_status=$(HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" show-options -t "$_approx_session" -v status 2>"$RUNTIME/approx-show.err") && \
       [ "$_approx_status" = off ]; then
        PASS=$((PASS + 1))
        _s2t_test_print_case "[PASS] $LABEL APPROX" 'compiled APPROX warning followed by real tmux execution' \
            "$(_s2t_test_format_argv screen -S "$_approx_session" -X hardstatus off)" \
            "$(_s2t_test_format_argv tmux set-option -t "$_approx_session" status off)"
        printf 'APPROX_EXEC\tPASS\t%s\n' "$LABEL" >> "$LOG"
    else
        FAIL=$((FAIL + 1))
        printf '%b[FAIL]%b %s compiled executable-APPROX integration check failed\n' "$R" "$Z" "$LABEL"
        printf 'APPROX_EXEC\tFAIL\t%s\n' "$LABEL" >> "$LOG"
        [ ! -s "$RUNTIME/approx.err" ] || sed 's/^/  approx stderr: /' "$RUNTIME/approx.err"
        [ ! -s "$RUNTIME/approx-show.err" ] || sed 's/^/  show stderr: /' "$RUNTIME/approx-show.err"
    fi

    # Strict mode must preserve the warning but refuse the same APPROX state
    # change inside the compiled screen hardlink.
    TOTAL=$((TOTAL + 1))
    HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" set-option -t "$_approx_session" status on >/dev/null 2>&1 || :
    HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" NO_COLOR=1 SCREEN2TMUX_COLOR=never \
       "$SCREEN_BIN" --strict -S "$_approx_session" -X hardstatus off >"$RUNTIME/strict.out" 2>"$RUNTIME/strict.err"
    _strict_rc=$?
    _strict_status=$(HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" show-options -t "$_approx_session" -v status 2>"$RUNTIME/strict-show.err" || :)
    if [ "$_strict_rc" -eq 3 ] && [ "$_strict_status" = on ] && \
       grep -F 'screen2tmux: APPROX:' "$RUNTIME/strict.err" >/dev/null 2>&1 && \
       grep -F -- '--strict keeps APPROX mappings advisory' "$RUNTIME/strict.err" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        _s2t_test_print_case "[PASS] $LABEL STRICT" 'compiled strict mode blocks APPROX tmux execution' \
            "$(_s2t_test_format_argv screen --strict -S "$_approx_session" -X hardstatus off)" '<APPROX: advisory only>'
        printf 'STRICT_APPROX\tPASS\t%s\n' "$LABEL" >> "$LOG"
    else
        FAIL=$((FAIL + 1))
        printf '%b[FAIL]%b %s compiled strict-APPROX integration check failed (rc=%s status=%s)\n' "$R" "$Z" "$LABEL" "$_strict_rc" "$_strict_status"
        printf 'STRICT_APPROX\tFAIL\t%s\trc=%s\tstatus=%s\n' "$LABEL" "$_strict_rc" "$_strict_status" >> "$LOG"
    fi

    # Also cover APPROX modifiers whose final command is assembled later. The
    # native C argv translator must honor the strict-blocked state too.
    TOTAL=$((TOTAL + 1))
    _strict_named=screen2tmux_strict_named_$$
    HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" kill-session -t "$_strict_named" >/dev/null 2>&1 || :
    HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" NO_COLOR=1 SCREEN2TMUX_COLOR=never \
       "$SCREEN_BIN" --strict -d -m -S "$_strict_named" >"$RUNTIME/strict-named.out" 2>"$RUNTIME/strict-named.err"
    _strict_named_rc=$?
    HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" has-session -t "$_strict_named" >/dev/null 2>&1
    _strict_named_exists=$?
    if [ "$_strict_named_rc" -eq 3 ] && [ "$_strict_named_exists" -ne 0 ] && \
       grep -F -- '--strict keeps APPROX mappings advisory' "$RUNTIME/strict-named.err" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        _s2t_test_print_case "[PASS] $LABEL STRICT-NOTICE" 'compiled strict mode blocks delayed APPROX execution' \
            "$(_s2t_test_format_argv screen --strict -d -m -S "$_strict_named")" '<APPROX: advisory only>'
        printf 'STRICT_NOTICE\tPASS\t%s\n' "$LABEL" >> "$LOG"
    else
        FAIL=$((FAIL + 1))
        printf '%b[FAIL]%b %s compiled strict delayed-APPROX check failed (rc=%s exists_rc=%s)\n' "$R" "$Z" "$LABEL" "$_strict_named_rc" "$_strict_named_exists"
        printf 'STRICT_NOTICE\tFAIL\t%s\trc=%s\texists_rc=%s\n' "$LABEL" "$_strict_named_rc" "$_strict_named_exists" >> "$LOG"
    fi

    # EXTERNAL startup mappings can execute through the compiled hardlink when
    # the required helper exists. Use a private telnet stub and a fresh tmux
    # server so the server inherits the helper directory in PATH.
    TOTAL=$((TOTAL + 1))
    HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" kill-server >/dev/null 2>&1 || :
    _external_bin=$RUNTIME/external-bin
    _external_args=$RUNTIME/telnet.args
    mkdir -p "$_external_bin"
    cat > "$_external_bin/telnet" <<EOF_EXTERNAL_HELPER
#!/bin/sh
printf '%s\n' "\$@" > '$_external_args'
sleep 1
EOF_EXTERNAL_HELPER
    chmod 755 "$_external_bin/telnet"
    PATH="$_external_bin:$PATH" HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" NO_COLOR=1 SCREEN2TMUX_COLOR=never \
       "$SCREEN_BIN" -d -m //telnet example.com 23 >"$RUNTIME/external.out" 2>"$RUNTIME/external.err"
    _external_rc=$?
    sleep 1
    if [ "$_external_rc" -eq 0 ] && [ -f "$_external_args" ] && \
       [ "$(sed -n '1p' "$_external_args")" = example.com ] && \
       [ "$(sed -n '2p' "$_external_args")" = 23 ] && \
       grep -F 'screen2tmux: EXTERNAL:' "$RUNTIME/external.err" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        _s2t_test_print_case "[PASS] $LABEL EXTERNAL" 'compiled EXTERNAL mapping launches installed telnet helper' \
            "$(_s2t_test_format_argv screen -d -m //telnet example.com 23)" \
            "$(_s2t_test_format_argv tmux new-session -d telnet example.com 23)"
        printf 'EXTERNAL_EXEC\tPASS\t%s\n' "$LABEL" >> "$LOG"
    else
        FAIL=$((FAIL + 1))
        printf '%b[FAIL]%b %s compiled executable-EXTERNAL integration check failed (rc=%s)\n' "$R" "$Z" "$LABEL" "$_external_rc"
        printf 'EXTERNAL_EXEC\tFAIL\t%s\trc=%s\n' "$LABEL" "$_external_rc" >> "$LOG"
        [ ! -s "$RUNTIME/external.err" ] || sed 's/^/  external stderr: /' "$RUNTIME/external.err"
        [ ! -f "$_external_args" ] || sed 's/^/  helper argv: /' "$_external_args"
    fi

    # Strict mode must keep the same helper-backed EXTERNAL mapping advisory
    # and must not create a tmux server or execute the helper.
    TOTAL=$((TOTAL + 1))
    HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" kill-server >/dev/null 2>&1 || :
    rm -f "$_external_args"
    PATH="$_external_bin:$PATH" HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" NO_COLOR=1 SCREEN2TMUX_COLOR=never \
       "$SCREEN_BIN" --strict -d -m //telnet example.com 23 >"$RUNTIME/external-strict.out" 2>"$RUNTIME/external-strict.err"
    _external_strict_rc=$?
    if [ "$_external_strict_rc" -eq 5 ] && [ ! -e "$_external_args" ] && \
       grep -F -- '--strict keeps EXTERNAL mappings advisory' "$RUNTIME/external-strict.err" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        _s2t_test_print_case "[PASS] $LABEL STRICT-EXTERNAL" 'compiled strict mode blocks helper-backed EXTERNAL execution' \
            "$(_s2t_test_format_argv screen --strict -d -m //telnet example.com 23)" '<EXTERNAL: advisory only>'
        printf 'STRICT_EXTERNAL\tPASS\t%s\n' "$LABEL" >> "$LOG"
    else
        FAIL=$((FAIL + 1))
        printf '%b[FAIL]%b %s compiled strict-EXTERNAL integration check failed (rc=%s helper_ran=%s)\n' \
            "$R" "$Z" "$LABEL" "$_external_strict_rc" "$([ -e "$_external_args" ] && printf yes || printf no)"
        printf 'STRICT_EXTERNAL\tFAIL\t%s\trc=%s\n' "$LABEL" "$_external_strict_rc" >> "$LOG"
    fi

    HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" kill-server >/dev/null 2>&1 || :
done

printf 'SUMMARY: pass=%s fail=%s total=%s\n' "$PASS" "$FAIL" "$TOTAL" >> "$LOG"
printf '\n%bBuilt screen summary:%b %s %bPASS%b, %s %bFAIL%b, %s integration checks\n' "$C" "$Z" "$PASS" "$G" "$Z" "$FAIL" "$R" "$Z" "$TOTAL"
printf '%bBuilt screen log:%b %s\n' "$C" "$Z" "$LOG"
[ "$FAIL" -eq 0 ]
