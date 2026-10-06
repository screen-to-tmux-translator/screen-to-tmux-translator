#!/bin/sh
# Compare every selected Screen compatibility interface with the canonical
# sourced function over the complete first/middle/last placement matrix.
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
CANONICAL=${CANONICAL_SOURCE:-$PROJECT/bin/screen-function-source.sh}
MINIFIED=${MINIFIED_SOURCE:-$PROJECT/bin/screen-function-source-minified.sh}
CANONICAL_ONELINER=${CANONICAL_ONELINER_SOURCE:-$PROJECT/bin/screen-function-source.oneliner.sh}
MINIFIED_ONELINER=${MINIFIED_ONELINER_SOURCE:-$PROJECT/bin/screen-function-source-minified.oneliner.sh}
STANDALONE=${STANDALONE_SCREEN:-$PROJECT/bin/screen.sh}
WORKER=$TEST_DIR/interface-equivalence-worker.sh
CASES=$TEST_DIR/cases.sh
ORACLE=${ORACLE:-$TEST_DIR/screen-syntax-oracle.sh}
RUN_TIMESTAMP=${SCREEN2TMUX_RUN_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}
EQUIV_LOG=${EQUIV_LOG:-$PROJECT/logs/test-interface-equivalence-$RUN_TIMESTAMP.log}
REQUESTED=${SCREEN2TMUX_EQUIV_INTERFACES:-all}
EXTERNAL_BUILT_REGISTRY=${SCREEN2TMUX_EQUIV_BUILT_REGISTRY:-}

for _f in "$CANONICAL" "$WORKER" "$CASES" "$ORACLE"; do
    [ -r "$_f" ] || { printf 'ERROR: cannot read equivalence input: %s\n' "$_f" >&2; exit 2; }
done
mkdir -p "$(dirname -- "$EQUIV_LOG")"
: > "$EQUIV_LOG"
# shellcheck disable=SC1090
. "$CANONICAL"
# shellcheck disable=SC1090
. "$TEST_DIR/output-format.sh"
# shellcheck disable=SC1090
. "$ORACLE"

_tmp=${TMPDIR:-/tmp}/screen2tmux-equivalence-$$
rm -rf "$_tmp"
mkdir -p "$_tmp" || exit 2
trap 'rm -rf "$_tmp"' 0 1 2 3 15
META_FULL=$_tmp/meta-full.tsv
CASE_MAP=$_tmp/case-map.tsv
REGISTRY=$_tmp/registry.tsv
BUILT_INPUT=$_tmp/built-registry.tsv
: > "$CASE_MAP"; : > "$REGISTRY"; : > "$BUILT_INPUT"
TAB=$(printf '\t')

expected_rc()
{
    case "$1" in
        exact) printf '0' ;;
        unsupported) printf '2' ;;
        approx) printf '3' ;;
        moot) printf '4' ;;
        external) printf '5' ;;
        invalid) printf '64' ;;
        *) printf '255' ;;
    esac
}

ORACLE_PASS=0
ORACLE_FAIL=0
case_()
{
    _cm_id=$1; _cm_class=$2; _cm_desc=$3
    shift 3
    _cm_screen=$(_s2t_test_format_argv screen "$@")
    _cm_expected_rc=$(expected_rc "$_cm_class")
    screen_syntax_oracle "$@" >/dev/null 2>&1
    _cm_oracle_rc=$?
    if [ "$_cm_class" = invalid ]; then _cm_oracle_expected=64; else _cm_oracle_expected=0; fi
    if [ "$_cm_oracle_rc" -eq "$_cm_oracle_expected" ]; then
        _cm_oracle_ok=1; _cm_oracle_reason=-; ORACLE_PASS=$((ORACLE_PASS + 1))
    else
        _cm_oracle_ok=0; ORACLE_FAIL=$((ORACLE_FAIL + 1))
        _cm_oracle_reason=$(printf '%s' "${SCREEN_ORACLE_REASON:-unknown oracle failure}" | tr '\t\n' '  ')
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$_cm_id" "$_cm_class" "$_cm_desc" "$_cm_screen" "$_cm_expected_rc" \
        "$_cm_oracle_expected" "$_cm_oracle_rc" "$_cm_oracle_ok" "$_cm_oracle_reason" >> "$CASE_MAP"
}
# shellcheck disable=SC1090
. "$CASES"

