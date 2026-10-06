#!/bin/sh
# Build pristine tmux 3.7c using the project release baseline. POSIX sh.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sh "$HERE/scripts/build-tmux-one.sh" 3.7c 3.7c 0
