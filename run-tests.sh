#!/bin/sh
# Build (optionally), discover, and test every successful tmux compatibility build.
# Full plain text is logged before terminal-only truncation/colorization.
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION=$(cat "$HERE/VERSION" 2>/dev/null || printf unknown)
LOG_DIR=${SCREEN2TMUX_LOG_DIR:-$HERE/logs}
RUN_TIMESTAMP=${SCREEN2TMUX_RUN_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}
TEST_QUIET=0
REQUESTED_WIDTH=
EQUIV_REQUEST=all
EQUIV_CUSTOM=0
VERBOSITY=normal
BUILD_REQUESTED=0
BUILD_VERSIONS=
LIST_EQUIV=0
TAB=$(printf '\t')

usage()
{
    cat <<'USAGE'
Usage: sh run-tests.sh [options]

  --build [VERSION ...]       Build both original and patched tmux variants
                              before testing. With no VERSION, builds 3.7d.
                              Versions may be comma-separated or space-separated.
  --verbosity LEVEL           quiet, normal (default), or verbose. This controls
                              build console detail; quiet also suppresses routine
                              per-case PASS rows from the terminal only.
  --quiet                     Hide per-case "screen -> tmux" mapping columns.
  --truncate-lines N          Limit terminal display lines to N columns. Full logs
                              are never truncated. --trunkate-lines is an alias.
  --equivalence NAME          Restrict interface equivalence to NAME. Repeatable.
  --equivalence-only NAME     Alias for --equivalence NAME.
  --list-equivalence-interfaces
                              Print currently available interfaces and exit.

Examples:
  sh run-tests.sh --build
  sh run-tests.sh --build 3.7d,latest
  sh run-tests.sh --build 3.7d 3.8 latest --verbosity normal

The canonical screen-function-source interface is always the equivalence reference.
Every successful patched build discovered under build/ is added automatically.
USAGE
}

append_build_versions()
{
    _raw=$1
    _oldifs=$IFS; IFS=,
    for _v in $_raw; do
        IFS=$_oldifs
        [ -n "$_v" ] || continue
        if [ -z "$BUILD_VERSIONS" ]; then BUILD_VERSIONS=$_v; else BUILD_VERSIONS="$BUILD_VERSIONS $_v"; fi
        IFS=,
    done
    IFS=$_oldifs
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --build)
            BUILD_REQUESTED=1; shift
            while [ "$#" -gt 0 ]; do
                case "$1" in --*) break ;; *) append_build_versions "$1"; shift ;; esac
            done
            ;;
        --build=*) BUILD_REQUESTED=1; append_build_versions "${1#*=}"; shift ;;
        --verbosity)
            [ "$#" -ge 2 ] || { printf 'ERROR: --verbosity requires quiet, normal, or verbose.\n' >&2; exit 64; }
            VERBOSITY=$2; shift 2 ;;
        --verbosity=*) VERBOSITY=${1#*=}; shift ;;
        --quiet) TEST_QUIET=1; shift ;;
        --equivalence|--equivalence-only)
            [ "$#" -ge 2 ] || { printf 'ERROR: %s requires an interface name.\n' "$1" >&2; exit 64; }
            if [ "$EQUIV_CUSTOM" -eq 0 ]; then EQUIV_REQUEST=$2; EQUIV_CUSTOM=1; else EQUIV_REQUEST="$EQUIV_REQUEST,$2"; fi
            shift 2 ;;
        --equivalence=*|--equivalence-only=*)
            _eq=${1#*=}; [ -n "$_eq" ] || { printf 'ERROR: %s requires an interface name.\n' "${1%%=*}" >&2; exit 64; }
            if [ "$EQUIV_CUSTOM" -eq 0 ]; then EQUIV_REQUEST=$_eq; EQUIV_CUSTOM=1; else EQUIV_REQUEST="$EQUIV_REQUEST,$_eq"; fi
            shift ;;
        --list-equivalence-interfaces) LIST_EQUIV=1; shift ;;
        --truncate-lines|--trunkate-lines)
            [ "$#" -ge 2 ] || { printf 'ERROR: %s requires a positive integer.\n' "$1" >&2; exit 64; }
            REQUESTED_WIDTH=$2; shift 2 ;;
        --truncate-lines=*|--trunkate-lines=*) REQUESTED_WIDTH=${1#*=}; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'ERROR: unknown run-tests.sh argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done
case "$VERBOSITY" in quiet|normal|verbose) : ;; *) printf 'ERROR: --verbosity must be quiet, normal, or verbose.\n' >&2; exit 64 ;; esac
if [ "$BUILD_REQUESTED" -eq 1 ] && [ -z "$BUILD_VERSIONS" ]; then BUILD_VERSIONS=3.7d; fi

