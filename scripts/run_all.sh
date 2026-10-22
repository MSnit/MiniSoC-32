#!/usr/bin/env bash
# =============================================================================
#  MiniSoC-32 — run_all.sh
#  Runs full simulation regression then synthesis check.
#  Usage: bash scripts/run_all.sh
# =============================================================================
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
source ~/vlsi-env/bin/activate

echo "============================================================"
echo "  MiniSoC-32  —  Full Run"
echo "============================================================"

echo ""
echo "--- Unit Tests ---"
bash "$REPO/scripts/regress.sh"

echo ""
echo "--- Synthesis (Yosys) ---"
cd "$REPO"
yosys -s syn/synth.ys 2>&1 | tee syn/reports/synth.log
grep -E "(Number of cells|cells:)" syn/reports/synth.log | tail -n 25 || true

echo ""
echo "--- Gate-Level Simulation (GLS) ---"
python3 "$REPO/scripts/prepare_gls.py"
iverilog -g2012 -o /tmp/tb_gls.vvp /usr/share/yosys/simlib.v "$REPO/syn/reports/minisoc_top_gls.v" "$REPO/tb/system/tb_minisoc_top_gls.sv"
vvp /tmp/tb_gls.vvp

echo ""
echo "============================================================"
echo "  ALL DONE"
echo "============================================================"
