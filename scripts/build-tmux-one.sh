#!/bin/sh
# Build one pristine or Screen-compat tmux tree. POSIX sh.
# Sources live under src/ and build/install artifacts under build/ by default.
set -eu

if [ "$#" -ne 3 ]; then
    printf 'usage: %s VERSION_OR_REF NAME PATCHED(0|1)\n' "$0" >&2
    exit 64
fi

REQUESTED_REF=$1
NAME=$2
PATCHED=$3
case "$PATCHED" in 0|1) : ;; *) printf 'ERROR: PATCHED must be 0 or 1.\n' >&2; exit 64 ;; esac

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SOURCE_PARENT=${SCREEN2TMUX_SOURCE_ROOT:-$PROJECT/src}
BUILD_PARENT=${SCREEN2TMUX_BUILD_ROOT:-$PROJECT/build}
VERBOSITY=${SCREEN2TMUX_BUILD_VERBOSITY:-normal}
case "$VERBOSITY" in quiet|normal|verbose) : ;; *) printf 'ERROR: build verbosity must be quiet, normal, or verbose (got: %s)\n' "$VERBOSITY" >&2; exit 64 ;; esac
SUFFIX=
[ "$PATCHED" -eq 1 ] && SUFFIX=-patched
SOURCE_DIR=$SOURCE_PARENT/tmux-$NAME$SUFFIX
BUILD_DIR=$BUILD_PARENT/tmux-$NAME$SUFFIX
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

case "${SCREEN2TMUX_COLOR:-auto}" in auto|'') COLOR_MODE=auto ;; always) COLOR_MODE=always ;; never) COLOR_MODE=never ;; *) printf 'ERROR: SCREEN2TMUX_COLOR must be auto, always, or never.\n' >&2; exit 64 ;; esac
COLOR_ENABLED=0
if [ -z "${NO_COLOR:-}" ]; then
    case "$COLOR_MODE" in always) COLOR_ENABLED=1 ;; auto) [ -t 1 ] && [ "${TERM:-}" != dumb ] && COLOR_ENABLED=1 ;; esac
fi
if [ "$COLOR_ENABLED" -eq 1 ]; then
    G=$(printf '\033[32m'); R=$(printf '\033[31m'); Y=$(printf '\033[33m'); C=$(printf '\033[36m'); Z=$(printf '\033[0m')
else G=; R=; Y=; C=; Z=; fi

say_label() { printf '%s%s%s: %s\n' "$C" "$1" "$Z" "$2"; }
say_ok() { printf '%s[OK]%s %s\n' "$G" "$Z" "$1"; }
say_fail() { printf '%s[FAIL]%s %s\n' "$R" "$Z" "$1" >&2; }

if command -v getconf >/dev/null 2>&1; then _jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2'); else _jobs=2; fi
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
need_cmd() { command -v "$1" >/dev/null 2>&1 || MISSING_CMDS="$MISSING_CMDS $1"; }
check_dependencies()
{
    MISSING_CMDS=; MISSING_LIBS=
    need_cmd sh; need_cmd make; need_cmd "$CC_BIN"; need_cmd pkg-config; need_cmd autoconf; need_cmd automake
    need_cmd aclocal; need_cmd autoreconf; need_cmd patch; need_cmd tar; need_cmd awk; need_cmd sed; need_cmd grep
    need_cmd diff; need_cmd cmp; need_cmd ln; need_cmd id
    [ -n "${TMUX_SOURCE_DIR:-}" ] || need_cmd git
    if ! command -v yacc >/dev/null 2>&1 && ! command -v bison >/dev/null 2>&1; then MISSING_CMDS="$MISSING_CMDS yacc-or-bison"; fi
    if command -v pkg-config >/dev/null 2>&1; then
        pkg-config --exists 'libevent_core >= 2' 2>/dev/null || pkg-config --exists 'libevent >= 2' 2>/dev/null || MISSING_LIBS="$MISSING_LIBS libevent-2.x-development"
        pkg-config --exists tinfow 2>/dev/null || pkg-config --exists tinfo 2>/dev/null || pkg-config --exists ncursesw 2>/dev/null || pkg-config --exists ncurses 2>/dev/null || MISSING_LIBS="$MISSING_LIBS ncurses/terminfo-development"
    else
        MISSING_LIBS="$MISSING_LIBS libevent-2.x-development ncurses/terminfo-development"
    fi
}
have_missing_dependencies() { [ -n "$MISSING_CMDS$MISSING_LIBS" ]; }
detect_package_manager()
{
    if [ -n "${SCREEN2TMUX_PACKAGE_MANAGER:-}" ]; then
        case "$SCREEN2TMUX_PACKAGE_MANAGER" in apt-get|dnf|yum|apk|brew) PACKAGE_MANAGER=$SCREEN2TMUX_PACKAGE_MANAGER ;; *) printf 'ERROR: unsupported SCREEN2TMUX_PACKAGE_MANAGER=%s\n' "$SCREEN2TMUX_PACKAGE_MANAGER" >&2; return 1 ;; esac
        command -v "$PACKAGE_MANAGER" >/dev/null 2>&1 || { printf 'ERROR: requested package manager is not installed: %s\n' "$PACKAGE_MANAGER" >&2; return 1; }
        return 0
    fi
    for _pm in apt-get dnf yum apk brew; do command -v "$_pm" >/dev/null 2>&1 && { PACKAGE_MANAGER=$_pm; return 0; }; done
    PACKAGE_MANAGER=; return 1
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
    else printf 'ERROR: installing packages with %s requires root privileges or sudo.\n' "$PACKAGE_MANAGER" >&2; return 1; fi
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
    printf 'Detected package manager: %s\nPackages requested: %s\n' "$PACKAGE_MANAGER" "$_packages" >&2
    case "$PACKAGE_MANAGER" in
        apt-get) run_privileged apt-get update; run_privileged apt-get install -y $_packages ;;
        dnf) run_privileged dnf install -y $_packages ;;
        yum) run_privileged yum install -y $_packages ;;
        apk) run_privileged apk add $_packages ;;
        brew) brew install $_packages ;;
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
    if have_missing_dependencies; then print_missing_dependencies; printf 'ERROR: dependencies are still incomplete after package installation.\n' >&2; exit 2; fi
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

