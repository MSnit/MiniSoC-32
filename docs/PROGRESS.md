# MiniSoC-32 Progress Log

> Auto-updated by agents. Newest entries at the top.

---

## 2026-10-22 — Firmware Suite, Drivers, and Full-System Testbench (`soc_tb`)

### ✅ Done
- **Firmware Infrastructure (`fw/`)**:
  - `include/minisoc.h`: Added comprehensive register maps, CSR access macros, and inline driver functions for UART, SPI, GPIO, and Timer.
  - `src/startup.S`: Vector initialization, stack pointer setup, `.data` copy from ROM to RAM, `.bss` zeroing, and `mtvec` interrupt handler hook.
  - `link.ld`: Memory map defining IROM (`0x0000_0000`, 4 KB) and DRAM (`0x0001_0000`, 4 KB) sections with `_stack_top`.
  - `Makefile`: Enhanced to support individual demo builds (`make demos`), dump disassemblies, and generate padded 1024-word hex images.
- **Drivers and Demo Programs (`fw/src/`)**:
  - `demo_blink.c`: (1) GPIO LED blink using Timer delay cycles.
  - `demo_uart.c`: (2) UART "Hello SoC" banner printing and interactive RX-to-TX character echo.
  - `demo_spi.c`: (3) SPI Master full-duplex transmission and reception against model slave.
  - `demo_timer_irq.c`: (4) Timer interrupt test verifying CPU CSR `mstatus.MIE` and `mie.MTIE` trap execution, ISR tick count, and MRET return.
  - `self_test.c`: (5) Comprehensive multi-peripheral self-test that exercises DRAM, GPIO, Timer IRQ, SPI, and prints "ALL TESTS PASSED" and "PASS" over UART, driving `GPIO_OUT = 0xFF` on success.
- **Full-System Testbench (`tb/soc_tb.sv`)**:
  - Instantiates `minisoc_top`, loads `fw/build/minisoc.hex`, models SPI slave response, and captures UART TX serial stream in real time.
  - Deserializes UART start/data/stop bits into ASCII characters, streams output to simulation console, buffers received text, and checks for "PASS" string and hardware confirmation `GPIO_OUT = 0xFF`.
- **Regression Suite (`scripts/regress.sh`)**:
  - Automatically compiles firmware and demos, executes all 11 unit testbenches and both system testbenches (`minisoc_top` and `soc_tb`), and displays a formatted PASS/FAIL summary table (13/13 PASS).

### 🐛 Bugs / Fixes
1. **Dual-Port IROM for `.rodata` Access (`irom.sv` & `minisoc_top.sv`)**: When executing C firmware, constant strings and `.data` initializers reside in IROM (`0x0000_xxxx`). Previously, `minisoc_top` connected IROM only to the CPU's instruction fetch port (`imem`), returning 0 for any data bus (`dmem`) load from ROM. Added Port B to `irom.sv` connected to the Wishbone interconnect slave port, enabling simultaneous instruction fetch and `.rodata` loads without contention.
2. **Register File Write-Through Bypass (`regfile.sv`)**: In the 5-stage pipeline, when an instruction in the Writeback (WB) stage writes to `rd` in the same clock cycle that a subsequent instruction in the Decode (ID) stage reads `rs = rd`, the non-blocking assignment in `always_ff` previously returned uninitialized/stale values. Added internal combinational bypass in `regfile.sv` (`(we && rd == rs) ? rd_data : regs[rs]`), eliminating uninitialized pipeline hazards.
3. **IROM Testbench Port Binding (`tb_irom.sv`)**: Added declarations for Port B signals to support wildcard `.*` instantiation.

---

## 2026-10-22 — Full Flow Verification: RTL, Lint, Simulation, Synthesis & GDSII Signoff

### ✅ Done
- **Verilator Linting (`verilator --lint-only -Wall`)**:
  - Removed timescale mismatch between RTL files and testbenches.
  - Resolved unused signal/parameter warnings cleanly across all modules (`minisoc_top`, `rv32i_cpu`, `wb_interconnect`, `irom`, `dram`, `uart`, `spi_master`, `gpio`, `timer`, `alu`, `control`, `imm_gen`, `regfile`, `csr_regfile`).
  - Achieved 100% clean lint with zero warnings and zero errors across the entire codebase and for each individual module.
