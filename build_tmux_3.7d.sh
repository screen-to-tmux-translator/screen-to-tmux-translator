#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$HERE/scripts/build-tmux-variant.sh" release_3.7d tmux-3.7d