printf '%stmux build%s\n' "$C" "$Z"
say_label VERSION "$REQUESTED_REF"
say_label NAME "$NAME"
say_label PATCHED "$PATCHED"
say_label VERBOSITY "$VERBOSITY"
say_label SOURCE_DIR "$SOURCE_DIR"
say_label BUILD_DIR "$BUILD_DIR"
say_label JOBS "$JOBS"

resolve_checkout()
{
    _rr=$1
    if [ -n "${TMUX_PIN_COMMIT:-}" ]; then printf '%s\n' "$TMUX_PIN_COMMIT"; return 0; fi
    if [ "$_rr" = latest ]; then
        for _c in origin/master origin/main master main; do git -C "$SOURCE_DIR" rev-parse --verify "$_c^{commit}" 2>/dev/null && return 0; done
        return 1
    fi
    # Accept an exact tag/branch/commit first, then the historical tmux
    # release_VERSION branch convention used by development branches.
    for _c in "origin/release_$_rr" "refs/tags/$_rr" "origin/$_rr" "$_rr" "refs/tags/tmux-$_rr" "refs/tags/v$_rr"; do
        git -C "$SOURCE_DIR" rev-parse --verify "$_c^{commit}" 2>/dev/null && return 0
    done
    return 1
}

if [ -n "${TMUX_SOURCE_DIR:-}" ]; then
    [ -d "$TMUX_SOURCE_DIR" ] || { printf 'ERROR: TMUX_SOURCE_DIR is not a directory: %s\n' "$TMUX_SOURCE_DIR" >&2; exit 2; }
    say_label SOURCE "local override $TMUX_SOURCE_DIR"
    mkdir -p "$SOURCE_DIR"
    cp -R "$TMUX_SOURCE_DIR"/. "$SOURCE_DIR"/
    if [ -d "$SOURCE_DIR/.git" ] && command -v git >/dev/null 2>&1; then COMMIT=$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null || printf local-source); else COMMIT=local-source; fi
    RESOLVED_REF=local-source
else
    say_label DOWNLOAD "$GIT_URL"
    if ! git clone --quiet "$GIT_URL" "$SOURCE_DIR"; then printf 'ERROR: failed to download tmux from %s\n' "$GIT_URL" >&2; exit 69; fi
    if ! COMMIT=$(resolve_checkout "$REQUESTED_REF"); then
        printf 'ERROR: could not resolve tmux version/ref %s.\n' "$REQUESTED_REF" >&2
        printf 'Tried exact tag/branch/commit plus release_%s.\n' "$REQUESTED_REF" >&2
        exit 69
    fi
    if ! git -C "$SOURCE_DIR" checkout --quiet --detach "$COMMIT"; then printf 'ERROR: failed to check out tmux commit %s\n' "$COMMIT" >&2; exit 69; fi
    RESOLVED_REF=$REQUESTED_REF
