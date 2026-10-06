#!/bin/sh
# screen-to-tmux-translator 0.3.3
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
#
# By default, creation with -S NAME is classified APPROX because GNU Screen may
# have multiple sessions with the same user label while tmux session names are
# unique. Set SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES=1 to opt into direct
# tmux -s NAME creation when your deployment enforces unique Screen labels.

SCREEN2TMUX_VERSION=0.3.3

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
    _s2t_run tmux "$@"
}

_s2t_color_enabled()
{
    [ -z "${NO_COLOR:-}" ] || return 1
    case "${SCREEN2TMUX_COLOR:-auto}" in
        always) return 0 ;;
        never) return 1 ;;
        auto|'') [ -t 2 ] && [ "${TERM:-}" != dumb ] ;;
        *) return 1 ;;
    esac
}

_s2t_color_token()
{
    _s2t_ct_color=$1
    _s2t_ct_text=$2
    if _s2t_color_enabled; then
        case "$_s2t_ct_color" in
            green)   _s2t_ct_code='\033[32m' ;;
            red)     _s2t_ct_code='\033[31m' ;;
            yellow)  _s2t_ct_code='\033[33m' ;;
            cyan)    _s2t_ct_code='\033[36m' ;;
            magenta) _s2t_ct_code='\033[35m' ;;
            *)       _s2t_ct_code= ;;
        esac
        printf '%b%s%b' "$_s2t_ct_code" "$_s2t_ct_text" '\033[0m'
    else
        printf '%s' "$_s2t_ct_text"
    fi
}

_s2t_class_color()
{
    case "$1" in
        EXACT)       printf green ;;
        APPROX)      printf yellow ;;
        UNSUPPORTED) printf red ;;
        MOOT)        printf cyan ;;
        EXTERNAL)    printf magenta ;;
        INVALID)     printf red ;;
        *)           printf cyan ;;
    esac
}

_s2t_invalid()
{
    _s2t_inv_label=$(_s2t_color_token red "invalid/unknown Screen syntax")
    printf 'screen2tmux: %s: %s\n' "$_s2t_inv_label" "$*" >&2
    return 64
}

_s2t_report()
{
    _s2t_class=$1
    _s2t_rc=$2
    _s2t_reason=$3
    _s2t_suggestion=${4-}
    _s2t_class_label=$(_s2t_color_token "$(_s2t_class_color "$_s2t_class")" "$_s2t_class")
    printf 'screen2tmux: %s: %s\n' "$_s2t_class_label" "$_s2t_reason" >&2
    if [ -n "$_s2t_suggestion" ]; then
        _s2t_suggestion_label=$(_s2t_color_token cyan suggestion)
        printf 'screen2tmux: %s: %s\n' "$_s2t_suggestion_label" "$_s2t_suggestion" >&2
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
    _s2t_note_label=$(_s2t_color_token cyan note)
    printf 'screen2tmux: %s: %s\n' "$_s2t_note_label" "$*" >&2
}

_s2t_uncertain_arg()
{
    _s2t_arg_desc=$1
    _s2t_reason=$2
    _s2t_suggestion=${3-}
    _s2t_warning_label=$(_s2t_color_token yellow WARNING)
    printf 'screen2tmux: %s: uncertain translation of argument %s: %s\n' "$_s2t_warning_label" "$_s2t_arg_desc" "$_s2t_reason" >&2
    if [ -n "$_s2t_suggestion" ]; then
        _s2t_suggestion_label=$(_s2t_color_token cyan suggestion)
        printf 'screen2tmux: %s: %s\n' "$_s2t_suggestion_label" "$_s2t_suggestion" >&2
    fi
    return 3
}

_s2t_tmux_format_literal()
{
    # tmux format strings use ## for a literal #.  A number of tmux commands
    # format-expand names before storing them (new-session -s/-n, new-window
    # -n, rename-session, rename-window).  Escape only that documented format
    # metacharacter; do not invent a more general quoting language.
    _s2t_format_literal=$(printf '%s' "$1" | sed 's/#/##/g')
}

_s2t_selector_is_risky()
{
    # Generic tmux target strings reserve separators, IDs, braces and glob
    # metacharacters that Screen selectors do not interpret the same way.
    case "$1" in
        ''|*[!A-Za-z0-9_-]*) return 0 ;;
        *) return 1 ;;
    esac
}

