#!/bin/sh
# Compare any built patched tmux hardlink named "screen" with the canonical
# source translator over the full 683 dry-run placement matrix.
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$HERE/.." && pwd)
CANONICAL=${CANONICAL:-$PROJECT/bin/screen-function-source.sh}
CASES=${CASES:-$HERE/cases.sh}
WORKER=${WORKER:-$HERE/interface-equivalence-worker.sh}
RUN_TIMESTAMP=${SCREEN2TMUX_RUN_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}
LOG=${BUILT_SCREEN_LOG:-$PROJECT/logs/test-built-tmux-screen-$RUN_TIMESTAMP.log}

if [ "$#" -lt 1 ]; then
    printf '[SKIP] built tmux screen hardlink tests: no built screen binary supplied\n'
    mkdir -p "$(dirname -- "$LOG")"
    printf 'SKIP: no built screen binary supplied\n' > "$LOG"
    exit 0
fi

for _need in "$CANONICAL" "$CASES" "$WORKER"; do
    [ -r "$_need" ] || { printf 'ERROR: required test input missing: %s\n' "$_need" >&2; exit 2; }
done

mkdir -p "$(dirname -- "$LOG")"
: > "$LOG"
TMPBASE=${TMPDIR:-/tmp}/screen2tmux-built-screen-$$
rm -rf "$TMPBASE"
mkdir -p "$TMPBASE"
trap 'rm -rf "$TMPBASE"' EXIT HUP INT TERM
TAB=$(printf '\t')
PASS=0
FAIL=0
TOTAL=0

color=0
if [ -z "${NO_COLOR:-}" ]; then
    case "${SCREEN2TMUX_COLOR:-auto}" in
        always) color=1 ;;
        auto|'') [ -t 1 ] && [ "${TERM:-}" != dumb ] && color=1 ;;
    esac
fi
if [ "$color" -eq 1 ]; then G='\033[32m'; R='\033[31m'; C='\033[36m'; Z='\033[0m'; else G=; R=; C=; Z=; fi

EXPECTED=$TMPBASE/expected
EXPECTED_META=$TMPBASE/expected.tsv
"$WORKER" source-full "$CANONICAL" "$EXPECTED" "$CASES" "$EXPECTED_META"
EXPECTED_COUNT=$(cat "$EXPECTED/count")
if [ "$EXPECTED_COUNT" -ne 683 ]; then
    printf 'ERROR: canonical full matrix produced %s variants, expected 683\n' "$EXPECTED_COUNT" >&2
    exit 2
fi

printf 'built tmux screen hardlink test\n' >> "$LOG"
printf 'EXPECTED_VARIANTS: %s\n' "$EXPECTED_COUNT" >> "$LOG"

