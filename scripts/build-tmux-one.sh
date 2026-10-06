#!/bin/sh
# Build one pristine or Screen-compat tmux tree, preserving a full source tree
# and a separate build/install tree. POSIX sh.
set -eu

if [ "$#" -ne 3 ]; then
    printf 'usage: %s BRANCH NAME PATCHED(0|1)\n' "$0" >&2
    exit 64
fi

BRANCH=$1
NAME=$2
PATCHED=$3
case "$PATCHED" in 0|1) : ;; *) printf 'ERROR: PATCHED must be 0 or 1.\n' >&2; exit 64 ;; esac

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SOURCE_PARENT=${SCREEN2TMUX_SOURCE_ROOT:-$PROJECT}
BUILD_PARENT=${SCREEN2TMUX_BUILD_ROOT:-$PROJECT}
SUFFIX=
[ "$PATCHED" -eq 1 ] && SUFFIX=-patched
SOURCE_DIR=$SOURCE_PARENT/source-tmux-$NAME$SUFFIX
BUILD_DIR=$BUILD_PARENT/build-tmux-$NAME$SUFFIX
INSTALL_DIR=$BUILD_DIR/install
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
Normal tmux-from-Git build dependency sets:
  Debian/Ubuntu: build-essential git autoconf automake pkg-config bison libevent-dev libncurses-dev patch diffutils gawk sed grep tar coreutils
  Fedora/RHEL:   gcc make git autoconf automake pkgconf-pkg-config bison libevent-devel ncurses-devel patch diffutils gawk sed grep tar coreutils
  Alpine:        build-base git autoconf automake pkgconf bison libevent-dev ncurses-dev patch diffutils gawk sed grep tar coreutils
  macOS/Homebrew: git autoconf automake pkg-config bison libevent ncurses diffutils gawk gnu-sed grep gnu-tar coreutils
HELP
}

MISSING_CMDS=
MISSING_LIBS=
need_cmd()
{
    if ! command -v "$1" >/dev/null 2>&1; then
        MISSING_CMDS="$MISSING_CMDS $1"
    fi
}

check_dependencies()
{
    MISSING_CMDS=
    MISSING_LIBS=
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
    need_cmd id
    if [ -z "${TMUX_SOURCE_DIR:-}" ]; then need_cmd git; fi
    if ! command -v yacc >/dev/null 2>&1 && ! command -v bison >/dev/null 2>&1; then
        MISSING_CMDS="$MISSING_CMDS yacc-or-bison"
    fi

    if command -v pkg-config >/dev/null 2>&1; then
        if pkg-config --exists 'libevent_core >= 2' 2>/dev/null || pkg-config --exists 'libevent >= 2' 2>/dev/null; then :; else
            MISSING_LIBS="$MISSING_LIBS libevent-2.x-development"
        fi
        if pkg-config --exists tinfow 2>/dev/null || pkg-config --exists tinfo 2>/dev/null || \
           pkg-config --exists ncursesw 2>/dev/null || pkg-config --exists ncurses 2>/dev/null; then :; else
            MISSING_LIBS="$MISSING_LIBS ncurses/terminfo-development"
        fi
    else
        MISSING_LIBS="$MISSING_LIBS libevent-2.x-development ncurses/terminfo-development"
    fi
}

have_missing_dependencies() { [ -n "$MISSING_CMDS$MISSING_LIBS" ]; }

detect_package_manager()
{
    if [ -n "${SCREEN2TMUX_PACKAGE_MANAGER:-}" ]; then
        case "$SCREEN2TMUX_PACKAGE_MANAGER" in apt-get|dnf|yum|apk|brew) PACKAGE_MANAGER=$SCREEN2TMUX_PACKAGE_MANAGER ;; *)
            printf 'ERROR: unsupported SCREEN2TMUX_PACKAGE_MANAGER=%s\n' "$SCREEN2TMUX_PACKAGE_MANAGER" >&2; return 1 ;; esac
        command -v "$PACKAGE_MANAGER" >/dev/null 2>&1 || { printf 'ERROR: requested package manager is not installed: %s\n' "$PACKAGE_MANAGER" >&2; return 1; }
        return 0
    fi
    for _pm in apt-get dnf yum apk brew; do
        if command -v "$_pm" >/dev/null 2>&1; then PACKAGE_MANAGER=$_pm; return 0; fi
    done
    PACKAGE_MANAGER=
    return 1
}

