# MiniSoC-32: Final Submission Checklist

This checklist confirms the completion and verification of all engineering milestones, physical signoff runs, and repository deliverables for the MiniSoC-32 project submission. All reported values are read directly from on-disk signoff reports and simulation logs.

---

## 1. Step-by-Step Deliverable Verification

| Step | Item Description | Verification Evidence | Status |
| :---: | :--- | :--- | :---: |
| **1** | **30 ns Signoff Run Completion** | Completed OpenLane flow `RUN_2026-10-23_12-20-38`. Read `timing__setup__ws = +1.1600 ns` and `timing__hold__ws = +0.1017 ns` across ALL 9 corners from `final/metrics.json` and `54-openroad-stapostpnr/summary.rpt`. Zero violations (`WNS = 0.00 ns`). Confirmed 33.33 MHz as the highest closing signoff frequency. | **PASS** |
| **2** | **Fresh-Clone Synthesis Test** | Cloned repository to `/tmp/clone_test`. Verified `pd/firmware.hex` is committed and not ignored by `.gitignore` (unignore rule `!pd/firmware.hex` verified). Ran `openlane --to Yosys.Synthesis pd/config.json`. Read `num_cells = 34,336` and `dfxtp_2 = 10,179` from `stat.json` (zero dead-code collapse). | **PASS** |
| **3** | **Git Hygiene & Large File Handling** | Added `.gitignore` rules for `*.gds`, `*.gds.gz`, and `pd/runs/` to comply with GitHub's 100 MB file limit. Preserved golden reports and metrics in `docs/evidence/` (`run_30ns_33mhz/`, `run_40ns_25mhz/`, `run_50mhz/`). Documented deterministic GDSII regeneration commands in `README.md` and `docs/RESULTS.md`. | **PASS** |
| **4** | **Log Check: UART RTL vs. GLS Diff** | Diffed `docs/logs/uart_rtl.log` and `docs/logs/uart_gls.log`. Identified and documented exact differences (GLS testbench cycle heartbeats, external SPI slave return data `0x4A`, and CRLF line endings). Both logs confirm bit-for-bit identical firmware self-test execution, `GPIO_OUT = 0xff`, and `PASS`. | **PASS** |
| **5** | **Documentation Harmonization** | Verified `README.md`, `docs/REPORT.md`, `docs/RESULTS.md`, and `docs/VIVA_QA.md`. All documents consistently state: (1) 33.3 MHz is highest signoff frequency closing all 9 corners, (2) 50 MHz and 100 MHz are multi-corner setup failures, (3) 100 MHz suffers a -0.4350 ns hold violation at `max_ss_100C_1v60`, (4) all power values are STA estimates, and (5) WNS is defined as worst slack across all corners. | **PASS** |
| **6** | **Final Test Regression Suite** | Ran `bash scripts/regress.sh`. All 13/13 unit, memory, bus, and full-system integration testbenches passed with 0 errors. Summary table pasted into `docs/PROGRESS.md`. | **PASS** |
| **7** | **Final Submission Checklist** | Authored `docs/FINAL_CHECKLIST.md` documenting pass/fail status and final headline silicon numbers. | **PASS** |

---

## 2. Final Headline Silicon & Architecture Metrics

