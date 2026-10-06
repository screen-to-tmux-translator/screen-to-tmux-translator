#!/bin/sh
# Compare every selected Screen compatibility interface with the canonical
# sourced function over the complete first/middle/last placement matrix.
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
CANONICAL=${CANONICAL_SOURCE:-$PROJECT/bin/screen-function-source.sh}
MINIFIED=${MINIFIED_SOURCE:-$PROJECT/bin/screen-function-source-minified.sh}
STANDALONE=${STANDALONE_SCREEN:-$PROJECT/bin/screen.sh}
TMUX37_SCREEN=${SCREEN2TMUX_EQUIV_TMUX_3_7D:-$PROJECT/build-tmux-3.7d-patched/install/bin/screen}
TMUXLATEST_SCREEN=${SCREEN2TMUX_EQUIV_TMUX_LATEST:-$PROJECT/build-tmux-latest-patched/install/bin/screen}
WORKER=$TEST_DIR/interface-equivalence-worker.sh
CASES=$TEST_DIR/cases.sh
RUN_TIMESTAMP=${SCREEN2TMUX_RUN_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}
EQUIV_LOG=${EQUIV_LOG:-$PROJECT/logs/test-interface-equivalence-$RUN_TIMESTAMP.log}
REQUESTED=${SCREEN2TMUX_EQUIV_INTERFACES:-all}

for _f in "$CANONICAL" "$WORKER" "$CASES"; do
    [ -r "$_f" ] || { printf 'ERROR: cannot read equivalence input: %s\n' "$_f" >&2; exit 2; }
done
mkdir -p "$(dirname -- "$EQUIV_LOG")"
: > "$EQUIV_LOG"
# Load canonical formatting helpers and screen().
# shellcheck disable=SC1090
. "$CANONICAL"
# shellcheck disable=SC1090
. "$TEST_DIR/output-format.sh"

_tmp=${TMPDIR:-/tmp}/screen2tmux-equivalence-$$
rm -rf "$_tmp"
mkdir -p "$_tmp" || exit 2
trap 'rm -rf "$_tmp"' 0 1 2 3 15
META_FULL=$_tmp/meta-full.tsv
CASE_MAP=$_tmp/case-map.tsv
REGISTRY=$_tmp/registry.tsv
: > "$CASE_MAP"
: > "$REGISTRY"
TAB=$(printf '\t')

case_()
{
    _cm_id=$1; _cm_class=$2; _cm_desc=$3
    shift 3
    _cm_screen=$(_s2t_test_format_argv screen "$@")
    printf '%s\t%s\t%s\t%s\n' "$_cm_id" "$_cm_class" "$_cm_desc" "$_cm_screen" >> "$CASE_MAP"
}
# shellcheck disable=SC1090
. "$CASES"

_color_enabled=0
if [ -z "${NO_COLOR:-}" ]; then
    case "${SCREEN2TMUX_COLOR:-auto}" in
        always) _color_enabled=1 ;;
        auto|'') if [ -t 1 ] && [ "${TERM:-}" != dumb ]; then _color_enabled=1; fi ;;
        never) : ;;
    esac
fi
if [ "$_color_enabled" -eq 1 ]; then G='\033[32m'; R='\033[31m'; C='\033[36m'; Y='\033[33m'; Z='\033[0m'; else G=; R=; C=; Y=; Z=; fi

want_interface()
{
    _wi_name=$1
    [ "$REQUESTED" = all ] && return 0
    _wi_oldifs=$IFS
    IFS=,
    for _wi_item in $REQUESTED; do
        IFS=$_wi_oldifs
        [ "$_wi_item" = "$_wi_name" ] && return 0
        case "$_wi_name:$_wi_item" in
            screen-function-source:canonical|screen-function-source:source) return 0 ;;
            screen-function-source-minified:minified) return 0 ;;
            screen-script:script|screen-script:screen.sh) return 0 ;;
            tmux-3.7d:3.7d|tmux-3.7d:tmux37) return 0 ;;
            tmux-latest:latest|tmux-latest:master) return 0 ;;
        esac
        IFS=,
    done
    IFS=$_wi_oldifs
    return 1
}

