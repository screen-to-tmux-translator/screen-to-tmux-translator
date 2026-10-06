#!/bin/sh
# Optional live tmux behavioral checks for assumptions that cannot be proven by
# argv translation alone. Uses a private -L server and does not touch the user's
# normal tmux server.
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$HERE/.." && pwd)
RUN_TIMESTAMP=${SCREEN2TMUX_RUN_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}
LOG=${BEHAVIOR_LOG:-$PROJECT/logs/test-tmux-behavior-$RUN_TIMESTAMP.log}
mkdir -p "$(dirname -- "$LOG")"
: > "$LOG"

_color_enabled=0
if [ -z "${NO_COLOR:-}" ]; then
    case "${SCREEN2TMUX_COLOR:-auto}" in
        always) _color_enabled=1 ;;
        auto|'') if [ -t 1 ] && [ "${TERM:-}" != dumb ]; then _color_enabled=1; fi ;;
        never) : ;;
    esac
fi
if [ "$_color_enabled" -eq 1 ]; then
    G='\033[32m'; R='\033[31m'; Y='\033[33m'; C='\033[36m'; Z='\033[0m'
else G=; R=; Y=; C=; Z=; fi

if ! command -v tmux >/dev/null 2>&1; then
    printf '%b[SKIP]%b live tmux behavior tests: tmux executable not installed\n' "$Y" "$Z"
    printf 'SKIP: tmux executable not installed\n' >> "$LOG"
    exit 0
fi

SOCK="screen2tmux-behavior-$$"
P=0
F=0

tmux_test()
{
    command tmux -L "$SOCK" -f /dev/null "$@"
}

cleanup()
{
    command tmux -L "$SOCK" kill-server >/dev/null 2>&1 || :
}
trap cleanup EXIT HUP INT TERM

pass()
{
    P=$((P + 1))
    printf '%b[PASS]%b %s\n' "$G" "$Z" "$1"
    printf 'PASS: %s\n' "$1" >> "$LOG"
}

fail()
{
    F=$((F + 1))
    printf '%b[FAIL]%b %s\n' "$R" "$Z" "$1"
    printf 'FAIL: %s\n' "$1" >> "$LOG"
}

printf 'tmux behavior test run\nTMUX_VERSION: %s\nSOCKET_NAME: %s\n' "$(tmux -V 2>/dev/null || printf unknown)" "$SOCK" >> "$LOG"

# GNU Screen may have PID.work and another PID.work. tmux cannot have two
# sessions both literally named work.
if tmux_test new-session -d -s dup >/dev/null 2>&1 && ! tmux_test new-session -d -s dup >/dev/null 2>&1; then
    pass "tmux rejects duplicate literal session names"
else
    fail "tmux duplicate-session-name behavior differs from expected"
fi

# Screen number N swaps when N is occupied. tmux move-window does not; the
# closest state-aware primitive is swap-window for the occupied case.
if tmux_test new-session -d -s swapcase -n zero >/dev/null 2>&1 && \
   tmux_test new-window -d -t swapcase:2 -n two >/dev/null 2>&1 && \
   tmux_test new-window -d -t swapcase:5 -n five >/dev/null 2>&1; then
    if tmux_test move-window -s swapcase:2 -t swapcase:5 >/dev/null 2>&1; then
        fail "move-window unexpectedly replaced an occupied destination"
    else
        pass "move-window rejects an occupied destination"
    fi
    if tmux_test swap-window -s swapcase:2 -t swapcase:5 >/dev/null 2>&1; then
        n2=$(tmux_test display-message -p -t swapcase:2 '#W' 2>/dev/null || printf '?')
        n5=$(tmux_test display-message -p -t swapcase:5 '#W' 2>/dev/null || printf '?')
        if [ "$n2" = five ] && [ "$n5" = two ]; then
            pass "swap-window reproduces Screen number's occupied-slot swap primitive"
        else
            fail "swap-window completed but expected names did not exchange (2=$n2 5=$n5)"
        fi
    else
        fail "swap-window failed in occupied-destination fixture"
    fi
else
    fail "could not construct occupied-window fixture"
fi