- **Simulation Regression (`scripts/regress.sh`)**:
  - All self-checking testbenches passed:
    - `tb_regfile` (PASS)
    - `tb_alu` (PASS)
    - `tb_hazard` (PASS)
    - `tb_rv32i_cpu` (PASS)
    - `tb_wb_interconnect` (PASS)
    - `tb_irom` (PASS)
    - `tb_dram` (PASS)
    - `tb_uart` (PASS)
    - `tb_spi` (PASS)
    - `tb_gpio` (PASS)
    - `tb_timer` (PASS)
    - `tb_minisoc_top` (PASS)
- **Logic Synthesis (`syn/synth.ys` via Yosys 0.52)**:
  - Corrected input file list in `syn/synth.ys` to reflect modern modular CPU structure.
  - Successfully synthesized hierarchical design with 80,633 cells (including 32,768 DFFs for 4 KB data memory).
  - Generated netlist `syn/reports/minisoc_top_netlist.v` and detailed area breakdown in `syn/reports/synth_area.rpt`.
- **Physical Design (OpenLane 2.3.10 with SkyWater sky130 PDK)**:
  - Fixed configuration paths in `pd/config.json`.
  - Configured dockerized OpenLane 2 run with `sky130A` / `sky130_fd_sc_hd`.
  - Executed all 78 stages of the Classic flow from synthesis to physical signoff.
  - **Results**:
    - DRC: Passed ✅ (0 errors in Magic & KLayout)
    - LVS: Passed ✅ (Clean netlist vs layout match)
    - Antenna: Passed ✅ (0 violations)
    - Timing: Setup Slack = +13.43 ns, Hold Slack = +0.11 ns (TNS = 0)
    - Power: 82.5 µW
    - Die Size: 57.36 µm × 68.08 µm
    - Generated Views: `pd/runs/RUN_2026-10-22_18-28-06/final/gds/minisoc_top.gds`, DEF, LEF, SPICE, SDC, SDF, SPEF.

### 🐛 Bugs / Fixes
1. **Interconnect Upper Address Bits Decoding (`wb_interconnect.sv`)**: Found during rigorous unmapped address testing that `region = m_wb_adr[23:16]` did not check whether upper address bits `m_wb_adr[31:24] == 8'h00`. Addresses such as `0x1000_0000` were erroneously aliasing to `IROM` instead of asserting `wb_err`. Added strict check for `m_wb_adr[31:24] == 8'h00` before decoding regions, and added continuous back-to-back bus transfer assertions in `tb_wb_interconnect.sv`.
2. **Timescale Inconsistency (`TIMESCALEMOD`)**: Some peripheral modules contained timescale directives while others did not. Removed timescales from synthesizable RTL modules (keeping them in testbenches) and unified simulation timescale.
3. **CSR MIP Bit 7 Latch/Unused Signal**: `csr_regfile` was latching `mip[7] <= timer_irq` but reading direct timer wire. Simplified `mip` to a combinational assignment `{24'd0, timer_irq, 7'd0}`, saving 32 flip-flops and cleaning lint.
4. **Synthesis File Missing (`syn/synth.ys` & `pd/config.json`)**: Template configuration referenced legacy `if_stage.sv` / `id_stage.sv` files instead of `alu.sv`, `control.sv`, `imm_gen.sv`. Updated file lists to point to the correct modular design.
5. **IROM Hex Missing at Synth**: `irom.sv` attempted to `$readmemh` non-existent file when synthesizing without firmware. Changed default parameter to empty string `""` so synthesis gracefully initializes empty array, while testbenches pass hex paths explicitly.
6. **Yosys DFFLIBMAP Syntax**: Fixed invalid shell redirection syntax inside `syn/synth.ys` script that aborted synthesis.

---

## 2026-10-22 — RTL Implementation & Unit / System Verification

