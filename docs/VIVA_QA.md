# MiniSoC-32: Viva Voce & Oral Defense Examination Q&A

**Project Title:** MiniSoC-32: A 32-Bit RV32I System-on-Chip from RTL to GDSII  
**Technology:** SkyWater 130nm CMOS Standard Cell Library (`sky130_fd_sc_hd`)  
**Scope:** Computer Architecture, SystemVerilog RTL, Open-Source EDA, Physical Design, Verification  

---

## Category 1: Computer Architecture & RISC-V ISA

### Q1: Why was the RV32I ISA chosen for this project, and what are its base requirements?
**Answer:**  
RV32I is the fundamental unprivileged base integer instruction set of RISC-V. It has 40 instructions, operates on 32-bit registers, and uses fixed 32-bit instruction encoding with four primary formats: R-type (register-register), I-type (immediate/load), S-type (store), and B-type (branch), plus U-type (upper immediate) and J-type (unconditional jump). It requires:
1. 32 general-purpose integer registers (`x0` to `x31`), where `x0` is hardwired to 0.
2. A 32-bit program counter (`PC`).
3. Support for byte, halfword, and word memory operations (`LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`) with sign/zero extension.
4. Support for ALU arithmetic/logic operations, conditional branches with PC-relative offsets, and indirect jumps (`JAL`, `JALR`).  
RV32I was chosen because it provides a complete general-purpose computing foundation without licensing fees, microarchitectural patents, or excess silicon overhead.

---

### Q2: Explain the classic 5-stage RISC pipeline implemented in MiniSoC-32.
**Answer:**  
MiniSoC-32 uses an in-order 5-stage pipeline:
1. **IF (Instruction Fetch)**: Fetches the 32-bit instruction word from Instruction ROM (`IROM`) at the address given by `pc_reg`. Computes `PC + 4` sequentially or updates `PC` from branch/jump/trap targets.
2. **ID (Instruction Decode)**: Reads source registers `rs1` and `rs2` from the register file, decodes control signals (ALU op, memory read/write, branch flags), and sign-extends the immediate operand in `imm_gen`.
3. **EX (Execute)**: The 32-bit ALU performs arithmetic, logical, or shift operations. Computes target addresses for branches (`PC + imm`) and jumps. Resolves branch conditions (`BEQ`, `BNE`, `BLT`, etc.).
4. **MEM (Memory Access)**: Drives the Wishbone data bus master interface for load and store instructions (`dmem_wb`). Checks for pending timer interrupts.
5. **WB (Writeback)**: Selects between the ALU result, memory load data, or `PC + 4` (for link registers in `JAL`/`JALR`), and writes the final value to the destination register `rd`.

---

### Q3: How are Read-After-Write (RAW) data hazards detected and resolved in MiniSoC-32?
**Answer:**  
RAW hazards occur when an instruction in the `EX` stage requires the result of a preceding instruction that has not yet completed writeback to the register file.  
MiniSoC-32 uses a dedicated hardware **Hazard Unit (`hazard_unit.sv`)** implementing operand data forwarding:
- **EX-to-EX Forwarding**: If `ex_mem_reg_write == 1` and `ex_mem_rd != 0` and `ex_mem_rd == id_ex_rs1`, the ALU operand A multiplexer selects the ALU output from the `MEM` stage (`ex_mem_alu_result`). The same check applies to `rs2`.
- **MEM-to-EX Forwarding**: If `mem_wb_reg_write == 1` and `mem_wb_rd != 0` and `mem_wb_rd == id_ex_rs1` (and not already forwarded by EX-to-EX), operand A takes `wb_result`. The same check applies to `rs2`.  
Forwarding eliminates pipeline stalls for register-to-register ALU sequences, maintaining a throughput of 1 instruction per cycle ($CPI = 1.0$).

---

### Q4: Why is data forwarding insufficient for load-use hazards, and how does the CPU handle them?
**Answer:**  
In a load instruction (`LW rd, imm(rs1)`), the data operand is retrieved from memory at the end of the `MEM` stage. If the immediately following instruction consumes that register in its `EX` stage, the required data does not physically exist in time for execution—it is only available at the end of cycle $n+1$, whereas the consumer needs it at the start of cycle $n+1$.  

