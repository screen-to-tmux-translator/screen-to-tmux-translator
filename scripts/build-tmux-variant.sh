#!/bin/sh
# Build one tmux branch twice from the same downloaded commit: pristine and
# Screen-compat patched. POSIX sh.
set -eu

if [ "$#" -ne 2 ]; then
    printf 'usage: %s BRANCH BUILD_NAME\n' "$0" >&2
    exit 64
fi

BRANCH=$1
BUILD_NAME=$2
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_BASE=${SCREEN2TMUX_BUILD_ROOT:-$PROJECT/build}
BUILD_ROOT=$BUILD_BASE/$BUILD_NAME
GIT_URL=${TMUX_GIT_URL:-https://github.com/tmux/tmux.git}
INTEGRATION=$PROJECT/tmux-integration/screen-to-tmux-translator
TMUX_C_PATCH=$PROJECT/tmux-integration/tmux.c-screen-compat.patch
CC_BIN=${CC:-cc}

case "$CC_BIN" in
    *' '*)
        printf 'ERROR: CC must name a compiler executable without embedded arguments (got: %s)\n' "$CC_BIN" >&2
        printf 'Put compiler flags in CFLAGS/CPPFLAGS/LDFLAGS instead.\n' >&2
        exit 64
        ;;
esac

if command -v getconf >/dev/null 2>&1; then
    _jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')
else
    _jobs=2
fi
case "$_jobs" in ''|*[!0-9]*) _jobs=2 ;; esac
[ "$_jobs" -gt 0 ] 2>/dev/null || _jobs=2
JOBS=${TMUX_BUILD_JOBS:-$_jobs}
case "$JOBS" in ''|*[!0-9]*) printf 'ERROR: TMUX_BUILD_JOBS must be a positive integer.\n' >&2; exit 64 ;; esac
[ "$JOBS" -gt 0 ] || { printf 'ERROR: TMUX_BUILD_JOBS must be greater than zero.\n' >&2; exit 64; }

print_dependency_help()
{
    cat >&2 <<'HELP'
Install the normal tmux-from-Git build dependencies, then rerun this script.
Common package sets:
  Debian/Ubuntu: apt-get install build-essential git autoconf automake pkg-config bison libevent-dev libncurses-dev patch
  Fedora/RHEL:   dnf install gcc make git autoconf automake pkgconf-pkg-config bison libevent-devel ncurses-devel patch
  Alpine:        apk add build-base git autoconf automake pkgconf bison libevent-dev ncurses-dev patch
  macOS/Homebrew: brew install autoconf automake pkg-config bison libevent ncurses
HELP
}

missing=
need_cmd()
{
    if ! command -v "$1" >/dev/null 2>&1; then
        missing="$missing $1"
    fi
}

need_cmd sh
need_cmd make
need_cmd "$CC_BIN"
need_cmd pkg-config
need_cmd autoconf
need_cmd automake
need_cmd aclocal
need_cmd autoreconf
need_cmd patch
need_cmd tar
need_cmd awk
need_cmd sed
need_cmd grep
need_cmd diff
need_cmd cmp
need_cmd ln
if [ -z "${TMUX_SOURCE_DIR:-}" ]; then
    need_cmd git
fi
if ! command -v yacc >/dev/null 2>&1 && ! command -v bison >/dev/null 2>&1; then
    missing="$missing yacc-or-bison"
fi

if [ -n "$missing" ]; then
    printf 'ERROR: missing build command(s):%s\n' "$missing" >&2
    print_dependency_help
    exit 2
fi

# Check the two mandatory development libraries before spending time cloning.
if pkg-config --exists 'libevent_core >= 2' 2>/dev/null || pkg-config --exists 'libevent >= 2' 2>/dev/null; then
    :
else
    printf 'ERROR: libevent 2.x development files were not found by pkg-config.\n' >&2
    print_dependency_help
    exit 2
fi

if pkg-config --exists tinfow 2>/dev/null || pkg-config --exists tinfo 2>/dev/null || \
   pkg-config --exists ncursesw 2>/dev/null || pkg-config --exists ncurses 2>/dev/null; then
    :
else
    printf 'ERROR: ncurses/terminfo development files were not found by pkg-config.\n' >&2
    print_dependency_help
    exit 2
fi

