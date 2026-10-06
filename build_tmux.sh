#!/bin/sh
# Build original and Screen-compat patched copies of one or more tmux versions.
# SCREEN2TMUX_PATCHED_ONLY=1 is used by build_tmux_patched.sh.
# POSIX sh. Versions may be comma-separated or supplied as separate arguments.
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DRIVER=${SCREEN2TMUX_BUILD_ONE:-$HERE/scripts/build-tmux-one.sh}
VERBOSITY=normal
VERSIONS=
PATCHED_ONLY=${SCREEN2TMUX_PATCHED_ONLY:-0}
case "$PATCHED_ONLY" in 0|1) : ;; *) printf 'ERROR: SCREEN2TMUX_PATCHED_ONLY must be 0 or 1.\n' >&2; exit 64 ;; esac

usage()
{
    cat <<'USAGE'
Usage: sh build_tmux.sh [--verbosity quiet|normal|verbose] [VERSION ...]

Builds BOTH original and Screen-compat patched variants of every requested
version. For patched-only builds, use build_tmux_patched.sh. VERSION may be
comma-separated, for example:

  sh build_tmux.sh 3.7d
  sh build_tmux.sh 3.7d,3.8,latest
  sh build_tmux.sh 3.7d 3.8 latest

With no VERSION, the project-pinned tmux 3.7d baseline is built. "latest"
resolves the current tmux master/main commit. Other values are accepted as exact
tags/branches/commits and also tried as release_VERSION branches.

Verbosity:
  quiet    stage results and errors only
  normal   default; concise configure summary plus width-wrapped compile results
  verbose  full Autotools/configure/make output

Default layout:
  src/tmux-VERSION/             src/tmux-VERSION-patched/
  build/tmux-VERSION/           build/tmux-VERSION-patched/
USAGE
}

append_version()
{
    _raw=$1
    _oldifs=$IFS; IFS=,
    for _v in $_raw; do
        IFS=$_oldifs
        [ -n "$_v" ] || continue
        case "$_v" in *[!A-Za-z0-9._+/@:-]*) printf 'ERROR: unsafe tmux version/ref: %s\n' "$_v" >&2; exit 64 ;; esac
        if [ -z "$VERSIONS" ]; then VERSIONS=$_v; else VERSIONS="$VERSIONS $_v"; fi
        IFS=,
    done
    IFS=$_oldifs
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --verbosity)
            [ "$#" -ge 2 ] || { printf 'ERROR: --verbosity requires quiet, normal, or verbose.\n' >&2; exit 64; }
            VERBOSITY=$2; shift 2 ;;
        --verbosity=*) VERBOSITY=${1#*=}; shift ;;
        -h|--help) usage; exit 0 ;;
        --*) printf 'ERROR: unknown build option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
        *) append_version "$1"; shift ;;
    esac
done
case "$VERBOSITY" in quiet|normal|verbose) : ;; *) printf 'ERROR: --verbosity must be quiet, normal, or verbose.\n' >&2; exit 64 ;; esac
[ -n "$VERSIONS" ] || VERSIONS=3.7d
[ -x "$DRIVER" ] || [ -r "$DRIVER" ] || { printf 'ERROR: tmux build driver is unavailable: %s\n' "$DRIVER" >&2; exit 2; }

_color=0
if [ -z "${NO_COLOR:-}" ]; then
    case "${SCREEN2TMUX_COLOR:-auto}" in always) _color=1 ;; auto|'') [ -t 1 ] && [ "${TERM:-}" != dumb ] && _color=1 ;; never) : ;; *) printf 'ERROR: SCREEN2TMUX_COLOR must be auto, always, or never.\n' >&2; exit 64 ;; esac
fi
if [ "$_color" -eq 1 ]; then G=$(printf '\033[32m'); R=$(printf '\033[31m'); C=$(printf '\033[36m'); Z=$(printf '\033[0m'); else G=; R=; C=; Z=; fi

sanitize_name() { printf '%s' "$1" | sed 's/[^A-Za-z0-9._+-]/_/g'; }
OVERALL=0
COUNT=0
PASS=0
FAIL=0

for VERSION in $VERSIONS; do
    NAME=$(sanitize_name "$VERSION")
    [ -n "$NAME" ] || NAME=tmux
    _pin=

    if [ "$PATCHED_ONLY" -eq 0 ]; then
        printf '\n===== %stmux %s: original%s =====\n' "$C" "$VERSION" "$Z"
        if SCREEN2TMUX_BUILD_VERBOSITY="$VERBOSITY" sh "$DRIVER" "$VERSION" "$NAME" 0; then
            PASS=$((PASS + 1)); _original_ok=1
        else
            _rc=$?; FAIL=$((FAIL + 1)); OVERALL=1; _original_ok=0
            printf '%s[FAIL]%s tmux %s original build (rc=%s)\n' "$R" "$Z" "$VERSION" "$_rc" >&2
        fi
        COUNT=$((COUNT + 1))

        _info=${SCREEN2TMUX_BUILD_ROOT:-$HERE/build}/tmux-$NAME/BUILD-INFO
        if [ "$_original_ok" -eq 1 ] && [ -r "$_info" ]; then _pin=$(sed -n 's/^SOURCE_COMMIT=//p' "$_info" | head -1); fi
    fi

    printf '\n===== %stmux %s: patched%s =====\n' "$C" "$VERSION" "$Z"
    if TMUX_PIN_COMMIT="$_pin" SCREEN2TMUX_BUILD_VERBOSITY="$VERBOSITY" sh "$DRIVER" "$VERSION" "$NAME" 1; then
        PASS=$((PASS + 1))
    else
        _rc=$?; FAIL=$((FAIL + 1)); OVERALL=1
        printf '%s[FAIL]%s tmux %s patched build (rc=%s)\n' "$R" "$Z" "$VERSION" "$_rc" >&2
    fi
    COUNT=$((COUNT + 1))
done

printf '\n%sBuild summary:%s %s %ssucceeded%s, %s %sfailed%s, %s variants requested\n' "$C" "$Z" "$PASS" "$G" "$Z" "$FAIL" "$R" "$Z" "$COUNT"
printf 'Source root: %s\n' "${SCREEN2TMUX_SOURCE_ROOT:-$HERE/src}"
printf 'Build root: %s\n' "${SCREEN2TMUX_BUILD_ROOT:-$HERE/build}"
exit "$OVERALL"