MiniSoC-32 detects this condition in hardware:
$$\text{Load-Use Hazard} = (\text{id\_ex\_mem\_read} == 1) \land [(\text{id\_ex\_rd} == \text{if\_id\_rs1}) \lor (\text{id\_ex\_rd} == \text{if\_id\_rs2})]$$
When asserted:
1. `stall_if = 1`: Freezes `pc_reg` so the next instruction is not fetched.
2. `stall_id = 1`: Freezes the `IF/ID` pipeline register to preserve the consumer instruction.
3. `flush_id_ex = 1`: Clears the `ID/EX` register, inserting a 1-cycle bubble (`NOP`).  
On the following cycle, the loaded data is forwarded from the `WB` stage into `EX` without further delay.

---

### Q5: What is the control hazard branch penalty in this core, and how is it handled?
**Answer:**  
Conditional branches and jumps are resolved in the **Execute (EX)** stage. By the time a branch is determined to be taken, two subsequent instructions have already entered the pipeline (one in `IF/ID` and one in `ID/EX`).  
- **Resolution**: The hazard unit asserts `flush_if_id = 1` and `flush_id_ex = 1`, converting both instructions into synchronous bubbles (`NOP`). Simultaneously, the PC multiplexer loads the branch target address into `pc_reg`.
- **Penalty**: A taken branch or jump incurs a deterministic **2-cycle penalty**. Untaken branches incur zero penalty ($CPI = 1$).

---

### Q6: Why is register `x0` hardwired to zero, and how is this implemented in hardware?
**Answer:**  
RISC-V mandates that register `x0` always reads as zero, and any writes to `x0` are discarded. This enables efficient pseudo-instructions:
- `NOP` is encoded as `ADDI x0, x0, 0`.
- Register moves (`MV rd, rs`) are encoded as `ADDI rd, rs, 0`.
- Unconditional jumps (`J label`) are encoded as `JAL x0, label`.  
In MiniSoC-32, this is enforced in two places in `rtl/cpu/regfile.sv`:
1. On read: `assign rs1_data = (rs1 == 5'd0) ? 32'd0 : ...`
2. On write: `if (we && (rd != 5'd0)) regs[rd] <= rd_data;`

---

### Q7: Explain the machine-mode CSR implementation and timer interrupt trap handling.
**Answer:**  
MiniSoC-32 implements a minimal Control and Status Register file (`csr_regfile.sv`):
- `mstatus`: Bit 3 (`MIE`) is the global interrupt enable.
- `mie`: Bit 7 (`MTIE`) enables the machine-timer interrupt.
- `mip`: Bit 7 (`MTIP`) reflects the external `timer_irq` line.
- `mtvec`: Base address of the trap handler (`0x0000_0070`).
- `mepc`: Latches the interrupted instruction PC.
- `mcause`: Latches the trap exception code (`0x8000_0007` for machine-timer interrupt).  

**Interrupt Sequence**:
1. When `timer_irq && mstatus.MIE && mie.MTIE` is detected in the `MEM` stage:
2. The active instruction PC is saved into `mepc`.
3. `mcause` is loaded with `0x8000_0007`.
4. Global interrupts are disabled (`mstatus.MIE = 0`).
5. The pipeline is flushed, and `pc_reg` is set to `mtvec`.

---

### Q8: How does the `MRET` instruction differ from a standard branch or jump?
**Answer:**  
`MRET` (Machine-mode Exception Return) is a privileged return instruction (opcode `0x73`, funct3 `0x0`, funct7 `0x18`):
1. Unlike branches or jumps which take a target from an immediate or register, `MRET` restores `PC` from the **`mepc` CSR**.
2. It automatically re-enables interrupts by restoring `mstatus.MIE = 1`.
3. It asserts pipeline flush signals to clear instructions fetched while returning from the trap handler.

---

## Category 2: SoC Interconnect & Memory Subsystem

### Q9: Why was the Wishbone B4 interconnect chosen, and how does its handshake work?
**Answer:**  
Wishbone B4 is an open-source, non-proprietary SoC bus specification widely adopted in open-source silicon projects. It is simpler than AXI4 while supporting pipelined transfers, byte enables, and bus errors.  
The standard handshake uses four primary signals:
- `wb_cyc` (Cycle): Master asserts to indicate a valid bus cycle.
- `wb_stb` (Strobe): Master asserts to indicate a valid slave transaction.
- `wb_we` (Write Enable): High for writes, low for reads.
- `wb_ack` (Acknowledge): Slave asserts when data has been accepted (write) or is valid (read).  
In MiniSoC-32, memory slaves respond with 0-wait-state combinational acks (`wb_ack = wb_stb && wb_cyc && rst_n`), completing accesses in 1 clock cycle.