package_list_for_manager()
{
    case "$1" in
        apt-get) printf '%s\n' 'build-essential git autoconf automake pkg-config bison libevent-dev libncurses-dev patch diffutils gawk sed grep tar coreutils' ;;
        dnf|yum) printf '%s\n' 'gcc make git autoconf automake pkgconf-pkg-config bison libevent-devel ncurses-devel patch diffutils gawk sed grep tar coreutils' ;;
        apk) printf '%s\n' 'build-base git autoconf automake pkgconf bison libevent-dev ncurses-dev patch diffutils gawk sed grep tar coreutils' ;;
        brew) printf '%s\n' 'git autoconf automake pkg-config bison libevent ncurses diffutils gawk gnu-sed grep gnu-tar coreutils' ;;
        *) return 1 ;;
    esac
}

run_privileged()
{
    if [ "$(id -u 2>/dev/null || printf 1)" -eq 0 ] 2>/dev/null; then "$@"
    elif command -v sudo >/dev/null 2>&1; then sudo "$@"
    else printf 'ERROR: installing packages with %s requires root privileges or sudo.\n' "$PACKAGE_MANAGER" >&2; return 1
    fi
}

print_missing_dependencies()
{
    printf 'Missing tmux build dependencies were detected.\n' >&2
    [ -z "$MISSING_CMDS" ] || printf '  command(s):%s\n' "$MISSING_CMDS" >&2
    [ -z "$MISSING_LIBS" ] || printf '  development library/libraries:%s\n' "$MISSING_LIBS" >&2
}

confirm_dependency_install()
{
    case "${SCREEN2TMUX_AUTO_INSTALL:-ask}" in
        1|y|Y|yes|YES|Yes) return 0 ;;
        0|n|N|no|NO|No) printf 'Dependency installation declined; build cancelled.\n' >&2; return 1 ;;
        ask|'') : ;;
        *) printf 'ERROR: SCREEN2TMUX_AUTO_INSTALL must be ask, yes, or no.\n' >&2; return 1 ;;
    esac
    printf 'Install the missing build software automatically and continue? [y/N] ' >&2
    _answer=
    if [ -r /dev/tty ]; then IFS= read -r _answer </dev/tty || _answer=; else IFS= read -r _answer || _answer=; fi
    case "$_answer" in y|Y|yes|YES|Yes) return 0 ;; *) printf 'Dependency installation declined; build cancelled.\n' >&2; return 1 ;; esac
}

install_build_dependencies()
{
    _packages=$(package_list_for_manager "$PACKAGE_MANAGER") || return 1
    printf 'Detected package manager: %s\n' "$PACKAGE_MANAGER" >&2
    printf 'Packages requested: %s\n' "$_packages" >&2
    printf 'Already-installed packages may simply be reported as current.\n' >&2
    case "$PACKAGE_MANAGER" in
        apt-get) run_privileged apt-get update; run_privileged apt-get install -y $_packages ;;
        dnf) run_privileged dnf install -y $_packages ;;
        yum) run_privileged yum install -y $_packages ;;
        apk) run_privileged apk add $_packages ;;
        brew) brew install $_packages ;;
        *) return 1 ;;
    esac
}

check_dependencies
if have_missing_dependencies; then
    print_missing_dependencies
    if ! detect_package_manager; then printf 'ERROR: no supported package manager was detected for automatic installation.\n' >&2; print_dependency_help; exit 2; fi
    _packages=$(package_list_for_manager "$PACKAGE_MANAGER")
    printf 'Automatic installer can use %s with: %s\n' "$PACKAGE_MANAGER" "$_packages" >&2
    if ! confirm_dependency_install; then print_dependency_help; exit 2; fi
    if ! install_build_dependencies; then printf 'ERROR: automatic dependency installation failed.\n' >&2; print_dependency_help; exit 2; fi
    printf 'Rechecking build dependencies after installation ...\n' >&2
    check_dependencies
    if have_missing_dependencies; then
        print_missing_dependencies
        printf 'ERROR: dependencies are still incomplete after package installation.\n' >&2
        exit 2
    fi
    printf 'Build dependencies are now satisfied; continuing.\n' >&2
fi

if [ "${SCREEN2TMUX_DEPENDENCY_CHECK_ONLY:-0}" = 1 ]; then printf 'Dependency check complete.\n'; exit 0; fi

if [ "$PATCHED" -eq 1 ]; then
    [ -r "$INTEGRATION" ] || { printf 'ERROR: missing integration source: %s\n' "$INTEGRATION" >&2; exit 2; }
    [ -r "$TMUX_C_PATCH" ] || { printf 'ERROR: missing tmux.c patch: %s\n' "$TMUX_C_PATCH" >&2; exit 2; }
fi

