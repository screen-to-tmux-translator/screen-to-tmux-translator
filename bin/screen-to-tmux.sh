#!/bin/sh
# screen-to-tmux-translator 0.2.0
# POSIX-shell compatibility translator for GNU Screen 5.0.x command lines.
#
# Source this file to define:
#   screen2tmux ...     explicit translator entry point
#   screen ...          drop-in function (unless SCREEN2TMUX_NO_SCREEN_FUNCTION=1)
#
# --dry-run may appear anywhere after the function name. It is removed before
# Screen parsing and causes the equivalent tmux command (or unsupported message)
# to be printed instead of executed.
#
# Exit status:
#   0   EXACT: safely translated (executed, or printed in dry-run mode)
#   2   UNSUPPORTED: valid Screen operation with no safe tmux translation
#   3   APPROX: useful tmux substitute exists but semantics differ; not executed
#   4   MOOT: Screen operation is unnecessary under tmux architecture; not executed
#   5   EXTERNAL: closest substitute requires a non-tmux program; not executed
#   64  INVALID: invalid/unknown Screen syntax for this translator
#   other status may be returned by tmux for EXACT mappings outside dry-run mode.

SCREEN2TMUX_VERSION=0.2.0

_s2t_shell_quote()
{
    # Shell-safe single-quoted word used internally to rebuild argv after
    # removing --dry-run.  This preserves embedded control characters.
    _s2t_q=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
    printf "'%s'" "$_s2t_q"
}

_s2t_display_quote()
{
    # Single-line diagnostic representation for dry-run/log output. Control
    # bytes are rendered as \r, \n, \t or \xHH so output cannot be corrupted.
    printf "'"
    printf '%s' "$1" | od -An -v -tu1 | awk '
        BEGIN { ORS="" }
        {
            for (i = 1; i <= NF; i++) {
                n = $i + 0
                if (n == 39)
                    printf "%c%c%c%c", 39, 92, 39, 39
                else if (n == 13)
                    printf "\\r"
                else if (n == 10)
                    printf "\\n"
                else if (n == 9)
                    printf "\\t"
                else if (n >= 32 && n <= 126)
                    printf "%c", n
                else
                    printf "\\x%02x", n
            }
        }'
    printf "'"
}

_s2t_print_command()
{
    _s2t_sep=
    for _s2t_arg do
        printf '%s' "$_s2t_sep"
        _s2t_display_quote "$_s2t_arg"
        _s2t_sep=' '
    done
    printf '\n'
}

_s2t_run()
{
    if [ "${_s2t_dry_run:-0}" -eq 1 ]; then
        _s2t_print_command "$@"
        return 0
    fi
    command "$@"
}

_s2t_tmux()
{
    if [ "${_s2t_utf8:-0}" -eq 1 ]; then
        _s2t_run tmux -u "$@"
    else
        _s2t_run tmux "$@"
    fi
}

_s2t_invalid()
{
    printf '%s\n' "screen2tmux: invalid/unknown Screen syntax: $*" >&2
    return 64
}

_s2t_report()
{
    _s2t_class=$1
    _s2t_rc=$2
    _s2t_reason=$3
    _s2t_suggestion=${4-}
    printf '%s\n' "screen2tmux: $_s2t_class: $_s2t_reason" >&2
    if [ -n "$_s2t_suggestion" ]; then
        printf '%s\n' "screen2tmux: suggestion: $_s2t_suggestion" >&2
    fi
    return "$_s2t_rc"
}

_s2t_unsupported()
{
    _s2t_report UNSUPPORTED 2 "$1" "${2-}"
}

_s2t_approx()
{
    _s2t_report APPROX 3 "$1" "${2-}"
}

_s2t_moot()
{
    _s2t_report MOOT 4 "$1" "${2-}"
}

_s2t_external()
{
    _s2t_report EXTERNAL 5 "$1" "${2-}"
}

_s2t_note()
{
    printf '%s\n' "screen2tmux: note: $*" >&2
}

# Backward-compatible internal name: callers not yet classified more narrowly
# are conservatively UNSUPPORTED.
_s2t_cannot()
{
    _s2t_unsupported "$@"
}

_s2t_need_arg()
{
    [ "$#" -gt 0 ] || return 1
    return 0
}

_s2t_make_target()
{
    if [ -n "${_s2t_session:-}" ] && [ -n "${_s2t_window:-}" ]; then
        _s2t_target=$_s2t_session:$_s2t_window
    elif [ -n "${_s2t_session:-}" ]; then
        _s2t_target=$_s2t_session
    elif [ -n "${_s2t_window:-}" ]; then
        _s2t_target=":$_s2t_window"
    else
        _s2t_target=
    fi
}

_s2t_screen_target()
{
    _s2t_make_target
    if [ -n "$_s2t_target" ]; then
        printf '%s\n' "$_s2t_target"
    fi
}

_s2t_known_internal()
{
    case "$1" in
        acladd|aclchg|acldel|aclgrp|aclumask|activity|addacl|allpartial|altscreen|at|auth|autodetach|autonuke|backtick|bce|bell|bell_msg|bind|bindkey|blanker|blankerprg|break|breaktype|bufferfile|bumpleft|bumpright|c1|caption|chacl|charset|chdir|cjkwidth|clear|collapse|colon|command|compacthist|console|copy|crlf|defautonuke|defbce|defbreaktype|defc1|defcharset|defdynamictitle|defencoding|defescape|defflow|defgr|defhstatus|defkanji|deflog|deflogin|defmode|defmonitor|defmousetrack|defnonblock|defobuflimit|defscrollback|defshell|defsilence|defslowpaste|defutf8|defwrap|defwritelock|detach|digraph|dinfo|displays|dumptermcap|dynamictitle|echo|encoding|escape|eval|exec|fit|flow|focus|focusminsize|gr|group|hardcopy|hardcopy_append|hardcopydir|hardstatus|height|help|history|hstatus|idle|ignorecase|info|kanji|kill|lastmsg|layout|license|lockscreen|log|logfile|login|logtstamp|mapdefault|mapnotnext|maptimeout|markkeys|meta|monitor|mousetrack|msgminwait|msgwait|multiinput|multiuser|next|nonblock|number|obuflimit|only|other|parent|partial|paste|pastefont|pow_break|pow_detach|pow_detach_msg|prev|printcmd|process|quit|readbuf|readreg|redisplay|register|remove|removebuf|rendition|reset|resize|screen|scrollback|select|sessionname|setenv|setsid|shell|shelltitle|silence|silencewait|sleep|slowpaste|sorendition|sort|source|split|startup_message|status|stuff|su|suspend|term|termcap|termcapinfo|terminfo|title|truecolor|umask|unbindall|unsetenv|utf8|vbell|vbell_msg|vbellwait|verbose|version|wall|width|windowlist|windows|wrap|writebuf|writelock|xoff|xon|zmodem|zombie|zombie_timeout)
            return 0 ;;
    esac
    return 1
}