---

### Q10: How does the address decoder route bus requests to six different slaves?
**Answer:**  
The address decoder in `rtl/bus/wb_interconnect.sv` decodes byte address bits **`m_wb_adr[23:16]`**:
- `0x00` $\to$ Instruction ROM (`0x0000_0000`–`0x0000_0FFF`)
- `0x01` $\to$ Data RAM (`0x0001_0000`–`0x0001_0FFF`)
- `0x02` $\to$ UART Controller (`0x0002_0000`–`0x0002_00FF`)
- `0x03` $\to$ SPI Master (`0x0003_0000`–`0x0003_00FF`)
- `0x04` $\to$ GPIO Controller (`0x0004_0000`–`0x0004_00FF`)
- `0x05` $\to$ 32-Bit Timer (`0x0005_0000`–`0x0005_00FF`)  
The decoder demultiplexes master control signals (`wb_stb`, `wb_we`, `wb_dat_o`, `wb_sel`) to the selected slave and multiplexes the selected slave's `wb_dat_i` and `wb_ack` back to the master. Unmapped addresses assert `m_wb_err`.

---

### Q11: Explain the purpose and architecture of the dual-port Instruction ROM.
**Answer:**  
In compiled C programs, string literals, jump tables, and constant data are placed in `.rodata` within the ROM image. If the ROM had only one port connected to instruction fetch (`imem`), any data load from ROM (`LW`, `LBU`) via the data bus (`dmem`) would fail or require bus arbitration that stalls instruction fetching.  
MiniSoC-32 implements **dual-port IROM (`irom.sv`)**:
- **Port A**: Read-only, connected to the CPU `imem_wb` bus for continuous instruction fetch.
- **Port B**: Read-only, connected to Slave 0 of the Wishbone interconnect, servicing `.rodata` reads from `dmem_wb`.  
Both ports read the same internal 1024-word memory array concurrently without bus contention.

---

### Q12: How is byte-enable masking implemented in Data RAM?
**Answer:**  
In `rtl/mem/dram.sv`, the 4 KB RAM is organized as four parallel byte lanes (`mem_b0` to `mem_b3`), each containing 1024 bytes:
```systemverilog
if (wb_sel[0]) mem_b0[word_addr] <= wb_dat_o[7:0];
if (wb_sel[1]) mem_b1[word_addr] <= wb_dat_o[15:8];
if (wb_sel[2]) mem_b2[word_addr] <= wb_dat_o[23:16];
if (wb_sel[3]) mem_b3[word_addr] <= wb_dat_o[31:24];
```
This enables single-byte stores (`SB`, `wb_sel = 4'b0001`), halfword stores (`SH`, `wb_sel = 4'b0011`), and full word stores (`SW`, `wb_sel = 4'b1111`) without read-modify-write overhead.

---

### Q13: What happens when an unmapped address is accessed on the bus?
**Answer:**  
If the CPU accesses an address outside defined peripheral and memory ranges (e.g., `0x0006_0000` to `0xFFFF_FFFF`), the address decoder detects no matching slave (`slave_sel == 6'b000000`). It immediately asserts **`m_wb_err = 1`** and terminates the transaction without bus deadlocks.

---

### Q14: How is bus contention avoided between instruction fetch and data memory access?
**Answer:**  
The SoC uses a Harvard-style split bus architecture at the CPU boundary:
- The CPU has two independent Wishbone master ports: `imem_wb` (dedicated to instruction fetch) and `dmem_wb` (dedicated to data load/store).
- Because `imem_wb` connects directly to Port A of the dual-port IROM while `dmem_wb` accesses the interconnect, instruction fetch and data memory transactions execute concurrently every clock cycle without pipeline stalls.

---

## Category 3: Memory-Mapped Peripherals

