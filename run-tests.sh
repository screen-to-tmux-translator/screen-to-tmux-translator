#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$HERE/tests/test-screen-cli.sh" "$@"
"$HERE/tests/test-regressions.sh" "$@"