# Fit the Screen-command column to the longest command in this corpus so every
# -> marker begins in the same column without reserving unnecessary space.
_s2t_test_map_screen_width=$(awk -F '\t' 'length($4) > m { m=length($4) } END { print (m ? m : 49) }' "$CASE_MAP")

_color_enabled=0
if [ -z "${NO_COLOR:-}" ]; then
    case "${SCREEN2TMUX_COLOR:-auto}" in
        always) _color_enabled=1 ;;
        auto|'') [ -t 1 ] && [ "${TERM:-}" != dumb ] && _color_enabled=1 ;;
        never) : ;;
    esac
fi
if [ "$_color_enabled" -eq 1 ]; then G='\033[32m'; R='\033[31m'; C='\033[36m'; Y='\033[33m'; Z='\033[0m'; else G=; R=; C=; Y=; Z=; fi

# Dynamic compiled-interface registry format:
#   interface-name<TAB>/absolute/path/to/screen<TAB>human label
if [ -n "$EXTERNAL_BUILT_REGISTRY" ]; then
    [ -r "$EXTERNAL_BUILT_REGISTRY" ] || { printf 'ERROR: cannot read built equivalence registry: %s\n' "$EXTERNAL_BUILT_REGISTRY" >&2; exit 2; }
    cat "$EXTERNAL_BUILT_REGISTRY" > "$BUILT_INPUT"
else
    _build_root=${SCREEN2TMUX_BUILD_ROOT:-$PROJECT/build}
    for _screen in "$_build_root"/tmux-*-patched/install/bin/screen; do
        [ -x "$_screen" ] || continue
        _dir=$(CDPATH= cd -- "$(dirname -- "$_screen")/../.." && pwd)
        _base=$(basename -- "$_dir")
        _ver=${_base#tmux-}; _ver=${_ver%-patched}
        printf 'tmux-%s\t%s\ttmux-%s screen hardlink\n' "$_ver" "$_screen" "$_ver" >> "$BUILT_INPUT"
    done
    # Backward-compatible discovery for 0.4.1-era layouts.
    for _screen in "$PROJECT"/build-tmux-*-patched/install/bin/screen; do
        [ -x "$_screen" ] || continue
        _dir=$(CDPATH= cd -- "$(dirname -- "$_screen")/../.." && pwd)
        _base=$(basename -- "$_dir")
        _ver=${_base#build-tmux-}; _ver=${_ver%-patched}
        grep -F "tmux-$_ver${TAB}" "$BUILT_INPUT" >/dev/null 2>&1 || printf 'tmux-%s\t%s\ttmux-%s screen hardlink\n' "$_ver" "$_screen" "$_ver" >> "$BUILT_INPUT"
    done
fi

want_interface()
{
    _wi_name=$1
    [ "$REQUESTED" = all ] && return 0
    _wi_version=
    case "$_wi_name" in tmux-*) _wi_version=${_wi_name#tmux-} ;; esac
    _wi_oldifs=$IFS; IFS=,
    for _wi_item in $REQUESTED; do
        IFS=$_wi_oldifs
        [ "$_wi_item" = "$_wi_name" ] && return 0
        [ -n "$_wi_version" ] && [ "$_wi_item" = "$_wi_version" ] && return 0
        case "$_wi_name:$_wi_item" in
            screen-function-source:canonical|screen-function-source:source) return 0 ;;
            screen-function-source-minified:minified) return 0 ;;
            screen-function-source-oneliner:oneliner|screen-function-source-oneliner:source-oneliner) return 0 ;;
            screen-function-source-minified-oneliner:minified-oneliner) return 0 ;;
            screen-script:script|screen-script:screen.sh) return 0 ;;
            tmux-latest:master) return 0 ;;
        esac
        IFS=,
    done
    IFS=$_wi_oldifs
    return 1
}

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
    esac || { printf 'ERROR: requested equivalence interface is unavailable: %s (%s)\n' "$_as_name" "$_as_path" >&2; return 2; }
    printf '%s\t%s\t%s\t%s\n' "$_as_name" "$_as_mode" "$_as_path" "$_as_label" >> "$REGISTRY"
}