### Q15: How does the UART baud rate generator operate, and why use 16× oversampling?
**Answer:**  
The UART baud rate generator uses a 16-bit programmable divisor:
$$\text{baud\_div} = \frac{f_{clk}}{16 \times \text{baud}}$$
The clock divider produces a 16× tick enable.  
**Why 16× Oversampling?**  
In asynchronous serial communication, there is no shared clock. The receiver must detect the start bit (falling edge) and sample in the middle of each data bit to maximize noise margin:
1. When `uart_rx` falls, a 4-bit counter counts 8 ticks (mid-point of the start bit) to verify it is not noise.
2. The receiver then counts 16 ticks between subsequent samples, placing every sample point directly at the center (50% mark) of data bits 0–7 and the stop bit.

---

### Q16: Explain SPI Mode 0 and the role of the SPI clock divider.
**Answer:**  
SPI Mode 0 is defined by:
- **`CPOL = 0`**: SCK idles low when inactive.
- **`CPHA = 0`**: Data is sampled on the leading (rising) edge of SCK and shifted out on the trailing (falling) edge.  
In `spi_master.sv`, a programmable clock divider generates SCK:
$$f_{sck} = \frac{f_{clk}}{2 \times (\text{clk\_div} + 1)}$$
An 8-bit shift register shifts MOSI bits out on falling edges and shifts MISO bits in on rising edges. An 8-bit chip-select register (`spi_cs_n`) enables selecting up to 8 independent SPI slaves.

---

### Q17: Why are two-stage synchronizer flip-flops used on the GPIO inputs?
**Answer:**  
GPIO pins interface with external physical switches or asynchronous external chips whose signal transitions are uncorrelated with the SoC's internal clock (`clk`).  
If an asynchronous input transitions within the setup or hold time window of an internal flip-flop, the flip-flop can enter a **metastable state** (an intermediate non-logic voltage level), causing downstream logic hazards or system crashes.  
Passing the signal through two cascaded D-flip-flops (`sync0` and `sync1`) allows metastable oscillations to settle before the signal is sampled by internal logic, reducing the Mean Time Between Failures (MTBF) by orders of magnitude.

---

### Q18: Explain the timer compare-match interrupt mechanism and W1C status register.
**Answer:**  
In `rtl/periph/timer.sv`, an internal 32-bit register increments on every clock cycle when enabled (`TIMER_CTRL[0] == 1`).  
- **Compare Match**: When `TIMER_VAL == TIMER_CMP`, the hardware asserts `TIMER_STAT[0]` (`irq_pending`) and drives `timer_irq_out = 1` to the CPU.
- **Auto-Reload**: If `TIMER_CTRL[2] == 1`, the counter resets to 0 and continues counting.
- **Write-1-to-Clear (W1C)**: To clear the interrupt, firmware writes a `1` to `TIMER_STAT[0]`. Writing `0` has no effect. This prevents race conditions where an interrupt could be accidentally cleared while another event is triggering.

---

### Q19: Why are all peripheral register offsets structured on 32-bit word boundaries?
**Answer:**  
RV32I naturally generates 32-bit aligned byte addresses (`0x00`, `0x04`, `0x08`, `0x0C`). Aligning peripheral registers to 4-byte boundaries ensures that every register access corresponds to a simple word load/store (`LW`/`SW`), eliminating unaligned access exceptions and simplifying address decoding logic.

---

## Category 4: Logic Synthesis & EDA Toolchain

### Q20: What role does Yosys play in the toolchain, and how does it map generic RTL?
**Answer:**  
Yosys is an open-source framework for Verilog synthesis. Its flow includes:
1. **Elaboration & Hierarchy**: Parses SystemVerilog, checks modules, elaborates parameters, and builds the design hierarchy.
2. **Behavioral Optimization**: Performs dead-code elimination, constant folding, and state machine extraction.
3. **Logic Mapping**: Converts high-level operators (`+`, `-`, muxes) into generic logic gates and D-flip-flops.
4. **Technology Mapping (`abc`)**: Maps generic Boolean logic networks to the standard cell library (`sky130_fd_sc_hd`) based on Liberty (`.lib`) timing and area models.

---

### Q21: What is the difference between sequential inference and combinational logic in SystemVerilog?
**Answer:**  
- **Combinational Logic (`always_comb`)**: Outputs depend solely on current inputs. All branches of `if`/`case` constructs must be fully specified (or have defaults); otherwise, unwanted memory elements (**latches**) are inferred.
- **Sequential Logic (`always_ff @(posedge clk or negedge rst_n)`)**: Inferred as edge-triggered D-flip-flops. The state is only updated on the active clock edge.

---

