# Shared compact console formatting helpers for test scripts. POSIX sh.
# Detailed logs remain unmodified/full; these helpers only format stdout.

_s2t_test_map_left_width=${SCREEN2TMUX_MAP_LEFT_WIDTH:-36}
case "$_s2t_test_map_left_width" in ''|*[!0-9]*) _s2t_test_map_left_width=36 ;; esac
[ "$_s2t_test_map_left_width" -ge 20 ] 2>/dev/null || _s2t_test_map_left_width=36

_s2t_test_quiet=${SCREEN2TMUX_TEST_QUIET:-0}

_s2t_test_format_argv()
{
    _tf_sep=
    for _tf_arg do
        printf '%s' "$_tf_sep"
        if command -v _s2t_display_quote >/dev/null 2>&1; then
            _s2t_display_quote "$_tf_arg"
        else
            # Fallback for scripts that do not source the translator first.
            printf "'%s'" "$(printf '%s' "$_tf_arg" | sed "s/'/'\\\\''/g")"
        fi
        _tf_sep=' '
    done
}

_s2t_test_rhs_for_class()
{
    _tf_class=$1
    _tf_output=$2
    case "$_tf_class" in
        exact)
            case "$_tf_output" in
                "'tmux'"*)
                    case "$_tf_output" in *'
'*) printf '%s' '<translator output; no single tmux command>' ;; *) printf '%s' "$_tf_output" ;; esac
                    ;;
                *) printf '%s' '<translator output; no tmux command>' ;;
            esac
            ;;
        approx) printf '%s' '<APPROX: no automatic tmux execution>' ;;
        unsupported) printf '%s' '<UNSUPPORTED>' ;;
        moot) printf '%s' '<MOOT: no tmux action>' ;;
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
    if [ "$_s2t_test_quiet" = 1 ]; then
        printf '%-*s %s\n' "$_s2t_test_map_left_width" "$_tf_prefix" "$_tf_desc"
    else
        printf '%-*s | %s -> %s | %s\n' "$_s2t_test_map_left_width" "$_tf_prefix" "$_tf_screen" "$_tf_tmux" "$_tf_desc"
    fi
}
