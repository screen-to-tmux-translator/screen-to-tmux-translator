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
TMUX_3_7C_PIN=${SCREEN2TMUX_TMUX_3_7C_PIN:-refs/tags/3.7c}
TMUX_3_7D_PIN=${SCREEN2TMUX_TMUX_3_7D_PIN:-e9634d40749a5ae330aabf5aa46a81505b094a6b}
INTEGRATION=$PROJECT/tmux-integration/screen-compat.c
TMUX_PATCH=$PROJECT/tmux-integration/tmux-screen-compat.patch
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

DISPLAY_WIDTH=${SCREEN2TMUX_CONSOLE_WIDTH:-}
if [ -z "$DISPLAY_WIDTH" ]; then
    if [ -r /dev/tty ] && command -v stty >/dev/null 2>&1; then
        _display_size=$(stty size </dev/tty 2>/dev/null || :)
        case "$_display_size" in *' '*) DISPLAY_WIDTH=${_display_size#* } ;; esac
    fi
    [ -n "$DISPLAY_WIDTH" ] || DISPLAY_WIDTH=${COLUMNS:-120}
fi
case "$DISPLAY_WIDTH" in ''|*[!0-9]*) DISPLAY_WIDTH=120 ;; esac
[ "$DISPLAY_WIDTH" -ge 40 ] 2>/dev/null || DISPLAY_WIDTH=120

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

print_dependency_install_command()
{
    _packages=$(package_list_for_manager "$PACKAGE_MANAGER") || return 1
    case "$PACKAGE_MANAGER" in
        apt-get)
            printf 'If you do not have administrator rights, ask an administrator to run:\n' >&2
            printf '  sudo apt-get update && sudo apt-get install -y %s\n' "$_packages" >&2
            printf '  (or run the same apt-get commands directly from a root shell)\n' >&2
            ;;
        dnf)
            printf 'If you do not have administrator rights, ask an administrator to run:\n' >&2
            printf '  sudo dnf install -y %s\n' "$_packages" >&2
            printf '  (or run dnf directly from a root shell)\n' >&2
            ;;
        yum)
            printf 'If you do not have administrator rights, ask an administrator to run:\n' >&2
            printf '  sudo yum install -y %s\n' "$_packages" >&2
            printf '  (or run yum directly from a root shell)\n' >&2
            ;;
        apk)
            printf 'If you do not have administrator rights, ask an administrator to run:\n' >&2
            printf '  sudo apk add %s\n' "$_packages" >&2
            printf '  (or run apk directly from a root shell)\n' >&2
            ;;
        brew)
            printf 'Install the missing Homebrew build dependencies with:\n' >&2
            printf '  brew install %s\n' "$_packages" >&2
            ;;
    esac
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
    printf 'Install the missing build software automatically and continue? This may invoke sudo. [y/N] ' >&2
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
    print_dependency_install_command
    printf 'After the missing software is installed, rerun the same build command.\n' >&2
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
    [ -r "$TMUX_PATCH" ] || { printf 'ERROR: missing tmux integration patch: %s\n' "$TMUX_PATCH" >&2; exit 2; }
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
case "$REQUESTED_REF" in
    3.7c|release_3.7c) [ -n "${TMUX_PIN_COMMIT:-}" ] || say_label SOURCE_PIN "$TMUX_3_7C_PIN (project 3.7c release-tag baseline)" ;;
    3.7d|release_3.7d) [ -n "${TMUX_PIN_COMMIT:-}" ] || say_label SOURCE_PIN "$TMUX_3_7D_PIN (project 3.7d archived baseline)" ;;
esac