_s2t_query()
{
    _s2t_cmd=${1-}
    [ -n "$_s2t_cmd" ] || { _s2t_invalid "-Q requires a query command"; return $?; }
    shift
    _s2t_make_target
    case "$_s2t_cmd" in
        windows)
            if [ -n "$_s2t_session" ]; then _s2t_tmux list-windows -t "$_s2t_session"; else _s2t_tmux list-windows; fi ;;
        number)
            if [ -n "$_s2t_target" ]; then _s2t_tmux display-message -p -t "$_s2t_target" '#I'; else _s2t_tmux display-message -p '#I'; fi ;;
        title)
            if [ -n "$_s2t_target" ]; then _s2t_tmux display-message -p -t "$_s2t_target" '#W'; else _s2t_tmux display-message -p '#W'; fi ;;
        info)
            if [ -n "$_s2t_target" ]; then
                _s2t_tmux display-message -p -t "$_s2t_target" '#{session_name}:#{window_index}.#{pane_index} #{pane_width}x#{pane_height} #{pane_current_command}'
            else
                _s2t_tmux display-message -p '#{session_name}:#{window_index}.#{pane_index} #{pane_width}x#{pane_height} #{pane_current_command}'
            fi ;;
        lastmsg)
            _s2t_tmux show-messages ;;
        echo)
            _s2t_tmux display-message -p "$*" ;;
        select)
            if [ "$#" -gt 0 ]; then
                _s2t_sel=$1
                if [ -n "$_s2t_session" ]; then _s2t_tmux select-window -t "$_s2t_session:$_s2t_sel"; else _s2t_tmux select-window -t ":$_s2t_sel"; fi
            else
                if [ -n "$_s2t_target" ]; then _s2t_tmux display-message -p -t "$_s2t_target" '#I #W'; else _s2t_tmux display-message -p '#I #W'; fi
            fi ;;
        *)
            if _s2t_known_internal "$_s2t_cmd"; then
                _s2t_cannot "Screen command '$_s2t_cmd' is recognized, but Screen only permits a subset of commands to return useful -Q results." "Use tmux list-*, show-*, or display-message -p with format variables."
            else
                _s2t_invalid "unknown -Q command '$_s2t_cmd'"
            fi ;;
    esac
}