[ -r "$INTEGRATION" ] || { printf 'ERROR: missing integration source: %s\n' "$INTEGRATION" >&2; exit 2; }
[ -r "$TMUX_C_PATCH" ] || { printf 'ERROR: missing tmux.c patch: %s\n' "$TMUX_C_PATCH" >&2; exit 2; }

printf 'tmux Screen-compat build\n'
printf 'BRANCH: %s\n' "$BRANCH"
printf 'BUILD_NAME: %s\n' "$BUILD_NAME"
printf 'BUILD_ROOT: %s\n' "$BUILD_ROOT"
printf 'JOBS: %s\n' "$JOBS"

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

REPO=$BUILD_ROOT/download
if [ -n "${TMUX_SOURCE_DIR:-}" ]; then
    [ -d "$TMUX_SOURCE_DIR" ] || { printf 'ERROR: TMUX_SOURCE_DIR is not a directory: %s\n' "$TMUX_SOURCE_DIR" >&2; exit 2; }
    printf 'SOURCE: local override %s\n' "$TMUX_SOURCE_DIR"
    mkdir -p "$REPO"
    cp -R "$TMUX_SOURCE_DIR"/. "$REPO"/
    if [ -d "$REPO/.git" ] && command -v git >/dev/null 2>&1; then
        COMMIT=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || printf local-source)
    else
        COMMIT=local-source
    fi
else
    printf 'Downloading %s branch %s ...\n' "$GIT_URL" "$BRANCH"
    if ! git clone --quiet --depth 1 --branch "$BRANCH" "$GIT_URL" "$REPO"; then
        printf 'ERROR: failed to download tmux branch %s from %s\n' "$BRANCH" "$GIT_URL" >&2
        exit 69
    fi
    COMMIT=$(git -C "$REPO" rev-parse HEAD)
fi
printf 'SOURCE_COMMIT: %s\n' "$COMMIT"

ORIG_SRC=$BUILD_ROOT/original/source
PATCH_SRC=$BUILD_ROOT/patched/source
ORIG_PREFIX=$BUILD_ROOT/original/install
PATCH_PREFIX=$BUILD_ROOT/patched/install
mkdir -p "$ORIG_SRC" "$PATCH_SRC"

copy_snapshot()
{
    _dest=$1
    if [ -d "$REPO/.git" ] && command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --verify HEAD >/dev/null 2>&1; then
        git -C "$REPO" archive --format=tar HEAD | tar -xf - -C "$_dest"
    else
        cp -R "$REPO"/. "$_dest"/
        rm -rf "$_dest/.git"
    fi
}

copy_snapshot "$ORIG_SRC"
copy_snapshot "$PATCH_SRC"

# Apply the integration conservatively. If upstream tmux.c moved enough that
# the two known insertion points no longer match, stop rather than guessing.
cp "$INTEGRATION" "$PATCH_SRC/screen-to-tmux-translator"
if ! patch -d "$PATCH_SRC" -p1 --fuzz=0 --batch < "$TMUX_C_PATCH" > "$BUILD_ROOT/patch.log" 2>&1; then
    cat "$BUILD_ROOT/patch.log" >&2
    printf 'ERROR: Screen compatibility patch does not apply cleanly to tmux branch %s commit %s.\n' "$BRANCH" "$COMMIT" >&2
    printf 'Refusing to guess at a new tmux.c insertion point.\n' >&2
    exit 65
fi
# Some patch implementations create tmux.c.orig when a hunk applies at an
# offset even with zero fuzz. It is a patch backup, not part of the requested
# source change; remove it only when pristine upstream did not already have it.
if [ ! -e "$ORIG_SRC/tmux.c.orig" ]; then rm -f "$PATCH_SRC/tmux.c.orig"; fi

# Enforce the source-footprint contract before autogen creates generated files.
diff -qr "$ORIG_SRC" "$PATCH_SRC" > "$BUILD_ROOT/source-diff.txt" || :
_diff_count=$(wc -l < "$BUILD_ROOT/source-diff.txt" | awk '{print $1}')
if [ "$_diff_count" -ne 2 ] || \
   ! grep -q 'tmux.c differ' "$BUILD_ROOT/source-diff.txt" || \
   ! grep -q 'screen-to-tmux-translator' "$BUILD_ROOT/source-diff.txt"; then
    printf 'ERROR: patched source footprint is not exactly one changed file plus one added translator file.\n' >&2
    cat "$BUILD_ROOT/source-diff.txt" >&2
    exit 65