# Listing current interfaces is a read-only operation and should not create a
# timestamped test run when no build was requested.
if [ "$LIST_EQUIV" -eq 1 ] && [ "$BUILD_REQUESTED" -eq 0 ]; then
    printf '%s\n' screen-function-source screen-function-source-minified screen-script
    _list_root=${SCREEN2TMUX_BUILD_ROOT:-$HERE/build}
    for _screen in "$_list_root"/tmux-*-patched/install/bin/screen; do
        [ -x "$_screen" ] || continue
        _d=$(CDPATH= cd -- "$(dirname -- "$_screen")/../.." && pwd)
        _b=$(basename -- "$_d"); _v=${_b#tmux-}; _v=${_v%-patched}
        printf 'tmux-%s\n' "$_v"
    done
    exit 0
fi

if [ -n "$REQUESTED_WIDTH" ]; then
    case "$REQUESTED_WIDTH" in ''|*[!0-9]*) printf 'ERROR: --truncate-lines requires a positive integer.\n' >&2; exit 64 ;; esac
    [ "$REQUESTED_WIDTH" -gt 0 ] || { printf 'ERROR: --truncate-lines requires a positive integer.\n' >&2; exit 64; }
    CONSOLE_WIDTH=$REQUESTED_WIDTH; WIDTH_SOURCE=argument
else
    CONSOLE_WIDTH=; WIDTH_SOURCE=terminal
    if [ -r /dev/tty ] && command -v stty >/dev/null 2>&1; then _size=$(stty size </dev/tty 2>/dev/null || :); case "$_size" in *' '*) CONSOLE_WIDTH=${_size#* } ;; esac; fi
    if [ -z "$CONSOLE_WIDTH" ] && [ -n "${COLUMNS:-}" ]; then CONSOLE_WIDTH=$COLUMNS; WIDTH_SOURCE=COLUMNS; fi
    if [ -z "$CONSOLE_WIDTH" ] && command -v tput >/dev/null 2>&1; then CONSOLE_WIDTH=$(tput cols 2>/dev/null || :); fi
    case "$CONSOLE_WIDTH" in ''|*[!0-9]*) CONSOLE_WIDTH=120; WIDTH_SOURCE=fallback ;; esac
    [ "$CONSOLE_WIDTH" -gt 0 ] 2>/dev/null || { CONSOLE_WIDTH=120; WIDTH_SOURCE=fallback; }
fi
case "$RUN_TIMESTAMP" in *[!0-9A-Za-z._-]*|'') printf 'ERROR: invalid SCREEN2TMUX_RUN_TIMESTAMP: %s\n' "$RUN_TIMESTAMP" >&2; exit 64 ;; esac
case "${SCREEN2TMUX_COLOR:-auto}" in auto|'') COLOR_MODE=auto ;; always) COLOR_MODE=always ;; never) COLOR_MODE=never ;; *) printf 'ERROR: SCREEN2TMUX_COLOR must be auto, always, or never.\n' >&2; exit 64 ;; esac
COLOR_ENABLED=0
if [ -z "${NO_COLOR:-}" ]; then case "$COLOR_MODE" in always) COLOR_ENABLED=1 ;; auto) [ -t 1 ] && [ "${TERM:-}" != dumb ] && COLOR_ENABLED=1 ;; esac; fi