resolve_checkout()
{
    _rr=$1
    if [ -n "${TMUX_PIN_COMMIT:-}" ]; then printf '%s\n' "$TMUX_PIN_COMMIT"; return 0; fi

    # 3.7c is the default released baseline. The project pins that request to
    # the release tag rather than following origin/release_3.7c. The resolved
    # commit is checked out detached and recorded in BUILD-INFO. An exact commit
    # may be supplied with SCREEN2TMUX_TMUX_3_7C_PIN or TMUX_PIN_COMMIT for
    # content-addressed audits. The supplied 3.7d archive remains pinned to its
    # verified exact commit for historical reproducibility.
    case "$_rr" in
        3.7c|release_3.7c)
            git -C "$SOURCE_DIR" rev-parse --verify "$TMUX_3_7C_PIN^{commit}" 2>/dev/null && return 0
            return 1
            ;;
        3.7d|release_3.7d) printf '%s\n' "$TMUX_3_7D_PIN"; return 0 ;;
    esac

    if [ "$_rr" = latest ]; then
        for _c in origin/master origin/main master main; do git -C "$SOURCE_DIR" rev-parse --verify "$_c^{commit}" 2>/dev/null && return 0; done
        return 1
    fi

    # For other requests prefer immutable-looking exact tags/commits before
    # mutable branch names, then try tmux's historical release_VERSION branch.
    for _c in "refs/tags/$_rr" "refs/tags/tmux-$_rr" "refs/tags/v$_rr" "$_rr" "origin/$_rr" "origin/release_$_rr"; do
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
        case "$REQUESTED_REF" in
            3.7c|release_3.7c) printf 'Tried pinned tmux 3.7c release ref %s.\n' "$TMUX_3_7C_PIN" >&2 ;;
            3.7d|release_3.7d) printf 'Tried pinned tmux 3.7d commit %s.\n' "$TMUX_3_7D_PIN" >&2 ;;
            latest) printf 'Tried upstream master/main refs.\n' >&2 ;;
            *) printf 'Tried exact tag/commit/branch refs plus release_%s.\n' "$REQUESTED_REF" >&2 ;;
        esac
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
    cp "$INTEGRATION" "$SOURCE_DIR/screen-compat.c"
    if ! patch -d "$SOURCE_DIR" -p1 --fuzz=0 --batch < "$TMUX_PATCH" > "$BUILD_DIR/patch.log" 2>&1; then
        cat "$BUILD_DIR/patch.log" >&2
        printf 'ERROR: Screen compatibility patch does not apply cleanly to tmux %s commit %s.\n' "$REQUESTED_REF" "$COMMIT" >&2
        printf 'Refusing to guess at new tmux source integration points.\n' >&2
        exit 65
    fi
    for _patched_file in Makefile.am tmux.h tmux.c; do
        [ -e "$_pristine/$_patched_file.orig" ] || rm -f "$SOURCE_DIR/$_patched_file.orig"
    done
    diff -qr "$_pristine" "$SOURCE_DIR" > "$BUILD_DIR/source-diff.txt" || :
    _diff_count=$(wc -l < "$BUILD_DIR/source-diff.txt" | awk '{print $1}')
    if [ "$_diff_count" -ne 4 ] || \
       ! grep -q 'Makefile.am differ' "$BUILD_DIR/source-diff.txt" || \
       ! grep -q 'tmux.c differ' "$BUILD_DIR/source-diff.txt" || \
       ! grep -q 'tmux.h differ' "$BUILD_DIR/source-diff.txt" || \
       ! grep -q 'screen-compat.c' "$BUILD_DIR/source-diff.txt"; then
        printf 'ERROR: patched source footprint is not exactly three changed tmux files plus screen-compat.c.\n' >&2
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
            awk 'index($0,"@@S2T_")==1 { next } { print; fflush() }'
            ;;
        quiet)
            awk '
            /^@@S2T_STAGE_OK\t/ { sub(/^@@S2T_STAGE_OK\t/, ""); print "[OK] " $0; fflush(); next }
            /^@@S2T_STAGE_FAIL\t/ { sub(/^@@S2T_STAGE_FAIL\t/, ""); print "[FAIL] " $0; fflush(); next }
            /(^|[^A-Za-z])(error:|ERROR:|fatal:)/ { print; fflush(); next }
            '
            ;;
        normal)
            awk -v width="$DISPLAY_WIDTH" -v realcc="$CC_BIN" '
            function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
            function emit(s) { print s; fflush() }
            function clean_name(name,    hadlib) {
                name = trim(name)
                sub(/^for /, "", name)
                sub(/^whether /, "", name)
                gsub(/[^[:space:]]*\/\.screen2tmux-cc/, "C compiler", name)
                sub(/ usability$/, "", name)
                sub(/ presence$/, "", name)
                sub(/^working /, "", name)
                if (name == "a BSD-compatible install") name = "install"
                else if (name == "a thread-safe mkdir -p") name = "mkdir -p"
                else if (name == "gawk") name = "awk"
                else if (name == "gcc") name = "C compiler"
                else if (name == "build environment is sane") name = "build environment sane"
                else if (name == "we are cross compiling") name = "cross compiling"
                else if (name == "we are using the GNU C compiler") name = "GNU C compiler"
                else if (name == "build system type") name = "build"
                else if (name == "host system type") name = "host"
                else if (name == "that generated files are newer than configure") name = "generated files newer than configure"
                else if (name == "C compiler default output file name") name = "compiler output"
                else if (name == "suffix of executables") name = "executable suffix"
                else if (name == "suffix of object files") name = "object suffix"
                else if (name == "C compiler option to accept ISO C89") name = "C89 mode"
                else if (name == "C compiler option to accept ISO C99") name = "C99 mode"
                else if (name == "dependency style of C compiler") name = "dependency style"
                else if (name == "how to run the C preprocessor") name = "C preprocessor"
                else if (name == "grep that handles long lines and -e") name = "grep"
                else if (name == "pkg-config is at least version 0.9.0") name = "pkg-config >= 0.9.0"
                else if (name == "it is safe to define __EXTENSIONS__") name = "safe to define __EXTENSIONS__"
                else if (name ~ /^if free doesn.t work very well$/) name = "free workaround needed"
                if (name ~ /^library containing /) { sub(/^library containing /, "", name); name = name " library" }
                gsub(/ is declared$/, " declared", name)
                return trim(name)
            }
            function clean_value(value) {
                value = trim(value)
                sub(/^\(cached\)[[:space:]]*/, "", value)
                gsub(/[^[:space:]]*\/\.screen2tmux-cc/, realcc, value)
                return value
            }
            function add_cfg(kind, name, value,    key) {
                name = clean_name(name)
                value = clean_value(value)
                if (name == "C compiler" && value != "yes" && value != "no") value = realcc
                key = name SUBSEP value
                if (kind == "yes") { if (!seen_yes[name]++) yes[++ny] = name }
                else if (kind == "no") { if (!seen_no[name]++) no[++nn] = name }
                else if (!seen_values[key]++) values[++nv] = name "=" value
            }
            function emit_items(label, a, n, sep,    i,prefix,indent,line,piece,item) {
                if (n == 0) return
                prefix = label ": "
                indent = sprintf("%*s", length(prefix), "")
                line = prefix
                for (i = 1; i <= n; i++) {
                    item = a[i]
                    piece = (line == prefix ? "" : sep) item
                    if (length(line) > length(prefix) && length(line) + length(piece) > width) {
                        emit(line)
                        line = indent item
                    } else line = line piece
                }
                emit(line)
            }
            function add_compile(item,    prefix,indent,piece) {
                prefix = "Compiling "
                indent = sprintf("%*s", length(prefix), "")
                if (compile_line == "") {
                    compile_line = prefix item
                    return
                }
                piece = " " item
                if (length(compile_line) + length(piece) > width) {
                    emit(compile_line)
                    compile_line = indent item
                } else compile_line = compile_line piece
            }
            function emit_compile() {
                if (compile_line == "") return
                emit(compile_line)
                compile_line = ""
            }
            function flush_cfg() {
                emit_items("Configure yes", yes, ny, "  ")
                emit_items("Configure no", no, nn, "  ")
                emit_items("Configure values", values, nv, ", ")
                delete yes; delete no; delete values
                delete seen_yes; delete seen_no; delete seen_values
                ny=nn=nv=0
            }
            function capture_cfg(line,    p,name,value) {
                if (!in_cfg || line !~ /^checking /) return 0
                p = index(line, "... ")
                if (!p) return 0
                name = substr(line, 10, p - 10)
                value = clean_value(substr(line, p + 4))
                name = clean_name(name)
                if (value == "yes") add_cfg("yes", name, value)
                else if (value == "no") add_cfg("no", name, value)
                else add_cfg("value", name, value)
                return 1
            }
            /^@@S2T_STAGE_BEGIN\t/ {
                sub(/^@@S2T_STAGE_BEGIN\t/, "")
                in_cfg = ($0 == "Configuring tmux")
                in_compile = ($0 == "Compiling tmux")
                emit($0 " ...")
                next
            }
            /^@@S2T_STAGE_OK\t/ {
                sub(/^@@S2T_STAGE_OK\t/, "")
                if ($0 == "Configuring tmux") flush_cfg()
                if ($0 == "Compiling tmux") emit_compile()
                in_cfg = 0; in_compile = 0
                emit("[OK] " $0)
                next
            }
            /^@@S2T_STAGE_FAIL\t/ {
                sub(/^@@S2T_STAGE_FAIL\t/, "")
                if ($0 == "Configuring tmux") flush_cfg()
                if ($0 == "Compiling tmux") emit_compile()
                in_cfg = 0; in_compile = 0
                emit("[FAIL] " $0)
                next
            }
            /^@@S2T_COMPILE_OK\t/ { sub(/^@@S2T_COMPILE_OK\t/, ""); add_compile($0 " ... [OK]"); next }
            /^@@S2T_COMPILE_FAIL\t/ { sub(/^@@S2T_COMPILE_FAIL\t/, ""); add_compile($0 " ... [FAIL]"); next }
            { if (capture_cfg($0)) next }
            /(^|[^A-Za-z])(warning:|WARNING:)/ { if (in_compile) emit_compile(); emit($0); next }
            /(^|[^A-Za-z])(error:|ERROR:|fatal:)/ { if (in_compile) emit_compile(); emit($0); next }
            '
            ;;
    esac | color_build_stream
}