fi
say_label SOURCE_COMMIT "$COMMIT"

if [ "$PATCHED" -eq 1 ]; then
    _pristine=$BUILD_DIR/.pristine-source
    mkdir -p "$_pristine"
    cp -R "$SOURCE_DIR"/. "$_pristine"/
    cp "$INTEGRATION" "$SOURCE_DIR/screen-to-tmux-translator"
    if ! patch -d "$SOURCE_DIR" -p1 --fuzz=0 --batch < "$TMUX_C_PATCH" > "$BUILD_DIR/patch.log" 2>&1; then
        cat "$BUILD_DIR/patch.log" >&2
        printf 'ERROR: Screen compatibility patch does not apply cleanly to tmux %s commit %s.\n' "$REQUESTED_REF" "$COMMIT" >&2
        printf 'Refusing to guess at a new tmux.c insertion point.\n' >&2
        exit 65
    fi
    [ -e "$_pristine/tmux.c.orig" ] || rm -f "$SOURCE_DIR/tmux.c.orig"
    diff -qr "$_pristine" "$SOURCE_DIR" > "$BUILD_DIR/source-diff.txt" || :
    _diff_count=$(wc -l < "$BUILD_DIR/source-diff.txt" | awk '{print $1}')
    if [ "$_diff_count" -ne 2 ] || ! grep -q 'tmux.c differ' "$BUILD_DIR/source-diff.txt" || ! grep -q 'screen-to-tmux-translator' "$BUILD_DIR/source-diff.txt"; then
        printf 'ERROR: patched source footprint is not exactly one changed file plus one added translator file.\n' >&2
        cat "$BUILD_DIR/source-diff.txt" >&2
        exit 65
    fi
    rm -rf "$_pristine"
    say_ok 'Screen compatibility patch applied'
fi

CC_WRAPPER=$BUILD_DIR/.screen2tmux-cc
cat > "$CC_WRAPPER" <<'CCWRAP'
#!/bin/sh
real=${SCREEN2TMUX_REAL_CC:?}
progress=${SCREEN2TMUX_CC_PROGRESS:-0}
compile=0
src=
for arg do
    [ "$arg" = -c ] && compile=1
    case "$arg" in *.c|*.cc|*.cpp|*.cxx) src=$arg ;; esac
done
if [ "$progress" = 1 ] && [ "$compile" = 1 ]; then
    if "$real" "$@"; then
        printf '@@S2T_COMPILE_OK\t%s\n' "${src##*/}"
        exit 0
    else
        rc=$?
        printf '@@S2T_COMPILE_FAIL\t%s\n' "${src##*/}" >&2
        exit "$rc"
    fi
fi
exec "$real" "$@"
CCWRAP
chmod 755 "$CC_WRAPPER"

render_build_stream()
{
    case "$VERBOSITY" in
        verbose)
            awk 'index($0,"@@S2T_")==1 { next } { print }'
            ;;
        quiet)
            awk '
            /^@@S2T_STAGE_OK\t/ { sub(/^@@S2T_STAGE_OK\t/, ""); print "[OK] " $0; next }
            /^@@S2T_STAGE_FAIL\t/ { sub(/^@@S2T_STAGE_FAIL\t/, ""); print "[FAIL] " $0; next }
            /(^|[^A-Za-z])(error:|ERROR:|fatal:)/ { print; next }
            '
            ;;
        normal)
            awk '
            /^@@S2T_STAGE_BEGIN\t/ { sub(/^@@S2T_STAGE_BEGIN\t/, ""); print $0 " ..."; next }
            /^@@S2T_STAGE_OK\t/ { sub(/^@@S2T_STAGE_OK\t/, ""); print "[OK] " $0; next }
            /^@@S2T_STAGE_FAIL\t/ { sub(/^@@S2T_STAGE_FAIL\t/, ""); print "[FAIL] " $0; next }
            /^@@S2T_COMPILE_OK\t/ { sub(/^@@S2T_COMPILE_OK\t/, ""); print "Compiling " $0 " ... [OK]"; next }
            /^@@S2T_COMPILE_FAIL\t/ { sub(/^@@S2T_COMPILE_FAIL\t/, ""); print "Compiling " $0 " ... [FAIL]"; next }
            /(^|[^A-Za-z])(warning:|WARNING:)/ { print; next }
            /(^|[^A-Za-z])(error:|ERROR:|fatal:)/ { print; next }
            '
            ;;
    esac | color_build_stream
}