_s2t_xcommand()
{
    _s2t_cmd=${1-}
    [ -n "$_s2t_cmd" ] || { _s2t_invalid "-X requires a Screen command"; return $?; }
    shift
    _s2t_make_target
    case "$_s2t_cmd" in
        screen)
            _s2t_nw_name=
            _s2t_nw_index=
            _s2t_nw_hist=
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    -t) shift; [ "$#" -gt 0 ] || { _s2t_invalid "screen -t requires a title"; return $?; }; _s2t_nw_name=$1; shift ;;
                    -h) shift; [ "$#" -gt 0 ] || { _s2t_invalid "screen -h requires a history size"; return $?; }; _s2t_nw_hist=$1; shift ;;
                    --) shift; break ;;
                    -*) _s2t_cannot "internal Screen 'screen' option '$1' has no safe generic tmux translation in this release." "Create the window with tmux new-window and configure the corresponding tmux option explicitly."; return $? ;;
                    [0-9]*:* ) _s2t_nw_index=${1%%:*}; _s2t_nw_name=${1#*:}; shift; break ;;
                    [0-9]* ) _s2t_nw_index=$1; shift; break ;;
                    *) break ;;
                esac
            done
            if [ -n "$_s2t_nw_hist" ]; then
                _s2t_cannot "Screen can choose scrollback size while creating this window; tmux history-limit is an option whose creation-time semantics are server/session scoped." "Set 'history-limit $_s2t_nw_hist' in tmux.conf before creating panes, then use tmux new-window."
                return $?
            fi
            if [ -n "$_s2t_session" ] && [ -n "$_s2t_nw_index" ]; then _s2t_nw_target=$_s2t_session:$_s2t_nw_index
            elif [ -n "$_s2t_session" ]; then _s2t_nw_target=$_s2t_session
            elif [ -n "$_s2t_nw_index" ]; then _s2t_nw_target=:$_s2t_nw_index
            else _s2t_nw_target=; fi
            if [ -n "$_s2t_nw_target" ] && [ -n "$_s2t_nw_name" ]; then _s2t_tmux new-window -t "$_s2t_nw_target" -n "$_s2t_nw_name" "$@"
            elif [ -n "$_s2t_nw_target" ]; then _s2t_tmux new-window -t "$_s2t_nw_target" "$@"
            elif [ -n "$_s2t_nw_name" ]; then _s2t_tmux new-window -n "$_s2t_nw_name" "$@"
            else _s2t_tmux new-window "$@"; fi ;;
        select)
            if [ "$#" -gt 0 ]; then _s2t_sel=$1; else _s2t_sel=${_s2t_window:-}; fi
            [ -n "$_s2t_sel" ] || { _s2t_invalid "select requires a target window in noninteractive translation"; return $?; }
            if [ -n "$_s2t_session" ]; then _s2t_tmux select-window -t "$_s2t_session:$_s2t_sel"; else _s2t_tmux select-window -t ":$_s2t_sel"; fi ;;
        title)
            [ "$#" -gt 0 ] || { _s2t_invalid "title requires a title in shell translation"; return $?; }
            if [ -n "$_s2t_target" ]; then _s2t_tmux rename-window -t "$_s2t_target" "$1"; else _s2t_tmux rename-window "$1"; fi ;;
        number)
            [ "$#" -gt 0 ] || { if [ -n "$_s2t_target" ]; then _s2t_tmux display-message -p -t "$_s2t_target" '#I'; else _s2t_tmux display-message -p '#I'; fi; return $?; }
            _s2t_dest=$1
            if [ -z "$_s2t_target" ]; then _s2t_cannot "renumbering requires a determinate Screen window target." "Use screen -S session -p window -X number N or tmux move-window -s source -t destination."; return $?; fi
            if [ -n "$_s2t_session" ]; then _s2t_tmux move-window -s "$_s2t_target" -t "$_s2t_session:$_s2t_dest"; else _s2t_tmux move-window -s "$_s2t_target" -t ":$_s2t_dest"; fi ;;
        kill)
            if [ -n "$_s2t_target" ]; then _s2t_tmux kill-window -t "$_s2t_target"; else _s2t_tmux kill-window; fi ;;
        next) if [ -n "$_s2t_session" ]; then _s2t_tmux next-window -t "$_s2t_session"; else _s2t_tmux next-window; fi ;;
        prev) if [ -n "$_s2t_session" ]; then _s2t_tmux previous-window -t "$_s2t_session"; else _s2t_tmux previous-window; fi ;;
        other) if [ -n "$_s2t_session" ]; then _s2t_tmux last-window -t "$_s2t_session"; else _s2t_tmux last-window; fi ;;
        collapse) if [ -n "$_s2t_session" ]; then _s2t_tmux move-window -r -t "$_s2t_session"; else _s2t_tmux move-window -r; fi ;;
        sort) _s2t_cannot "Screen mutates window numbers by sorting actual windows alphabetically; tmux can sort list/chooser views but has no direct mutating sort command." "Script list-windows plus move-window if persistent alphabetical indices are required." ;;
        stuff)
            [ "$#" -gt 0 ] || { _s2t_invalid "stuff requires text"; return $?; }
            if [ -n "$_s2t_target" ]; then _s2t_tmux send-keys -l -t "$_s2t_target" "$*"; else _s2t_tmux send-keys -l "$*"; fi ;;
        xon) if [ -n "$_s2t_target" ]; then _s2t_tmux send-keys -t "$_s2t_target" C-q; else _s2t_tmux send-keys C-q; fi ;;
        xoff) if [ -n "$_s2t_target" ]; then _s2t_tmux send-keys -t "$_s2t_target" C-s; else _s2t_tmux send-keys C-s; fi ;;
        split)
            if [ "${1-}" = "-v" ]; then
                _s2t_approx "Screen split -v creates another display region without creating a new PTY; tmux split-window -h creates a new pane/PTY." "Closest visual substitute: tmux split-window -h${_s2t_target:+ -t $_s2t_target}."
            else
                _s2t_approx "Screen split creates another display region without creating a new PTY; tmux split-window -v creates a new pane/PTY." "Closest visual substitute: tmux split-window -v${_s2t_target:+ -t $_s2t_target}."
            fi ;;
        focus)
            _s2t_focus_base=
            if [ -n "$_s2t_session" ]; then _s2t_focus_base="$_s2t_session:"; fi
            case "${1-next}" in
                next|'') _s2t_focus_suggest="tmux select-pane -t ${_s2t_focus_base}.+" ;;
                prev) _s2t_focus_suggest="tmux select-pane -t ${_s2t_focus_base}.-" ;;
                up) _s2t_focus_suggest="tmux select-pane -t ${_s2t_focus_base}.{up-of}" ;;
                down) _s2t_focus_suggest="tmux select-pane -t ${_s2t_focus_base}.{down-of}" ;;
                left) _s2t_focus_suggest="tmux select-pane -t ${_s2t_focus_base}.{left-of}" ;;
                right) _s2t_focus_suggest="tmux select-pane -t ${_s2t_focus_base}.{right-of}" ;;
                top) _s2t_focus_suggest="tmux select-pane -t ${_s2t_focus_base}.{top}" ;;
                bottom) _s2t_focus_suggest="tmux select-pane -t ${_s2t_focus_base}.{bottom}" ;;
                *) _s2t_invalid "unknown focus direction '$1'"; return $? ;;
            esac
            _s2t_approx "Screen focus moves among display regions; tmux select-pane moves among PTY panes, so the object model is different." "Closest substitute: $_s2t_focus_suggest" ;;
        only) _s2t_approx "Screen 'only' removes the other display regions while preserving their windows; tmux zoom merely hides other panes temporarily." "Closest non-destructive substitute: tmux resize-pane -Z${_s2t_target:+ -t $_s2t_target}." ;;
        remove) _s2t_cannot "Screen removes a display region without killing its window; tmux has no separate region object because a pane is both the PTY and the layout object." "Use resize-pane -Z to zoom, or break-pane before kill-pane if you need to preserve the process." ;;
        fit) _s2t_cannot "Screen fits a window layer to a display region; tmux automatically sizes pane PTYs to their layout cells." "Usually no command is needed; use resize-pane/resize-window if explicit geometry is required." ;;
        resize)
            _s2t_amount=${1-}
            case "$_s2t_amount" in
                '') _s2t_unsupported "Interactive Screen resize without an amount has no safe noninteractive one-command mapping." "Use tmux resize-pane -L/-R/-U/-D N or resize-pane -x/-y." ;;
                *) _s2t_approx "Screen resize changes a display-region boundary according to Screen's region orientation; mapping '+/-' to a fixed tmux direction would be wrong." "Choose the appropriate tmux resize-pane direction explicitly for the pane layout; requested Screen amount was '$_s2t_amount'." ;;
            esac ;;
        redisplay) _s2t_tmux refresh-client ;;
        detach) if [ -n "$_s2t_session" ]; then _s2t_tmux detach-client -s "$_s2t_session"; else _s2t_tmux detach-client; fi ;;
        pow_detach) if [ -n "$_s2t_session" ]; then _s2t_tmux detach-client -P -s "$_s2t_session"; else _s2t_tmux detach-client -P; fi ;;
        suspend) _s2t_tmux suspend-client ;;
        quit) if [ -n "$_s2t_session" ]; then _s2t_tmux kill-session -t "$_s2t_session"; else _s2t_cannot "Screen 'quit' kills its one Screen session, while tmux may hold many sessions in one server." "Specify screen -S name -X quit so it can map to tmux kill-session -t name; use tmux kill-server only if you truly want every tmux session."; fi ;;
        lockscreen) _s2t_approx "Screen lockscreen locks the current Screen display; translating an external -X invocation to tmux lock-session would broaden the scope to every client on that session." "Closest client-scoped substitute is tmux lock-client when a specific tmux client context is available." ;;
        sessionname)
            [ "$#" -gt 0 ] || { _s2t_invalid "sessionname requires a new name in shell translation"; return $?; }
            if [ -n "$_s2t_session" ]; then _s2t_tmux rename-session -t "$_s2t_session" "$1"; else _s2t_tmux rename-session "$1"; fi ;;
        hardcopy)
            _s2t_hist=0
            if [ "${1-}" = "-h" ]; then _s2t_hist=1; shift; fi
            _s2t_file=${1-}
            if [ "$_s2t_hist" -eq 1 ]; then
                if [ -n "$_s2t_target" ]; then _s2t_cap="tmux capture-pane -p -S - -t $( _s2t_shell_quote "$_s2t_target" )"; else _s2t_cap='tmux capture-pane -p -S -'; fi
            else
                if [ -n "$_s2t_target" ]; then _s2t_cap="tmux capture-pane -p -t $( _s2t_shell_quote "$_s2t_target" )"; else _s2t_cap='tmux capture-pane -p'; fi
            fi
            if [ -n "$_s2t_file" ]; then
                if [ "$_s2t_dry_run" -eq 1 ]; then printf '%s > %s\n' "$_s2t_cap" "$( _s2t_shell_quote "$_s2t_file" )"; else sh -c "$_s2t_cap > \"\$1\"" sh "$_s2t_file"; fi
            else
                _s2t_cannot "Screen hardcopy without a filename writes to Screen's hardcopy naming convention; tmux capture-pane normally writes to stdout." "Use screen ... -X hardcopy /path/file, or tmux capture-pane -p > file."
            fi ;;
        scrollback)
            [ "$#" -gt 0 ] || { _s2t_invalid "scrollback requires a line count"; return $?; }
            _s2t_cannot "Changing Screen scrollback on an existing window does not map exactly to tmux history-limit for an already-created pane." "Set tmux history-limit before pane creation (usually in tmux.conf)." ;;
        readbuf)
            [ "$#" -gt 0 ] || { _s2t_invalid "readbuf requires a filename for noninteractive translation"; return $?; }
            _s2t_tmux load-buffer "$1" ;;
        writebuf)
            [ "$#" -gt 0 ] || { _s2t_invalid "writebuf requires a filename for noninteractive translation"; return $?; }
            _s2t_tmux save-buffer "$1" ;;
        removebuf) _s2t_tmux delete-buffer ;;
        register)
            [ "$#" -ge 2 ] || { _s2t_invalid "register requires a register name and string"; return $?; }
            _s2t_buf=$1; shift; _s2t_tmux set-buffer -b "$_s2t_buf" "$*" ;;
        paste) if [ -n "$_s2t_target" ]; then _s2t_tmux paste-buffer -t "$_s2t_target"; else _s2t_tmux paste-buffer; fi ;;
        copy) if [ -n "$_s2t_target" ]; then _s2t_tmux copy-mode -t "$_s2t_target"; else _s2t_tmux copy-mode; fi ;;
        log)
            case "${1-}" in
                on) _s2t_approx "Screen 'log on' uses Screen's built-in logfile policy and any previously configured logfile pattern; tmux pipe-pane is a general output pipe and has no shared Screen logfile state." "Closest substitute: tmux pipe-pane -o${_s2t_target:+ -t $_s2t_target} 'cat >>FILE', choosing FILE explicitly." ;;
                off) _s2t_approx "Screen 'log off' disables Screen's own logger; tmux pipe-pane without a command closes the pane's output pipe, which might have been used for something other than logging." "If the pane pipe was created only for logging, use: tmux pipe-pane${_s2t_target:+ -t $_s2t_target}." ;;
                *) _s2t_invalid "log expects on or off in shell translation" ;;
            esac ;;
        logfile) _s2t_cannot "Screen has a built-in logfile naming/flush subsystem; tmux logging is implemented with pipe-pane to an external process." "Use tmux pipe-pane -o 'cat >>file'; put tmux format variables such as #{session_name}, #{window_index}, and #{pane_index} in the shell command." ;;
        logtstamp) _s2t_cannot "Screen can insert inactivity timestamps into its built-in logs; tmux has no equivalent logging filter." "Pipe the pane through an external timestamping program using tmux pipe-pane." ;;
        monitor)
            _s2t_state=${1-on}
            case "$_s2t_state" in on|off) if [ -n "$_s2t_target" ]; then _s2t_tmux set-option -wt "$_s2t_target" monitor-activity "$_s2t_state"; else _s2t_tmux set-option -w monitor-activity "$_s2t_state"; fi ;; *) _s2t_invalid "monitor expects on/off" ;; esac ;;
        silence)
            _s2t_val=${1-on}
            case "$_s2t_val" in off) _s2t_val=0 ;; on) _s2t_val=30 ;; esac
            case "$_s2t_val" in *[!0-9]*) _s2t_invalid "silence expects on/off/seconds" ;; *) if [ -n "$_s2t_target" ]; then _s2t_tmux set-option -wt "$_s2t_target" monitor-silence "$_s2t_val"; else _s2t_tmux set-option -w monitor-silence "$_s2t_val"; fi ;; esac ;;
        vbell)
            case "${1-}" in on|off) if [ -n "$_s2t_session" ]; then _s2t_tmux set-option -t "$_s2t_session" visual-bell "$1"; else _s2t_tmux set-option -g visual-bell "$1"; fi ;; *) _s2t_invalid "vbell expects on/off" ;; esac ;;
        source)
            [ "$#" -gt 0 ] || { _s2t_invalid "source requires a filename"; return $?; }
            _s2t_unsupported "Screen 'source' reads Screen command syntax, which tmux source-file cannot parse." "Translate the screenrc fragment to tmux.conf syntax first, then use tmux source-file on the translated file." ;;
        setenv)
            [ "$#" -ge 2 ] || { _s2t_invalid "setenv requires NAME VALUE in noninteractive translation"; return $?; }
            _s2t_name=$1; shift; if [ -n "$_s2t_session" ]; then _s2t_tmux set-environment -t "$_s2t_session" "$_s2t_name" "$*"; else _s2t_tmux set-environment "$_s2t_name" "$*"; fi ;;
        unsetenv)
            [ "$#" -ge 1 ] || { _s2t_invalid "unsetenv requires NAME"; return $?; }
            if [ -n "$_s2t_session" ]; then _s2t_tmux set-environment -u -t "$_s2t_session" "$1"; else _s2t_tmux set-environment -u "$1"; fi ;;
        chdir) _s2t_cannot "Screen changes a backend-wide default directory for future windows; tmux normally chooses a directory at new-session/new-window/split-window time." "Use tmux new-window -c DIR or split-window -c DIR." ;;
        escape) _s2t_cannot "Screen 'escape' encodes both command and literal-prefix characters as a two-character pair; tmux exposes prefix and prefix2 as independent key options." "Use tmux set-option prefix KEY and, if desired, set-option prefix2 KEY." ;;
        bind)
            [ "$#" -ge 2 ] || { _s2t_invalid "bind requires key and command"; return $?; }
            _s2t_key=$1; shift
            case "$1" in
                screen) shift; _s2t_tmux bind-key "$_s2t_key" new-window "$@" ;;
                kill) shift; _s2t_tmux bind-key "$_s2t_key" kill-window "$@" ;;
                *) _s2t_cannot "Screen bind command '$1' is valid but command-name/argument translation is not automatically safe." "Bind the corresponding tmux command explicitly with tmux bind-key." ;;
            esac ;;
        unbindall) _s2t_tmux unbind-key -a ;;
        truecolor)
            case "${1-}" in on) _s2t_approx "Screen truecolor toggles Screen's handling, while tmux terminal-features is server/terminal-capability configuration." "If detection is wrong, use tmux set-option -as terminal-features ',TERM:RGB' for the actual terminal type rather than '*'." ;; off) _s2t_cannot "Removing RGB from tmux terminal feature detection globally is not a safe equivalent of Screen truecolor off." "Override terminal-features/terminal-overrides for the specific client terminal if required." ;; *) _s2t_invalid "truecolor expects on/off" ;; esac ;;
        altscreen)
            case "${1-}" in on|off) if [ -n "$_s2t_target" ]; then _s2t_tmux set-option -pt "$_s2t_target" alternate-screen "$1"; else _s2t_tmux set-option -p alternate-screen "$1"; fi ;; *) _s2t_invalid "altscreen expects on/off" ;; esac ;;
        reset) if [ -n "$_s2t_target" ]; then _s2t_tmux send-keys -R -t "$_s2t_target"; else _s2t_tmux send-keys -R; fi ;;
        encoding|kanji|charset|gr|c1)
            _s2t_cannot "Screen provides legacy encoding/ISO-2022 translation ('$(_s2t_shell_quote "$_s2t_cmd")'); tmux intentionally uses a modern UTF-8-oriented terminal model." "Use UTF-8 applications, or an external transcoder such as luit/iconv when legacy encodings are unavoidable." ;;
        hardstatus)
            case "${1-}" in
                on|off) _s2t_approx "Screen hardstatus and tmux status lines overlap in purpose but are not the same terminal facility." "Closest substitute: tmux set-option${_s2t_session:+ -t $_s2t_session} status $1." ;;
                alwayslastline|lastline) _s2t_approx "Screen hardstatus placement maps only approximately to tmux's status line." "Closest substitute: tmux set-option${_s2t_session:+ -t $_s2t_session} status-position bottom." ;;
                alwaysfirstline|firstline) _s2t_approx "Screen hardstatus placement maps only approximately to tmux's status line." "Closest substitute: tmux set-option${_s2t_session:+ -t $_s2t_session} status-position top." ;;
                *) _s2t_cannot "Screen hardstatus has physical-hardstatus and formatting modes that do not map one-to-one." "Use tmux status, status-position, status-left, status-right and status-format options." ;;
            esac ;;
        caption)
            case "${1-}" in
                always) _s2t_approx "Screen captions label display regions; tmux pane-border-status labels pane borders. They are visually similar but attach to different objects." "Closest substitute: tmux set-option -w pane-border-status bottom (optionally targeted to the desired window)." ;;
                splitonly) _s2t_cannot "Screen can enable captions only when a display has multiple regions; tmux has no identical split-only pane-border-status mode." "Use pane-border-status plus a format condition, or a hook/script, if conditional display is important." ;;
                *) _s2t_cannot "Screen caption syntax does not map one-to-one to tmux pane-border formatting." "Use pane-border-status and pane-border-format." ;;
            esac ;;
        multiuser) _s2t_cannot "Screen toggles an internal multiuser mode; tmux cross-user access is controlled by its server socket plus server-access." "Grant/revoke a specific OS user with tmux server-access and ensure socket filesystem permissions allow connection." ;;
        acladd|addacl)
            [ "$#" -ge 1 ] || { _s2t_invalid "$_s2t_cmd requires a user"; return $?; }
            _s2t_approx "Screen ACL access is scoped to one Screen session and can be refined per command/window; tmux server-access grants access at the tmux server level." "Closest substitute: tmux server-access -a $1, after reviewing the broader scope and socket permissions." ;;
        acldel)
            [ "$#" -ge 1 ] || { _s2t_invalid "acldel requires a user"; return $?; }
            _s2t_approx "Screen acldel removes a user from one Screen session; tmux server-access revokes access to the whole tmux server." "Closest substitute: tmux server-access -d $1, if server-wide revocation is intended." ;;
        aclchg|chacl|aclgrp|aclumask|umask|writelock|auth|su)
            _s2t_cannot "Screen's ACL/authentication operation '$_s2t_cmd' has finer or different semantics than tmux server-access/read-only clients." "Use tmux server-access, Unix socket permissions, and read-only clients where appropriate; there is no exact per-command/per-window Screen ACL equivalent." ;;
        break|breaktype|pow_break|flow|console)
            _s2t_external "Screen includes direct serial/device functionality for '$_s2t_cmd'; tmux panes always contain PTYs and tmux has no built-in serial-device control layer." "Run picocom, cu, minicom, tio, or another serial application inside a tmux pane and use that program's serial controls." ;;
        zmodem)
            _s2t_cannot "Screen has built-in ZMODEM interception/pass-through policy; tmux does not." "Run rz/sz or terminal/file-transfer tooling externally and leave tmux as the PTY multiplexer." ;;
        displays) _s2t_tmux list-clients ;;
        dinfo) _s2t_tmux display-message -p '#{client_name} #{client_tty} #{client_width}x#{client_height} #{client_termname}' ;;
        windows) if [ -n "$_s2t_session" ]; then _s2t_tmux list-windows -t "$_s2t_session"; else _s2t_tmux list-windows; fi ;;
        help) _s2t_tmux list-keys ;;
        info) if [ -n "$_s2t_target" ]; then _s2t_tmux display-message -p -t "$_s2t_target" '#{session_name}:#{window_index}.#{pane_index} #{pane_width}x#{pane_height}'; else _s2t_tmux display-message -p '#{session_name}:#{window_index}.#{pane_index} #{pane_width}x#{pane_height}'; fi ;;
        lastmsg) _s2t_tmux show-messages ;;
        version) _s2t_tmux -V ;;
        license) _s2t_cannot "Screen has an interactive license command; tmux does not expose its license text as a runtime command." "Read tmux's COPYING file from the source/package." ;;
        layout)
            case "${1-}" in
                next) _s2t_approx "Screen 'layout next' switches among saved display-region layouts; tmux next-layout cycles pane-layout algorithms/history, not Screen layout objects." "Closest visual substitute: tmux next-layout." ;;
                prev) _s2t_approx "Screen 'layout prev' switches among saved display-region layouts; tmux previous-layout operates on pane layouts." "Closest visual substitute: tmux previous-layout." ;;
                show) _s2t_approx "Screen 'layout show' reports the selected saved Screen layout; tmux exposes the current pane geometry as an encoded layout string." "Closest inspection command: tmux display-message -p '#{window_layout}'." ;;
                select) shift; [ "$#" -gt 0 ] || { _s2t_invalid "layout select requires a layout"; return $?; }; _s2t_approx "Screen selects a saved named/numbered display layout; tmux select-layout selects a pane layout name or encoded geometry." "If '$1' is intentionally a tmux layout name, use: tmux select-layout '$1'." ;;
                *) _s2t_unsupported "Screen has persistent named/numbered layout objects; tmux has current/encoded pane layouts but not the same saved-layout collection." "Use #{window_layout} to capture an encoded tmux layout and select-layout to restore it, or store names in user options/scripts." ;;
            esac ;;
        *)
            if _s2t_known_internal "$_s2t_cmd"; then
                _s2t_cannot "Screen command '$_s2t_cmd' is valid/recognized but has no safe automatic mapping implemented in screen-to-tmux-translator $SCREEN2TMUX_VERSION." "Use 'tmux list-commands' and the project cross-reference to select the closest tmux operation."
            else
                _s2t_invalid "unknown Screen command '$_s2t_cmd'"
            fi ;;
    esac
}