for SCREEN_BIN do
    if [ ! -x "$SCREEN_BIN" ]; then
        FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
        printf '%b[FAIL]%b built screen missing/not executable: %s\n' "$R" "$Z" "$SCREEN_BIN"
        printf 'BUILD\tFAIL\tmissing\t%s\n' "$SCREEN_BIN" >> "$LOG"
        continue
    fi
    case "$SCREEN_BIN" in
        */screen) : ;;
        *)
            FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
            printf '%b[FAIL]%b built binary basename is not screen: %s\n' "$R" "$Z" "$SCREEN_BIN"
            printf 'BUILD\tFAIL\tbasename\t%s\n' "$SCREEN_BIN" >> "$LOG"
            continue
            ;;
    esac

    BIN_DIR=$(CDPATH= cd -- "$(dirname -- "$SCREEN_BIN")" && pwd)
    SCREEN_BIN=$BIN_DIR/screen
    TMUX_BIN=$BIN_DIR/tmux
    LABEL=$(basename -- "$(dirname -- "$(dirname -- "$(dirname -- "$BIN_DIR")")")")
    [ -x "$TMUX_BIN" ] || {
        FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
        printf '%b[FAIL]%b sibling patched tmux missing: %s\n' "$R" "$Z" "$TMUX_BIN"
        printf 'BUILD\tFAIL\tmissing-tmux\t%s\n' "$SCREEN_BIN" >> "$LOG"
        continue
    }

    _it=$(ls -di "$TMUX_BIN" | awk '{print $1}')
    _is=$(ls -di "$SCREEN_BIN" | awk '{print $1}')
    TOTAL=$((TOTAL + 1))
    if [ "$_it" = "$_is" ]; then
        PASS=$((PASS + 1))
        printf '%b[PASS]%b %s screen is a hardlink to patched tmux\n' "$G" "$Z" "$LABEL"
        printf 'HARDLINK\tPASS\t%s\t%s\n' "$LABEL" "$SCREEN_BIN" >> "$LOG"
    else
        FAIL=$((FAIL + 1))
        printf '%b[FAIL]%b %s screen is not a hardlink to sibling tmux\n' "$R" "$Z" "$LABEL"
        printf 'HARDLINK\tFAIL\t%s\t%s\n' "$LABEL" "$SCREEN_BIN" >> "$LOG"
        continue
    fi

    ACTUAL=$TMPBASE/actual-$LABEL
    ACTUAL_META=$TMPBASE/actual-$LABEL.tsv
    SCREEN2TMUX_EQUIV_JOBS=${SCREEN2TMUX_BUILT_JOBS:-${SCREEN2TMUX_EQUIV_JOBS:-8}} \
        "$WORKER" standalone-full "$SCREEN_BIN" "$ACTUAL" "$CASES" "$ACTUAL_META"
    ACTUAL_COUNT=$(cat "$ACTUAL/count")
    if [ "$ACTUAL_COUNT" -ne "$EXPECTED_COUNT" ]; then
        FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
        printf '%b[FAIL]%b %s produced %s variants, expected %s\n' "$R" "$Z" "$LABEL" "$ACTUAL_COUNT" "$EXPECTED_COUNT"
        printf 'COUNT\tFAIL\t%s\t%s\t%s\n' "$LABEL" "$ACTUAL_COUNT" "$EXPECTED_COUNT" >> "$LOG"
        continue
    fi

    _current_id=
    _current_desc=
    _current_ok=1
    flush_matrix_case()
    {
        [ -n "$_current_id" ] || return 0
        if [ "$_current_ok" -eq 1 ]; then
            printf '%b[PASS]%b %s %s %s\n' "$G" "$Z" "$LABEL" "$_current_id" "$_current_desc"
        fi
    }

    while IFS="$TAB" read -r _base _id _place _desc; do
        if [ "$_id" != "$_current_id" ]; then
            flush_matrix_case
            _current_id=$_id
            _current_desc=$_desc
            _current_ok=1
        fi

        TOTAL=$((TOTAL + 1))
        _er=$(cat "$EXPECTED/$_base.rc")
        _ar=$(cat "$ACTUAL/$_base.rc")
        if [ "$_er" = "$_ar" ] && cmp -s "$EXPECTED/$_base.out" "$ACTUAL/$_base.out"; then
            PASS=$((PASS + 1))
            printf 'MATRIX\tPASS\t%s\t%s\t%s\t%s\n' "$LABEL" "$_id" "$_place" "$_er" >> "$LOG"
        else
            FAIL=$((FAIL + 1))
            _current_ok=0
            printf '%b[FAIL]%b %s %s placement=%s %s (rc expected=%s actual=%s)\n' "$R" "$Z" "$LABEL" "$_id" "$_place" "$_desc" "$_er" "$_ar"
            printf 'MATRIX\tFAIL\t%s\t%s\t%s\t%s\t%s\n' "$LABEL" "$_id" "$_place" "$_er" "$_ar" >> "$LOG"
        fi
    done < "$EXPECTED_META"
    flush_matrix_case

    # One real execution smoke test against an isolated default tmux socket.
    # This proves the hardlink does more than print the right dry-run output.
    RUNTIME=$TMPBASE/runtime-$LABEL
    mkdir -p "$RUNTIME/home" "$RUNTIME/tmux"
    chmod 700 "$RUNTIME/tmux"
    TOTAL=$((TOTAL + 1))
    if HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" NO_COLOR=1 SCREEN2TMUX_COLOR=never \
       "$SCREEN_BIN" -d -m >/dev/null 2>"$RUNTIME/screen.err" && \
       HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" list-sessions >/dev/null 2>"$RUNTIME/list.err"; then
        PASS=$((PASS + 1))
        printf '%b[PASS]%b %s real screen hardlink execution created an isolated tmux session\n' "$G" "$Z" "$LABEL"
        printf 'EXEC\tPASS\t%s\n' "$LABEL" >> "$LOG"
    else
        FAIL=$((FAIL + 1))
        printf '%b[FAIL]%b %s real screen hardlink execution smoke test failed\n' "$R" "$Z" "$LABEL"
        printf 'EXEC\tFAIL\t%s\n' "$LABEL" >> "$LOG"
    fi
    HOME="$RUNTIME/home" TMUX_TMPDIR="$RUNTIME/tmux" "$TMUX_BIN" kill-server >/dev/null 2>&1 || :
done

printf 'SUMMARY: pass=%s fail=%s total=%s expected_variants=%s\n' "$PASS" "$FAIL" "$TOTAL" "$EXPECTED_COUNT" >> "$LOG"
printf '\n%bBuilt screen summary:%b %s %bPASS%b, %s %bFAIL%b, %s comparisons/checks\n' "$C" "$Z" "$PASS" "$G" "$Z" "$FAIL" "$R" "$Z" "$TOTAL"
printf '%bBuilt screen log:%b %s\n' "$C" "$Z" "$LOG"
[ "$FAIL" -eq 0 ]