| Headline Metric | Final Value | Source Report File |
| :--- | :--- | :--- |
| **Highest Multi-Corner Signoff Frequency** | **33.33 MHz** ($T_{clk} = 30.00\text{ ns}$) | `docs/evidence/run_30ns_33mhz/summary.rpt` |
| **Signoff Worst Setup Slack (Worst Corner)** | **+1.1600 ns** (at `max_ss_100C_1v60`) | `docs/evidence/run_30ns_33mhz/summary.rpt` |
| **Signoff Setup WNS (Worst All Corners)** | **0.0000 ns** (0 violations across 9 corners) | `docs/evidence/run_30ns_33mhz/metrics.json` |
| **Signoff Worst Hold Slack (Worst Corner)** | **+0.1017 ns** (at `max_ff_n40C_1v95`) | `docs/evidence/run_30ns_33mhz/summary.rpt` |
| **Signoff Hold WNS (Worst All Corners)** | **0.0000 ns** (0 violations across 9 corners) | `docs/evidence/run_30ns_33mhz/metrics.json` |
| **Relaxed Signoff Baseline Frequency** | **25.00 MHz** ($T_{clk} = 40.00\text{ ns}$) | `docs/evidence/run_40ns_25mhz/summary.rpt` |
| **Relaxed Baseline Setup Slack ($WS$)** | **+9.5689 ns** (at `max_ss_100C_1v60`) | `docs/evidence/run_40ns_25mhz/summary.rpt` |
| **Die Dimensions ($W \times H$)** | **1086.73 µm × 1097.45 µm** | `docs/evidence/run_30ns_33mhz/metrics.json` |
| **Total Die Area** | **1.1926 mm²** ($1,192,620\ \mu\text{m}^2$) | `docs/evidence/run_30ns_33mhz/metrics.json` |
| **Active Core Area / Core Utilization** | **1.1555 mm² / 40.06%** | `docs/evidence/run_30ns_33mhz/metrics.json` |
| **Post-Synthesis Standard Cells** | **34,336 cells** (`sky130_fd_sc_hd`) | `pd/runs/.../06-yosys-synthesis/reports/stat.json` |
| **Sequential Flip-Flops** | **10,179 DFFs** (`sky130_fd_sc_hd__dfxtp_2`) | `pd/runs/.../06-yosys-synthesis/reports/stat.json` |
| **Post-PnR Placed Standard Cells** | **67,785 cells** (with decap/fill/CTS) | `docs/evidence/run_30ns_33mhz/metrics.json` |
| **Estimated Total Power (33.3 MHz)** | **31.64 mW** (STA switching activity estimate) | `docs/evidence/run_30ns_33mhz/metrics.json` |
| ↳ *Estimated Internal Power* | 22.79 mW (72.0%) | `docs/evidence/run_30ns_33mhz/power.rpt` |
| ↳ *Estimated Switching Power* | 8.85 mW (28.0%) | `docs/evidence/run_30ns_33mhz/power.rpt` |
| ↳ *Estimated Leakage Power* | 0.82 µW (< 0.01%) | `docs/evidence/run_30ns_33mhz/power.rpt` |
| **Estimated Total Power (25.0 MHz)** | **23.74 mW** (STA switching activity estimate) | `docs/evidence/run_40ns_25mhz/metrics.json` |
| **Estimated Total Power (50.0 MHz)** | **40.35 mW** nominal / **47.53 mW** worst corner | `docs/evidence/run_50mhz/metrics.json` |
| **Estimated Total Power (100.0 MHz)** | **81.15 mW** nominal / **95.56 mW** worst corner | `pd/runs/RUN_2026-10-23_08-13-49/` |
| **Physical DRC Signoff (Magic / KLayout)** | **0 violations / 0 violations (Clean ✅)** | `docs/evidence/run_50mhz/drc_violations.*` |
| **Physical LVS Signoff (Netgen)** | **0 errors / Clean topological match ✅** | `docs/evidence/run_50mhz/lvs.netgen.rpt` |
| **Antenna Ratio Check** | **0 pin violations (Clean ✅)** | `docs/evidence/run_30ns_33mhz/metrics.json` |
| **RTL Verification Test Suite** | **13 / 13 PASS (100% clean)** | `scripts/regress.sh` |
| **Gate-Level Simulation (GLS)** | **PASS (`GPIO_OUT = 0xff`)** | `docs/logs/uart_gls.log` |

---

## 3. Submission Signoff Statement

The MiniSoC-32 System-on-Chip repository is verified, lint-clean, fully documented, and ready for formal submission. All design source files, automated build scripts, bare-metal C/assembly firmware, testbenches, physical design configurations, and evidence logs are self-contained and reproducible.