if [ "$REQUESTED" = all ] || want_interface screen-function-source-minified; then add_selected screen-function-source-minified source-full "$MINIFIED" 'screen-function-source-minified.sh' || exit $?; fi
if [ "$REQUESTED" = all ] || want_interface screen-function-source-oneliner; then add_selected screen-function-source-oneliner source-full "$CANONICAL_ONELINER" 'screen-function-source.oneliner.sh' || exit $?; fi
if [ "$REQUESTED" = all ] || want_interface screen-function-source-minified-oneliner; then add_selected screen-function-source-minified-oneliner source-full "$MINIFIED_ONELINER" 'screen-function-source-minified.oneliner.sh' || exit $?; fi
if [ "$REQUESTED" = all ] || want_interface screen-script; then add_selected screen-script standalone-full "$STANDALONE" 'screen.sh (self-contained)' || exit $?; fi
while IFS="$TAB" read -r _bn _bp _bl; do
    [ -n "$_bn" ] || continue
    if [ "$REQUESTED" = all ] || want_interface "$_bn"; then add_selected "$_bn" standalone-full "$_bp" "$_bl" || exit $?; fi
done < "$BUILT_INPUT"

# A typo or unavailable explicitly requested build must not silently degrade to
# reference-only testing.
if [ "$REQUESTED" != all ]; then
    _oldifs=$IFS; IFS=,
    for _req in $REQUESTED; do
        IFS=$_oldifs
        case "$_req" in
            screen-function-source|canonical|source|screen-function-source-minified|minified|screen-function-source-oneliner|oneliner|source-oneliner|screen-function-source-minified-oneliner|minified-oneliner|screen-script|script|screen.sh) _known=1 ;;
            *)
                _known=0
                while IFS="$TAB" read -r _bn _bp _bl; do
                    _bv=${_bn#tmux-}
                    case "$_req" in "$_bn"|"$_bv") _known=1; break ;; master) [ "$_bn" = tmux-latest ] && { _known=1; break; } ;; esac
                done < "$BUILT_INPUT"
                ;;
        esac
        [ "$_known" -eq 1 ] || { printf 'ERROR: unknown or unavailable equivalence interface: %s\n' "$_req" >&2; exit 64; }
        IFS=,
    done
    IFS=$_oldifs
fi

INTERFACE_COUNT=$(wc -l < "$REGISTRY" | tr -d ' ')
printf '%bEquivalence interfaces (%s):%b\n' "$C" "$INTERFACE_COUNT" "$Z"
while IFS="$TAB" read -r _iname _imode _ipath _ilabel; do
    printf '  %s\n    %s\n' "$_ilabel" "$_ipath"
    printf 'INTERFACE\t%s\t%s\t%s\t%s\n' "$_iname" "$_imode" "$_ipath" "$_ilabel" >> "$EQUIV_LOG"
done < "$REGISTRY"

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
    if wait "$_pid"; then :; else printf 'ERROR: equivalence worker failed for %s\n' "$_name" >&2; _worker_fail=1; fi
done < "$PIDS"
[ "$_worker_fail" -eq 0 ] || exit 1

REF_COUNT=$(cat "$REF_DIR/count")
while IFS="$TAB" read -r _pid _name _out; do
    _count=$(cat "$_out/count")
    [ "$_count" -eq "$REF_COUNT" ] || { printf 'ERROR: equivalence interface %s produced %s variants, expected %s\n' "$_name" "$_count" "$REF_COUNT" >&2; exit 2; }
done < "$PIDS"