# The canonical sourced function is always the reference, even when the user
# asks to exercise just one other interface.
printf '%s\t%s\t%s\t%s\n' 'screen-function-source' 'source-full' "$CANONICAL" 'screen-function-source.sh (reference)' >> "$REGISTRY"

add_selected()
{
    _as_name=$1; _as_mode=$2; _as_path=$3; _as_label=$4
    want_interface "$_as_name" || return 0
    [ "$_as_name" = screen-function-source ] && return 0
    case "$_as_mode" in
        source-full) [ -r "$_as_path" ] ;;
        standalone-full) [ -x "$_as_path" ] ;;
        *) return 2 ;;
    esac || {
        printf 'ERROR: requested equivalence interface is unavailable: %s (%s)\n' "$_as_name" "$_as_path" >&2
        return 2
    }
    printf '%s\t%s\t%s\t%s\n' "$_as_name" "$_as_mode" "$_as_path" "$_as_label" >> "$REGISTRY"
}

if [ "$REQUESTED" = all ] || want_interface screen-function-source-minified; then
    add_selected screen-function-source-minified source-full "$MINIFIED" 'screen-function-source-minified.sh' || exit $?
fi
if [ "$REQUESTED" = all ] || want_interface screen-script; then
    add_selected screen-script standalone-full "$STANDALONE" 'screen.sh' || exit $?
fi
if [ "$REQUESTED" = all ]; then
    [ ! -x "$TMUX37_SCREEN" ] || add_selected tmux-3.7d standalone-full "$TMUX37_SCREEN" 'tmux-3.7d screen hardlink' || exit $?
else
    if want_interface tmux-3.7d; then add_selected tmux-3.7d standalone-full "$TMUX37_SCREEN" 'tmux-3.7d screen hardlink' || exit $?; fi
fi
if [ "$REQUESTED" = all ]; then
    [ ! -x "$TMUXLATEST_SCREEN" ] || add_selected tmux-latest standalone-full "$TMUXLATEST_SCREEN" 'tmux-latest screen hardlink' || exit $?
else
    if want_interface tmux-latest; then add_selected tmux-latest standalone-full "$TMUXLATEST_SCREEN" 'tmux-latest screen hardlink' || exit $?; fi
fi

# Validate a non-all request so a typo does not silently run only the reference.
if [ "$REQUESTED" != all ]; then
    _oldifs=$IFS; IFS=,
    for _req in $REQUESTED; do
        IFS=$_oldifs
        case "$_req" in
            screen-function-source|canonical|source|screen-function-source-minified|minified|screen-script|script|screen.sh|tmux-3.7d|3.7d|tmux37|tmux-latest|latest|master) : ;;
            *) printf 'ERROR: unknown equivalence interface: %s\n' "$_req" >&2; exit 64 ;;
        esac
        IFS=,
    done
    IFS=$_oldifs
fi

INTERFACE_COUNT=$(wc -l < "$REGISTRY" | tr -d ' ')
INTERFACE_LABELS=$(awk -F '\t' '{ if (NR>1) printf ", "; printf "%s", $4 } END { print "" }' "$REGISTRY")
printf '%bEquivalence interfaces (%s):%b %s\n' "$C" "$INTERFACE_COUNT" "$Z" "$INTERFACE_LABELS"
printf 'INTERFACES\t%s\t%s\n' "$INTERFACE_COUNT" "$INTERFACE_LABELS" >> "$EQUIV_LOG"

