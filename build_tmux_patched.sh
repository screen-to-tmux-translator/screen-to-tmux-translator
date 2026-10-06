#!/bin/sh
# Build only Screen-compat patched tmux copies. POSIX sh.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "${1:-}" in
    -h|--help)
        cat <<'USAGE'
Usage: sh build_tmux_patched.sh [--verbosity quiet|normal|verbose] [VERSION ...]

Builds only the Screen-compat patched variant of every requested tmux version.
VERSION may be comma-separated or supplied as separate arguments. With no
VERSION, the project-pinned 3.7c release baseline is built. "latest" resolves the current tmux master/main commit.

Examples:
  sh build_tmux_patched.sh
  sh build_tmux_patched.sh latest
  sh build_tmux_patched.sh 3.7c,latest
USAGE
        exit 0
        ;;
esac
SCREEN2TMUX_PATCHED_ONLY=1
export SCREEN2TMUX_PATCHED_ONLY
exec sh "$HERE/build_tmux.sh" "$@"
