#!/bin/sh
# Internal worker for test-interface-equivalence.sh.
set -u

MODE=$1
INTERFACE=$2
OUTDIR=$3
CASES=$4
META=${5:-}

mkdir -p "$OUTDIR" || exit 2
SEQ=0
ACTIVE=0
JOBS=${SCREEN2TMUX_EQUIV_JOBS:-8}
case "$JOBS" in ''|*[!0-9]*) JOBS=8 ;; esac
[ "$JOBS" -gt 0 ] 2>/dev/null || JOBS=8

case "$MODE" in
    source-full|source-last)
        # shellcheck disable=SC1090
        . "$INTERFACE" || exit $?
        ;;
    standalone-last) : ;;
    *) printf 'unknown worker mode: %s\n' "$MODE" >&2; exit 2 ;;
esac

invoke()
{
    _iw_out=$1
    shift
    case "$MODE" in
        source-full|source-last) NO_COLOR=1 SCREEN2TMUX_COLOR=never screen "$@" >"$_iw_out" 2>&1 ;;
        standalone-last) NO_COLOR=1 SCREEN2TMUX_COLOR=never "$INTERFACE" "$@" >"$_iw_out" 2>&1 ;;
    esac
}

emit()
{
    _iw_id=$1; _iw_desc=$2; _iw_place=$3
    shift 3
    SEQ=$((SEQ + 1))
    _iw_base=$(printf '%04d' "$SEQ")
    if [ "$MODE" = standalone-last ]; then
        (
            invoke "$OUTDIR/$_iw_base.out" "$@"
            printf '%s\n' "$?" > "$OUTDIR/$_iw_base.rc"
            exit 0
        ) &
        ACTIVE=$((ACTIVE + 1))
        if [ "$ACTIVE" -ge "$JOBS" ]; then
            wait
            ACTIVE=0
        fi
    else
        invoke "$OUTDIR/$_iw_base.out" "$@"
        printf '%s\n' "$?" > "$OUTDIR/$_iw_base.rc"
    fi
    if [ -n "$META" ]; then
        printf '%s\t%s\t%s\t%s\n' "$_iw_base" "$_iw_id" "$_iw_place" "$_iw_desc" >> "$META"
    fi
}

case_()
{
    _iw_id=$1; _iw_expected=$2; _iw_desc=$3
    shift 3
    case "$MODE" in
        source-full)
            emit "$_iw_id" "$_iw_desc" first --dry-run "$@"
            if [ "$#" -gt 0 ]; then
                _iw_first=$1; shift
                emit "$_iw_id" "$_iw_desc" middle "$_iw_first" --dry-run "$@"
                set -- "$_iw_first" "$@"
            fi
            emit "$_iw_id" "$_iw_desc" last "$@" --dry-run
            ;;
        source-last|standalone-last)
            emit "$_iw_id" "$_iw_desc" last "$@" --dry-run
            ;;
    esac
}

[ -z "$META" ] || : > "$META"
# shellcheck disable=SC1090
. "$CASES"
if [ "$MODE" = standalone-last ]; then wait; fi
printf '%s\n' "$SEQ" > "$OUTDIR/count"