### ✅ Done
- **CPU Implementation (`rtl/cpu/`)**:
  - `alu.sv`: 32-bit ALU supporting all RV32I arithmetic, logical, comparison, and shift operations.
  - `regfile.sv`: 32×32-bit 2R/1W register file with hardwired `x0 = 0`.
  - `imm_gen.sv`: Immediate sign-extension for I, S, B, U, J instruction types.
  - `control.sv`: Opcode/funct3/funct7 decoder producing ALU, memory, branch, jump, and CSR control signals.
  - `hazard_unit.sv`: EX-to-EX and MEM-to-EX forwarding, 1-cycle load-use hazard stalling, branch and MRET pipeline flush.
  - `csr_regfile.sv`: Minimal machine-mode CSR set (`mstatus`, `mie`, `mip`, `mtvec`, `mepc`, `mcause`), trap entry, and `MRET`.
  - `rv32i_cpu.sv`: Full 5-stage pipelined CPU wrapper with dual Wishbone B4 master ports (IMEM and DMEM).
- **Bus & Memory (`rtl/bus/`, `rtl/mem/`)**:
  - `wb_interconnect.sv`: 1-master to 6-slave Wishbone B4 interconnect with address decode logic (`[23:16]`) and bus error generation.
  - `irom.sv`: 4 KB instruction ROM (0-wait-state combinational reads, loaded via `$readmemh`).
  - `dram.sv`: 4 KB data RAM (0-wait-state combinational reads, synchronous byte-enabled writes).
- **Peripherals (`rtl/periph/`)**:
  - `uart.sv`: Full-duplex UART with 16× oversampled baud rate generator, TX buffer, RX FIFO/status.
  - `spi_master.sv`: Mode 0 SPI master with programmable clock divider, 8 chip-select lines.
  - `gpio.sv`: 8-bit GPIO controller with direction control and 2-FF input synchronization.
  - `timer.sv`: 32-bit timer with compare-match interrupt, auto-reload, and W1C status.
- **Top-Level Integration (`rtl/top/minisoc_top.sv`)**:
  - Integrated CPU, interconnect, memories, and 4 peripherals.
- **Firmware & Linker (`fw/`)**:
  - `link.ld`, `startup.S`, `main.c`, `minisoc.h`, `bin2hex.py`, and `Makefile`.
- **System Testbench (`tb/system/tb_minisoc_top.sv`)**:
  - Self-checking firmware verification testing CPU execution, UART, SPI, GPIO, and Timer IRQ handler.

### 🐛 Bugs / Fixes
1. **Address Decoder Slicing (`wb_interconnect.sv`)**: Initial address decode used bits `[27:12]`, causing mismatch on `0x0001_0000`. Updated decoder to index on `m_wb_adr[23:16]`.
2. **UART Multiple Drivers (`uart.sv`)**: Resolved driver collision between `always_ff` blocks for `tx_shift` and `rx_ready`.
3. **UART Baud Divisor Matching (`uart.sv`)**: Synchronized TX and RX baud generators to clock on a common 16× tick divider.
4. **Hazard Unit RS/RD Matching (`hazard_unit.sv`)**: Corrected load-use condition to compare `id_ex_rd` against `if_id_rs1` / `if_id_rs2` instead of `id_ex_rs1`.
5. **Trap Return PC (`rv32i_cpu.sv`)**: Flushed bubbles with `pc=0` previously caused `mepc` corruption during interrupt entry. Calculated exact active instruction PC for `mepc`. Added `mret_taken` flush to clear pipeline on return.

---

## 2026-10-22 — Project Kickoff

### ✅ Done
- Created full repo directory structure (`rtl/`, `tb/`, `fw/`, `syn/`, `pd/`, `docs/`, `scripts/`)
- Authored `docs/ARCHITECTURE.md` with:
  - Mermaid top-level block diagram
  - Complete memory map (6 regions)
  - Pipeline description (5 stages, hazard table, pipeline register fields)
  - Wishbone bus signal table and address decoder logic
  - Full register maps for UART, SPI, GPIO, Timer
  - Interrupt architecture (minimal CSR set)
  - Top-level port list for `minisoc_top`
  - File tree
