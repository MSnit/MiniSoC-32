#!/usr/bin/env bash
# =============================================================================
#  MiniSoC-32 — regress.sh
#  Runs every unit testbench and the system-level test.
#  Prints PASS/FAIL summary at the end.
#  Usage: bash scripts/regress.sh
# =============================================================================
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
source ~/vlsi-env/bin/activate

PASS=0
FAIL=0
RESULTS=()

run_tb() {
    local name="$1"
    local files="${@:2}"
    echo -n "  [$name] ... "
    if iverilog -g2012 -Wall -o /tmp/tb_run.vvp $files 2>/tmp/tb_compile.log \
       && vvp /tmp/tb_run.vvp 2>&1 | tee /tmp/tb_run.log | grep -q "PASS"; then
        echo "PASS"
        PASS=$((PASS+1))
        RESULTS+=("PASS  $name")
    else
        echo "FAIL"
        cat /tmp/tb_compile.log 2>/dev/null || true
        cat /tmp/tb_run.log 2>/dev/null || true
        FAIL=$((FAIL+1))
        RESULTS+=("FAIL  $name")
    fi
}

echo ""
echo "=== Unit: CPU ==="
run_tb "regfile"     $REPO/rtl/cpu/regfile.sv       $REPO/tb/unit/cpu/tb_regfile.sv
run_tb "alu"         $REPO/rtl/cpu/alu.sv            $REPO/tb/unit/cpu/tb_alu.sv
run_tb "hazard_unit" $REPO/rtl/cpu/hazard_unit.sv   $REPO/tb/unit/cpu/tb_hazard.sv
run_tb "rv32i_cpu"   $REPO/rtl/cpu/*.sv             $REPO/tb/unit/cpu/tb_rv32i_cpu.sv

echo ""
echo "=== Unit: Bus ==="
run_tb "wb_interconnect" $REPO/rtl/bus/wb_interconnect.sv $REPO/tb/unit/bus/tb_wb_interconnect.sv

echo ""
echo "=== Unit: Memory ==="
run_tb "irom" $REPO/rtl/mem/irom.sv $REPO/tb/unit/mem/tb_irom.sv
run_tb "dram" $REPO/rtl/mem/dram.sv $REPO/tb/unit/mem/tb_dram.sv

echo ""
echo "=== Unit: Peripherals ==="
run_tb "uart"   $REPO/rtl/periph/uart.sv       $REPO/tb/unit/periph/tb_uart.sv
run_tb "spi"    $REPO/rtl/periph/spi_master.sv $REPO/tb/unit/periph/tb_spi.sv
run_tb "gpio"   $REPO/rtl/periph/gpio.sv       $REPO/tb/unit/periph/tb_gpio.sv
run_tb "timer"  $REPO/rtl/periph/timer.sv      $REPO/tb/unit/periph/tb_timer.sv

echo ""
echo "=== System Test ==="
run_tb "minisoc_top" \
    $REPO/rtl/cpu/*.sv \
    $REPO/rtl/bus/*.sv \
    $REPO/rtl/mem/*.sv \
    $REPO/rtl/periph/*.sv \
    $REPO/rtl/top/*.sv \
    $REPO/tb/system/tb_minisoc_top.sv

echo ""
echo "============================================================"
echo "  RESULTS"
echo "============================================================"
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo ""
echo "  PASSED: $PASS   FAILED: $FAIL"
echo "============================================================"

[ "$FAIL" -eq 0 ]
