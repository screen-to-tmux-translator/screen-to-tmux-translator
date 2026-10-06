#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$HERE/scripts/build-tmux-one.sh" release_3.7d 3.7d 0