verbosity_filter()
{
    case "$VERBOSITY" in
        quiet)
            awk '
            /^\[PASS\]/ { next }
            /^Compiling .* \[OK\]$/ { next }
            { print }
            '
            ;;
        *) cat ;;
    esac
}
truncate_stream()
{
    awk -v max="$CONSOLE_WIDTH" '{ if (length($0) > max) { if (max > 3) print substr($0,1,max-3) "..."; else print substr($0,1,max) } else print }'
}
colorize_stream()
{
    if [ "$COLOR_ENABLED" -ne 1 ]; then cat; return; fi
    awk -v G="$(printf '\033[32m')" -v R="$(printf '\033[31m')" -v Y="$(printf '\033[33m')" -v C="$(printf '\033[36m')" -v M="$(printf '\033[35m')" -v Z="$(printf '\033[0m')" '
    function color_token(s, token, col, p) { p=index(s,token); if (!p) return s; return substr(s,1,p-1) col token Z substr(s,p+length(token)) }
    {
        line=$0
        if (line ~ /^Configure yes:/) {
            p=index(line,":"); print C substr(line,1,p-1) Z ":" G substr(line,p+1) Z; cfg="yes"; next
        }
        if (line ~ /^Configure no:/) {
            p=index(line,":"); print C substr(line,1,p-1) Z ":" R substr(line,p+1) Z; cfg="no"; next
        }
        if (line ~ /^Configure values:/) {
            p=index(line,":"); print C substr(line,1,p-1) Z substr(line,p); cfg="values"; next
        }
        if (cfg != "" && line ~ /^ +/) {
            if (cfg == "yes") print G line Z
            else if (cfg == "no") print R line Z
            else print line
            next
        }
        cfg=""
        if (line ~ /^\[(PASS|FAIL)\].*\|/) {
            if (line ~ / exact( |[ ]*\|)/) line=color_token(line,"exact",G)
            else if (line ~ / approx( |[ ]*\|)/) line=color_token(line,"approx",Y)
            else if (line ~ / unsupported( |[ ]*\|)/) line=color_token(line,"unsupported",R)
            else if (line ~ / moot( |[ ]*\|)/) line=color_token(line,"moot",C)
            else if (line ~ / external( |[ ]*\|)/) line=color_token(line,"external",M)
            else if (line ~ / invalid( |[ ]*\|)/) line=color_token(line,"invalid",R)
        }
        gsub(/\[PASS\]/,G "[PASS]" Z,line); gsub(/\[OK\]/,G "[OK]" Z,line)
        gsub(/\[FAIL\]/,R "[FAIL]" Z,line); gsub(/\[SKIP\]/,Y "[SKIP]" Z,line); gsub(/\[DIVERGED\]/,R "[DIVERGED]" Z,line)
        gsub(/: EXACT:/,": " G "EXACT" Z ":",line); gsub(/: APPROX:/,": " Y "APPROX" Z ":",line)
        gsub(/: UNSUPPORTED:/,": " R "UNSUPPORTED" Z ":",line); gsub(/: MOOT:/,": " C "MOOT" Z ":",line)
        gsub(/: EXTERNAL:/,": " M "EXTERNAL" Z ":",line); gsub(/: INVALID:/,": " R "INVALID" Z ":",line)
        gsub(/: WARNING:/,": " Y "WARNING" Z ":",line); gsub(/: suggestion:/,": " C "suggestion" Z ":",line); gsub(/: note:/,": " C "note" Z ":",line)
        if (line ~ /^(Summary|Regression summary|Interface equivalence summary|Screen\/interface summary|Behavior summary|Built screen summary|Build summary):/) { gsub(/ PASS/," " G "PASS" Z,line); gsub(/ FAIL/," " R "FAIL" Z,line); gsub(/ succeeded/," " G "succeeded" Z,line); gsub(/ failed/," " R "failed" Z,line) }
        sub(/^ERROR:/,R "ERROR" Z ":",line); sub(/^WARNING:/,Y "WARNING" Z ":",line); sub(/^Compiling /,C "Compiling" Z " ",line)
        sub(/^Summary:/,C "Summary" Z ":",line); sub(/^Regression summary:/,C "Regression summary" Z ":",line)
        sub(/^Interface equivalence summary:/,C "Interface equivalence summary" Z ":",line); sub(/^Screen\/interface summary:/,C "Screen/interface summary" Z ":",line); sub(/^Behavior summary:/,C "Behavior summary" Z ":",line)
        sub(/^Built screen summary:/,C "Built screen summary" Z ":",line); sub(/^Build summary:/,C "Build summary" Z ":",line)
        sub(/^Log:/,C "Log" Z ":",line); sub(/^Regression log:/,C "Regression log" Z ":",line); sub(/^Equivalence log:/,C "Equivalence log" Z ":",line); sub(/^Combined log:/,C "Combined log" Z ":",line)
        sub(/^Behavior log:/,C "Behavior log" Z ":",line); sub(/^Built screen log:/,C "Built screen log" Z ":",line); sub(/^Log archive:/,C "Log archive" Z ":",line)
        sub(/^RUN_TIMESTAMP:/,C "RUN_TIMESTAMP" Z ":",line); sub(/^RUN_STARTED:/,C "RUN_STARTED" Z ":",line); sub(/^RUN_FINISHED:/,C "RUN_FINISHED" Z ":",line)
        sub(/^PROJECT:/,C "PROJECT" Z ":",line); sub(/^CONSOLE_WIDTH:/,C "CONSOLE_WIDTH" Z ":",line); sub(/^VERBOSITY:/,C "VERBOSITY" Z ":",line)
        sub(/^MAPPINGS:/,C "MAPPINGS" Z ":",line); sub(/^BUILD_REQUEST:/,C "BUILD_REQUEST" Z ":",line); sub(/^DISCOVERED_BUILDS:/,C "DISCOVERED_BUILDS" Z ":",line); sub(/^DISCOVERED_BUILD:/,C "DISCOVERED_BUILD" Z ":",line)
        if (line ~ /^LOG_[A-Z0-9_.-]+:/) { p=index(line,":"); line=C substr(line,1,p-1) Z substr(line,p) }
        sub(/^RUN_STATUS: PASS$/,"RUN_STATUS: " G "PASS" Z,line); sub(/^RUN_STATUS: FAIL$/,"RUN_STATUS: " R "FAIL" Z,line)
        if (line ~ /^===== .* =====$/) { sub(/^===== /,"===== " C,line); sub(/ =====$/,Z " =====",line) }
        print line
    }'
}
terminal_stream() { verbosity_filter | truncate_stream | colorize_stream; }