_s2t_session_selector_is_risky()
{
    # Screen FindSocket() has additional session matching rules: a selector
    # beginning with digits may match a socket PID prefix, PID prefixes are
    # otherwise skipped, and the tty prefix is optional. tmux session targets
    # do not have those rules. Stop instead of guessing these arguments.
    case "$1" in
        ''|[0-9]*|tty*|*[!A-Za-z0-9_-]*) return 0 ;;
        *) return 1 ;;
    esac
}

_s2t_guard_target_arguments()
{
    if [ -n "${_s2t_session:-}" ] && _s2t_session_selector_is_risky "$_s2t_session"; then
        _s2t_uncertain_arg "Screen session selector '$_s2t_session'" "Screen socket matching may interpret leading digits as a PID, may strip PID prefixes, treats a tty prefix specially, and otherwise uses Screen-specific prefix rules; tmux target syntax has different ID, separator, and pattern rules." "Choose the intended tmux session explicitly and rewrite the target; this translator will not guess how that Screen selector should be interpreted."
        return $?
    fi
    if [ -n "${_s2t_window:-}" ] && _s2t_selector_is_risky "$_s2t_window"; then
        _s2t_uncertain_arg "Screen window selector '$_s2t_window'" "tmux window/pane targets have a different selector grammar from Screen window names and numbers." "Choose the intended tmux window explicitly and rewrite the target; this translator will not guess how that Screen selector should be interpreted."
        return $?
    fi
    return 0
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
    _s2t_guard_target_arguments || return $?
    _s2t_make_target
    case "$_s2t_cmd" in
        windows)
            if [ -n "$_s2t_session" ]; then _s2t_windows_suggest="tmux list-windows -t $_s2t_session"; else _s2t_windows_suggest="tmux list-windows"; fi
            _s2t_approx "Screen -Q windows has Screen-specific window-list formatting and markers; tmux list-windows reports a different format." "Closest substitute: $_s2t_windows_suggest. Use -F to build output compatible with the consumer if exact formatting matters." ;;
        number)
            if [ -n "$_s2t_target" ]; then _s2t_tmux display-message -p -t "$_s2t_target" '#{window_index} (#{window_name})'; else _s2t_tmux display-message -p '#{window_index} (#{window_name})'; fi ;;
        title)
            if [ -n "$_s2t_target" ]; then _s2t_tmux display-message -p -t "$_s2t_target" '#W'; else _s2t_tmux display-message -p '#W'; fi ;;
        info)
            _s2t_approx "Screen -Q info emits Screen's own fixed status summary; tmux has no byte-compatible equivalent." "Use tmux display-message -p with explicit format fields such as '#{session_name}:#{window_index}.#{pane_index} #{pane_width}x#{pane_height} #{pane_current_command}'." ;;
        lastmsg)
            _s2t_approx "Screen -Q lastmsg returns Screen's single most recent message; tmux show-messages returns a message history with different formatting and scope." "Use tmux show-messages and select the desired entry in a script if approximate behavior is sufficient." ;;
        echo)
            if [ "$#" -eq 0 ]; then
                _s2t_invalid "echo requires a string"
            elif [ "$#" -eq 1 ]; then
                _s2t_tmux display-message -pl "$1"
            elif [ "$#" -eq 2 ] && [ "$1" = -n ]; then
                _s2t_tmux display-message -pl "$2"
            elif [ "$#" -eq 2 ] && [ "$1" = -p ]; then
                _s2t_unsupported "Screen echo -p expands Screen's own % status-format language; tmux formats use a different #{} language." "Translate the Screen format deliberately instead of passing it to tmux display-message."
            else
                _s2t_uncertain_arg "echo arguments '$*'" "Screen accepts a narrow one/two-argument form and extra argument interpretation is not safely representable as a tmux display-message invocation." "Use Screen's documented 'echo [-n] [-p] string' form and translate the intended formatting explicitly."
            fi ;;
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
    _s2t_guard_target_arguments || return $?
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
            if [ -n "$_s2t_nw_index" ]; then
                _s2t_uncertain_arg "Screen window start index '$_s2t_nw_index'" "Screen treats this number as StartAt and chooses the first free window number at or above it; tmux -t :N addresses the exact index N and fails or changes behavior when N is occupied." "Choose the desired tmux index after inspecting current windows; this translator will not emulate Screen's free-slot search."
                return $?
            fi
            if [ -n "$_s2t_session" ] && [ -n "$_s2t_nw_index" ]; then _s2t_nw_target=$_s2t_session:$_s2t_nw_index
            elif [ -n "$_s2t_session" ]; then _s2t_nw_target=$_s2t_session
            elif [ -n "$_s2t_nw_index" ]; then _s2t_nw_target=:$_s2t_nw_index
            else _s2t_nw_target=; fi
            if [ -n "$_s2t_nw_name" ]; then _s2t_tmux_format_literal "$_s2t_nw_name"; _s2t_nw_name_tmux=$_s2t_format_literal; else _s2t_nw_name_tmux=; fi
            if [ -n "$_s2t_nw_target" ] && [ -n "$_s2t_nw_name_tmux" ]; then _s2t_tmux new-window -t "$_s2t_nw_target" -n "$_s2t_nw_name_tmux" "$@"
            elif [ -n "$_s2t_nw_target" ]; then _s2t_tmux new-window -t "$_s2t_nw_target" "$@"
            elif [ -n "$_s2t_nw_name_tmux" ]; then _s2t_tmux new-window -n "$_s2t_nw_name_tmux" "$@"
            else _s2t_tmux new-window "$@"; fi ;;
        select)
            if [ "$#" -gt 0 ]; then _s2t_sel=$1; else _s2t_sel=${_s2t_window:-}; fi
            [ -n "$_s2t_sel" ] || { _s2t_invalid "select requires a target window in noninteractive translation"; return $?; }
            if [ -n "$_s2t_session" ]; then _s2t_tmux select-window -t "$_s2t_session:$_s2t_sel"; else _s2t_tmux select-window -t ":$_s2t_sel"; fi ;;
        title)
            [ "$#" -gt 0 ] || { _s2t_invalid "title requires a title in shell translation"; return $?; }
            _s2t_tmux_format_literal "$1"
            if [ -n "$_s2t_target" ]; then _s2t_tmux rename-window -t "$_s2t_target" "$_s2t_format_literal"; else _s2t_tmux rename-window "$_s2t_format_literal"; fi ;;
        number)
            [ "$#" -gt 0 ] || { if [ -n "$_s2t_target" ]; then _s2t_tmux display-message -p -t "$_s2t_target" '#I'; else _s2t_tmux display-message -p '#I'; fi; return $?; }
            _s2t_dest=$1
            if [ -z "$_s2t_target" ]; then _s2t_cannot "renumbering requires a determinate Screen window target." "Use screen -S session -p window -X number N and inspect the destination before choosing a tmux operation."; return $?; fi
            if [ -n "$_s2t_session" ]; then _s2t_dest_target="$_s2t_session:$_s2t_dest"; else _s2t_dest_target=":$_s2t_dest"; fi
            _s2t_approx "Screen number swaps window numbers when the destination is occupied, whereas tmux move-window fails on an occupied destination unless destructive flags are used." "If $_s2t_dest_target exists, use: tmux swap-window -s $_s2t_target -t $_s2t_dest_target. If it does not exist, use: tmux move-window -s $_s2t_target -t $_s2t_dest_target." ;;
        kill)
            if [ -n "$_s2t_target" ]; then _s2t_tmux kill-window -t "$_s2t_target"; else _s2t_tmux kill-window; fi ;;
        next) if [ -n "$_s2t_session" ]; then _s2t_tmux next-window -t "$_s2t_session"; else _s2t_tmux next-window; fi ;;
        prev) if [ -n "$_s2t_session" ]; then _s2t_tmux previous-window -t "$_s2t_session"; else _s2t_tmux previous-window; fi ;;
        other) if [ -n "$_s2t_session" ]; then _s2t_tmux last-window -t "$_s2t_session"; else _s2t_tmux last-window; fi ;;
        collapse)
            if [ -n "$_s2t_session" ]; then _s2t_collapse_suggest="tmux move-window -r -t $_s2t_session"; else _s2t_collapse_suggest="tmux move-window -r"; fi
            _s2t_approx "Screen collapse always renumbers windows consecutively from 0; tmux move-window -r starts from the session's base-index option." "Closest substitute when base-index is 0: $_s2t_collapse_suggest. Otherwise script explicit indices or temporarily account for base-index." ;;
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
        redisplay)
            _s2t_approx "Screen redisplay acts on a particular attached Display; a Screen session selector does not identify one unique tmux client when several clients are attached." "From the intended tmux client use: tmux refresh-client. Otherwise choose a concrete client from 'tmux list-clients -t SESSION' and use refresh-client -t CLIENT." ;;
        detach)
            _s2t_approx "Screen's internal detach command requires one concrete Display and detaches that Display only; tmux detach-client -s SESSION would detach every client attached to the session." "From the intended tmux client use: tmux detach-client. Otherwise identify one client with tmux list-clients -t SESSION and use tmux detach-client -t CLIENT." ;;
        pow_detach)
            _s2t_approx "Screen's internal pow_detach acts on one concrete Display and also signals that attacher's parent; a session-wide tmux detach would broaden the operation." "From the intended client use tmux detach-client -P, or select one concrete client and use tmux detach-client -P -t CLIENT." ;;
        suspend)
            _s2t_approx "Screen suspend operates on the invoking/selected Display; an external Screen session selector does not uniquely identify a tmux client." "From the intended tmux client use: tmux suspend-client. Otherwise choose a concrete target-client explicitly." ;;
        quit) if [ -n "$_s2t_session" ]; then _s2t_tmux kill-session -t "$_s2t_session"; else _s2t_cannot "Screen 'quit' kills its one Screen session, while tmux may hold many sessions in one server." "Specify screen -S name -X quit so it can map to tmux kill-session -t name; use tmux kill-server only if you truly want every tmux session."; fi ;;
        lockscreen) _s2t_approx "Screen lockscreen locks the current Screen display; translating an external -X invocation to tmux lock-session would broaden the scope to every client on that session." "Closest client-scoped substitute is tmux lock-client when a specific tmux client context is available." ;;
        sessionname)
            [ "$#" -gt 0 ] || { _s2t_invalid "sessionname requires a new name in shell translation"; return $?; }
            _s2t_tmux_format_literal "$1"
            if [ -n "$_s2t_session" ]; then _s2t_tmux rename-session -t "$_s2t_session" "$_s2t_format_literal"; else _s2t_tmux rename-session "$_s2t_format_literal"; fi ;;
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
                _s2t_approx "Screen hardcopy and tmux capture-pane are close but not byte-for-byte equivalent in whitespace/history/rendering details, so automatic execution could change saved output." "Closest substitute: $_s2t_cap > $( _s2t_shell_quote "$_s2t_file" )."
            else
                _s2t_cannot "Screen hardcopy without a filename writes to Screen's hardcopy naming convention; tmux capture-pane normally writes to stdout." "Use an explicit file with tmux capture-pane -p > file after reviewing the formatting differences."
            fi ;;
        scrollback)
            [ "$#" -gt 0 ] || { _s2t_invalid "scrollback requires a line count"; return $?; }
            _s2t_cannot "Changing Screen scrollback on an existing window does not map exactly to tmux history-limit for an already-created pane." "Set tmux history-limit before pane creation (usually in tmux.conf)." ;;
        readbuf)
            [ "$#" -gt 0 ] || { _s2t_invalid "readbuf requires a filename for noninteractive translation"; return $?; }
            _s2t_approx "Screen readbuf loads the current Screen user's copy buffer inside one Screen backend; tmux paste buffers are shared by the entire tmux server." "Use a session-namespaced tmux buffer explicitly, for example: tmux load-buffer -b screen2tmux:${_s2t_session:-SESSION}:copy '$1'." ;;
        writebuf)
            [ "$#" -gt 0 ] || { _s2t_invalid "writebuf requires a filename for noninteractive translation"; return $?; }
            _s2t_approx "Screen writebuf writes the current Screen user's copy buffer; tmux's default buffer namespace is server-wide." "If you maintain a session-namespaced compatibility buffer, save it explicitly, for example: tmux save-buffer -b screen2tmux:${_s2t_session:-SESSION}:copy '$1'." ;;
        removebuf) _s2t_unsupported "Screen removebuf deletes Screen's exchange file (BufferFile); it does not delete the in-memory copy buffer, so tmux delete-buffer would perform a different operation." "If you intended to remove Screen's exchange file, remove that file explicitly. If you intended to clear a tmux paste buffer, use tmux delete-buffer deliberately." ;;
        register)
            [ "$#" -ge 2 ] || { _s2t_invalid "register requires a register name and string"; return $?; }
            _s2t_buf=$1; shift
            _s2t_approx "Screen named registers belong to the Screen backend, while tmux named paste buffers are server-wide and can collide with unrelated sessions." "Use a namespaced tmux buffer, for example: tmux set-buffer -b screen2tmux:${_s2t_session:-SESSION}:reg:$_s2t_buf TEXT." ;;
        paste)
            if [ "$#" -eq 0 ]; then
                _s2t_unsupported "Screen paste with no register argument enters Screen's interactive register prompt; tmux paste-buffer immediately pastes a server-wide buffer, so the previous mapping was not equivalent." "Specify the intended Screen register and translate it to a session-namespaced tmux buffer, or enter tmux copy-mode/paste-buffer explicitly."
            else
                _s2t_approx "Screen paste can concatenate Screen registers/copy buffers with Screen-specific encoding semantics; tmux paste-buffer uses server-wide named buffers and a different model." "Translate the requested registers into session-namespaced tmux buffers and paste the intended buffer explicitly."
            fi ;;
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
                screen) _s2t_approx "Screen key bindings belong to one Screen backend/session; tmux key tables are server-wide, so bind-key could affect unrelated tmux sessions." "Closest substitute after reviewing server-wide scope: tmux bind-key $_s2t_key new-window." ;;
                kill) _s2t_approx "Screen key bindings belong to one Screen backend/session; tmux key tables are server-wide, so bind-key could affect unrelated tmux sessions." "Closest substitute after reviewing server-wide scope: tmux bind-key $_s2t_key kill-window." ;;
                *) _s2t_cannot "Screen bind command '$1' is valid but command-name/argument translation is not automatically safe." "Bind the corresponding tmux command explicitly with tmux bind-key after reviewing server-wide scope." ;;
            esac ;;
        unbindall) _s2t_approx "Screen unbindall affects the current Screen session's command bindings; tmux unbind-key -a alters server-wide key tables." "Use tmux unbind-key -a only if server-wide removal is intended, or place compatibility bindings in a dedicated tmux key table." ;;
        truecolor)
            case "${1-}" in on) _s2t_approx "Screen truecolor toggles Screen's handling, while tmux terminal-features is server/terminal-capability configuration." "If detection is wrong, use tmux set-option -as terminal-features ',TERM:RGB' for the actual terminal type rather than '*'." ;; off) _s2t_cannot "Removing RGB from tmux terminal feature detection globally is not a safe equivalent of Screen truecolor off." "Override terminal-features/terminal-overrides for the specific client terminal if required." ;; *) _s2t_invalid "truecolor expects on/off" ;; esac ;;
        altscreen)
            case "${1-}" in
                on|off) _s2t_approx "Screen altscreen changes one backend-wide use_altscreen switch for the Screen session; tmux alternate-screen is a window/pane option and may differ across existing and future panes." "Closest substitute requires applying tmux set-option -w/-p alternate-screen $1 to the intended windows/panes and establishing the desired default for future panes." ;;
                *) _s2t_invalid "altscreen expects on/off" ;;
            esac ;;
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
        displays)
            if [ -n "$_s2t_session" ]; then
                _s2t_approx "Screen displays lists Displays attached to one Screen session; tmux list-clients can be scoped to that session but uses different output fields and formatting." "Closest substitute: tmux list-clients -t $_s2t_session"
            else
                _s2t_approx "Screen displays lists Displays attached to its one Screen backend; a tmux server may contain clients for many sessions." "Choose a tmux session explicitly, then use tmux list-clients -t SESSION."
            fi ;;
        dinfo) _s2t_approx "Screen dinfo requires a particular Display and reports Screen-specific terminal/display state; a session name alone cannot choose one tmux client." "From the intended client, inspect tmux format variables such as #{client_name}, #{client_tty}, #{client_width}, #{client_height}, and #{client_termname}." ;;
        windows)
            if [ -n "$_s2t_session" ]; then _s2t_windows_suggest="tmux list-windows -t $_s2t_session"; else _s2t_windows_suggest="tmux list-windows"; fi
            _s2t_approx "Screen windows uses Screen-specific formatting/flags; tmux list-windows is functionally similar but not output-compatible." "Closest substitute: $_s2t_windows_suggest." ;;
        help) _s2t_approx "Screen help renders Screen's current command-class bindings; tmux list-keys renders tmux's server-wide key tables with different command names and formatting." "Closest substitute: tmux list-keys, optionally with -T TABLE." ;;
        info) _s2t_approx "Screen info emits a Screen-specific window/display status summary; tmux has no byte-compatible equivalent." "Use tmux display-message -p with explicit format variables for the fields your script needs." ;;
        lastmsg) _s2t_approx "Screen lastmsg reports one Screen message; tmux show-messages reports a differently formatted message history." "Use tmux show-messages and select the desired message in a script." ;;
        version) _s2t_unsupported "Screen's internal version command reports Screen's version/status text; tmux -V reports tmux and is not an equivalent command result." "Use the native Screen command when Screen version output is required, or tmux -V explicitly for tmux's version." ;;
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
    _s2t_quiet=0
    _s2t_Uflag=0
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
            --help) _s2t_unsupported "Screen --help describes Screen's CLI and command model; tmux -h describes a different program and is not output-compatible." "Run the native Screen help when Screen documentation is required, or run tmux -h explicitly for tmux help."; return $? ;;
            --version) _s2t_unsupported "Screen --version reports the GNU Screen version; tmux -V reports a different program and cannot preserve that result." "Run the native Screen binary for Screen's version, or tmux -V explicitly for tmux's version."; return $? ;;
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
                        q) _s2t_quiet=1; _s2t_opt=$_s2t_rest ;;
                        Q) _s2t_mode=Q; _s2t_opt=$_s2t_rest ;;
                        r) _s2t_attach=1; _s2t_attach_strength=$((_s2t_attach_strength + 1)); _s2t_opt=$_s2t_rest ;;
                        R) _s2t_attach=1; if [ "$_s2t_attach_strength" -gt 0 ]; then _s2t_attach_strength=2; fi; _s2t_attach_strength=$((_s2t_attach_strength + 2)); _s2t_opt=$_s2t_rest ;;
                        x) _s2t_attach=1; _s2t_xflag=1; _s2t_opt=$_s2t_rest ;;
                        d) _s2t_detach=1; _s2t_opt=$_s2t_rest ;;
                        D) _s2t_detach=2; _s2t_opt=$_s2t_rest ;;
                        s) [ -z "$_s2t_rest" ] || { _s2t_invalid "-s requires its argument as the next word"; return $?; }; [ "$#" -gt 0 ] || { _s2t_invalid "-s requires a shell"; return $?; }; _s2t_shell=$1; shift; _s2t_opt= ;;
                        S) [ -z "$_s2t_rest" ] || { _s2t_invalid "-S requires its argument as the next word"; return $?; }; [ "$#" -gt 0 ] || { _s2t_invalid "-S requires a session name"; return $?; }; _s2t_session=$1; shift; _s2t_opt= ;;
                        X) _s2t_mode=X; _s2t_opt=$_s2t_rest ;;
                        v) _s2t_unsupported "Screen -v reports the GNU Screen version; tmux -V reports a different program and cannot preserve that result." "Run the native Screen binary for Screen's version, or tmux -V explicitly for tmux's version."; return $? ;;
                        U) _s2t_Uflag=1; _s2t_opt=$_s2t_rest ;;
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
        if [ "$_s2t_quiet" -eq 1 ]; then
            _s2t_approx "Screen -q with -ls/-list suppresses listing output and returns Screen-specific status codes derived from usable and unusable socket counts; tmux list-sessions has different output and exit-status semantics." "For human inspection use tmux list-sessions${_s2t_session:+ with a filter matching '$_s2t_session'}. For scripts, rewrite the test around tmux list-sessions -F/-f and define the desired exit-status contract explicitly."
        elif [ -n "$_s2t_session" ]; then
            _s2t_approx "Screen -ls/-list reports Screen socket names, attached/detached state, dead sockets and socket-directory information; tmux list-sessions uses a different session model and output format." "Closest substitute: tmux list-sessions -f '#{m:*$_s2t_session*,#{session_name}}'."
        else
            _s2t_approx "Screen -ls/-list reports Screen socket names, attached/detached state, dead sockets and socket-directory information; tmux list-sessions uses a different session model and output format." "Closest substitute: tmux list-sessions."
        fi
        return $?
    fi

    if { [ "$_s2t_attach" -eq 1 ] || { [ "$_s2t_detach" -gt 0 ] && [ "$_s2t_mflag" -eq 0 ]; }; } && [ -n "$_s2t_session" ]; then
        _s2t_guard_target_arguments || return $?
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
        if [ "$_s2t_Aflag" -eq 1 ]; then
            _s2t_approx "Screen -A explicitly adapts all Screen window sizes to the current terminal when attaching; tmux uses its own client/window-size policy and has no equivalent adapt-all-windows flag." "Use tmux's normal window-size policy or configure window-size explicitly. No automatic translation is executed for the -A attach semantics."
            return $?
        fi
        if [ "$_s2t_Uflag" -eq 1 ]; then
            _s2t_approx "Screen -U tells the attached Screen display to use UTF-8 and also changes the default encoding for newly created Screen windows; tmux -u only forces the client UTF-8 assumption." "If you only need tmux to assume a UTF-8 client, invoke tmux -u explicitly. The full Screen -U attach semantics are not automatically translated."
            return $?
        fi
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
                _s2t_unsupported "Screen -R/-RR can automatically select among detached Screen sockets and create a new session if no suitable socket exists; tmux has no one-command equivalent with the same selection rules." "Choose a tmux session explicitly, or implement the Screen detached-session selection policy in a wrapper before calling tmux."
                return $?
            fi
            if [ -n "$_s2t_window" ]; then _s2t_r_target="$_s2t_session:$_s2t_window"; else _s2t_r_target=$_s2t_session; fi
            if [ "$_s2t_detach" -eq 2 ]; then _s2t_r_suggest="tmux new-session -A -D -X -s $_s2t_session"
            elif [ "$_s2t_detach" -eq 1 ]; then _s2t_r_suggest="tmux new-session -A -D -s $_s2t_session"
            else _s2t_r_suggest="tmux new-session -A -s $_s2t_session"; fi
            if [ "$_s2t_attach_strength" -ge 4 ]; then _s2t_r_kind='-RR'; else _s2t_r_kind='-R'; fi
            _s2t_approx "Screen $_s2t_r_kind only considers sockets suitable under Screen's attached/detached rules and may create a new session; tmux new-session -A will attach an existing named tmux session even when Screen would reject it as already attached. Screen -RR also has different multiple-match selection behavior." "Closest common-case substitute: $_s2t_r_suggest${_s2t_window:+, then select $_s2t_r_target if it exists}."
            return $?
        fi

        if [ -z "$_s2t_attach_target" ]; then
            _s2t_approx "Screen -r without a selector only succeeds when Screen can resolve an appropriate session under Screen's own detached-session rules; tmux attach-session without -t selects according to tmux's session rules." "If you know the intended session, use tmux attach-session -t NAME."
            return $?
        fi
        if [ "$_s2t_detach" -eq 0 ] && [ "$_s2t_xflag" -eq 0 ]; then
            _s2t_approx "Screen -r resumes a detached Screen session and normally refuses an already attached session; tmux attach-session normally permits an additional client." "Closest substitute: tmux attach-session -t $_s2t_attach_target. Use Screen -x semantics when multiple simultaneous clients are intended, or -d -r when detaching an existing attachment first."
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

    if [ "$_s2t_Uflag" -eq 1 ]; then
        _s2t_approx "Screen -U has two semantics: it declares the Screen display UTF-8 capable and sets UTF-8 as the default encoding for newly created Screen windows. tmux -u does not implement Screen's per-window encoding policy." "If you only need tmux to assume a UTF-8 client, invoke tmux -u explicitly. No automatic translation is executed for Screen -U."
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
                if [ -n "${TMUX:-}" ] && [ "$_s2t_mflag" -eq 0 ] && [ -z "$_s2t_session" ]; then _s2t_serial_create='tmux new-window'; else _s2t_serial_create="tmux new-session${_s2t_session:+ -s $_s2t_session}"; fi
                if [ -n "$_s2t_baud" ]; then
                    _s2t_external "Screen can attach its window directly to $_s2t_dev; tmux panes always run a process on a PTY." "Closest substitute: $_s2t_serial_create picocom -b $_s2t_baud $_s2t_dev"
                else
                    _s2t_external "Screen can attach its window directly to $_s2t_dev; tmux panes always run a process on a PTY." "Closest substitute: $_s2t_serial_create picocom $_s2t_dev"
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
                if [ -n "${TMUX:-}" ] && [ "$_s2t_mflag" -eq 0 ] && [ -z "$_s2t_session" ]; then _s2t_telnet_create='tmux new-window'; else _s2t_telnet_create="tmux new-session${_s2t_session:+ -s $_s2t_session}"; fi
                _s2t_external "Screen's //telnet is a built-in network terminal endpoint; tmux has no built-in Telnet client." "Closest substitute: $_s2t_telnet_create telnet$_s2t_telnet_af $_s2t_host${_s2t_port:+ $_s2t_port}"
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

    # Automatic Screen logging is only approximately reproducible with tmux
    # pipe-pane and hooks, so never silently drop it or execute it as EXACT.
    if [ "$_s2t_log" -eq 1 ]; then
        _s2t_log_path=${_s2t_logfile:-tmux.log}
        _s2t_approx "Screen -L enables Screen's built-in logging policy; tmux has no matching startup logging flag and pipe-pane only covers selected panes unless additional hooks are installed." "Closest initial-pane substitute: create the session, then run tmux pipe-pane -o 'cat >>$_s2t_log_path'; add after-new-window/after-split-window hooks if automatic logging of future panes is required."
        return $?
    fi

    # Screen -m deliberately forces a new Screen session even when already
    # inside Screen. tmux deliberately blocks an attached nested new-session
    # by default when $TMUX is set. Do not hide that safeguard or unset TMUX
    # automatically; require an explicit operator decision.
    if [ -n "${TMUX:-}" ] && [ "$_s2t_mflag" -eq 1 ] && [ "$_s2t_new_detached" -eq 0 ]; then
        _s2t_approx "Screen -m forces a new attached Screen session even from inside Screen, but tmux normally rejects an attached nested new-session while TMUX is set." "If nesting is intentional, explicitly unset TMUX for the new tmux invocation; otherwise omit -m to create a window in the current tmux session."
        return $?
    fi

    # GNU Screen creates a new window in the current Screen session when STY is
    # set, no -S selector is supplied, and -m was not requested.  For a drop-in
    # tmux compatibility function, TMUX is the corresponding current-context
    # signal.  Do this only on the ordinary creation path: list/attach/-X/-Q and
    # Screen-only options have already been handled above.
    if [ -n "${TMUX:-}" ] && [ "$_s2t_mflag" -eq 0 ] && [ -z "$_s2t_session" ]; then
        if [ "$_s2t_new_detached" -eq 1 ]; then
            _s2t_unsupported "Screen's nested-session rule and -d -m request conflict here: -d -m explicitly creates a new detached Screen session rather than a window in the current session." "Use -m only when a new tmux session is intended; otherwise omit -d -m to create a tmux window in the current session."
            return $?
        fi
        if [ -n "$_s2t_title" ]; then
            _s2t_tmux_format_literal "$_s2t_title"
            _s2t_tmux new-window -n "$_s2t_format_literal" "$@"
        else
            _s2t_tmux new-window "$@"
        fi
        return $?
    fi

    # GNU Screen socket names include a process-specific prefix, so multiple
    # Screen backends may share the same user-supplied -S label. tmux session
    # names are unique. Refuse to call this EXACT unless the operator opts into
    # a unique-label deployment policy.
    if [ -n "$_s2t_session" ] && [ "${SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES:-0}" != 1 ]; then
        if [ "$_s2t_new_detached" -eq 1 ]; then _s2t_name_suggest="tmux new-session -d -s $_s2t_session"; else _s2t_name_suggest="tmux new-session -s $_s2t_session"; fi
        _s2t_approx "GNU Screen permits multiple sessions whose socket names share the same -S label (for example different PID.name sockets), while tmux requires each session name to be unique." "If your environment guarantees unique Screen labels, set SCREEN2TMUX_ASSUME_UNIQUE_SESSION_NAMES=1; closest substitute starts with: $_s2t_name_suggest."
        return $?
    fi

    # Normal session creation with no semantic compromises remaining under the
    # selected session-name policy. tmux format-expands -s/-n, so preserve
    # literal Screen # characters with tmux's documented ## escape.
    if [ -n "$_s2t_session" ]; then _s2t_tmux_format_literal "$_s2t_session"; _s2t_session_tmux=$_s2t_format_literal; else _s2t_session_tmux=; fi
    if [ -n "$_s2t_title" ]; then _s2t_tmux_format_literal "$_s2t_title"; _s2t_title_tmux=$_s2t_format_literal; else _s2t_title_tmux=; fi
    if [ -n "$_s2t_session_tmux" ] && [ -n "$_s2t_title_tmux" ]; then
        if [ "$_s2t_new_detached" -eq 1 ]; then _s2t_tmux new-session -d -s "$_s2t_session_tmux" -n "$_s2t_title_tmux" "$@"
        else _s2t_tmux new-session -s "$_s2t_session_tmux" -n "$_s2t_title_tmux" "$@"; fi
    elif [ -n "$_s2t_session_tmux" ]; then
        if [ "$_s2t_new_detached" -eq 1 ]; then _s2t_tmux new-session -d -s "$_s2t_session_tmux" "$@"
        else _s2t_tmux new-session -s "$_s2t_session_tmux" "$@"; fi
    elif [ -n "$_s2t_title_tmux" ]; then
        if [ "$_s2t_new_detached" -eq 1 ]; then _s2t_tmux new-session -d -n "$_s2t_title_tmux" "$@"
        else _s2t_tmux new-session -n "$_s2t_title_tmux" "$@"; fi
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
