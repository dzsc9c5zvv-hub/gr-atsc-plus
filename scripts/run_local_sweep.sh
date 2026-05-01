#!/bin/bash
# Real-IQ regression sweep — run all 16 combos against a captured ATSC IQ
# file and print a clean-percent scoreboard sorted by performance.
#
# Usage:
#   bash scripts/run_local_sweep.sh <path-to-cs16-file>
#
# The IQ file should be 8 MS/s CS16 captured per docs/proven_capture_recipe.md.
# Output: results/<date>-real-rf<N>-local.md plus a console scoreboard.
#
# Run this BEFORE pushing any C++ changes to atsc_equalizer_long /
# atsc_viterbi_soft / atsc_fpll_tight / atsc_sync_tunable / atsc_fs_checker_inst
# to make sure stock stays at ~60% and forks don't regress.

set -e

if [ -z "$1" ] || [ ! -f "$1" ]; then
    echo "Usage: $0 <path-to-rf-capture.cs16>"
    exit 2
fi

IQ="$1"
SWEEP_DIR=$(mktemp -d)
ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"

echo "=== gr-atsc-plus 16-combo real-IQ sweep ==="
echo "Input: $IQ ($(du -h "$IQ" | cut -f1))"
echo "Sweep dir: $SWEEP_DIR"
echo

COMBOS=(
    stock long_eq soft_vit long_eq_soft_vit
    tight_fpll very_tight_fpll
    hysteresis_sync force_emit_sync max_relax_sync
    tight_fpll_long_eq tight_fpll_soft_vit
    hysteresis_long_eq hysteresis_long_eq_soft_vit
    tight_fpll_hysteresis full_stack full_stack_force_emit
)

for combo in "${COMBOS[@]}"; do
    printf "  %-32s " "$combo"
    python3.12 "$ROOT/run_combo.py" "$IQ" "$SWEEP_DIR/${combo}.ts" "$combo" 2>/dev/null
    python3.12 - "$SWEEP_DIR/${combo}.ts" <<'PYEOF'
import sys
d = open(sys.argv[1], 'rb').read()
n = len(d) // 188
if n == 0:
    print("FAIL (empty TS)")
    sys.exit()
KEEP = {0, 0x1FFB, 0x1FFF} | {p|s for p in range(0x30, 0x90, 0x10) for s in range(6)}
c = sum(1 for i in range(n)
        if d[i*188] == 0x47
        and not ((d[i*188+1] >> 7) & 1)
        and (((d[i*188+1] & 0x1F) << 8) | d[i*188+2]) in KEEP)
t = sum(1 for i in range(n) if d[i*188] == 0x47 and ((d[i*188+1] >> 7) & 1))
print(f"clean={100*c/n:5.1f}%  tei={100*t/n:5.1f}%  pkts={n}")
PYEOF
done

echo
echo "Done. Sorted leaderboard:"
echo

for combo in "${COMBOS[@]}"; do
    python3.12 - "$SWEEP_DIR/${combo}.ts" "$combo" <<'PYEOF'
import sys
d = open(sys.argv[1], 'rb').read()
n = len(d) // 188
if n == 0:
    print(f"  0.0  {sys.argv[2]}")
    sys.exit()
KEEP = {0, 0x1FFB, 0x1FFF} | {p|s for p in range(0x30, 0x90, 0x10) for s in range(6)}
c = sum(1 for i in range(n)
        if d[i*188] == 0x47
        and not ((d[i*188+1] >> 7) & 1)
        and (((d[i*188+1] & 0x1F) << 8) | d[i*188+2]) in KEEP)
print(f"{100*c/n:6.1f}  {sys.argv[2]}")
PYEOF
done | sort -rn

rm -rf "$SWEEP_DIR"