mkdir -p "$LOG_DIR"
LOG_DIR=$(CDPATH= cd -- "$LOG_DIR" && pwd)
BUILD_ROOT=${SCREEN2TMUX_BUILD_ROOT:-$HERE/build}
mkdir -p "$BUILD_ROOT"

REG_LOG=$LOG_DIR/test-regressions-$RUN_TIMESTAMP.log
EQUIV_LOG=$LOG_DIR/test-interface-equivalence-$RUN_TIMESTAMP.log
SYSTEM_BEHAVIOR_LOG=$LOG_DIR/test-tmux-behavior-$RUN_TIMESTAMP.log
BUILT_SCREEN_LOG=$LOG_DIR/test-built-tmux-screen-$RUN_TIMESTAMP.log
BUILD_RUN_LOG=$LOG_DIR/test-build-$RUN_TIMESTAMP.log
CONSOLE_LOG=$LOG_DIR/test-run-console-$RUN_TIMESTAMP.log
ARCHIVE=$LOG_DIR/screen-to-tmux-translator-$VERSION-test-logs-$RUN_TIMESTAMP.zip
BUILD_REGISTRY=$LOG_DIR/.build-registry-$RUN_TIMESTAMP-$$.tsv
EQUIV_BUILT_REGISTRY=$LOG_DIR/.equiv-build-registry-$RUN_TIMESTAMP-$$.tsv
ARCHIVE_LIST=$LOG_DIR/.archive-list-$RUN_TIMESTAMP-$$.txt
trap 'rm -f "$BUILD_REGISTRY" "$EQUIV_BUILT_REGISTRY" "$ARCHIVE_LIST"' 0 1 2 3 15

check_new_artifact() { [ ! -e "$1" ] || { printf 'ERROR: test-run artifact already exists: %s\nUse a new timestamp or remove the existing artifact.\n' "$1" >&2; exit 73; }; }
for _f in "$REG_LOG" "$EQUIV_LOG" "$CONSOLE_LOG" "$ARCHIVE"; do check_new_artifact "$_f"; done
[ "$BUILD_REQUESTED" -eq 0 ] || check_new_artifact "$BUILD_RUN_LOG"
: > "$REG_LOG"; : > "$EQUIV_LOG"; : > "$CONSOLE_LOG"; : > "$BUILD_REGISTRY"; : > "$EQUIV_BUILT_REGISTRY"; : > "$ARCHIVE_LIST"
[ "$BUILD_REQUESTED" -eq 0 ] || : > "$BUILD_RUN_LOG"