mkdir -p "$SOURCE_PARENT" "$BUILD_PARENT"
rm -rf "$SOURCE_DIR" "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

printf 'tmux build\n'
printf 'BRANCH: %s\n' "$BRANCH"
printf 'NAME: %s\n' "$NAME"
printf 'PATCHED: %s\n' "$PATCHED"
printf 'SOURCE_DIR: %s\n' "$SOURCE_DIR"
printf 'BUILD_DIR: %s\n' "$BUILD_DIR"
printf 'JOBS: %s\n' "$JOBS"

resolve_latest_commit()
{
    if [ -n "${TMUX_LATEST_COMMIT:-}" ]; then printf '%s\n' "$TMUX_LATEST_COMMIT"; return 0; fi
    _other=$SOURCE_PARENT/source-tmux-latest
    [ "$PATCHED" -eq 0 ] || _other=$SOURCE_PARENT/source-tmux-latest
    if [ "$PATCHED" -eq 0 ]; then _other=$SOURCE_PARENT/source-tmux-latest-patched; fi
    if [ -d "$_other/.git" ]; then
        git -C "$_other" rev-parse HEAD 2>/dev/null && return 0
    fi
    git ls-remote "$GIT_URL" refs/heads/master | awk 'NR==1 {print $1}'
}

if [ -n "${TMUX_SOURCE_DIR:-}" ]; then
    [ -d "$TMUX_SOURCE_DIR" ] || { printf 'ERROR: TMUX_SOURCE_DIR is not a directory: %s\n' "$TMUX_SOURCE_DIR" >&2; exit 2; }
    printf 'SOURCE: local override %s\n' "$TMUX_SOURCE_DIR"
    mkdir -p "$SOURCE_DIR"
    cp -R "$TMUX_SOURCE_DIR"/. "$SOURCE_DIR"/
    if [ -d "$SOURCE_DIR/.git" ] && command -v git >/dev/null 2>&1; then COMMIT=$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null || printf local-source); else COMMIT=local-source; fi
else
    TARGET_COMMIT=
    if [ "$BRANCH" = master ]; then
        TARGET_COMMIT=$(resolve_latest_commit)
        [ -n "$TARGET_COMMIT" ] || { printf 'ERROR: could not resolve tmux master commit.\n' >&2; exit 69; }
        printf 'LATEST_COMMIT: %s\n' "$TARGET_COMMIT"
    fi
    printf 'Downloading %s branch %s ...\n' "$GIT_URL" "$BRANCH"
    if ! git clone --quiet --branch "$BRANCH" --single-branch "$GIT_URL" "$SOURCE_DIR"; then
        printf 'ERROR: failed to download tmux branch %s from %s\n' "$BRANCH" "$GIT_URL" >&2
        exit 69
    fi
    if [ -n "$TARGET_COMMIT" ]; then
        if ! git -C "$SOURCE_DIR" checkout --quiet "$TARGET_COMMIT"; then
            printf 'ERROR: failed to check out synchronized latest commit %s\n' "$TARGET_COMMIT" >&2
            exit 69
        fi
    fi
    COMMIT=$(git -C "$SOURCE_DIR" rev-parse HEAD)
fi
printf 'SOURCE_COMMIT: %s\n' "$COMMIT"

if [ "$PATCHED" -eq 1 ]; then
    _pristine=$BUILD_DIR/.pristine-source
    mkdir -p "$_pristine"
    cp -R "$SOURCE_DIR"/. "$_pristine"/
    cp "$INTEGRATION" "$SOURCE_DIR/screen-to-tmux-translator"
    if ! patch -d "$SOURCE_DIR" -p1 --fuzz=0 --batch < "$TMUX_C_PATCH" > "$BUILD_DIR/patch.log" 2>&1; then
        cat "$BUILD_DIR/patch.log" >&2
        printf 'ERROR: Screen compatibility patch does not apply cleanly to tmux branch %s commit %s.\n' "$BRANCH" "$COMMIT" >&2
        printf 'Refusing to guess at a new tmux.c insertion point.\n' >&2
        exit 65
    fi
    if [ ! -e "$_pristine/tmux.c.orig" ]; then rm -f "$SOURCE_DIR/tmux.c.orig"; fi
    diff -qr "$_pristine" "$SOURCE_DIR" > "$BUILD_DIR/source-diff.txt" || :
    _diff_count=$(wc -l < "$BUILD_DIR/source-diff.txt" | awk '{print $1}')
    if [ "$_diff_count" -ne 2 ] || ! grep -q 'tmux.c differ' "$BUILD_DIR/source-diff.txt" || ! grep -q 'screen-to-tmux-translator' "$BUILD_DIR/source-diff.txt"; then
        printf 'ERROR: patched source footprint is not exactly one changed file plus one added translator file.\n' >&2
        cat "$BUILD_DIR/source-diff.txt" >&2
        exit 65
    fi
    rm -rf "$_pristine"