# Generate every selected interface concurrently. Source-based workers are
# intrinsically serial, while standalone workers use their own bounded job pool.
# Running the interface workers together keeps the five-way compiled-build run
# from multiplying wall-clock time by the number of interfaces.
REF_DIR=$_tmp/out-screen-function-source
PIDS=$_tmp/worker-pids.tsv
: > "$PIDS"
NO_COLOR=1 SCREEN2TMUX_COLOR=never sh "$WORKER" source-full "$CANONICAL" "$REF_DIR" "$CASES" "$META_FULL" &
printf '%s\t%s\t%s\n' "$!" screen-function-source "$REF_DIR" >> "$PIDS"
while IFS="$TAB" read -r _name _mode _path _label; do
    [ "$_name" = screen-function-source ] && continue
    _out=$_tmp/out-$_name
    NO_COLOR=1 SCREEN2TMUX_COLOR=never sh "$WORKER" "$_mode" "$_path" "$_out" "$CASES" &
    printf '%s\t%s\t%s\n' "$!" "$_name" "$_out" >> "$PIDS"
done < "$REGISTRY"

_worker_fail=0
while IFS="$TAB" read -r _pid _name _out; do
    if wait "$_pid"; then :; else
        printf 'ERROR: equivalence worker failed for %s\n' "$_name" >&2
        _worker_fail=1
    fi
done < "$PIDS"
[ "$_worker_fail" -eq 0 ] || exit 1

REF_COUNT=$(cat "$REF_DIR/count")
while IFS="$TAB" read -r _pid _name _out; do
    _count=$(cat "$_out/count")
    [ "$_count" -eq "$REF_COUNT" ] || {
        printf 'ERROR: equivalence interface %s produced %s variants, expected %s\n' "$_name" "$_count" "$REF_COUNT" >&2
        exit 2
    }
done < "$PIDS"

CASE_PASS=0
CASE_FAIL=0
VARIANT_COMPARISONS=0
DIVERGENCES=0
_current_id=
_current_desc=
_current_class=
_current_screen=
_current_last_base=
_current_ok=1
_current_div=$_tmp/current-divergences
: > "$_current_div"

flush_case()
{
    [ -n "$_current_id" ] || return 0
    _mout=$(cat "$REF_DIR/$_current_last_base.out")
    _mtmux=$(_s2t_test_rhs_for_class "$_current_class" "$_mout")
    _way="${INTERFACE_COUNT}-way"
    if [ "$_current_ok" -eq 1 ]; then
        CASE_PASS=$((CASE_PASS + 1))
        _prefix=$(printf '[PASS] %s %s %s' "$_current_id" "$_current_class" "$_way")
        _s2t_test_print_case "$_prefix" "$_current_desc" "$_current_screen" "$_mtmux"
    else
        CASE_FAIL=$((CASE_FAIL + 1))
        _prefix=$(printf '[FAIL] %s %s %s' "$_current_id" "$_current_class" "$_way")
        _s2t_test_print_case "$_prefix" "$_current_desc" "$_current_screen" "$_mtmux"
        cat "$_current_div"
    fi
    : > "$_current_div"
}

while IFS="$TAB" read -r _base _id _place _desc; do
    if [ "$_id" != "$_current_id" ]; then
        flush_case
        _current_id=$_id
        _current_desc=$_desc
        _current_ok=1
        _current_last_base=
        _map=$(awk -F '\t' -v id="$_id" '$1 == id { print; exit }' "$CASE_MAP")
        IFS="$TAB" read -r _mid _current_class _mdesc _current_screen <<EOF_MAP
$_map
EOF_MAP
    fi
    _current_last_base=$_base
    _rr=$(cat "$REF_DIR/$_base.rc")

    # Compare only non-reference interfaces; the canonical matrix is the baseline.
    while IFS="$TAB" read -r _name _mode _path _label; do
        [ "$_name" = screen-function-source ] && continue
        VARIANT_COMPARISONS=$((VARIANT_COMPARISONS + 1))
        _out=$_tmp/out-$_name
        _ar=$(cat "$_out/$_base.rc")
        _rc_diff=0; _out_diff=0
        [ "$_rr" = "$_ar" ] || _rc_diff=1
        cmp -s "$REF_DIR/$_base.out" "$_out/$_base.out" || _out_diff=1
        if [ "$_rc_diff" -eq 0 ] && [ "$_out_diff" -eq 0 ]; then
            printf 'COMPARE\tPASS\t%s\t%s\t%s\t%s\n' "$_id" "$_place" "$_name" "$_rr" >> "$EQUIV_LOG"
        else
            _current_ok=0
            DIVERGENCES=$((DIVERGENCES + 1))
            _why=
            [ "$_rc_diff" -eq 0 ] || _why="rc expected=$_rr actual=$_ar"
            if [ "$_out_diff" -ne 0 ]; then
                if [ -n "$_why" ]; then _why="$_why; output differs"; else _why='output differs'; fi
            fi
            printf '    [DIVERGED] %s placement=%s (%s)\n' "$_label" "$_place" "$_why" >> "$_current_div"
            printf 'COMPARE\tFAIL\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_id" "$_place" "$_name" "$_rr" "$_ar" "$_why" >> "$EQUIV_LOG"
        fi
    done < "$REGISTRY"