color_build_stream()
{
    if [ "$COLOR_ENABLED" -ne 1 ]; then cat; return; fi
    awk -v G="$G" -v R="$R" -v Y="$Y" -v C="$C" -v Z="$Z" '
    {
        line=$0
        gsub(/\[OK\]/, G "[OK]" Z, line)
        gsub(/\[FAIL\]/, R "[FAIL]" Z, line)
        sub(/^Compiling /, C "Compiling" Z " ", line)
        sub(/^WARNING:/, Y "WARNING" Z ":", line)
        sub(/^ERROR:/, R "ERROR" Z ":", line)
        print line
    }'
}

run_logged()
{
    _label=$1; _log=$2; shift 2
    _rc_file=$BUILD_DIR/.build-$$.rc
    rm -f "$_rc_file"
    (
        if "$@"; then _rc=0; else _rc=$?; fi
        printf '%s\n' "$_rc" > "$_rc_file"
        exit 0
    ) 2>&1 | tee "$_log" | render_build_stream
    [ -r "$_rc_file" ] || { printf 'ERROR: could not recover build status for %s\n' "$_label" >&2; return 125; }
    _rc=$(cat "$_rc_file"); rm -f "$_rc_file"; return "$_rc"
}

stage()
{
    _name=$1; shift
    printf '@@S2T_STAGE_BEGIN\t%s\n' "$_name"
    if "$@"; then printf '@@S2T_STAGE_OK\t%s\n' "$_name"; return 0; fi
    _rc=$?; printf '@@S2T_STAGE_FAIL\t%s\n' "$_name" >&2; return "$_rc"
}

autogen_stage() { cd "$SOURCE_DIR" && sh ./autogen.sh; }
configure_stage() { cd "$BUILD_DIR" && SCREEN2TMUX_REAL_CC="$CC_BIN" "$SOURCE_DIR/configure" CC="$CC_WRAPPER" --prefix="$INSTALL_DIR"; }
compile_stage() { cd "$BUILD_DIR" && SCREEN2TMUX_REAL_CC="$CC_BIN" SCREEN2TMUX_CC_PROGRESS=1 make -j"$JOBS"; }
install_stage() { cd "$BUILD_DIR" && SCREEN2TMUX_REAL_CC="$CC_BIN" make install; }
build_tree()
{
    stage 'Generating build system' autogen_stage || return $?
    stage 'Configuring tmux' configure_stage || return $?
    stage 'Compiling tmux' compile_stage || return $?
    stage 'Installing tmux' install_stage || return $?
}

if ! run_logged "tmux $NAME${SUFFIX} build" "$BUILD_DIR/build.log" build_tree; then
    say_fail "tmux $NAME${SUFFIX} build failed; see $BUILD_DIR/build.log"
    exit 1
fi
rm -f "$CC_WRAPPER"

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
REQUESTED_VERSION=$REQUESTED_REF
RESOLVED_REF=$RESOLVED_REF
SOURCE_URL=$GIT_URL
SOURCE_COMMIT=$COMMIT
SOURCE_DIR=$SOURCE_DIR
BUILD_DIR=$BUILD_DIR
PATCHED=$PATCHED
TMUX_VERSION=$TMUX_VERSION
TMUX_BIN=$TMUX_BIN
SCREEN_BIN=$SCREEN_BIN
INFO

if [ "$PATCHED" -eq 1 ]; then _counter=$BUILD_PARENT/tmux-$NAME; else _counter=$BUILD_PARENT/tmux-$NAME-patched; fi
if [ -r "$_counter/BUILD-INFO" ]; then
    _counter_commit=$(sed -n 's/^SOURCE_COMMIT=//p' "$_counter/BUILD-INFO" | head -1)
    if [ -n "$_counter_commit" ] && [ "$_counter_commit" != "$COMMIT" ]; then
        printf 'ERROR: counterpart build uses a different source commit (%s != %s).\n' "$_counter_commit" "$COMMIT" >&2
        printf 'Rebuild both %s variants so original and patched are directly comparable.\n' "$NAME" >&2
        exit 65
    fi
fi

printf '\n%sBuild complete.%s\n' "$G" "$Z"
say_label TMUX_VERSION "$TMUX_VERSION"
say_label SOURCE_DIR "$SOURCE_DIR"
say_label BUILD_DIR "$BUILD_DIR"
say_label TMUX_BIN "$TMUX_BIN"
[ -z "$SCREEN_BIN" ] || say_label SCREEN_BIN "$SCREEN_BIN"
say_label BUILD_INFO "$BUILD_DIR/BUILD-INFO"