CASE_PASS=0; CASE_FAIL=0; VARIANT_COMPARISONS=0; DIVERGENCES=0; VALIDATION_FAILURES=0
_current_id=; _current_desc=; _current_class=; _current_screen=; _current_last_base=; _current_ok=1; _current_expected_rc=0
_current_div=$_tmp/current-divergences
: > "$_current_div"
flush_case()
{
    [ -n "$_current_id" ] || return 0
    _mout=$(cat "$REF_DIR/$_current_last_base.out")
    _mtmux=$(_s2t_test_rhs_for_class "$_current_class" "$_mout")
    if [ "$_current_ok" -eq 1 ]; then
        CASE_PASS=$((CASE_PASS + 1)); _prefix=$(printf '[PASS] %s %s' "$_current_id" "$_current_class")
        _s2t_test_print_case "$_prefix" "$_current_desc" "$_current_screen" "$_mtmux"
    else
        CASE_FAIL=$((CASE_FAIL + 1)); _prefix=$(printf '[FAIL] %s %s' "$_current_id" "$_current_class")
        _s2t_test_print_case "$_prefix" "$_current_desc" "$_current_screen" "$_mtmux"; cat "$_current_div"
    fi
    : > "$_current_div"
}

while IFS="$TAB" read -r _base _id _place _desc; do
    if [ "$_id" != "$_current_id" ]; then
        flush_case
        _current_id=$_id; _current_desc=$_desc; _current_ok=1; _current_last_base=
        _map=$(awk -F '\t' -v id="$_id" '$1 == id { print; exit }' "$CASE_MAP")
        IFS="$TAB" read -r _mid _current_class _mdesc _current_screen _current_expected_rc _oracle_expected _oracle_actual _oracle_ok _oracle_reason <<EOF_MAP
$_map
EOF_MAP
        if [ "$_oracle_ok" -eq 1 ]; then
            _current_ok=1
            printf 'ORACLE\tPASS\t%s\t%s\n' "$_id" "$_oracle_actual" >> "$EQUIV_LOG"
        else
            _current_ok=0; VALIDATION_FAILURES=$((VALIDATION_FAILURES + 1))
            printf '    [ORACLE FAIL] expected=%s actual=%s (%s)\n' "$_oracle_expected" "$_oracle_actual" "$_oracle_reason" >> "$_current_div"
            printf 'ORACLE\tFAIL\t%s\t%s\t%s\t%s\n' "$_id" "$_oracle_expected" "$_oracle_actual" "$_oracle_reason" >> "$EQUIV_LOG"
        fi
    fi
    _current_last_base=$_base
    _rr=$(cat "$REF_DIR/$_base.rc")
    if [ "$_rr" -ne "$_current_expected_rc" ]; then
        _current_ok=0; VALIDATION_FAILURES=$((VALIDATION_FAILURES + 1))
        printf '    [REFERENCE FAIL] placement=%s expected rc=%s actual rc=%s\n' "$_place" "$_current_expected_rc" "$_rr" >> "$_current_div"
        printf 'REFERENCE\tFAIL\t%s\t%s\t%s\t%s\n' "$_id" "$_place" "$_current_expected_rc" "$_rr" >> "$EQUIV_LOG"
    else
        printf 'REFERENCE\tPASS\t%s\t%s\t%s\n' "$_id" "$_place" "$_rr" >> "$EQUIV_LOG"
    fi
    while IFS="$TAB" read -r _name _mode _path _label; do
        [ "$_name" = screen-function-source ] && continue
        VARIANT_COMPARISONS=$((VARIANT_COMPARISONS + 1))
        _out=$_tmp/out-$_name; _ar=$(cat "$_out/$_base.rc")
        _rc_diff=0; _out_diff=0
        [ "$_rr" = "$_ar" ] || _rc_diff=1
        cmp -s "$REF_DIR/$_base.out" "$_out/$_base.out" || _out_diff=1
        if [ "$_rc_diff" -eq 0 ] && [ "$_out_diff" -eq 0 ]; then
            printf 'COMPARE\tPASS\t%s\t%s\t%s\t%s\n' "$_id" "$_place" "$_name" "$_rr" >> "$EQUIV_LOG"
        else
            _current_ok=0; DIVERGENCES=$((DIVERGENCES + 1)); _why=
            [ "$_rc_diff" -eq 0 ] || _why="rc expected=$_rr actual=$_ar"
            if [ "$_out_diff" -ne 0 ]; then if [ -n "$_why" ]; then _why="$_why; output differs"; else _why='output differs'; fi; fi
            printf '    [DIVERGED] %s placement=%s (%s)\n' "$_label" "$_place" "$_why" >> "$_current_div"
            printf 'COMPARE\tFAIL\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_id" "$_place" "$_name" "$_rr" "$_ar" "$_why" >> "$EQUIV_LOG"
        fi
    done < "$REGISTRY"