run_component()
{
    _name=$1; shift
    _rc_file=$LOG_DIR/.run-tests-$RUN_TIMESTAMP-$$.rc
    rm -f "$_rc_file"
    printf '\n===== %s =====\n' "$_name" | tee -a "$CONSOLE_LOG" | terminal_stream
    (
        NO_COLOR=1 SCREEN2TMUX_TEST_QUIET="$TEST_QUIET" SCREEN2TMUX_MAP_LEFT_WIDTH=26 SCREEN2TMUX_MAP_DESC_WIDTH=52 SCREEN2TMUX_MAP_SCREEN_WIDTH=49 "$@"
        _rc=$?; printf '%s\n' "$_rc" > "$_rc_file"; exit 0
    ) 2>&1 | tee -a "$CONSOLE_LOG" | terminal_stream
    [ -r "$_rc_file" ] || { printf 'ERROR: could not recover status for %s\n' "$_name" | tee -a "$CONSOLE_LOG" | terminal_stream >&2; return 125; }
    _rc=$(cat "$_rc_file"); rm -f "$_rc_file"; return "$_rc"
}

run_build_component()
{
    _rc_file=$LOG_DIR/.run-tests-build-$RUN_TIMESTAMP-$$.rc
    rm -f "$_rc_file"
    printf '\n===== requested tmux builds =====\n' | tee -a "$CONSOLE_LOG" "$BUILD_RUN_LOG" | terminal_stream
    (
        set -- --verbosity "$VERBOSITY"
        for _bv in $BUILD_VERSIONS; do set -- "$@" "$_bv"; done
        NO_COLOR=1 SCREEN2TMUX_COLOR=never SCREEN2TMUX_CONSOLE_WIDTH="$CONSOLE_WIDTH" sh "$HERE/build_tmux.sh" "$@"
        _rc=$?; printf '%s\n' "$_rc" > "$_rc_file"; exit 0
    ) 2>&1 | tee -a "$CONSOLE_LOG" "$BUILD_RUN_LOG" | terminal_stream
    [ -r "$_rc_file" ] || return 125
    _rc=$(cat "$_rc_file"); rm -f "$_rc_file"; return "$_rc"
}

{
    printf 'screen-to-tmux-translator test run\nVERSION: %s\nRUN_TIMESTAMP: %s\nRUN_STARTED: %s\nPROJECT: %s\n' "$VERSION" "$RUN_TIMESTAMP" "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$HERE"
    printf 'CONSOLE_WIDTH: %s (%s; measured once at startup)\nVERBOSITY: %s\n' "$CONSOLE_WIDTH" "$WIDTH_SOURCE" "$VERBOSITY"
    if [ "$TEST_QUIET" -eq 1 ]; then printf 'MAPPINGS: hidden (--quiet)\n'; else printf 'MAPPINGS: shown\n'; fi
    if [ "$BUILD_REQUESTED" -eq 1 ]; then printf 'BUILD_REQUEST: %s\n' "$BUILD_VERSIONS"; else printf 'BUILD_REQUEST: none\n'; fi
    printf '%s\n' '=============================================================================='
} | tee -a "$CONSOLE_LOG" | terminal_stream

suite_rc=0
if [ "$BUILD_REQUESTED" -eq 1 ]; then if run_build_component; then :; else suite_rc=1; fi; fi

