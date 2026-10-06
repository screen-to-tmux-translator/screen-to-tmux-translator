#!/bin/sh
# Independent syntax oracle for the test corpus, derived from GNU Screen 5.0.2
# screen.c option parsing and comm.c command metadata.  It performs no tmux
# translation and is intentionally separate from bin/screen-function-source.sh.

_ORACLE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../docs" && pwd)
SCREEN_COMMAND_MANIFEST=${SCREEN_COMMAND_MANIFEST:-$_ORACLE_DIR/screen-5.0.2-command-manifest.tsv}

_oracle_invalid()
{
    SCREEN_ORACLE_REASON=$*
    return 64
}

_oracle_command_meta()
{
    awk -F '\t' -v c="$1" '$1 == c { print $2 "\t" $3; found=1; exit } END { if (!found) exit 1 }' "$SCREEN_COMMAND_MANIFEST"
}

_oracle_check_arity()
{
    _oca_expr=$1
    _oca_n=$2
    _oca_args=$(printf '%s\n' "$_oca_expr" | sed -n 's/.*\(ARGS_[0-9][0-9]*\).*/\1/p')
    [ -n "$_oca_args" ] || return 0
    _oca_digits=${_oca_args#ARGS_}
    case "$_oca_expr" in
        *ARGS_ORMORE*)
            _oca_min=$(printf '%s' "$_oca_digits" | cut -c1)
            [ "$_oca_n" -ge "$_oca_min" ]
            return $?
            ;;
    esac
    case "$_oca_digits" in
        *"$_oca_n"*) return 0 ;;
        *) return 1 ;;
    esac
}

screen_syntax_oracle()
{
    SCREEN_ORACLE_REASON=
    _oc_mode=
    _oc_cmd=
    _oc_query=0
    _oc_session=
    _oc_window=

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --) shift; break ;;
            --help|--version) shift; [ "$#" -eq 0 ] || _oracle_invalid "arguments after $1"; return $? ;;
            -list|-ls|-wipe)
                shift
                if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then shift; fi
                [ "$#" -eq 0 ] || { _oracle_invalid "extra arguments after list/wipe selector"; return $?; }
                return 0
                ;;
            -Logfile)
                shift; [ "$#" -gt 0 ] || { _oracle_invalid "-Logfile requires a filename"; return $?; }
                shift; continue ;;
            -*)
                _oc_opt=${1#-}; shift
                while [ -n "$_oc_opt" ]; do
                    _oc_ch=$(printf '%.1s' "$_oc_opt")
                    _oc_rest=${_oc_opt#?}
                    case "$_oc_ch" in
                        4|6|a|A|i|m|O|P|q|U) _oc_opt=$_oc_rest ;;
                        v) [ -z "$_oc_rest" ] || { _oracle_invalid "-v may not be clustered with $_oc_rest in oracle corpus"; return $?; }; [ "$#" -eq 0 ] || { _oracle_invalid "arguments after -v"; return $?; }; return 0 ;;
                        p)
                            if [ -n "$_oc_rest" ]; then _oc_window=$_oc_rest; _oc_opt=
                            else [ "$#" -gt 0 ] || { _oracle_invalid "-p requires a window"; return $?; }; _oc_window=$1; shift; _oc_opt=; fi ;;
                        c)
                            if [ -n "$_oc_rest" ]; then _oc_opt=
                            else [ "$#" -gt 0 ] || { _oracle_invalid "-c requires a file"; return $?; }; shift; _oc_opt=; fi ;;
                        e)
                            if [ -n "$_oc_rest" ]; then _oc_opt=
                            else [ "$#" -gt 0 ] || { _oracle_invalid "-e requires two command characters"; return $?; }; shift; _oc_opt=; fi ;;
                        f)
                            case "$_oc_rest" in ''|n|a|0|1|y) _oc_opt= ;; *) _oracle_invalid "invalid -f form"; return $? ;; esac ;;
                        h|t|T|s|S)
                            [ -z "$_oc_rest" ] || { _oracle_invalid "-$_oc_ch requires its argument as next word"; return $?; }
                            [ "$#" -gt 0 ] || { _oracle_invalid "-$_oc_ch requires an argument"; return $?; }
                            [ "$_oc_ch" = S ] && _oc_session=$1
                            shift; _oc_opt= ;;
                        l)
                            case "$_oc_rest" in ''|n|0|y|1|a|s|ist) _oc_opt= ;; *) _oracle_invalid "invalid -l form"; return $? ;; esac ;;
                        L)
                            if [ "$_oc_rest" = ogfile ]; then [ "$#" -gt 0 ] || { _oracle_invalid "-Logfile requires a filename"; return $?; }; shift; _oc_opt=
                            elif [ -z "$_oc_rest" ]; then _oc_opt=
                            else _oracle_invalid "invalid -L form"; return $?; fi ;;
                        Q) _oc_mode=Q; _oc_query=1; _oc_opt=$_oc_rest ;;
                        X) _oc_mode=X; _oc_opt=$_oc_rest ;;
                        r|R|x|d|D) _oc_opt=$_oc_rest ;;
                        w) [ "$_oc_rest" = ipe ] || { _oracle_invalid "unknown -w form"; return $?; }; _oc_opt= ;;
                        *) _oracle_invalid "unknown option -$_oc_ch"; return $? ;;
                    esac
                done
                ;;
            *) break ;;
        esac
    done

    if [ "$_oc_mode" = X ] || [ "$_oc_mode" = Q ]; then
        [ "$#" -gt 0 ] || { _oracle_invalid "-$_oc_mode requires a command"; return $?; }
        _oc_cmd=$1; shift
        _oc_meta=$(_oracle_command_meta "$_oc_cmd") || { _oracle_invalid "unknown Screen command $_oc_cmd"; return $?; }
        _oc_expr=${_oc_meta%%	*}
        _oc_q=${_oc_meta#*	}
        if [ "$_oc_mode" = Q ] && [ "$_oc_q" != yes ]; then
            _oracle_invalid "Screen command $_oc_cmd is not query-capable"
            return $?
        fi
        _oracle_check_arity "$_oc_expr" "$#" || { _oracle_invalid "wrong argument count for $_oc_cmd"; return $?; }
        case "$_oc_cmd" in
            focus)
                case "${1-}" in ''|next|prev|up|down|left|right|top|bottom) ;; *) _oracle_invalid "invalid focus direction"; return $? ;; esac ;;
        esac
        return 0
    fi

    # Remaining operands are a session selector (for attach/detach forms) or
    # the initial program and its arguments. Both are syntactically valid here.
    return 0
}