done < "$META_FULL"
flush_case

# Normal execution parity through a private tmux stub applies to the source and
# script implementations. Compiled hardlinks execute against their real tmux.
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
_exec_rr=$?; _exec_ok=1; _exec_count=1; _exec_div=$_tmp/exec-div; : > "$_exec_div"
while IFS="$TAB" read -r _name _mode _path _label; do
    [ "$_name" = screen-function-source ] && continue
    case "$_name" in
        tmux-*) continue ;;
        screen-script) _exec_count=$((_exec_count + 1)); PATH="$_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never "$_path" -d -m bash >"$_tmp/exec.$_name" 2>&1; _er=$? ;;
        *)
            [ "$_mode" = source-full ] || continue
            _exec_count=$((_exec_count + 1))
            PATH="$_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never sh -c '. "$1"; screen -d -m bash' sh "$_path" >"$_tmp/exec.$_name" 2>&1; _er=$?
            ;;
    esac
    if [ "$_er" -ne "$_exec_rr" ] || ! cmp -s "$_exec_ref" "$_tmp/exec.$_name"; then _exec_ok=0; printf '    [DIVERGED] %s execution path\n' "$_label" >> "$_exec_div"; fi
done < "$REGISTRY"
if [ "$_exec_ok" -eq 1 ]; then
    _s2t_test_print_case "[PASS] EXEC" 'normal execution path (script/source interfaces)' "$(_s2t_test_format_argv screen -d -m bash)" "$(_s2t_test_format_argv tmux new-session -d bash)"
else
    _s2t_test_print_case "[FAIL] EXEC" 'normal execution path (script/source interfaces)' "$(_s2t_test_format_argv screen -d -m bash)" "$(_s2t_test_format_argv tmux new-session -d bash)"; cat "$_exec_div"; CASE_FAIL=$((CASE_FAIL + 1))
fi

printf 'SUMMARY: interfaces=%s variants=%s cases_pass=%s cases_fail=%s oracle_pass=%s oracle_fail=%s validation_failures=%s comparisons=%s divergences=%s\n' \
    "$INTERFACE_COUNT" "$REF_COUNT" "$CASE_PASS" "$CASE_FAIL" "$ORACLE_PASS" "$ORACLE_FAIL" "$VALIDATION_FAILURES" "$VARIANT_COMPARISONS" "$DIVERGENCES" >> "$EQUIV_LOG"
printf '\n%bScreen/interface summary:%b %s interfaces; %s variants/interface; oracle %s %bPASS%b/%s %bFAIL%b; %s %bPASS%b cases/%s %bFAIL%b; %s comparisons; %s divergences\n' \
    "$C" "$Z" "$INTERFACE_COUNT" "$REF_COUNT" "$ORACLE_PASS" "$G" "$Z" "$ORACLE_FAIL" "$R" "$Z" \
    "$CASE_PASS" "$G" "$Z" "$CASE_FAIL" "$R" "$Z" "$VARIANT_COMPARISONS" "$DIVERGENCES"
printf '%bCombined log:%b %s\n' "$C" "$Z" "$EQUIV_LOG"
[ "$CASE_FAIL" -eq 0 ] && [ "$ORACLE_FAIL" -eq 0 ] && [ "$VALIDATION_FAILURES" -eq 0 ]
