#!/bin/sh
# Verify canonical/minified full-matrix parity and three-way parity for every case.
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
CANONICAL=${CANONICAL_SOURCE:-$PROJECT/bin/screen-function-source.sh}
MINIFIED=${MINIFIED_SOURCE:-$PROJECT/bin/screen-function-source-minified.sh}
STANDALONE=${STANDALONE_SCREEN:-$PROJECT/bin/screen.sh}
WORKER=$TEST_DIR/interface-equivalence-worker.sh
CASES=$TEST_DIR/cases.sh
RUN_TIMESTAMP=${SCREEN2TMUX_RUN_TIMESTAMP:-$(date '+%Y%m%d-%H%M%S')}
EQUIV_LOG=${EQUIV_LOG:-$PROJECT/logs/test-interface-equivalence-$RUN_TIMESTAMP.log}

for _f in "$CANONICAL" "$MINIFIED" "$STANDALONE" "$WORKER" "$CASES"; do
    [ -r "$_f" ] || { printf 'ERROR: cannot read equivalence input: %s\n' "$_f" >&2; exit 2; }
done
mkdir -p "$(dirname -- "$EQUIV_LOG")"
: > "$EQUIV_LOG"
_tmp=${TMPDIR:-/tmp}/screen2tmux-equivalence-$$
rm -rf "$_tmp"
mkdir -p "$_tmp/canonical-full" "$_tmp/minified-full" "$_tmp/standalone-last" || exit 2
trap 'rm -rf "$_tmp"' 0 1 2 3 15
META_FULL=$_tmp/meta-full.tsv
META_STANDALONE=$_tmp/meta-standalone.tsv

_color_enabled=0
if [ -z "${NO_COLOR:-}" ]; then
    case "${SCREEN2TMUX_COLOR:-auto}" in
        always) _color_enabled=1 ;;
        auto|'') if [ -t 1 ] && [ "${TERM:-}" != dumb ]; then _color_enabled=1; fi ;;
        never) : ;;
    esac
fi
if [ "$_color_enabled" -eq 1 ]; then G='\033[32m'; R='\033[31m'; C='\033[36m'; Z='\033[0m'; else G=; R=; C=; Z=; fi

# Generate the full 683-placement outputs for both source files concurrently.
NO_COLOR=1 SCREEN2TMUX_COLOR=never sh "$WORKER" source-full "$CANONICAL" "$_tmp/canonical-full" "$CASES" "$META_FULL" & _p1=$!
NO_COLOR=1 SCREEN2TMUX_COLOR=never sh "$WORKER" source-full "$MINIFIED" "$_tmp/minified-full" "$CASES" & _p2=$!
wait "$_p1"; _w1=$?
wait "$_p2"; _w2=$?
[ "$_w1" -eq 0 ] && [ "$_w2" -eq 0 ] || { printf 'ERROR: source equivalence worker failed\n' >&2; exit 1; }

# Every base command is also invoked through the real standalone wrapper.
NO_COLOR=1 SCREEN2TMUX_COLOR=never sh "$WORKER" standalone-last "$STANDALONE" "$_tmp/standalone-last" "$CASES" "$META_STANDALONE" || exit $?

PASS=0
FAIL=0
TOTAL=0
TAB=$(printf '\t')

while IFS="$TAB" read -r _base _id _place _desc; do
    TOTAL=$((TOTAL + 1))
    _ra=$(cat "$_tmp/canonical-full/$_base.rc")
    _rb=$(cat "$_tmp/minified-full/$_base.rc")
    if [ "$_ra" = "$_rb" ] && cmp -s "$_tmp/canonical-full/$_base.out" "$_tmp/minified-full/$_base.out"; then
        PASS=$((PASS + 1)); _res=PASS
    else
        FAIL=$((FAIL + 1)); _res=FAIL
        printf '%b[FAIL]%b SOURCE %s %-6s %s\n' "$R" "$Z" "$_id" "$_place" "$_desc"
    fi
    printf 'SOURCE_PARITY\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_base" "$_id" "$_place" "$_res" "$_ra" "$_rb" >> "$EQUIV_LOG"
done < "$META_FULL"