# Discover every successful build. BUILD-INFO is written only after a completed
# build, so failed/partial directories are intentionally ignored.
discover_one()
{
    _dir=$1
    [ -r "$_dir/BUILD-INFO" ] || return 0
    _tmux=$(sed -n 's/^TMUX_BIN=//p' "$_dir/BUILD-INFO" | head -1)
    _screen=$(sed -n 's/^SCREEN_BIN=//p' "$_dir/BUILD-INFO" | head -1)
    _patched=$(sed -n 's/^PATCHED=//p' "$_dir/BUILD-INFO" | head -1)
    _name=$(sed -n 's/^BUILD_NAME=tmux-//p' "$_dir/BUILD-INFO" | head -1)
    [ -n "$_name" ] || { _b=$(basename -- "$_dir"); _name=${_b#tmux-}; _name=${_name#build-tmux-}; }
    [ -x "$_tmux" ] || return 0
    case "$_patched" in 1) _variant=patched; _base=${_name%-patched}; [ -x "$_screen" ] || return 0 ;; *) _variant=original; _base=$_name; _screen=- ;; esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$_base" "$_variant" "$_tmux" "$_screen" "$_dir" >> "$BUILD_REGISTRY"
}
for _dir in "$BUILD_ROOT"/tmux-*; do [ -d "$_dir" ] && discover_one "$_dir"; done
# Read old 0.4.1 layouts too, but do not duplicate names already found in build/.
if [ "$BUILD_ROOT" = "$HERE/build" ]; then
    for _dir in "$HERE"/build-tmux-*; do
        [ -d "$_dir" ] || continue
        _bn=$(basename -- "$_dir"); _guess=${_bn#build-tmux-}; _guess=${_guess%-patched}
        grep -E "^${_guess}[[:space:]]" "$BUILD_REGISTRY" >/dev/null 2>&1 || discover_one "$_dir"
    done
fi
if [ -s "$BUILD_REGISTRY" ]; then sort -t "$TAB" -k1,1 -k2,2 "$BUILD_REGISTRY" -o "$BUILD_REGISTRY"; fi
while IFS="$TAB" read -r _name _variant _tmux _screen _dir; do
    [ "$_variant" = patched ] || continue
    printf 'tmux-%s\t%s\ttmux-%s screen hardlink\n' "$_name" "$_screen" "$_name" >> "$EQUIV_BUILT_REGISTRY"
done < "$BUILD_REGISTRY"

BUILD_COUNT=$(wc -l < "$BUILD_REGISTRY" | tr -d ' ')
PATCHED_COUNT=$(wc -l < "$EQUIV_BUILT_REGISTRY" | tr -d ' ')
{
    printf 'DISCOVERED_BUILDS: %s\n' "$BUILD_COUNT"
    while IFS="$TAB" read -r _name _variant _tmux _screen _dir; do printf 'DISCOVERED_BUILD: tmux-%s %s (%s)\n' "$_name" "$_variant" "$_dir"; done < "$BUILD_REGISTRY"
    printf '%s\n' '=============================================================================='
} | tee -a "$CONSOLE_LOG" | terminal_stream

if [ "$LIST_EQUIV" -eq 1 ]; then
    printf '%s\n' screen-function-source screen-function-source-minified screen-script
    while IFS="$TAB" read -r _en _ep _elabel; do printf '%s\n' "$_en"; done < "$EQUIV_BUILT_REGISTRY"
    exit 0
fi

if run_component 'Screen CLI/oracle + interface equivalence tests' env EQUIV_LOG="$EQUIV_LOG" SCREEN2TMUX_EQUIV_INTERFACES="$EQUIV_REQUEST" SCREEN2TMUX_EQUIV_BUILT_REGISTRY="$EQUIV_BUILT_REGISTRY" "$HERE/tests/test-interface-equivalence.sh"; then :; else suite_rc=1; fi
if run_component 'focused regressions' env REG_LOG="$REG_LOG" "$HERE/tests/test-regressions.sh"; then :; else suite_rc=1; fi

# With built patched tmux binaries available, test behavior once per requested
# version against the patched binary. The pristine originals are build baselines,
# not additional behavior targets. Fall back to a system tmux only when there is
# no patched build to exercise.
if [ "$PATCHED_COUNT" -eq 0 ]; then
    check_new_artifact "$SYSTEM_BEHAVIOR_LOG"; : > "$SYSTEM_BEHAVIOR_LOG"
    if run_component 'live tmux behavior tests' env BEHAVIOR_LOG="$SYSTEM_BEHAVIOR_LOG" "$HERE/tests/test-tmux-behavior.sh"; then :; else suite_rc=1; fi
fi

if [ "$PATCHED_COUNT" -gt 0 ]; then
    check_new_artifact "$BUILT_SCREEN_LOG"; : > "$BUILT_SCREEN_LOG"
    set --
    while IFS="$TAB" read -r _en _ep _elabel; do set -- "$@" "$_ep"; done < "$EQUIV_BUILT_REGISTRY"
    if run_component 'built patched tmux integration checks' env BUILT_SCREEN_LOG="$BUILT_SCREEN_LOG" "$HERE/tests/test-built-tmux-screen.sh" "$@"; then :; else suite_rc=1; fi
fi

# One live behavior pass per successfully built version, using its patched tmux.
DYNAMIC_LOGS=
while IFS="$TAB" read -r _name _variant _tmux _screen _dir; do
    [ "$_variant" = patched ] || continue
    _safe=$(printf '%s-patched' "$_name" | sed 's/[^A-Za-z0-9._-]/_/g')
    _blog=$LOG_DIR/test-tmux-behavior-tmux-$_safe-$RUN_TIMESTAMP.log
    check_new_artifact "$_blog"; : > "$_blog"
    if run_component "tmux $_name patched behavior tests" env TMUX_BIN="$_tmux" BEHAVIOR_LOG="$_blog" "$HERE/tests/test-tmux-behavior.sh"; then :; else suite_rc=1; fi
    DYNAMIC_LOGS="$DYNAMIC_LOGS $_blog"
done < "$BUILD_REGISTRY"

{
    printf '\n%s\n' '=============================================================================='
    printf 'RUN_FINISHED: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    if [ "$suite_rc" -eq 0 ]; then printf 'RUN_STATUS: PASS\n'; else printf 'RUN_STATUS: FAIL\n'; fi
    printf 'LOG_REGRESSIONS: %s\nLOG_SCREEN_INTERFACES: %s\n' "$REG_LOG" "$EQUIV_LOG"
    [ "$PATCHED_COUNT" -ne 0 ] || printf 'LOG_TMUX_BEHAVIOR: %s\n' "$SYSTEM_BEHAVIOR_LOG"
    [ "$BUILD_REQUESTED" -eq 0 ] || printf 'LOG_BUILD: %s\n' "$BUILD_RUN_LOG"
    [ "$PATCHED_COUNT" -eq 0 ] || printf 'LOG_BUILT_SCREEN: %s\n' "$BUILT_SCREEN_LOG"
    for _dl in $DYNAMIC_LOGS; do printf 'LOG_BUILD_BEHAVIOR: %s\n' "$_dl"; done
    printf 'LOG_CONSOLE: %s\nLOG_ARCHIVE: %s\n' "$CONSOLE_LOG" "$ARCHIVE"
} | tee -a "$CONSOLE_LOG" | terminal_stream

archive_logs()
{
    _archive=$1; shift
    if command -v zip >/dev/null 2>&1; then (cd "$LOG_DIR" || exit 1; zip -q "$(basename -- "$_archive")" "$@"); return $?; fi
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$LOG_DIR" "$_archive" "$@" <<'PY'
import os, sys, zipfile
log_dir, archive, *names = sys.argv[1:]
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for name in names:
        zf.write(os.path.join(log_dir, name), arcname=name)
PY
        return $?
    fi
    printf 'ERROR: cannot create requested ZIP: neither zip nor python3 is installed.\n' >&2; return 127
}

set -- "$(basename -- "$REG_LOG")" "$(basename -- "$EQUIV_LOG")" "$(basename -- "$CONSOLE_LOG")"
[ "$PATCHED_COUNT" -ne 0 ] || set -- "$@" "$(basename -- "$SYSTEM_BEHAVIOR_LOG")"
[ "$BUILD_REQUESTED" -eq 0 ] || set -- "$@" "$(basename -- "$BUILD_RUN_LOG")"
[ "$PATCHED_COUNT" -eq 0 ] || set -- "$@" "$(basename -- "$BUILT_SCREEN_LOG")"
for _dl in $DYNAMIC_LOGS; do set -- "$@" "$(basename -- "$_dl")"; done
if archive_logs "$ARCHIVE" "$@"; then printf 'Log archive: %s\n' "$ARCHIVE" | terminal_stream; else suite_rc=1; printf 'ERROR: failed to create log archive: %s\n' "$ARCHIVE" | tee -a "$CONSOLE_LOG" | terminal_stream >&2; fi
exit "$suite_rc"
