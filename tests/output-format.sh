# Shared compact console formatting helpers for test scripts. POSIX sh.
# Detailed logs remain unmodified/full; these helpers only format stdout.

_s2t_test_map_left_width=${SCREEN2TMUX_MAP_LEFT_WIDTH:-26}
case "$_s2t_test_map_left_width" in ''|*[!0-9]*) _s2t_test_map_left_width=26 ;; esac
[ "$_s2t_test_map_left_width" -ge 20 ] 2>/dev/null || _s2t_test_map_left_width=26

_s2t_test_map_desc_width=${SCREEN2TMUX_MAP_DESC_WIDTH:-52}
case "$_s2t_test_map_desc_width" in ''|*[!0-9]*) _s2t_test_map_desc_width=52 ;; esac
[ "$_s2t_test_map_desc_width" -ge 20 ] 2>/dev/null || _s2t_test_map_desc_width=52

_s2t_test_map_screen_width=${SCREEN2TMUX_MAP_SCREEN_WIDTH:-49}
case "$_s2t_test_map_screen_width" in ''|*[!0-9]*) _s2t_test_map_screen_width=49 ;; esac
[ "$_s2t_test_map_screen_width" -ge 6 ] 2>/dev/null || _s2t_test_map_screen_width=49

_s2t_test_quiet=${SCREEN2TMUX_TEST_QUIET:-0}

_s2t_test_class_color_code()
{
    case "$1" in
        exact) printf '\033[32m' ;;
        approx|approx-run) printf '\033[33m' ;;
        unsupported|invalid) printf '\033[31m' ;;
        moot) printf '\033[36m' ;;
        external|external-run) printf '\033[35m' ;;
        *) printf '' ;;
    esac
}

_s2t_test_color_enabled()
{
    [ -z "${NO_COLOR:-}" ] || return 1
    case "${SCREEN2TMUX_COLOR:-auto}" in
        always) return 0 ;;
        never) return 1 ;;
        auto|'') [ -t 1 ] && [ "${TERM:-}" != dumb ] ;;
        *) return 1 ;;
    esac
}

_s2t_test_color_class_token()
{
    _tf_cc_class=$1
    _tf_cc_text=$2
    if _s2t_test_color_enabled; then
        _tf_cc_code=$(_s2t_test_class_color_code "$_tf_cc_class")
        if [ -n "$_tf_cc_code" ]; then
            printf '%b%s%b' "$_tf_cc_code" "$_tf_cc_text" '\033[0m'
            return
        fi
    fi
    printf '%s' "$_tf_cc_text"
}

# Human-readable shell command rendering. Keep ordinary argv bare and quote only
# arguments that actually need shell protection (spaces, #, backslashes, control
# bytes, etc.). Control bytes keep the translator's one-line escaped form.
_s2t_test_full_quote()
{
    if command -v _s2t_display_quote >/dev/null 2>&1; then
        _s2t_display_quote "$1"
        return
    fi
    printf "'"
    printf '%s' "$1" | od -An -v -tu1 | awk '''
        BEGIN { ORS="" }
        {
            for (i = 1; i <= NF; i++) {
                n = $i + 0
                if (n == 39) printf "%c%c%c%c", 39, 92, 39, 39
                else if (n == 13) printf "\\r"
                else if (n == 10) printf "\\n"
                else if (n == 9) printf "\\t"
                else if (n >= 32 && n <= 126) printf "%c", n
                else printf "\\x%02x", n
            }
        }'''
    printf "'"
}

_s2t_test_format_arg()
{
    _tf_arg=$1
    case "$_tf_arg" in
        '') printf "''" ;;
        *[!A-Za-z0-9_@%+=:,./-]*) _s2t_test_full_quote "$_tf_arg" ;;
        *) printf '%s' "$_tf_arg" ;;
    esac
}

_s2t_test_format_argv()
{
    _tf_sep=
    for _tf_arg do
        printf '%s' "$_tf_sep"
        _s2t_test_format_arg "$_tf_arg"
        _tf_sep=' '
    done
}