### Q22: Why was Verilator linting enforced with `-Wall --lint-only`?
**Answer:**  
Verilator performs static analysis of SystemVerilog code, catching errors that standard simulators often silently accept:
- **`WIDTH`**: Mismatched bitwidths in assignments or comparisons.
- **`UNOPTFLAT`**: Combinational loops or unoptimized logic paths.
- **`LATCH`**: Inadvertently inferred transparent latches.
- **`CASEINCOMPLETE`**: Non-exhaustive case statements.  
Enforcing zero warnings across the entire codebase ensured that the RTL was 100% clean and synthesizable before physical design.

---

### Q23: Why did generic synthesis unroll DRAM into 32,768 flip-flops, and how should large memories be handled in ASICs?
**Answer:**  
In generic synthesis, memory arrays declared as `logic [7:0] mem [0:1023]` are synthesized using standard-cell D-flip-flops and large multiplexer trees. For 4 KB, this creates $4096 \times 8 = 32,768$ flip-flops and over 80,000 gates.  
In production ASICs, large memories are never built from standard cells; they are implemented using **SRAM Compiler Macros** (generated by tools like OpenRAM). These macros use 6T SRAM bitcells that are over $10\times$ more dense and consume significantly less dynamic power.

---

### Q24: How does the bare-metal C startup code (crt0) transition execution to `main()`?
**Answer:**  
In `fw/src/startup.S`:
1. **Stack Pointer**: Sets `sp = _stack_top` (`0x0001_1000`, the top of 4 KB DRAM).
2. **Copy `.data`**: Copies initialized data from ROM (LMA, `_etext`) to RAM (VMA, `_sdata` to `_edata`).
3. **Zero `.bss`**: Clears uninitialized global and static variables (`_sbss` to `_ebss`) by writing zeros.
4. **Setup Trap Vector**: Writes `_isr_entry` into the `mtvec` CSR.
5. **Call `main`**: Executes `call main`. If `main()` returns, the CPU enters an infinite loop (`.Lhalt: j .Lhalt`).

---

## Category 5: Physical Design & ASIC Signoff

### Q25: Walk through the OpenLane 2 physical design stages from RTL to GDSII.
**Answer:**  
1. **Synthesis**: Yosys maps RTL to SkyWater 130nm standard cells (`sky130_fd_sc_hd`); OpenROAD performs initial static timing analysis (STA).
2. **Floorplanning**: Establishes die area ($1086.73 \times 1097.45\ \mu\text{m}$, $1.1926\text{ mm}^2$), active core boundaries ($1.1555\text{ mm}^2$ at 40.06% core utilization), I/O pin placement, and well-tap cell insertion.
3. **Power Distribution Network (PDN)**: Generates power and ground grids (`VPWR`/`VGND`) on metal layers Met4 and Met5.
4. **Global Placement**: Positions standard cell instances across the core using analytical placement (Replace).
5. **Detailed Placement**: Legalizes cell positions into discrete standard cell rows without overlaps.
6. **Clock Tree Synthesis (CTS)**: Synthesizes a balanced buffer tree using TritonCTS to deliver the clock with minimal skew.
7. **Global Routing**: FastRoute creates routing guides across metal layers Met1–Met5.
8. **Detailed Routing**: TritonRoute completes physical wire connections, resolving DRC design rules.
9. **DFM / Fill Insertion**: Inserts decap and dummy fill cells to satisfy metal density rules.
10. **Signoff**: Runs Magic DRC, KLayout DRC, Netgen LVS, antenna rule verification, and final multi-corner STA. Generates the final GDSII layout.

---

### Q26: Explain the difference between Worst Setup Slack ($WSS$), Worst Negative Slack ($WNS$), and multi-corner signoff.
**Answer:**  
- **Setup Time ($T_{setup}$)**: The minimum time data must remain stable *before* the active clock edge.
  $$\text{Setup Slack} = T_{clk} - (T_{cq} + T_{comb\_max} + T_{setup} + T_{skew})$$
  A setup violation ($Slack < 0$) means the path delay exceeds the clock period.
