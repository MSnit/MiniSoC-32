# MiniSoC-32: Open-Source RISC-V (RV32I) System-on-Chip

[![RTL Verification](https://img.shields.io/badge/RTL%20Verification-13%2F13%20PASS-brightgreen.svg)]()
[![Verilator Lint](https://img.shields.io/badge/Verilator%20Lint-100%25%20Clean-brightgreen.svg)]()
[![Synthesis](https://img.shields.io/badge/Yosys-Synthesizable-brightgreen.svg)]()
[![OpenLane 2 Signoff](https://img.shields.io/badge/OpenLane%202-GDSII%20Clean%20(Sky130)-brightgreen.svg)]()
[![Gate-Level Sim](https://img.shields.io/badge/GLS-PASS-brightgreen.svg)]()

**MiniSoC-32** is a synthesizable 32-bit RISC-V System-on-Chip designed from RTL architecture to GDSII silicon layout using exclusively open-source EDA tools. The core implements the standard unprivileged RV32I integer instruction set in a classic 5-stage pipeline, connected over a Wishbone B4 interconnect to 4 KB instruction ROM, 4 KB byte-addressable data RAM, and 4 memory-mapped peripherals (UART, SPI Master, GPIO, Timer with interrupt).

---

## Architecture Overview

```mermaid
flowchart TD
    subgraph CPU ["RV32I 5-Stage Pipelined CPU"]
        IF["IF (Instruction Fetch)"] --> ID["ID (Instruction Decode)"]
        ID --> EX["EX (Execute / ALU)"]
        EX --> MEM["MEM (Memory Access)"]
        MEM --> WB["WB (Writeback)"]
        HAZ["Hazard Unit\n(Forwarding + Stall/Flush)"] -.-> ID
        HAZ -.-> EX
        CSR["Machine CSR File\n(Timer IRQ, MRET)"] -.-> EX
        CSR -.-> MEM
    end

    subgraph BUS ["Wishbone Interconnect (1 Master, 6 Slaves)"]
        DEC["Address Decoder\nBits [23:16]"]
    end

    subgraph MEMORY ["Memory Subsystem"]
        IROM["4 KB Dual-Port IROM\n(0x0000_0000)\nPort A: Fetch | Port B: .rodata"]
        DRAM["4 KB Byte-Enabled DRAM\n(0x0001_0000)"]
    end

    subgraph PERIPHERALS ["Memory-Mapped Peripherals"]
        UART["UART (0x0002_0000)\n16x Baud Divisor, TX/RX Buffers"]
        SPI["SPI Master (0x0003_0000)\nMode 0, 8 Chip Selects"]
        GPIO["8-bit GPIO (0x0004_0000)\nDirection Register + Sync"]
        TIMER["32-bit Timer (0x0005_0000)\nCompare Match Interrupt"]
    end

    CPU -->|"IMEM Wishbone Port"| IROM
    CPU -->|"DMEM Wishbone Port"| DEC
    DEC --> IROM
    DEC --> DRAM
    DEC --> UART
    DEC --> SPI
    DEC --> GPIO
    DEC --> TIMER
    TIMER -->|"timer_irq"| CSR
```

### Key Technical Specifications
- **CPU Core**: RV32I 5-stage pipeline (`IF`, `ID`, `EX`, `MEM`, `WB`).
- **Hazard Handling**:
  - Full data forwarding (EX-to-EX and MEM-to-EX paths for ALU operations).
  - 1-cycle hardware load-use hazard stall with pipeline bubble insertion.
  - 2-cycle branch and jump flush penalty.
- **CSR & Interrupts**: Minimal machine-mode CSRs (`mstatus`, `mie`, `mip`, `mtvec`, `mepc`, `mcause`), vectored machine-timer interrupt trap handling, and `MRET` instruction.
- **Interconnect**: Wishbone B4 pipelined architecture, byte-enable (`wb_sel[3:0]`) support, with address decoding on `m_wb_adr[23:16]`.
- **Memory**:
  - 4 KB dual-port Instruction ROM (concurrent CPU fetch and `.rodata` Wishbone access).
  - 4 KB byte-addressable Data RAM with independent byte lanes.
- **Peripherals**:
  - UART: Full-duplex, 16× oversampled baud rate generator, status flags (`tx_idle`, `rx_ready`).
  - SPI Master: Mode 0 (CPOL=0, CPHA=0), programmable clock divider, 8 chip-select lines.
  - GPIO: 8-bit bidirectional I/O with data direction register and 2-stage synchronizer flip-flops.
  - Timer: 32-bit up-counter with target compare match, auto-reload, and interrupt assertion to CPU.

---

## Memory Map

| Region | Base Address | End Address | Size | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Instruction ROM** | `0x0000_0000` | `0x0000_0FFF` | 4 KB | Read-only firmware storage (`.text`, `.rodata`) |
| **Data RAM** | `0x0001_0000` | `0x0001_0FFF` | 4 KB | Read/Write data storage (`.data`, `.bss`, stack) |
| **UART Controller** | `0x0002_0000` | `0x0002_00FF` | 256 B | Data TX/RX registers, status, and baud divisor |
| **SPI Master** | `0x0003_0000` | `0x0003_00FF` | 256 B | Control/status, clock divider, chip-select, TX/RX |
| **GPIO Controller** | `0x0004_0000` | `0x0004_00FF` | 256 B | Data input, data output, and direction registers |
| **32-Bit Timer** | `0x0005_0000` | `0x0005_00FF` | 256 B | Counter value, compare match, control, and status |

**Reset Vector:** `0x0000_0000`  
**Stack Pointer Top:** `0x0001_1000` (Top of DRAM)

---

## Repository Structure

```text
minisoc/
├── docs/                      # Comprehensive technical documentation
│   ├── ARCHITECTURE.md        # Hardware specifications and register maps
│   ├── REPORT.md              # Full academic final-year project report
│   ├── RESULTS.md             # Synthesis, physical design, and timing signoff
│   ├── PROGRESS.md            # Engineering development log & bug fix tracker
│   └── VIVA_QA.md             # 30 viva exam questions and detailed answers
├── fw/                        # Bare-metal C & Assembly firmware
│   ├── include/minisoc.h      # Memory-mapped peripheral drivers & CSR macros
│   ├── src/startup.S          # Vector initialization, crt0, stack & trap handler
│   ├── src/main.c             # Multi-peripheral self-test firmware
│   ├── src/demo_*.c           # Individual peripheral demo programs
│   ├── link.ld                # GNU ld linker script (IROM + DRAM sections)
│   └── Makefile               # Firmware compilation and hex generation
├── rtl/                       # Synthesizable SystemVerilog RTL
│   ├── cpu/                   # ALU, Regfile, Control, Imm-Gen, Hazards, CSRs, CPU
│   ├── bus/                   # Wishbone B4 interconnect and address decoder
│   ├── mem/                   # Dual-port IROM and byte-enabled DRAM
│   ├── periph/                # UART, SPI Master, GPIO, and 32-bit Timer
│   └── top/minisoc_top.sv     # System-on-Chip top-level integration
├── tb/                        # Self-checking testbenches
│   ├── unit/cpu/              # CPU module unit testbenches
│   ├── unit/bus/              # Bus decoder testbench
│   ├── unit/mem/              # IROM and DRAM unit testbenches
│   ├── unit/periph/           # UART, SPI, GPIO, and Timer testbenches
│   ├── soc_tb.sv              # Full-system testbench with real-time UART RX
│   └── system/                # System-level RTL and Gate-Level testbenches
├── syn/                       # Yosys synthesis scripts & mapped netlists
├── pd/                        # OpenLane 2 configs, PnR runs, and GDSII layouts
└── scripts/                   # Automated build & regression scripts
    ├── regress.sh             # 13/13 test suite regression script
    ├── prepare_gls.py         # Gate-level simulation netlist prep script
    └── run_all.sh             # End-to-end regression, synthesis & GLS runner
```

---

## Toolchain Prerequisites

Ensure the following open-source tools are installed (Ubuntu / WSL):
- **Simulation**: Icarus Verilog (`iverilog` >= 12.0) or Verilator (>= 5.018)
- **Waveforms**: GTKWave
- **Firmware**: RISC-V GNU Toolchain (`riscv64-unknown-elf-gcc` or `riscv32-unknown-elf-gcc`)
- **Synthesis**: Yosys (>= 0.52)
- **Physical Design**: OpenLane 2 (>= 2.3.10) with SkyWater 130nm (`sky130_fd_sc_hd`) PDK installed in `~/.volare`

---

## Quickstart & Execution

### 1. Build Firmware & Demos
```bash
cd fw
make clean && make all
make demos
```

### 2. Run RTL Testbench Regression (13/13 PASS)
```bash
bash scripts/regress.sh
```

### 3. Run Yosys Logic Synthesis
```bash
yosys -s syn/synth.ys
```

### 4. Run OpenLane 2 Physical Design (RTL-to-GDSII)
```bash
# 50 MHz run
openlane --dockerized pd/config_50mhz.json

# 100 MHz run
openlane --dockerized pd/config_100mhz.json
```

### 5. Run Gate-Level Simulation (GLS)
```bash
python3 scripts/prepare_gls.py
iverilog -g2012 -o /tmp/tb_gls.vvp /usr/share/yosys/simlib.v syn/reports/minisoc_top_gls.v tb/system/tb_minisoc_top_gls.sv
vvp /tmp/tb_gls.vvp
```

### 6. Run Complete Pipeline (Regression + Synthesis + GLS)
```bash
bash scripts/run_all.sh
```

---

## Physical Design Signoff Summary (SkyWater 130nm)

| Metric | 50 MHz Target | 100 MHz Target | Signoff Status |
| :--- | :--- | :--- | :--- |
| **Clock Period ($T_{clk}$)** | 20.00 ns | 10.00 ns | Met ✅ |
| **Setup Slack (WSS)** | +13.43 ns | +5.45 ns | Met (WNS = 0.00 ns) ✅ |
| **Hold Slack (WHS)** | +0.115 ns | +0.116 ns | Met (Zero violations) ✅ |
| **Critical Path Delay** | 4.57 ns | 4.55 ns | Register file to ALU comparator |
| **Maximum Frequency ($F_{max}$)** | 218.8 MHz | 219.6 MHz | In SkyWater 130nm HD cells |
| **Total Power Dissipation** | 82.53 µW | 177.09 µW | Dynamic frequency scaling |
| **Die Dimensions** | 57.36 × 68.08 µm | 57.36 × 68.08 µm | 3,905.07 µm² die area |
| **Standard Cell Area** | 1,020.98 µm² | 1,024.73 µm² | Core utilization: 48.18% |
| **DRC / LVS / Antenna** | 0 / 0 / 0 | 0 / 0 / 0 | 100% Clean Signoff ✅ |

---

## Documentation Links

- **[Detailed Project Report](file:///home/manthan/minisoc/docs/REPORT.md)**: Comprehensive academic report with methodology, results, and architecture analysis.
- **[Architectural Specification](file:///home/manthan/minisoc/docs/ARCHITECTURE.md)**: Hardware interfaces, pipeline stages, and peripheral register maps.
- **[Physical Design Results](file:///home/manthan/minisoc/docs/RESULTS.md)**: OpenLane 2 metric tables, power analysis, and DRC/LVS logs.
- **[Engineering Progress Log](file:///home/manthan/minisoc/docs/PROGRESS.md)**: Chronological development history and bug fixes.
- **[Viva Voce Examination Q&A](file:///home/manthan/minisoc/docs/VIVA_QA.md)**: 30 likely technical interview and oral defense questions with in-depth answers.