fi

run_logged()
{
    _label=$1; _log=$2; shift 2
    _rc_file=$BUILD_DIR/.build-$$.rc
    rm -f "$_rc_file"
    printf '\n===== %s =====\n' "$_label"
    (
        if "$@"; then _rc=0; else _rc=$?; fi
        printf '%s\n' "$_rc" > "$_rc_file"
        exit 0
    ) 2>&1 | tee "$_log"
    [ -r "$_rc_file" ] || { printf 'ERROR: could not recover build status for %s\n' "$_label" >&2; return 125; }
    _rc=$(cat "$_rc_file"); rm -f "$_rc_file"; return "$_rc"
}

build_tree()
{
    (
        set -e
        cd "$SOURCE_DIR"
        sh ./autogen.sh
        cd "$BUILD_DIR"
        "$SOURCE_DIR/configure" --prefix="$INSTALL_DIR"
        make -j"$JOBS"
        make install
    )
}

if ! run_logged "tmux $NAME${SUFFIX} build" "$BUILD_DIR/build.log" build_tree; then
    printf 'ERROR: tmux build failed. See %s\n' "$BUILD_DIR/build.log" >&2
    exit 1
fi

TMUX_BIN=$INSTALL_DIR/bin/tmux
[ -x "$TMUX_BIN" ] || { printf 'ERROR: build did not produce %s\n' "$TMUX_BIN" >&2; exit 1; }
SCREEN_BIN=
if [ "$PATCHED" -eq 1 ]; then
    SCREEN_BIN=$INSTALL_DIR/bin/screen
    rm -f "$SCREEN_BIN"
    ln "$TMUX_BIN" "$SCREEN_BIN"
    _inode_tmux=$(ls -di "$TMUX_BIN" | awk '{print $1}')
    _inode_screen=$(ls -di "$SCREEN_BIN" | awk '{print $1}')
    [ "$_inode_tmux" = "$_inode_screen" ] || { printf 'ERROR: %s is not a hardlink to %s\n' "$SCREEN_BIN" "$TMUX_BIN" >&2; exit 1; }
fi

TMUX_VERSION=$($TMUX_BIN -V 2>/dev/null || printf unknown)
cat > "$BUILD_DIR/BUILD-INFO" <<INFO
BUILD_NAME=tmux-$NAME$SUFFIX
SOURCE_URL=$GIT_URL
SOURCE_BRANCH=$BRANCH
SOURCE_COMMIT=$COMMIT
SOURCE_DIR=$SOURCE_DIR
BUILD_DIR=$BUILD_DIR
PATCHED=$PATCHED
TMUX_VERSION=$TMUX_VERSION
TMUX_BIN=$TMUX_BIN
SCREEN_BIN=$SCREEN_BIN
INFO

# If the counterpart build exists, require the same source commit for a useful
# original-vs-patched comparison.
if [ "$PATCHED" -eq 1 ]; then _counter=$BUILD_PARENT/build-tmux-$NAME; else _counter=$BUILD_PARENT/build-tmux-$NAME-patched; fi
if [ -r "$_counter/BUILD-INFO" ]; then
    _counter_commit=$(sed -n 's/^SOURCE_COMMIT=//p' "$_counter/BUILD-INFO" | head -1)
    if [ -n "$_counter_commit" ] && [ "$_counter_commit" != "$COMMIT" ]; then
        printf 'ERROR: counterpart build uses a different source commit (%s != %s).\n' "$_counter_commit" "$COMMIT" >&2
        printf 'Rebuild both %s variants so original and patched are directly comparable.\n' "$NAME" >&2
        exit 65
    fi
fi

printf '\nBuild complete.\n'
printf 'TMUX_VERSION: %s\n' "$TMUX_VERSION"
printf 'SOURCE_DIR: %s\n' "$SOURCE_DIR"
printf 'BUILD_DIR: %s\n' "$BUILD_DIR"
printf 'TMUX_BIN: %s\n' "$TMUX_BIN"
if [ -n "$SCREEN_BIN" ]; then printf 'SCREEN_BIN: %s\n' "$SCREEN_BIN"; fi
printf 'BUILD_INFO: %s\n' "$BUILD_DIR/BUILD-INFO"
printf '\nRun %s/run-tests.sh to automatically test any discovered patched builds.\n' "$PROJECT"
