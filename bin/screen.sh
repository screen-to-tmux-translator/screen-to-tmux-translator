#!/bin/sh
# Standalone GNU Screen-compatible command front-end for screen-to-tmux-translator.
# The translation engine lives in screen-to-tmux.sh; this wrapper executes it.

case $0 in
    */*) _s2t_front_dir=${0%/*} ;;
    *)
        _s2t_front_path=$(command -v "$0" 2>/dev/null || printf '%s' "$0")
        case $_s2t_front_path in
            */*) _s2t_front_dir=${_s2t_front_path%/*} ;;
            *) _s2t_front_dir=. ;;
        esac
        ;;
esac

_s2t_front_dir=$(CDPATH= cd -- "$_s2t_front_dir" 2>/dev/null && pwd) || {
    printf '%s\n' "screen.sh: cannot resolve translator directory" >&2
    exit 127
}

SCREEN2TMUX_NO_SCREEN_FUNCTION=1
export SCREEN2TMUX_NO_SCREEN_FUNCTION
. "$_s2t_front_dir/screen-to-tmux.sh" || exit $?

screen2tmux "$@"