fi

run_logged()
{
    _label=$1
    _log=$2
    shift 2
    _rc_file=$BUILD_ROOT/.build-$$.rc
    rm -f "$_rc_file"
    printf '\n===== %s =====\n' "$_label"
    (
        if "$@"; then _rc=0; else _rc=$?; fi
        printf '%s\n' "$_rc" > "$_rc_file"
        exit 0
    ) 2>&1 | tee "$_log"
    if [ ! -r "$_rc_file" ]; then
        printf 'ERROR: could not recover build status for %s\n' "$_label" >&2
        return 125
    fi
    _rc=$(cat "$_rc_file")
    rm -f "$_rc_file"
    return "$_rc"
}

build_tree()
{
    _src=$1
    _prefix=$2
    (
        set -e
        cd "$_src"
        sh ./autogen.sh
        ./configure --prefix="$_prefix"
        make -j"$JOBS"
        make install
    )
}

if ! run_logged 'original tmux build' "$BUILD_ROOT/original-build.log" build_tree "$ORIG_SRC" "$ORIG_PREFIX"; then
    printf 'ERROR: original tmux build failed. See %s\n' "$BUILD_ROOT/original-build.log" >&2
    exit 1
fi
if ! run_logged 'patched tmux build' "$BUILD_ROOT/patched-build.log" build_tree "$PATCH_SRC" "$PATCH_PREFIX"; then
    printf 'ERROR: patched tmux build failed. See %s\n' "$BUILD_ROOT/patched-build.log" >&2
    exit 1
fi

ORIG_TMUX=$ORIG_PREFIX/bin/tmux
PATCH_TMUX=$PATCH_PREFIX/bin/tmux
PATCH_SCREEN=$PATCH_PREFIX/bin/screen
[ -x "$ORIG_TMUX" ] || { printf 'ERROR: original build did not produce %s\n' "$ORIG_TMUX" >&2; exit 1; }
[ -x "$PATCH_TMUX" ] || { printf 'ERROR: patched build did not produce %s\n' "$PATCH_TMUX" >&2; exit 1; }
rm -f "$PATCH_SCREEN"
ln "$PATCH_TMUX" "$PATCH_SCREEN"

_inode_tmux=$(ls -di "$PATCH_TMUX" | awk '{print $1}')
_inode_screen=$(ls -di "$PATCH_SCREEN" | awk '{print $1}')
if [ "$_inode_tmux" != "$_inode_screen" ]; then
    printf 'ERROR: %s is not a hardlink to %s\n' "$PATCH_SCREEN" "$PATCH_TMUX" >&2
    exit 1
fi

ORIG_VERSION=$($ORIG_TMUX -V 2>/dev/null || printf unknown)
PATCH_VERSION=$($PATCH_TMUX -V 2>/dev/null || printf unknown)
if [ "$ORIG_VERSION" != "$PATCH_VERSION" ]; then
    printf 'ERROR: original and patched tmux version output differs:\n  original: %s\n  patched:  %s\n' "$ORIG_VERSION" "$PATCH_VERSION" >&2
    exit 1
fi

cat > "$BUILD_ROOT/BUILD-INFO" <<INFO
BUILD_NAME=$BUILD_NAME
SOURCE_URL=$GIT_URL
SOURCE_BRANCH=$BRANCH
SOURCE_COMMIT=$COMMIT
TMUX_VERSION=$PATCH_VERSION
ORIGINAL_TMUX=$ORIG_TMUX
PATCHED_TMUX=$PATCH_TMUX
PATCHED_SCREEN=$PATCH_SCREEN
SCREEN_HARDLINK_INODE=$_inode_screen
INFO

printf '\nBuild complete.\n'
printf 'TMUX_VERSION: %s\n' "$PATCH_VERSION"
printf 'ORIGINAL_TMUX: %s\n' "$ORIG_TMUX"
printf 'PATCHED_TMUX: %s\n' "$PATCH_TMUX"
printf 'PATCHED_SCREEN: %s\n' "$PATCH_SCREEN"
printf 'BUILD_INFO: %s\n' "$BUILD_ROOT/BUILD-INFO"
printf '\nRun %s/run-tests.sh to automatically test any discovered patched builds.\n' "$PROJECT"