done < "$META_FULL"
flush_case

# Real execution parity through a private tmux stub for the three script/source
# interfaces. Compiled hardlinks are exercised separately against real tmux.
_stub=$_tmp/stub
mkdir -p "$_stub"
cat > "$_stub/tmux" <<'EOF_STUB'
#!/bin/sh
printf 'TMUX_EXEC'
for a do printf ' <%s>' "$a"; done
printf '\n'
EOF_STUB
chmod 755 "$_stub/tmux"

_exec_ref=$_tmp/exec.reference
PATH="$_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never sh -c '. "$1"; screen -d -m bash' sh "$CANONICAL" >"$_exec_ref" 2>&1
_exec_rr=$?
_exec_ok=1
_exec_count=1
_exec_div=$_tmp/exec-div
: > "$_exec_div"

while IFS="$TAB" read -r _name _mode _path _label; do
    [ "$_name" = screen-function-source ] && continue
    case "$_name" in
        screen-function-source-minified)
            _exec_count=$((_exec_count + 1))
            PATH="$_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never sh -c '. "$1"; screen -d -m bash' sh "$_path" >"$_tmp/exec.$_name" 2>&1; _er=$? ;;
        screen-script)
            _exec_count=$((_exec_count + 1))
            PATH="$_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never "$_path" -d -m bash >"$_tmp/exec.$_name" 2>&1; _er=$? ;;
        *) continue ;;
    esac
    if [ "$_er" -ne "$_exec_rr" ] || ! cmp -s "$_exec_ref" "$_tmp/exec.$_name"; then
        _exec_ok=0
        printf '    [DIVERGED] %s execution path\n' "$_label" >> "$_exec_div"
    fi
done < "$REGISTRY"

if [ "$_exec_ok" -eq 1 ]; then
    _s2t_test_print_case "[PASS] EXEC ${_exec_count}-way" 'normal execution path (script/source interfaces)' "$(_s2t_test_format_argv screen -d -m bash)" "$(_s2t_test_format_argv tmux new-session -d bash)"
else
    _s2t_test_print_case "[FAIL] EXEC ${_exec_count}-way" 'normal execution path (script/source interfaces)' "$(_s2t_test_format_argv screen -d -m bash)" "$(_s2t_test_format_argv tmux new-session -d bash)"
    cat "$_exec_div"
    CASE_FAIL=$((CASE_FAIL + 1))
fi

printf 'SUMMARY: interfaces=%s variants=%s cases_pass=%s cases_fail=%s comparisons=%s divergences=%s\n' \
    "$INTERFACE_COUNT" "$REF_COUNT" "$CASE_PASS" "$CASE_FAIL" "$VARIANT_COMPARISONS" "$DIVERGENCES" >> "$EQUIV_LOG"
printf '\n%bInterface equivalence summary:%b %s interfaces; %s variants/interface; %s %bPASS%b cases/%s %bFAIL%b; %s comparisons; %s divergences\n' \
    "$C" "$Z" "$INTERFACE_COUNT" "$REF_COUNT" "$CASE_PASS" "$G" "$Z" "$CASE_FAIL" "$R" "$Z" "$VARIANT_COMPARISONS" "$DIVERGENCES"
printf '%bEquivalence log:%b %s\n' "$C" "$Z" "$EQUIV_LOG"
[ "$CASE_FAIL" -eq 0 ]