screen2tmux()
{
    _s2t_dry_run=0
    _s2t_rebuilt=
    for _s2t_a do
        if [ "$_s2t_a" = "--dry-run" ]; then
            _s2t_dry_run=1
        else
            _s2t_rebuilt="$_s2t_rebuilt $(_s2t_shell_quote "$_s2t_a")"
        fi
    done
    eval "set -- $_s2t_rebuilt"
    if [ "${1-}" = "screen" ]; then shift; fi

    _s2t_session=
    _s2t_window=
    _s2t_screenrc=
    _s2t_Aflag=0
    _s2t_utf8=0
    _s2t_mode=
    _s2t_list=0
    _s2t_wipe=0
    _s2t_detach=0
    _s2t_mflag=0
    _s2t_attach=0
    _s2t_attach_strength=0
    _s2t_xflag=0
    _s2t_log=0
    _s2t_logfile=
    _s2t_title=
    _s2t_shell=
    _s2t_hist=
    _s2t_term=
    _s2t_escape=
    _s2t_unsupported_opt=
    _s2t_af=

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --) shift; break ;;
            --help) _s2t_tmux -h; return $? ;;
            --version) _s2t_tmux -V; return $? ;;
            -list) _s2t_list=1; shift; if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then _s2t_session=$1; shift; fi; continue ;;
            -ls) _s2t_list=1; shift; if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then _s2t_session=$1; shift; fi; continue ;;
            -wipe) _s2t_list=1; _s2t_wipe=1; shift; if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then _s2t_session=$1; shift; fi; continue ;;
            -Logfile) shift; [ "$#" -gt 0 ] || { _s2t_invalid "-Logfile requires a filename"; return $?; }; _s2t_logfile=$1; shift; continue ;;
            -*)
                _s2t_opt=${1#-}; shift
                while [ -n "$_s2t_opt" ]; do
                    _s2t_ch=$(printf '%.1s' "$_s2t_opt")
                    _s2t_rest=${_s2t_opt#?}
                    case "$_s2t_ch" in
                        4|6) _s2t_af=$_s2t_ch; _s2t_opt=$_s2t_rest ;;
                        a) _s2t_unsupported_opt="Screen -a capability-forcing has no exact tmux CLI equivalent"; _s2t_opt=$_s2t_rest ;;
                        A) _s2t_Aflag=1; _s2t_opt=$_s2t_rest ;;
                        p)
                            if [ -n "$_s2t_rest" ]; then _s2t_window=$_s2t_rest; _s2t_opt=; else [ "$#" -gt 0 ] || { _s2t_invalid "-p requires a window"; return $?; }; _s2t_window=$1; shift; _s2t_opt=; fi ;;
                        P) _s2t_unsupported_opt="Screen -P enables Screen-managed authentication; tmux uses Unix socket permissions/server-access"; _s2t_opt=$_s2t_rest ;;
                        c)
                            if [ -n "$_s2t_rest" ]; then _s2t_screenrc=$_s2t_rest; _s2t_opt=; else [ "$#" -gt 0 ] || { _s2t_invalid "-c requires a file"; return $?; }; _s2t_screenrc=$1; shift; _s2t_opt=; fi ;;
                        e)
                            if [ -n "$_s2t_rest" ]; then _s2t_escape=$_s2t_rest; _s2t_opt=; else [ "$#" -gt 0 ] || { _s2t_invalid "-e requires two command characters"; return $?; }; _s2t_escape=$1; shift; _s2t_opt=; fi ;;
                        f)
                            case "$_s2t_rest" in ''|n|a|0|1|y) _s2t_unsupported_opt="Screen flow-control option -f${_s2t_rest} has no direct tmux equivalent"; _s2t_opt= ;; *) _s2t_invalid "unknown Screen flow option -f$_s2t_rest"; return $? ;; esac ;;
                        h) [ -z "$_s2t_rest" ] || { _s2t_invalid "-h requires its argument as the next word"; return $?; }; [ "$#" -gt 0 ] || { _s2t_invalid "-h requires a history size"; return $?; }; _s2t_hist=$1; shift; _s2t_opt= ;;
                        i) _s2t_unsupported_opt="Screen -i changes XON/XOFF interrupt behavior; tmux has no equivalent multiplexer policy"; _s2t_opt=$_s2t_rest ;;
                        t) [ -z "$_s2t_rest" ] || { _s2t_invalid "-t requires its argument as the next word"; return $?; }; [ "$#" -gt 0 ] || { _s2t_invalid "-t requires a title"; return $?; }; _s2t_title=$1; shift; _s2t_opt= ;;
                        l)
                            case "$_s2t_rest" in
                                s) _s2t_list=1; _s2t_opt= ;;
                                ist) _s2t_list=1; _s2t_opt= ;;
                                n|0|'') _s2t_unsupported_opt="Screen login/utmp mode has no tmux pane equivalent"; _s2t_opt= ;;
                                y|1|a) _s2t_unsupported_opt="Screen login/utmp mode has no tmux pane equivalent"; _s2t_opt= ;;
                                *) _s2t_invalid "unknown Screen -l suboption '$_s2t_rest'"; return $? ;;
                            esac ;;
                        L)
                            if [ "$_s2t_rest" = ogfile ]; then [ "$#" -gt 0 ] || { _s2t_invalid "-Logfile requires a filename"; return $?; }; _s2t_logfile=$1; shift; _s2t_opt=; elif [ -z "$_s2t_rest" ]; then _s2t_log=1; _s2t_opt=; else _s2t_invalid "unknown Screen -L option '-L$_s2t_rest'"; return $?; fi ;;
                        m) _s2t_mflag=1; _s2t_opt=$_s2t_rest ;;
                        O) _s2t_unsupported_opt="Screen -O is a legacy VT100 output-compatibility mode; tmux uses terminfo/terminal-features instead"; _s2t_opt=$_s2t_rest ;;
                        T) [ -z "$_s2t_rest" ] || { _s2t_invalid "-T requires its argument as the next word"; return $?; }; [ "$#" -gt 0 ] || { _s2t_invalid "-T requires TERM"; return $?; }; _s2t_term=$1; shift; _s2t_opt= ;;
                        q) _s2t_opt=$_s2t_rest ;;
                        Q) _s2t_mode=Q; _s2t_opt=$_s2t_rest ;;
                        r) _s2t_attach=1; _s2t_attach_strength=$((_s2t_attach_strength + 1)); _s2t_opt=$_s2t_rest ;;
                        R) _s2t_attach=1; if [ "$_s2t_attach_strength" -gt 0 ]; then _s2t_attach_strength=2; fi; _s2t_attach_strength=$((_s2t_attach_strength + 2)); _s2t_opt=$_s2t_rest ;;
                        x) _s2t_attach=1; _s2t_xflag=1; _s2t_opt=$_s2t_rest ;;
                        d) _s2t_detach=1; _s2t_opt=$_s2t_rest ;;
                        D) _s2t_detach=2; _s2t_opt=$_s2t_rest ;;
                        s) [ -z "$_s2t_rest" ] || { _s2t_invalid "-s requires its argument as the next word"; return $?; }; [ "$#" -gt 0 ] || { _s2t_invalid "-s requires a shell"; return $?; }; _s2t_shell=$1; shift; _s2t_opt= ;;
                        S) [ -z "$_s2t_rest" ] || { _s2t_invalid "-S requires its argument as the next word"; return $?; }; [ "$#" -gt 0 ] || { _s2t_invalid "-S requires a session name"; return $?; }; _s2t_session=$1; shift; _s2t_opt= ;;
                        X) _s2t_mode=X; _s2t_opt=$_s2t_rest ;;
                        v) _s2t_tmux -V; return $? ;;
                        U) _s2t_utf8=1; _s2t_opt=$_s2t_rest ;;
                        w)
                            if [ "$_s2t_rest" = ipe ]; then _s2t_list=1; _s2t_wipe=1; _s2t_opt=; else _s2t_invalid "unknown Screen option '-w$_s2t_rest'"; return $?; fi ;;
                        *) _s2t_invalid "unknown Screen option '-$_s2t_ch'"; return $? ;;
                    esac
                done
                ;;
            *)
                # Screen consumes a lone remaining operand as a session selector for
                # detach/attach modes. For attach modes it also consumes a following
                # non-option session selector.
                if [ -z "$_s2t_session" ] && { [ "$_s2t_attach" -eq 1 ] || { [ "$_s2t_detach" -gt 0 ] && [ "$_s2t_mflag" -eq 0 ] && [ "$#" -eq 1 ]; }; }; then
                    _s2t_session=$1; shift; continue
                fi
                break ;;
        esac
    done

    if [ -n "$_s2t_unsupported_opt" ]; then
        _s2t_unsupported "$_s2t_unsupported_opt." "Configure the corresponding tmux terminal/access behavior explicitly; the base Screen operation was not executed."
        return $?
    fi
    if [ -n "$_s2t_screenrc" ]; then
        _s2t_unsupported "Screen -c reads Screen configuration syntax; tmux -f reads a different command language, so passing the same file to tmux is unsafe." "Translate '$_s2t_screenrc' to tmux.conf syntax first. Do not pass a screenrc directly to tmux -f."
        return $?
    fi
    if [ -n "${SCREENDIR:-}" ]; then
        _s2t_unsupported "SCREENDIR selects a directory containing Screen per-session sockets; tmux instead selects one server socket with -L name or -S path." "Choose an explicit tmux server, for example: tmux -L myserver ... or tmux -S /path/to/socket ..."
        return $?
    fi

    if [ "$_s2t_mode" = X ]; then _s2t_xcommand "$@"; return $?; fi
    if [ "$_s2t_mode" = Q ]; then _s2t_query "$@"; return $?; fi

    if [ "$_s2t_wipe" -eq 1 ]; then
        _s2t_moot "Screen -wipe cleans stale per-session socket records; tmux sessions are in-memory objects owned by one server and do not leave one stale socket per session." "Use tmux list-sessions. Only clean up the tmux server socket itself if that server is actually dead."
        return $?
    fi
    if [ "$_s2t_list" -eq 1 ]; then
        if [ -n "$_s2t_session" ]; then
            _s2t_tmux list-sessions -f "#{m:*$_s2t_session*,#{session_name}}"
        else
            _s2t_tmux list-sessions
        fi
        return $?
    fi

    # Plain -d/-D means detach an existing Screen session.  -d -m is different:
    # it creates a new detached Screen session, so it is handled later.
    if [ "$_s2t_detach" -gt 0 ] && [ "$_s2t_attach" -eq 0 ] && [ "$_s2t_mflag" -eq 0 ]; then
        if [ "$_s2t_detach" -eq 2 ]; then
            if [ -n "$_s2t_session" ]; then _s2t_tmux detach-client -P -s "$_s2t_session"; else _s2t_tmux detach-client -P; fi
        else
            if [ -n "$_s2t_session" ]; then _s2t_tmux detach-client -s "$_s2t_session"; else _s2t_tmux detach-client; fi
        fi
        return $?
    fi

    if [ "$_s2t_attach" -eq 1 ]; then
        _s2t_attach_target=$_s2t_session
        if [ -n "$_s2t_window" ]; then
            if [ -z "$_s2t_session" ]; then
                _s2t_approx "Screen can combine -p with an automatically selected session; tmux needs a determinate session when selecting a window at attach time." "Choose the session explicitly, then use tmux attach-session -t session:$_s2t_window."
                return $?
            fi
            _s2t_attach_target=$_s2t_session:$_s2t_window
        fi

        if [ "$_s2t_attach_strength" -ge 2 ]; then
            if [ -z "$_s2t_session" ]; then
                _s2t_unsupported "Screen -R/-RR can automatically choose or create an unnamed suitable session; tmux new-session -A requires a determinate session name for predictable behavior." "Supply -S name, then use tmux new-session -A -s name."
                return $?
            fi
            if [ -n "$_s2t_window" ]; then
                _s2t_approx "Screen can combine create-or-attach (-R/-RR) with -p window selection; tmux new-session -A cannot faithfully guarantee that selected window when it may have to create the session." "Use tmux new-session -A -s $_s2t_session, then select/attach to $_s2t_session:$_s2t_window when that window exists."
                return $?
            fi
            if [ "$_s2t_detach" -eq 2 ]; then _s2t_tmux new-session -A -D -X -s "$_s2t_session"
            elif [ "$_s2t_detach" -eq 1 ]; then _s2t_tmux new-session -A -D -s "$_s2t_session"
            else _s2t_tmux new-session -A -s "$_s2t_session"; fi
            return $?
        fi

        if [ -z "$_s2t_attach_target" ]; then
            _s2t_approx "Screen -r without a selector only succeeds when Screen can resolve an appropriate session under Screen's own detached-session rules; tmux attach-session without -t selects according to tmux's session rules." "If you know the intended session, use tmux attach-session -t NAME."
            return $?
        fi
        if [ "$_s2t_detach" -eq 2 ]; then _s2t_tmux attach-session -d -x -t "$_s2t_attach_target"
        elif [ "$_s2t_detach" -eq 1 ]; then _s2t_tmux attach-session -d -t "$_s2t_attach_target"
        else _s2t_tmux attach-session -t "$_s2t_attach_target"; fi
        return $?
    fi

    if [ "$_s2t_detach" -eq 2 ] && [ "$_s2t_mflag" -eq 1 ]; then
        _s2t_unsupported "Screen -D -m has process/daemonization semantics that do not correspond to creating one tmux session; tmux -D instead keeps the tmux server in the foreground." "For an ordinary detached session use tmux new-session -d; for a foreground tmux server use tmux -D."
        return $?
    fi

    if [ -n "$_s2t_hist" ]; then
        _s2t_unsupported "Screen -h sets initial-window scrollback during creation; tmux history-limit is a creation-time option whose safe scope cannot be changed for only this invocation on an existing server." "Configure 'set -g history-limit $_s2t_hist' before creating the pane/session."
        return $?
    fi
    if [ -n "$_s2t_term" ]; then
        _s2t_unsupported "Screen -T sets the virtual TERM for windows at creation; tmux default-terminal is a server option and changing it for only this invocation is not equivalent." "Configure 'set -g default-terminal $_s2t_term' in tmux.conf for the intended tmux server."
        return $?
    fi
    if [ -n "$_s2t_shell" ]; then
        _s2t_unsupported "Screen -s changes the default shell for current and future windows in that Screen session; a one-shot tmux new-session command would only choose an initial process." "Configure tmux default-shell, or run the desired shell explicitly in each new-session/new-window command."
        return $?
    fi
    if [ -n "$_s2t_escape" ]; then
        _s2t_unsupported "Screen -e sets Screen's command character plus its literal-escape character before startup; tmux models prefix/prefix2 and send-prefix differently." "Translate the intended key behavior explicitly with tmux prefix/prefix2 and key bindings."
        return $?
    fi

    # Direct character devices and built-in Telnet are Screen endpoint features,
    # not tmux features.  Offer an external-program substitute but never execute
    # it automatically as an EXACT translation.
    if [ "$#" -gt 0 ]; then
        case "$1" in
            /dev/tty*)
                _s2t_dev=$1
                shift
                _s2t_baud=
                if [ "$#" -gt 0 ]; then
                    case "$1" in
                        *[!0-9]*)
                            _s2t_external "Screen accepts native tty/stty option syntax for direct device windows; tmux has no built-in serial endpoint." "Run a serial application inside tmux and translate the tty settings explicitly, for example: tmux new-session 'picocom -b 115200 /dev/ttyUSB0'."
                            return $?
                            ;;
                        *) _s2t_baud=$1; shift ;;
                    esac
                fi
                if [ "$#" -gt 0 ]; then
                    _s2t_external "Screen accepts additional native tty/stty options for direct device windows; tmux has no built-in serial endpoint." "Translate those settings to picocom, tio, minicom, or cu options explicitly."
                    return $?
                fi
                if [ -n "$_s2t_baud" ]; then
                    _s2t_external "Screen can attach its window directly to $_s2t_dev; tmux panes always run a process on a PTY." "Closest substitute: tmux new-session${_s2t_session:+ -s $_s2t_session} picocom -b $_s2t_baud $_s2t_dev"
                else
                    _s2t_external "Screen can attach its window directly to $_s2t_dev; tmux panes always run a process on a PTY." "Closest substitute: tmux new-session${_s2t_session:+ -s $_s2t_session} picocom $_s2t_dev"
                fi
                return $?
                ;;
            //telnet)
                shift
                [ "$#" -gt 0 ] || { _s2t_invalid "//telnet requires a host"; return $?; }
                _s2t_host=$1
                shift
                _s2t_port=${1-}
                if [ "$#" -gt 1 ]; then _s2t_invalid "//telnet accepts host and optional port"; return $?; fi
                _s2t_telnet_af=
                [ "$_s2t_af" = 4 ] && _s2t_telnet_af=' -4'
                [ "$_s2t_af" = 6 ] && _s2t_telnet_af=' -6'
                _s2t_external "Screen's //telnet is a built-in network terminal endpoint; tmux has no built-in Telnet client." "Closest substitute: tmux new-session telnet$_s2t_telnet_af $_s2t_host${_s2t_port:+ $_s2t_port}"
                return $?
                ;;
        esac
    fi

    # A Screen -Logfile setting without -L still affects later Screen logging.
    # tmux has no corresponding persistent pane-log filename setting.
    if [ -n "$_s2t_logfile" ] && [ "$_s2t_log" -eq 0 ]; then
        _s2t_unsupported "Screen -Logfile stores a default logfile name even when logging is not yet enabled; tmux pipe-pane has no equivalent persistent logfile-name setting." "Create the tmux session normally, then use pipe-pane with an explicit destination whenever logging is enabled."
        return $?
    fi

    # -m means 'force a new Screen session even inside Screen'; it does NOT mean
    # detached.  Only -d -m creates a detached new session.
    if [ "$_s2t_detach" -eq 1 ] && [ "$_s2t_mflag" -eq 1 ]; then _s2t_new_detached=1; else _s2t_new_detached=0; fi

    if [ "$_s2t_Aflag" -eq 1 ]; then
        _s2t_note "Screen -A explicitly adapts windows to the attaching display; tmux performs client/window sizing as part of its normal layout model, so no extra tmux flag is emitted."
    fi

    # Automatic Screen logging is only approximately reproducible with tmux
    # pipe-pane and hooks, so never silently drop it or execute it as EXACT.
    if [ "$_s2t_log" -eq 1 ]; then
        _s2t_log_path=${_s2t_logfile:-tmux.log}
        _s2t_approx "Screen -L enables Screen's built-in logging policy; tmux has no matching startup logging flag and pipe-pane only covers selected panes unless additional hooks are installed." "Closest initial-pane substitute: create the session, then run tmux pipe-pane -o 'cat >>$_s2t_log_path'; add after-new-window/after-split-window hooks if automatic logging of future panes is required."
        return $?
    fi

    # Normal session creation with no semantic compromises remaining.
    if [ -n "$_s2t_session" ] && [ -n "$_s2t_title" ]; then
        if [ "$_s2t_new_detached" -eq 1 ]; then _s2t_tmux new-session -d -s "$_s2t_session" -n "$_s2t_title" "$@"
        else _s2t_tmux new-session -s "$_s2t_session" -n "$_s2t_title" "$@"; fi
    elif [ -n "$_s2t_session" ]; then
        if [ "$_s2t_new_detached" -eq 1 ]; then _s2t_tmux new-session -d -s "$_s2t_session" "$@"
        else _s2t_tmux new-session -s "$_s2t_session" "$@"; fi
    elif [ -n "$_s2t_title" ]; then
        if [ "$_s2t_new_detached" -eq 1 ]; then _s2t_tmux new-session -d -n "$_s2t_title" "$@"
        else _s2t_tmux new-session -n "$_s2t_title" "$@"; fi
    else
        if [ "$_s2t_new_detached" -eq 1 ]; then _s2t_tmux new-session -d "$@"
        else _s2t_tmux new-session "$@"; fi
    fi
}

if [ "${SCREEN2TMUX_NO_SCREEN_FUNCTION:-0}" != 1 ]; then
    screen()
    {
        screen2tmux "$@"
    }
fi