# Screen collapse always starts at zero. tmux session_renumber_windows starts
# from base-index, so move-window -r is not invariantly equivalent.
if tmux_test new-session -d -s collapsecase -n first >/dev/null 2>&1 && \
   tmux_test new-window -d -t collapsecase:3 -n second >/dev/null 2>&1 && \
   tmux_test new-window -d -t collapsecase:7 -n third >/dev/null 2>&1 && \
   tmux_test set-option -t collapsecase base-index 1 >/dev/null 2>&1 && \
   tmux_test move-window -r -t collapsecase >/dev/null 2>&1; then
    indices=$(tmux_test list-windows -t collapsecase -F '#I' 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
    if [ "$indices" = "1 2 3" ]; then
        pass "move-window -r honors base-index rather than Screen's fixed zero"
    else
        fail "unexpected renumber result for base-index=1: $indices"
    fi
else
    fail "could not construct base-index renumber fixture"
fi

# tmux buffers are server objects, not session objects.
if tmux_test new-session -d -s bufa >/dev/null 2>&1 && \
   tmux_test new-session -d -s bufb >/dev/null 2>&1 && \
   tmux_test set-buffer -b screen2tmux_probe shared-value >/dev/null 2>&1; then
    b=$(tmux_test show-buffer -b screen2tmux_probe 2>/dev/null || printf '?')
    if [ "$b" = shared-value ]; then
        pass "tmux named buffers are server-wide objects"
    else
        fail "could not observe server-wide tmux buffer"
    fi
else
    fail "could not construct tmux buffer-scope fixture"
fi

# tmux format strings use ## for a literal #. Name arguments such as
# new-session -s are format-expanded, so the translator must escape literal
# Screen # characters before passing them to tmux.
if tmux_test new-session -d -s 'fmt-##{session_name}' >/dev/null 2>&1; then
    if tmux_test has-session -t '=fmt-#{session_name}' >/dev/null 2>&1; then
        pass "tmux ## preserves a literal # in a format-expanded session name"
    else
        fail "tmux format-escaped session name was not preserved literally"
    fi
else
    fail "could not create format-escaped session-name fixture"
fi

# display-message -l must bypass tmux format expansion for Screen's literal
# echo command.
if lit=$(tmux_test display-message -p -l '#{session_name}' 2>/dev/null) && [ "$lit" = '#{session_name}' ]; then
    pass "display-message -l preserves literal Screen echo text"
else
    fail "display-message -l did not preserve literal format text: ${lit-}"
fi

# Screen 'screen N' searches for the first free slot at or above N. tmux
# new-window -t :N addresses N exactly and rejects an occupied slot.
if tmux_test new-session -d -s startatcase >/dev/null 2>&1 && \
   tmux_test new-window -d -t startatcase:5 -n occupied >/dev/null 2>&1; then
    if tmux_test new-window -d -t startatcase:5 -n second >/dev/null 2>&1; then
        fail "tmux unexpectedly treated occupied -t :5 as Screen StartAt semantics"
    else
        pass "tmux exact occupied index differs from Screen StartAt search"
    fi
else
    fail "could not construct StartAt comparison fixture"
fi

# alternate-screen is a window/pane option in tmux, unlike Screen's single
# backend-wide use_altscreen flag.
if tmux_test new-session -d -s altcase -n one >/dev/null 2>&1 && \
   tmux_test new-window -d -t altcase:1 -n two >/dev/null 2>&1 && \
   tmux_test set-option -p -t altcase:0 alternate-screen off >/dev/null 2>&1; then
    a0=$(tmux_test show-options -p -v -t altcase:0 alternate-screen 2>/dev/null || printf '?')
    a1=$(tmux_test show-options -p -v -t altcase:1 alternate-screen 2>/dev/null || printf '?')
    case "$a0:$a1" in
        off:on|0:1) pass "tmux alternate-screen can differ between panes" ;;
        *) fail "unexpected alternate-screen pane values: $a0 / $a1" ;;
    esac
else
    fail "could not construct alternate-screen scope fixture"
fi

printf '\n%bBehavior summary:%b %s %bPASS%b, %s %bFAIL%b\n' "$C" "$Z" "$P" "$G" "$Z" "$F" "$R" "$Z"
printf 'SUMMARY: pass=%s fail=%s\n' "$P" "$F" >> "$LOG"
printf 'Behavior log: %s\n' "$LOG"
[ "$F" -eq 0 ]