- **Worst Negative Slack (WNS)**: Defined as $\min(0, \text{Worst Slack})$ across **all evaluated PVT corners**. A design only closes timing if $WNS = 0.00\text{ ns}$ across every operating corner.
- **Why Multi-Corner Signoff Matters**:
  A design may show positive slack at nominal conditions ($25^\circ\text{C}, 1.80\text{V}$, typical silicon) but fail in production under worst-case temperature and voltage droop.
  For example, in MiniSoC-32 at 50 MHz ($T_{clk}=20.0\text{ ns}$):
  - Nominal corner (`nom_tt_025C_1v80`): Slack is **+8.384 ns** ($F_{\max,nom} \approx 86.09\text{ MHz}$).
  - Worst slow corner (`max_ss_100C_1v60`, 100°C, 1.60V): Carrier mobility drops and wire RC increases, stretching path delay to $22.715\text{ ns}$, yielding a setup slack of **-2.7145 ns** and **WNS = -2.7145 ns** (Failed multi-corner signoff).
  - True multi-corner signoff was achieved at **25 MHz (40.0 ns)**, which provides **+9.5689 ns slack** at `max_ss_100C_1v60`, closing cleanly with **WNS = 0.00 ns** across all 9 PVT corners.
- **Hold Time ($T_{hold}$)**: The minimum time data must remain stable *after* the active clock edge.
  $$\text{Hold Slack} = (T_{cq} + T_{comb\_min} - T_{skew}) - T_{hold}$$
  Hold violations cannot be fixed by slowing the clock—they must be resolved during PnR by inserting delay buffers. MiniSoC-32 achieved zero hold violations across all corners ($WHS = +0.1087\text{ ns}$).

---

### Q27: How does Clock Tree Synthesis (CTS) prevent hold time violations?
**Answer:**  
CTS inserts a balanced network of clock inverters and buffers from the clock root pin to all sequential flip-flops. By balancing propagation delays, it minimizes **clock skew** (the arrival time difference between any two flip-flops). In MiniSoC-32, OpenLane's CTS achieved balanced clock distribution across all 10,179 sequential flip-flops, leaving a positive hold slack margin of **+0.1087 ns** at the fastest corner (`min_ff_n40C_1v95`) and zero hold violations across all 9 corners.

---

### Q28: What is the difference between Magic DRC and KLayout DRC?
**Answer:**  
- **Magic DRC**: Uses an abstract, simplified corner-stitched geometry engine integrated directly with extraction and LVS. It performs fast continuous design-rule checks during interactive layout.
- **KLayout DRC**: Uses standard polygonal boolean geometry engines running golden, foundry-grade DRC decks. It catches deep sub-micron design rules (e.g., minimum enclosure rules, antenna ratios, density rules) with production foundry precision.  
Passing both ensures manufacturability at SkyWater.

---

### Q29: What is Layout-Versus-Schematic (LVS), and how does Netgen verify it?
**Answer:**  
LVS verifies that the physical geometry drawn in the GDSII layout exactly matches the logical circuit defined in the synthesized Verilog netlist.  
- **Extraction**: Magic extracts electrical devices (MOSFETs) and interconnect nets from the layout polygons.
- **Netlist Comparison**: Netgen compares the extracted SPICE netlist against the synthesized gate netlist. It verifies that every transistor, standard cell pin, supply rail (`VPWR`, `VGND`), and net match 1:1 with zero shorts, opens, or mismatched topologies.

---

### Q30: How were the power metrics calculated, and why does dynamic power scale linearly with frequency while leakage remains constant?
**Answer:**  
Power figures are **estimates** computed by OpenROAD Static Timing Analysis (STA) using Liberty (`.lib`) characterization tables under default switching activity assumptions (toggle rate $\alpha = 0.1$ at inputs):
$$P_{total} = P_{internal} + P_{switching} + P_{leakage}$$
- **Dynamic Power ($P_{internal} + P_{switching}$)**: Caused by charging and discharging parasitic capacitance ($C_{load}$) and momentary crowbar currents during CMOS transitions:
  $$P_{dyn} = C_{load} \cdot V_{DD}^2 \cdot f \cdot \alpha$$
  Because $P_{dyn} \propto f$, increasing frequency from 25 MHz to 50 MHz and 100 MHz scales estimated total power from **23.74 mW** (25 MHz) to **40.35 mW** (50 MHz) and **81.15 mW** (100 MHz) ($2.01\times$ scaling between 50 and 100 MHz).
- **Leakage Power ($P_{leakage}$)**: Caused by sub-threshold conduction and gate oxide tunneling when transistors are idle. Because supply voltage and temperature remained constant, leakage power remained negligible ($0.39$ to $0.82\ \mu\text{W}$).
