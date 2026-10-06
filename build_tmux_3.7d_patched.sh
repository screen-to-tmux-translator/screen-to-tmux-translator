#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sh "$HERE/scripts/build-tmux-one.sh" 3.7d 3.7d 1