# Normalize the translator's shell-safe dry-run representation for matrix
# display. Ordinary words are already bare; protected words remain quoted.
# The input is produced by this project, so evaluating it only to reconstruct
# argv is safe here.
_s2t_test_pretty_tmux_output()
{
    _tf_output=$1
    case "$_tf_output" in
        *'
'*) return 1 ;;
        tmux|tmux\ *|"'tmux'"*)
            eval "set -- $_tf_output" || return 1
            [ "${1:-}" = tmux ] || return 1
            _s2t_test_format_argv "$@"
            return 0
            ;;
    esac
    return 1
}

_s2t_test_rhs_for_class()
{
    _tf_class=$1
    _tf_output=$2
    case "$_tf_class" in
        exact)
            if _tf_pretty=$(_s2t_test_pretty_tmux_output "$_tf_output"); then
                printf '%s' "$_tf_pretty"
            else
                case "$_tf_output" in
                    *'
'*) printf '%s' '<translator output; no single tmux command>' ;;
                    *) printf '%s' '<translator output; no tmux command>' ;;
                esac
            fi
            ;;
        approx-run)
            _tf_last=$(printf '%s\n' "$_tf_output" | tail -n 1)
            if _tf_pretty=$(_s2t_test_pretty_tmux_output "$_tf_last"); then
                printf '%s' "$_tf_pretty"
            else
                printf '%s' '<APPROX: executable substitute; command output unavailable>'
            fi
            ;;
        approx) printf '%s' '<APPROX: advisory only>' ;;
        unsupported) printf '%s' '<UNSUPPORTED>' ;;
        moot) printf '%s' '<MOOT: no tmux action>' ;;
        external-run)
            _tf_last=$(printf '%s\n' "$_tf_output" | tail -n 1)
            if _tf_pretty=$(_s2t_test_pretty_tmux_output "$_tf_last"); then
                printf '%s' "$_tf_pretty"
            else
                printf '%s' '<EXTERNAL program required>'
            fi
            ;;
        external) printf '%s' '<EXTERNAL program required>' ;;
        invalid) printf '%s' '<INVALID Screen syntax>' ;;
        *) printf '%s' '<no automatic tmux command>' ;;
    esac
}

_s2t_test_print_case()
{
    _tf_prefix=$1
    _tf_desc=$2
    _tf_screen=$3
    _tf_tmux=$4
    _tf_class=${5-}

    if [ -n "$_tf_class" ]; then
        _tf_prefix_head=${_tf_prefix% *}
        _tf_prefix_class=${_tf_prefix##* }
        _tf_prefix_len=${#_tf_prefix}
        _tf_prefix_pad=$((_s2t_test_map_left_width - _tf_prefix_len))
        [ "$_tf_prefix_pad" -gt 0 ] || _tf_prefix_pad=1
        printf '%s ' "$_tf_prefix_head"
        _s2t_test_color_class_token "$_tf_class" "$_tf_prefix_class"
        printf '%*s' "$_tf_prefix_pad" ''
        if [ "$_s2t_test_quiet" = 1 ]; then
            printf ' %s\n' "$_tf_desc"
        else
            printf ' | %-*s | %-*s -> ' \
                "$_s2t_test_map_desc_width" "$_tf_desc" \
                "$_s2t_test_map_screen_width" "$_tf_screen"
            _s2t_test_color_class_token "$_tf_class" "$_tf_tmux"
            printf '\n'
        fi
    elif [ "$_s2t_test_quiet" = 1 ]; then
        printf '%-*s %s\n' "$_s2t_test_map_left_width" "$_tf_prefix" "$_tf_desc"
    else
        printf '%-*s | %-*s | %-*s -> %s\n' \
            "$_s2t_test_map_left_width" "$_tf_prefix" \
            "$_s2t_test_map_desc_width" "$_tf_desc" \
            "$_s2t_test_map_screen_width" "$_tf_screen" "$_tf_tmux"
    fi
}