# Last-placement rows in META_FULL are in the same case order as the 228
# standalone rows. Join them once, then compare all three byte-for-byte.
awk -F '\t' '$3 == "last" { print $1 "\t" $2 "\t" $4 }' "$META_FULL" > "$_tmp/full-last.tsv"
paste "$_tmp/full-last.tsv" "$META_STANDALONE" > "$_tmp/three-way.tsv"
THREE_PASS=0
THREE_FAIL=0
while IFS="$TAB" read -r _cbase _cid _cdesc _sbase _sid _splace _sdesc; do
    TOTAL=$((TOTAL + 1))
    _ra=$(cat "$_tmp/canonical-full/$_cbase.rc")
    _rb=$(cat "$_tmp/minified-full/$_cbase.rc")
    _rc=$(cat "$_tmp/standalone-last/$_sbase.rc")
    if [ "$_cid" = "$_sid" ] && [ "$_ra" = "$_rb" ] && [ "$_ra" = "$_rc" ] && \
       cmp -s "$_tmp/canonical-full/$_cbase.out" "$_tmp/minified-full/$_cbase.out" && \
       cmp -s "$_tmp/canonical-full/$_cbase.out" "$_tmp/standalone-last/$_sbase.out"; then
        PASS=$((PASS + 1)); THREE_PASS=$((THREE_PASS + 1)); _res=PASS
        printf '%b[PASS]%b %s three-way %s\n' "$G" "$Z" "$_cid" "$_cdesc"
    else
        FAIL=$((FAIL + 1)); THREE_FAIL=$((THREE_FAIL + 1)); _res=FAIL
        printf '%b[FAIL]%b %s three-way %s (rc canonical=%s minified=%s standalone=%s)\n' "$R" "$Z" "$_cid" "$_cdesc" "$_ra" "$_rb" "$_rc"
    fi
    printf 'THREE_WAY\t%s\t%s\t%s\t%s\t%s\n' "$_cid" "$_res" "$_ra" "$_rb" "$_rc" >> "$EQUIV_LOG"
done < "$_tmp/three-way.tsv"

# Normal execution parity through a private tmux stub.
_stub=$_tmp/stub
mkdir -p "$_stub"
cat > "$_stub/tmux" <<'EOF_STUB'
#!/bin/sh
printf 'TMUX_EXEC'
for a do printf ' <%s>' "$a"; done
printf '\n'
EOF_STUB
chmod 755 "$_stub/tmux"
exec_source() { _f=$1; _o=$2; PATH="$_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never sh -c '. "$1"; screen -d -m bash' sh "$_f" >"$_o" 2>&1; }
exec_source "$CANONICAL" "$_tmp/exec.canonical"; _ra=$?
exec_source "$MINIFIED" "$_tmp/exec.minified"; _rb=$?
PATH="$_stub:$PATH" NO_COLOR=1 SCREEN2TMUX_COLOR=never "$STANDALONE" -d -m bash >"$_tmp/exec.standalone" 2>&1; _rc=$?
TOTAL=$((TOTAL + 1))
if [ "$_ra" -eq "$_rb" ] && [ "$_ra" -eq "$_rc" ] && cmp -s "$_tmp/exec.canonical" "$_tmp/exec.minified" && cmp -s "$_tmp/exec.canonical" "$_tmp/exec.standalone"; then
    PASS=$((PASS + 1)); printf '%b[PASS]%b EXEC normal execution path with tmux stub\n' "$G" "$Z"; _exec=PASS
else
    FAIL=$((FAIL + 1)); printf '%b[FAIL]%b EXEC normal execution path with tmux stub\n' "$R" "$Z"; _exec=FAIL
fi
printf 'EXEC_PARITY\t%s\t%s\t%s\t%s\n' "$_exec" "$_ra" "$_rb" "$_rc" >> "$EQUIV_LOG"

FULL_COUNT=$(cat "$_tmp/canonical-full/count")
BASE_COUNT=$(cat "$_tmp/standalone-last/count")
printf 'SUMMARY: source_full=%s three_way_cases=%s three_way_pass=%s three_way_fail=%s total_comparisons=%s pass=%s fail=%s\n' "$FULL_COUNT" "$BASE_COUNT" "$THREE_PASS" "$THREE_FAIL" "$TOTAL" "$PASS" "$FAIL" >> "$EQUIV_LOG"
printf '\n%bInterface equivalence summary:%b source parity %s variants; three-way %s %bPASS%b/%s %bFAIL%b; total %s comparisons\n' "$C" "$Z" "$FULL_COUNT" "$THREE_PASS" "$G" "$Z" "$THREE_FAIL" "$R" "$Z" "$TOTAL"
printf '%bEquivalence log:%b %s\n' "$C" "$Z" "$EQUIV_LOG"
[ "$FAIL" -eq 0 ]