color_build_stream()
{
    if [ "$COLOR_ENABLED" -ne 1 ]; then cat; return; fi
    awk -v G="$G" -v R="$R" -v Y="$Y" -v C="$C" -v Z="$Z" '
    function emit(s) { print s; fflush() }
    {
        line=$0
        if (line ~ /^Configure yes:/) {
            p=index(line,":"); emit(C substr(line,1,p-1) Z ":" G substr(line,p+1) Z); cfg="yes"; next
        }
        if (line ~ /^Configure no:/) {
            p=index(line,":"); emit(C substr(line,1,p-1) Z ":" R substr(line,p+1) Z); cfg="no"; next
        }
        if (line ~ /^Configure values:/) {
            p=index(line,":"); emit(C substr(line,1,p-1) Z substr(line,p)); cfg="values"; next
        }
        if (cfg != "" && line ~ /^ +/) {
            if (cfg == "yes") emit(G line Z)
            else if (cfg == "no") emit(R line Z)
            else emit(line)
            next
        }
        cfg=""
        gsub(/\[OK\]/, G "[OK]" Z, line)
        gsub(/\[FAIL\]/, R "[FAIL]" Z, line)
        sub(/^Compiling /, C "Compiling" Z " ", line)
        sub(/^WARNING:/, Y "WARNING" Z ":", line)
        sub(/^ERROR:/, R "ERROR" Z ":", line)
        emit(line)
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
TMUX_3_7D_DEFAULT_PIN=$TMUX_3_7D_PIN
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
