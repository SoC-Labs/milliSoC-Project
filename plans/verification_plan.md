# milliSoC Verification Plan

| | |
|---|---|
| **Status** | Proposal — D1–D8 accepted; Stage 0 awaiting review |
| **Scope** | `millisoc_tech` RTL, `millisoc_sdk` firmware/apps, `verif/`, `flows/`, regression and coverage |
| **DUT** | milliSoC SoC top (`millisoc_tb` → `millisoc_system`) with Cortex-R5, Cortex-M85, PL192 VIC, NIC400, DMA350, QSPI, peripherals, MHU, shared SRAM, Ethos-U85, CoreSight debug |
| **Last updated** | 2026-11-05 |
| **Related plans** | `plans/ethos_u85_integration.md`, `plans/millisoc_debug_subsystem.md` |

**Implementation status:** no implementation has started. D1–D8 are accepted
and incorporated below; Stage 0 remains pending review of this plan.

---

## 1. Purpose and scope

This plan defines how milliSoC should be verified as an integrated SoC. It is
deliberately layered: it keeps the existing firmware-driven integration tests,
adds machine-checked test outcomes, adds RTL-level protocol and negative tests,
and closes coverage on milliSoC-owned logic and integration boundaries.

### 1.1 Goals

1. Make every test produce a **machine-checked pass/fail** via a terminal UART
   marker and a global timeout, so regression results cannot depend on a `$stop`
   or an unstructured log tail.
2. Verify the **R5-first boot path** end to end after every reset source:
   flash preamble, DMA preload of both TCMs, CPUWAIT release, and both cores
   running their applications.
3. Verify the **memory map** seen by the R5, M85, DMA350, debug APB/AXI, and
   U85: decode, aliasing, boundaries, access sizes, error responses, and
   consistency with firmware headers, scatter files, and NIC400 XML.
4. Verify **reset and interrupt architecture**: reset sources/scopes, reset cause
   recording, VIC0 and VIC1 (including daisy-chain), M85 NVIC, and every
   firmware-visible interrupt number.
5. Verify **shared resources and contention**: shared SRAM, main NIC400, RT
   peripheral NIC400, AHB/APB peripherals, DMA, MHU, QSPI, and U85.
6. Verify **debug and trace integration** at the interface level, deferring the
   full debug-subsystem programme to `plans/millisoc_debug_subsystem.md`.
7. Establish a **regression and coverage baseline** that runs locally, with
   published coverage numbers and waivers; keep the targets structured so CI can
   be added later.
8. Verify the **SoC-visible functionality of the Arm IP** (boot, reset,
   interrupts, bus transactions, memory map, firmware-visible registers, and
   error behavior) while treating the IP's internal implementation as
   pre-verified.

### 1.2 Non-goals

* Assume Arm IP internal implementation is pre-verified (Cortex-R5,
  Cortex-M85, NIC400, PL192, DMA350, CoreSight, Ethos-U85), but verify the
  **configured instance's SoC-visible functionality and integration**: boot,
  reset, interrupts, memory map, bus behavior, firmware-visible registers, and
  error responses.
* Do not replace the PL192 VIC with a GIC.
* Do not define a generic accelerator framework. Verify the U85 demonstrator
  against the replaceable boundary defined in `plans/ethos_u85_integration.md`.
* Do not treat FPGA timing closure or ASIC sign-off as part of this plan; those
  are follow-on flows.
* Do not assume cache coherency, TrustZone policy, or DMA visibility that is not
  explicitly implemented and tested.

### 1.3 Terminology

| Term | Meaning |
|------|---------|
| SoC test | Firmware-driven test running on R5 and/or M85, as today |
| Directed SV test | SystemVerilog stimulus/checker running in `millisoc_tb` |
| Unit test | Module-level TB, e.g. `verif/unit/millisoc_sys_ctrl_tb.sv` |
| Integration test | Multi-module RTL test around a subsystem boundary |
| Candidate defect | Behaviour inferred from source inspection but not yet reproduced |
| P0/P1/P2 | Verification priority: boot/security-critical, core function, robustness |

---

## 2. Current verification baseline (evidence, 2026-11-05)

### 2.1 Existing assets

| Asset | Location | Maturity | Notes |
|---|---|---|---|
| SoC testbench | `verif/testbench/millisoc_tb.sv` | Working for `hello` | Instantiates DUT, flash model, UART capture, DAP BFM, AXI loggers, trace checks |
| Flash model | `sst26vf064b` in TB | Basic | Preloaded with `image.hex` via `$readmemh`; no timing/error injection |
| UART capture | `verif/monitors/uart_logger.v` | Basic | Logs characters and stops on `0x04`; no structured test result |
| AXI loggers | `verif/monitors/axi3_logger.sv`, `axi4_logger.sv` | Passive | Handshake logging only; no protocol assertions/scoreboard |
| DAP SWD BFM | `verif/monitors/` / TB | Good | Self-checking AP0–AP3 and SWD checks; `ALL TESTS PASSED` in `hello` |
| Trace checks | `verif/testbench/millisoc_tb.sv` | Partial | M85 ITM and R5/M85 ETM activity checked when `+TRACE`; no packet decode |
| Unit TBs | `verif/unit/millisoc_sys_ctrl_tb.sv`, `millisoc_reset_ctrl_tb.sv` | New, untracked | Self-checking `$fatal`; not wired into any make target |
| Firmware apps | `millisoc_sdk/apps/` | Mixed | See §2.2 |
| Bootloader | `millisoc_sdk/bootloader/bootloader.c` | Working | R5-first boot, DMA, VIC, QSPI, CPUWAIT release |
| Simulation flow | `flows/simulate.mk` | Working for VCS | `make compile`/`run` require `SIMULATOR=vcs` |
| Regression flow | `flows/regression.mk` | **Empty** | No regression target |
| Lint flow | `flows/lint.mk` | Partial | `lint_hal` exists; not part of regression |
| Cocotb flow | root `make run_cocotb` | Broken | References missing `verif/cocotb/` |
| Questa flow | `flows/simulate.mk` | Broken | `run_mti`/`sim_mti` use undefined `$(TB_TOP)` |

### 2.2 SDK application status

| App | Files | What it actually does | Verification value | Status |
|---|---|---|---|---|
| `hello` | `hello_M.c`, `hello_R.c` | Both cores print a banner; `UartEndSimulation()` | Boot smoke test | Passes end to end |
| `reset_control` | `reset_control_M.c`, `reset_control_R.c` | Reset cause, CPUWAIT/MHU handshake, M85 local reset, software system reset, then requests watchdog reset | Best reset test | Does not complete the watchdog-reset stage |
| `reset_demo` | `reset_demo.c` only | Single-file demo | Low | `all_ds6` expects `_M`/`_R`; build fails |
| `sram_tests` | `sram_tests_M.c` | M85-only pattern test of a small shared-SRAM window | Low/medium | Does not test upper half or R5/DMA access |
| `mhu_tests` | `mhu_tests_M.c`, `mhu_tests_R.c` | Reads IDs, one doorbell, then waits | Medium | No mailbox/error/stress coverage |
| `bus_access` | `bus_access_M.c`, `bus_access_R.c` | Print-only stub | None as written | Needs real access matrix |
| `debug_access` | `debug_access_R.c` | Reads APBIC ROM component IDs | Low | Does not exercise system-bus debug |
| `u85_tests` | `u85_tests_M.c`, `u85_tests_R.c` | Writes U85 config registers; no completion/result checks | Low | Not a functional U85 test |

### 2.3 Observed test results

* `simulate/sim/hello/logs/run_hello.log` shows the bootloader banner, both UART
  banners, DAP BFM `ALL TESTS PASSED`, trace `PASS` lines, and `Test Ended`.
* `simulate/sim/reset_control/logs/run_reset_control.log` ends at the request for
  a watchdog system reset. The README already records that the watchdog-reset
  stage did not complete.
* Only `hello` and `reset_control` run directories are present. The other apps
  have not been run in this checkout.
* `CheckResults.log` (NIC400 DRC, 2026-11-02) contains warnings including
  `U85_SRAM0/1/EXT0` 40-bit address width against a 32-bit global address width,
  and an APB group `WriteIssuing(1) < WriteAcceptance(4)` mismatch.

### 2.4 Verification gaps and candidate defects

| ID | Gap / candidate defect | Evidence | Severity | Action |
|---|---|---|---|---|
| G1 | No machine-readable pass/fail; `$stop` on both cores; no global timeout | `verif/testbench/millisoc_tb.sv` `test_done` sticky logic and `$stop`; `uart_logger` stop on `0x04` | High | Add UART terminal markers (`*** TEST PASS ***`/`*** TEST FAIL ***`), `$fatal` timeout, `$finish`, and a log parser (D2) |
| G2 | R5 firmware only programs VIC0; IRQs 32–63 require VIC1 at `VIC_BASE+0x1000` | RTL instantiates two PL192 VICs (`Vic`/`Vic1`) with `HADDR_GIC[12]` select; `millisoc_sdk/libs/Drivers/Include/vic.h` defines only `VIC_BASE`; `vic.c` uses `1 << irq` | High (D3 accepted) | Add VIC1 support and directed VIC1 tests in Stage 1 |
| G3 | Shared SRAM decodes 1 MiB but currently implements 512 KiB; upper half aliases | NIC400 `SHARED_SRAM` = `0x30000000–0x300FFFFF`; `millisoc_sram_wrapper.sv` uses `memaddr[15:0]` into `SRAM #(.ADDR_WIDTH(16))` | Accepted limitation (D4) | Keep RTL/NIC as is; document the 512 KiB software limit; add an alias-characterization test; make the size configurable later |
| G4 | R5 `sys_memory_map.h` is stale/Corstone-derived: `SRAM_BASE 0x20000000`, `ITCM/DTCM` naming, no ATCM `0x80000000` | `millisoc_sdk/libs/Device/R5/Include/sys_memory_map.h`; bootloader loads R image at `0x80000000`; M85 header uses `SRAM_BASE 0x30000000` | High (D5 accepted) | Replace with an R5-specific map that matches the RTL, including the local ATCM and the AXI-slave/DMA TCM views; keep it separate from M85; add a consistency test |
| G5 | R5 `exectb_mcu.h` IRQn map disagrees with `irq_map.h` and RTL | `millisoc_sdk/libs/Device/R5/Include/exectb_mcu.h` (e.g. `QSPI=5`, `TIMER0=40`) vs `irq_map.h` (`QSPI=2`), vs `millisoc_system.sv` `Rx_CPU_IRQs` | High (D5 accepted) | Align the R5 `exectb_mcu.h` IRQn values with R5 `irq_map.h` (or remove the duplicate); keep R5 and M85 maps separate |
| G6 | Watchdog-reset scenario does not complete | `simulate/sim/reset_control/logs/run_reset_control.log` ends at watchdog request | High | Debug watchdog reset path; add timeout and reset-cause check |
| G7 | No AXI/AHB/APB protocol assertions or scoreboards; loggers are passive | `verif/monitors/axi3_logger.sv`, `axi4_logger.sv` | High | Add bind-based protocol assertions and a memory scoreboard |
| G8 | No functional/structural coverage | No coverage flags/files in `flows/simulate.mk`; no coverage dir | High | Add VCS coverage, covergroups, reports, waivers |
| G9 | No local regression target or manifest | `flows/regression.mk` empty | High | Add local `regress` targets, manifest, and parser; CI can be added later (D6) |
| G10 | Unit TBs are untracked and unwired | `verif/unit/` new files; no make target | Medium | Add `verif/unit/Makefile` and a unit regression |
| G11 | Stub/incomplete apps hide failures | `bus_access` print-only; `u85_tests` no checks; `sram_tests` 4 KiB M85-only; `reset_demo` single-file | Medium | Replace with checked tests |
| G12 | `make testcode` busy-waits with `sleep 5`; failures can hang | `flows/software.mk` | Medium | Fail fast on missing hex |
| G13 | `run_cocotb` references missing `verif/cocotb/`; `run_mti` uses undefined `TB_TOP` | root makefile / `flows/simulate.mk` | Low/Medium | Add dir or remove target; fix `TB_TOP` |
| G14 | NIC400 DRC warnings for U85 address width and APB group issuing/acceptance | `CheckResults.log` | Medium | Resolve or document in the integration plan |
| G15 | No negative/error tests, no reset-during-traffic, no contention/stress, no TrustZone/security tests | Test inventory | High | Add directed tests in Stages 2–3 |

**Decision status:** D3 and D5 are implementation work; D4 is an accepted current
limitation. See §11.3 and Appendix C. No implementation has started; Stage 0 is
pending review.

---

## 3. Verification strategy

### 3.1 Layered V-model

| Layer | What is verified | Primary method | Owner |
|---|---|---|---|
| L0 Static | Lint, CDC/RDC, elaboration, address-map consistency, parameter consistency | HAL lint, CDC tool, scripts | RTL/verification |
| L1 Unit | `sys_ctrl`, `reset_ctrl`, `sram_wrapper`, peripheral decode, UART, timers, watchdog, GPIO, SPI, MHU, DMA, QSPI, U85 wrapper, debug APBIC | Module TBs, reusable VIP | IP integration |
| L2 Integration | CPU subsystem, RT peripheral subsystem, main NIC400, shared SRAM, boot path, interrupts, reset, debug, U85 | Directed SV tests + assertions | SoC verification |
| L3 SoC | Boot, applications, memory map, reset, interrupts, DMA, MHU, U85, debug, trace, stress | Firmware-driven tests + TB checkers | SoC verification |
| L4 System | FPGA bring-up, debugger, flash, U85 | Hardware/FPGA tests | Platform |

### 3.2 Hybrid approach: keep firmware, add checkers

The existing firmware tests are good at exercising the **real software boot and
peripheral programming sequences**; they are weak at observability and negative
cases. The plan therefore:

* keeps `millisoc_tb` and the firmware flow as the system-level test vehicle;
* adds a UART `*** TEST PASS ***`/`*** TEST FAIL ***` contract and a log parser
  so firmware reports machine-readable results;
* adds **SV protocol assertions, memory-map checkers, interrupt/reset monitors,
  and coverage** around the existing DUT;
* adds **unit and integration TBs** only where firmware cannot reach (protocol
  errors, aliasing, contention, reset during traffic, debug internals);
* reuses Arm IP verification collateral (MHU VIP, QSPI cocotb/UVM, DMA350 and
  NIC400 validation) instead of re-implementing IP checkers, while still
  verifying the SoC-visible functionality of each configured IP instance (D1).

### 3.3 Risk-based priorities

* **P0:** boot path, reset cause/scope, R5 interrupt delivery, memory-map decode,
  shared SRAM size/alias characterization, watchdog reset, machine-checked
  regression.
* **P1:** DMA, QSPI, MHU, peripherals, M85 NVIC, debug system-bus access,
  U85 configuration/IRQ, protocol assertions, coverage.
* **P2:** stress/random, contention/performance, TrustZone/security policy,
  FPGA/ASIC-specific checks.

### 3.4 What “verified” means

For this plan:

* **Verified** — reproduced in simulation with a machine-checked result and a
  log/coverage artifact.
* **Observed** — read in source or an existing log; not independently reproduced.
* **Candidate** — inferred from source but not yet reproduced; must be confirmed
  by a directed test before it is treated as a defect or a guarantee.

---

## 4. DUT, interfaces, and configuration

### 4.1 Top level

* DUT top: `millisoc_system` inside `verif/testbench/millisoc_tb.sv`.
* Clock/reset: `FCLK`, `nPORESET`, plus DAP `SWCLKTCK`/`nTRST`, trace clock, and
  the 32 kHz RT clock in the RT peripheral subsystem.
* External pads: QSPI (`QSPI_SCLK`, `QSPI_nCS`, `QSPI_IO[3:0]`), two UART TX/RX
  pairs, DAP SWD/JTAG, trace, GPIO, SPI, reset request.
* Configuration: `millisoc.config` (`CPU_TYPE=CM85`, `R_CPU_TYPE=CR5`), U85
  present/absent, shared SRAM size, debug options.

### 4.2 Memory map (authoritative sources to reconcile)

| Region | Base | End | Seen by | Notes |
|---|---|---|---|---|
| M85 ITCM | `0x0000_0000` | `0x0000_FFFF` (64 KiB) | M85, DMA via `CPU_S` | Bootloader copies M image here |
| M85 DTCM | `0x2000_0000` | `0x2000_FFFF` (assumed) | M85 local | Not in all main-map decoders |
| Shared SRAM | `0x3000_0000` | `0x300F_FFFF` (1 MiB decoded; 512 KiB implemented) | R5, M85, DMA, debug, U85 | Upper 512 KiB aliases lower (D4). Software limit is `0x3007_FFFF` until the size is configurable. |
| Peripheral APB | `0x4000_0000` | `0x4000_9FFF` | R5 RT peripheral, M85 AHB peripheral | Timers, dual timer, UARTs, watchdog, RTC, SPI |
| GPIO | `0x4001_0000` / `0x4002_0000` | | R5/M85 | AHB GPIO |
| MHU SND | `0x4004_0000` | `0x4005_FFFF` | R5/M85 | MHU320AE |
| MHU REC | `0x4006_0000` | `0x4007_FFFF` | R5/M85 | MHU320AE |
| DMA config | `0x4400_0000` | `0x4400_1FFF` | R5/M85/debug | DMA350 |
| QSPI config | `0x4401_0000` | `0x4401_FFFF` | R5/M85/debug | AHB QSPI |
| VIC (PL192) | `0x4402_0000` | `0x4402_FFFF` | R5, debug (not currently decoded) | VIC0 at +0x0000, VIC1 at +0x1000 |
| SYS_CTRL | `0x4403_0000` | `0x4403_0FFF` | R5/M85/DMA/debug | reset/cpuwait |
| U85 config | `0x4403_2000` | `0x4403_3FFF` | R5/M85/debug | Ethos-U85 APB |
| QSPI flash | `0x6000_0000` | `0x603F_FFFF` | R5/M85/DMA/U85 EXT0 | Boot image/XIP |
| R5 TCM (AXI-slave/DMA view) | `0x8000_0000` | `0x8FFF_FFFF` | R5, DMA via `CPU_Rx_S` | R5 local ATCM is `0x00000000`; R5 app is linked at `0x0`, while the bootloader DMA-copies the R image to `0x80000000`. The equivalence of these two views is a boot-path verification item. |
| Debug APBIC ROM | `0xE00F_0000` | `0xE00F_3FFF` | Debug | Component IDs |
| Boot ROM | `0xFFFF_0000` | `0xFFFF_FFFF` | R5, DMA, debug | Generated bootrom |

**Reconciliation tasks:** `millisoc_tech/logical/nic400_millisoc_main/nic400_millisoc_main.xml`,
`millisoc_tech/logical/nic400_Rx_peripheral/nic400_Rx_peripheral.xml`,
`millisoc_sdk/libs/Device/R5/Include/sys_memory_map.h`,
`millisoc_sdk/libs/Device/M85/exectb_mcu/Include/sys_memory_map.h`,
`scatter/M85/armclang.scat`, `scatter/R5/armclang.scat`,
`scatter/R5/armclang_bootrom.scat`, and the TB must agree. The R5 header is
already inconsistent (G4). D5 intentionally keeps R5 and M85 maps separate:
each must be checked against its own RTL view, not against the other core's
header.

D4 records the current shared-SRAM implementation: the NIC400 decodes the full
1 MiB window, but only 512 KiB is instantiated, so accesses to
`0x3008_0000–0x300F_FFFF` alias the lower 512 KiB. This is accepted for now;
firmware and documentation must use the implemented range, and the size should
become a configuration parameter when the SRAM wrapper is parameterized. The
parameterization point is the `SRAM #(.ADDR_WIDTH(16))` instance (64 KiB × 64-bit
words = 512 KiB); expose the address width/size as a wrapper parameter, keep the
NIC400 decode at the 1 MiB maximum, and generate the firmware `SRAM_SIZE` from
the same configuration.

D5 requires an R5-specific firmware map, not a copy of the M85 map. At minimum,
the corrected R5 map should distinguish:

* the R5 local ATCM view (`0x0000_0000`, where the R5 application is linked);
* the `0x8000_0000` AXI-slave/DMA view used by the bootloader, with the actual
  ATCM/BTCM mapping confirmed in `IT-BOOT-001`;
* the shared SRAM at `0x3000_0000` with `SRAM_SIZE` set to the implemented
  size (currently `0x0008_0000`, maximum `0x0010_0000`);
* the R5 peripheral bases and the R5 IRQ map from `irq_map.h`; IRQs 32–63 are
  served by VIC1 (D3).

The M85 retains its own `sys_memory_map.h` and `exectb_mcu.h`; the two cores must
not be forced to share one header.

### 4.3 Interrupt map

**R5 (PL192 VIC, two instances):**

| IRQ | Source | VIC instance | Notes |
|---|---|---|---|
| 0 | DMA350 channel 0 done | VIC0 | Used by bootloader/reset_control |
| 1 | DMA350 channel 1 done | VIC0 | |
| 2 | QSPI finished | VIC0 | |
| 3–9 | MHU IPC (error/fault/mailbox, both directions) | VIC0 | |
| 10–25 | GPIO0 per-pin | VIC0 | `irq_map.h` |
| 26–41 | GPIO1 per-pin | VIC0 | `irq_map.h` |
| 42 | Timer 0 | VIC1 | `irq_map.h`; VIC1 support accepted (D3), driver update in Stage 1 |
| 43 | Timer 1 | VIC1 | |
| 44–46 | Dual timer 1 / 2 / combined | VIC1 | |
| 47–51 | UART0 TX / RX / TX overrun / RX overrun / combined | VIC1 | |
| 52–56 | UART1 TX / RX / TX overrun / RX overrun / combined | VIC1 | |
| 57 | Watchdog | VIC1 | |
| 58 | RTC | VIC1 | |
| 59–63 | SPI combined / RX / TX / RX overrun / TX timeout | VIC1 | |

Exact mapping comes from `millisoc_tech/logical/millisoc_system/millisoc_system.sv`
(`Rx_CPU_IRQs[63:10] = Rx_PERI_IRQS[55:2]`) and
`millisoc_tech/logical/millisoc_subsystems/millisoc_peripheral_subsystem/millisoc_peripheral_subsystem.sv`
(`PERI_IRQS`). The VIC1 instance is selected by `HADDR_GIC[12]` in
`millisoc_rt_cpu_subsystem.v`.

**Mapping gap to verify:** `PERI_IRQS[0]` (GPIO0 combined) and `PERI_IRQS[1]`
(GPIO1 combined) are not included in the `Rx_CPU_IRQs[63:10] = Rx_PERI_IRQS[55:2]`
slice. Only the per-pin GPIO interrupts reach the R5; the combined GPIO
interrupts are dropped. This should be confirmed as intentional or fixed.

**M85 (NVIC):**

| IRQ | Source |
|---|---|
| 0–1 | DMA350 channels 2–3 done |
| 2–8 | MHU IPC |
| 9 | GPIO0 combined |
| 10 | GPIO1 combined |
| 11–26 | GPIO0 per-pin |
| 27–42 | GPIO1 per-pin |
| 43–64 | Timers, UARTs, watchdog, RTC, SPI (see M85 `exectb_mcu.h`) |
| 65 | Ethos-U85 IRQ |

The M85 map in `millisoc_sdk/libs/Device/M85/exectb_mcu/Include/exectb_mcu.h`
matches the RTL pattern; the R5 map in `.../R5/Include/exectb_mcu.h` does not
(G5). `irq_map.h` is the R5 map used by the bootloader and matches RTL. D5
keeps these maps separate: `irq_map.h` is authoritative for the R5 and the M85
`exectb_mcu.h` enum is authoritative for the M85; the R5 `exectb_mcu.h` enum
must be aligned with `irq_map.h` or removed.

**VIC1 implementation requirement (D3):** extend `vic.h`/`vic.c` so IRQ numbers
below 32 target VIC0 and IRQ numbers 32–63 target VIC1 at `VIC_BASE+0x1000`,
including vector-address/priority register access and the VIC1→VIC0 daisy
chain. Select the VIC instance from the IRQ number and use a 32-bit mask such as
`1u << (irq & 31)`; do not shift a 32-bit value by an IRQ number ≥32. Add a
unit/integration test for the register decode and a firmware test that delivers
at least one IRQ from each VIC instance.

### 4.4 Bus fabric

* Main NIC400: masters R5, M85, DMA350, debug, U85 SRAM0/1/EXT0; slaves CPU_S,
  CPU_Rx_S, shared SRAM, QSPI, ROM, DMA/QSPI/SYS_CTRL/U85 config, APB group,
  debug.
* RT peripheral NIC400: R5 AXI peripheral port → APB/AHB peripherals.
* M85 has a dedicated AHB peripheral port into
  `millisoc_peripheral_subsystem` (`PERIPH_AHB.HSEL=1`, `HREADY=1`).
* Protocol conversions: AXI4/AXI3/AHB/APB; check ID widths, data widths, burst
  support, outstanding limits, exclusives, and error propagation at each
  boundary.
* NIC400 DRC warnings in `CheckResults.log` must be resolved or explicitly
  accepted before U85 integration is signed off.

### 4.5 Clock and reset domains

* System `FCLK` and `nPORESET` are the main domain.
* Debug: `SWCLKTCK`, `nTRST`, DAP domain; currently shares system clock/reset.
* Trace: `TRACECLK` output.
* RT peripheral: 32 kHz `RT_CLK` for RTC; check CDC into APB.
* QSPI: AHB clock and flash clock; check CDC and reset retention.
* Resets: POR, system reset request, watchdog, DAP, software system/R5/M85, R5
  debug reset. `millisoc_reset_ctrl` drives `nSYSRESET`, `nR5RESET`, `nM85RESET`,
  and the reset-cause bits in `sys_ctrl`.
* CPUWAIT: `sys_ctrl.cpu_mx_wait` drives M85 `CPUWAIT`; reset value holds M85
  until the bootloader releases it.

---

## 5. Verification environment architecture

### 5.1 Proposed directory layout

```
verif/
  testbench/millisoc_tb.sv          # existing top, extended
  monitors/                         # existing + new protocol/irq/reset monitors
  assertions/                       # bind modules for AXI/AHB/APB/reset/irq
  checkers/                         # memory map, boot, DMA, MHU scoreboards
  coverage/                         # covergroups and coverage control
  tests/                            # test manifest and SV test classes (if used)
  unit/                             # existing + new module TBs
  regress/                          # manifest, parsers, report generator
  cocotb/                           # optional, or remove the root target
flows/
  regression.mk                     # real targets
  lint.mk                           # already has lint_hal; add `lint`
  formal.mk                         # VC Formal targets (D8)
```

### 5.2 Testbench extensions

1. **Test selection:** `+TEST=<name>`, `+SEED=<n>`, `+TIMEOUT=<ns>`, `+TRACE`,
   `+DEBUG`, `+QSPI_ERR`, `+STRESS`. Unknown test names must `$fatal`. U85 is
   always present in the baseline (D7); U85 tests must not be skipped via a
   presence plusarg.
2. **Global timeout:** an independent `initial` block that calls
   `$fatal(1, "TIMEOUT: %s", test_name)` after `+TIMEOUT`; never rely on a
   firmware `$stop`.
3. **Termination:** replace `$stop` with `$finish` after all expected UARTs
   report, and `$fatal` on timeout or assertion failure, so batch simulators
   return a meaningful exit code. For multi-core tests, `uart_logger` sets a
   per-UART done flag on `0x04` instead of ending the simulation immediately;
   the TB finishes when every expected UART is done.
4. **Test-result contract:** each participating core ends its test by printing
   exactly one terminal marker on its UART: `*** TEST PASS ***` or
   `*** TEST FAIL ***` (optional detail may precede the marker; the marker must
   be the final terminal line). The regression runner parses every expected UART
   log; any `*** TEST FAIL ***`, missing marker, more than one marker, a
   timeout, or a non-zero simulator exit is a failure. The manifest declares
   which UART logs are expected. No `sys_ctrl.test_status` register is used
   (D2).
5. **Interrupt monitor:** records every CPU IRQ/FIQ assertion, VIC vector
   address, VIC instance, and NVIC IRQ number; checks expected/actual sets.
6. **Reset monitor:** records reset source, scope, pulse width, cause bits, and
   whether a reset occurred during traffic.
7. **Memory scoreboard:** for directed SV tests, a reference model of the
   address map and shared SRAM; for firmware tests, read-back checks in firmware.
8. **Protocol assertions:** bind AXI4/AXI3/AHB/APB protocol checkers to every
   DUT interface; fail on `VALID&&!READY` stalls beyond a limit, unstable payload,
   bad burst, response without request, and X/Z on handshakes.
9. **Coverage:** VCS `-cm line+cond+fsm+branch+tgl` for milliSoC-owned RTL;
   covergroups in `verif/coverage/`; merge and report per test/regression.
10. **Robust hierarchy:** prefer interface/port connections over deep
    hierarchical references; if a reference is unavoidable, centralize it in a
    `verif/testbench/millisoc_paths.svh`.

### 5.3 Firmware test contract

Add `millisoc_sdk/libs/Drivers/Include/test_report.h` with helpers that print
the terminal marker and end the simulation:

```c
#define TEST_PASS() do { \
    printf("\n*** TEST PASS ***\n"); \
    UartEndSimulation(); \
    for (;;) { } \
} while (0)

#define TEST_FAIL(x) do { \
    printf("\nTEST_FAIL_CODE=%u\n", (unsigned)(x)); \
    printf("*** TEST FAIL ***\n"); \
    UartEndSimulation(); \
    for (;;) { } \
} while (0)

#define TEST_CHECK(cond, x) do { \
    if (!(cond)) { TEST_FAIL(x); } \
} while (0)
```

`UartEndSimulation()` writes the existing `0x04` stop character, so the marker
must be printed first and flushed. The macro then halts the core so no further
output can appear. The regression parser requires exactly one terminal marker
per expected UART log; multi-core tests must have a marker on each participating
core's UART, and the manifest declares which logs are expected. A test that
hangs never prints a marker, so the global timeout turns it into a failure. The
exact tokens `*** TEST PASS ***` and `*** TEST FAIL ***` are the regression
contract; do not use `sys_ctrl.test_status`.

### 5.4 Regression runner

`flows/regression.mk` should provide:

* `regress_smoke` — `hello`, boot, reset smoke, one SV unit test.
* `regress` — all P0/P1 tests.
* `regress_extended` — P0/P1/P2, seed sweep, coverage merge.
* `regress_test TEST=<id>` — one test.
* `regress_report` — parse logs, produce JUnit XML/HTML, fail on any
  `*** TEST FAIL ***`, `$fatal`, timeout, or missing result.
* `lint` — HAL lint + waivers.
* `coverage` — merge and report; fail if below thresholds.

The runner must:

1. Build the bootrom, compile RTL, build the selected SDK app.
2. Run VCS in batch with a unique seed and timeout.
3. Require exactly one terminal UART marker in every expected UART log
   (`*** TEST PASS ***` or `*** TEST FAIL ***`), not just a log tail; a
   missing marker is a failure.
4. Collect `uart_*.log`, AXI logs, Tarmac, coverage, and the VCS exit code.
5. Never treat a `$stop`/zero exit as a pass.

---

## 6. Test plan

Test IDs are stable and are used by the manifest, coverage, and reports.

### 6.1 L0 — Static and formal

| ID | Objective | Method / checks | Priority |
|---|---|---|---|
| STA-001 | Lint milliSoC-owned RTL | `flows/lint.mk` `lint_hal` on `lint/milliSoC_lint.f`; zero unwaived errors; waivers reviewed | P0 |
| STA-002 | CDC/RDC | Check `SWCLKTCK`/`TRACECLK`/`RT_CLK`/QSPI crossings; all synchronizers and reset bridges reviewed | P0 |
| STA-003 | Elaboration/parameter sweep | Elaborate `CPU_TYPE=CM85`, `R_CPU_TYPE=CR5`, U85 always present (D7), SRAM size variants when parameterized; no latches, undriven, multi-driven | P1 |
| STA-004 | Address-map consistency | Parse NIC400 XML, R5 and M85 `sys_memory_map.h`, `sysctrl.h`, `ethos_u85.h`, scatter files, TB; assert each core’s map matches its RTL view; R5/M85 maps are intentionally separate (D5); document the 512 KiB SRAM limit (D4) | P0 |
| STA-005 | Interrupt-map consistency | Parse R5 `irq_map.h`, R5/M85 `exectb_mcu.h`, CMSIS headers, RTL; assert each core’s map matches its RTL view; R5/M85 maps are separate (D5); catch G5 | P0 |
| STA-006 | Reset/clock lint | All flops have reset or documented no-reset; async assert/sync release; reset polarity; no combinatorial reset loops | P1 |
| STA-007 | NIC400 DRC | Re-run NIC400 validation; resolve or waive U85 40-bit/32-bit and APB group warnings (G14) | P1 |
| STA-008 | Formal: `sys_ctrl`/`reset_ctrl` | One-shot reset command, no spurious reset, CPUWAIT reset value, cause bits; use VC Formal (D8) | P1 |
| STA-009 | Formal: address decode | Use VC Formal (D8) to prove no unintended overlap/alias for the main and RT peripheral maps, excluding the documented 512 KiB/1 MiB SRAM alias (D4); prove default-slave response for unmapped regions | P1 |

### 6.2 L1 — Unit tests

| ID | DUT | Objective / checks | Priority |
|---|---|---|---|
| UT-SYSCTRL-001 | `millisoc_sys_ctrl` | APB read/write all registers; reset values; ID regs; `reset_info` bits; CPUWAIT; reset command one-shot/priority; PSTRB; back-to-back; PREADY/PSLVERR | P0 |
| UT-RESET-001 | `millisoc_reset_ctrl` | Each source/scope; 4-cycle hold; edge behavior; DAP ack; simultaneous requests; request during reset; release synchronization | P0 |
| UT-SRAM-001 | `millisoc_sram_wrapper` + SIE300 | All bursts/sizes/strobes/IDs; read-after-write; boundaries; 512 KiB implemented within the 1 MiB decode; upper-half alias characterization (D4); Q-channel; reset | P0 |
| UT-PERIPH-001 | `millisoc_peripheral_subsystem` | AHB decode for APBSYS/GPIO0/GPIO1/MHU; default slave; aliasing; 32/64-bit M85 port; error response | P0 |
| UT-UART-001 | `cmsdk_apb_uart` 0/1 | Register map; baud tick; TX/RX; TX/RX/overrun/combined IRQ; loopback; reset; APB | P1 |
| UT-TIMER-001 | Timer0/1, dual timer | Prescale; 32/16-bit modes; free-running; IRQ; reset; APB | P1 |
| UT-WDOG-001 | `cmsdk_apb_watchdog` | Load/control/lock; lock key; bad key; interrupt; reset request; reset cause | P1 |
| UT-GPIO-001 | GPIO0/1 | Input/output; per-pin/combined IRQ; masks; edge/level; reset | P1 |
| UT-SPI-001 | `Ssp`/PL022 | Master/slave; IRQ; DMA handshake if wired; pad loopback | P2 |
| UT-MHU-001 | MHU320AE RT/MX | Doorbells; mailbox; channel IRQ; error/fault; reset; APB access; reuse Arm VIP | P0 |
| UT-DMA-001 | DMA350 | Config APB; channels 0–3; 1D/2D; burst; done/error IRQ; secure/non-secure; attributes; abort; reset | P0 |
| UT-QSPI-001 | `top_ahb_qspi` | Flash commands; XIP; QPI; cache; IRQ; reset retention; reuse `ahb_qspi` cocotb/UVM | P1 |
| UT-U85-001 | `millisoc_ai_subsystem` wrapper | APB config; ID/CID; reset; PMU; QBASE/QSIZE; IRQ; AXI SRAM/EXT; U85 model (always present, D7) | P1 |
| UT-DEBUG-001 | APBIC/DAP | AP0–AP3; APB-AP/AXI-AP/AHB-AP; component IDs; SWD/JTAG; reset; defer deep debug to debug plan | P1 |

### 6.3 L2 — Integration tests

| ID | Objective / checks | Priority |
|---|---|---|
| IT-BOOT-001 | Flash preamble → DMA → ITCM/ATCM → CPUWAIT release → both cores; check image sizes/offsets, boundary sizes, zero/oversize images, flash errors | P0 |
| IT-BOOT-002 | Flash image format: `concat_hex.py`, `$readmemh`, endianness, preamble, payload alignment; add checksum/CRC if adopted | P0 |
| IT-BOOT-003 | Boot after cold POR, system reset, watchdog, DAP reset, software reset; QSPI retention; repeated boot | P0 |
| IT-MEM-001 | Full address map from R5/M85/DMA/debug/U85; every region; boundaries; unmapped; default slave; byte/half/word/dword; exclusive; cacheability; shared SRAM 1 MiB decode vs 512 KiB implementation (D4) | P0 |
| IT-MEM-002 | Shared SRAM from all masters; confirm the documented upper-half alias at `0x30080000` (D4); byte strobes; bursts; back-to-back; verify the `0x3007FFFF` software limit | P0 |
| IT-MEM-003 | TCM: ITCM/ATCM sizes, aliasing, wait states, reset, DMA visibility, cache maintenance | P0 |
| IT-IRQ-001 | R5 VIC0 IRQ 0–31; VIC1 IRQ 32–63; daisy chain; vector address; priority; FIQ; enable/clear; spurious; nesting; IRQ during reset | P0 |
| IT-IRQ-002 | M85 NVIC IRQ 0–65; peripheral map; MHU; U85 IRQ 65; priorities; WFI wake | P0 |
| IT-IRQ-003 | Interrupt-map consistency: one directed interrupt per source on R5 and M85; R5 `irq_map.h` and M85 `exectb_mcu.h` are separate authoritative maps (D5); catch G5 | P0 |
| IT-VIC-001 | VIC0/VIC1 AHB decode at `VIC_BASE`/`VIC_BASE+0x1000`; vector/priority registers; VIC1→VIC0 daisy chain; IRQ 32–63 delivery; firmware driver dispatch (D3) | P0 |
| IT-RESET-001 | Reset source/scope matrix; preserve the other core/TCM/shared; QSPI retention; reset cause; reset during traffic; ack | P0 |
| IT-RESET-002 | Clock/reset sequencing: POR release, clock enables, CPUWAIT, boot; no spurious transactions; reset synchronization | P0 |
| IT-DMA-001 | DMA flash→TCM, shared→TCM, TCM→shared, shared→shared; bursts; 32/64-bit; IRQ; error; abort; concurrent with CPU | P1 |
| IT-QSPI-001 | Boot read; XIP; cache hit/miss; QPI; flash timing; reset retention; error injection | P1 |
| IT-PERIPH-001 | R5 RT peripheral vs M85 peripheral: UART0/1, timers, GPIO, SPI, watchdog, RTC; decode; IRQ; concurrent access; reset | P1 |
| IT-MHU-001 | R5↔M85 doorbell, mailbox, IRQ, error/fault, reset, concurrent; boot handshake | P0 |
| IT-SRAM-001 | Shared SRAM from R5/M85/DMA/debug/U85; implemented 512 KiB within the 1 MiB decode; upper-half alias characterization (D4); strobes; bursts; reset | P0 |
| IT-U85-001 | U85 config APB; IRQ; AXI SRAM/EXT; shared SRAM; power/Q-channel; reset; end-to-end inference with a reference model | P1 |
| IT-DEBUG-001 | DAP AP0–AP3; system-bus access via NIC400 DEBUG; R5/M85 debug; debug reset; security | P1 |
| IT-TRACE-001 | ITM, ETM M85/R5, funnel, TPIU, trace IDs, ATB backpressure, trace clock; extend existing `+TRACE` checks | P2 |

### 6.4 L3 — SoC firmware tests

Every firmware test binary on each participating core must end with exactly one
`*** TEST PASS ***` or `*** TEST FAIL ***` marker (D2); the manifest declares
the expected UART logs, and `PASS` in the table means every expected log contains
the pass marker and all checks succeeded.

| ID | App / scenario | Checks | Priority |
|---|---|---|---|
| FW-BOOT-001 | `hello` | Bootloader banner; both UART banners; terminal `*** TEST PASS ***` | P0 |
| FW-BOOT-002 | `reset_demo` converted to `_M`/`_R` | Boot after reset; both cores; PASS | P1 |
| FW-MEM-001 | `sram_tests` extended | Implemented 512 KiB from M85 and R5; confirm documented alias at `0x30080000`; stay within `0x3007FFFF`; patterns; read-back; PASS | P0 |
| FW-MEM-002 | `bus_access` implemented | R5/M85/DMA access matrix; unmapped/error; read/write; cache; PASS | P0 |
| FW-IRQ-001 | Timer/UART/GPIO IRQ test | R5 VIC0 and VIC1 (D3); M85 NVIC; priority/nesting; PASS | P0 |
| FW-IRQ-002 | VIC1 peripheral IRQ test | Timer0/1, UART0/1, watchdog, RTC, SPI; `vic_enable_irq` dispatch; vector address; PASS | P0 |
| FW-RESET-001 | `reset_control` completed | Watchdog reset; reset cause; local reset; system reset; re-boot; PASS | P0 |
| FW-MHU-001 | `mhu_tests` extended | Doorbell; mailbox; error/fault; both directions; stress; PASS | P1 |
| FW-DMA-001 | DMA test app | Copy matrix; IRQ; error; abort; PASS | P1 |
| FW-QSPI-001 | QSPI test app | Flash read/write/erase if supported; XIP; cache; retention; PASS | P1 |
| FW-PERIPH-001 | Peripheral test app | UART loopback; timers; GPIO; SPI; watchdog; RTC; PASS | P1 |
| FW-U85-001 | `u85_tests` extended | Config/ID; IRQ; inference; shared SRAM; PASS (U85 always present, D7) | P1 |
| FW-DEBUG-001 | `debug_access` extended | DAP; system-bus access; component IDs; PASS | P1 |
| FW-STRESS-001 | Stress app | Long random traffic; reset during traffic; concurrent DMA/U85; watchdog; PASS | P2 |
| FW-PERF-001 | Performance app | Latency/throughput for shared SRAM/DMA/QSPI; report metrics; PASS marker | P2 |

### 6.5 L4 — System / FPGA

| ID | Objective | Priority |
|---|---|---|
| SYS-FPGA-001 | Build, timing, resource; boot, UART, QSPI, debug, U85 on FPGA | P2 |
| SYS-DEBUG-001 | External debugger connect, halt, memory access, trace | P2 |

### 6.6 Negative and error tests (cross-cutting)

| ID | Scenario | Priority |
|---|---|---|
| NEG-001 | Unmapped address from R5, M85, DMA, debug; correct error response, no hang | P0 |
| NEG-002 | AXI/AHB protocol violation injection (bad burst, early response, unstable payload) → assertion fires | P1 |
| NEG-003 | Flash read error/timeout during boot; DMA error; recoverable reset | P1 |
| NEG-004 | DMA abort/disable during transfer; channel error; IRQ | P1 |
| NEG-005 | Watchdog bad key/lock; reset request; cause | P1 |
| NEG-006 | Reset during DMA/QSPI/U85 traffic; no deadlock; cause correct | P0 |
| NEG-007 | VIC spurious IRQ; rapid enable/disable; nested IRQ; FIQ | P1 |
| NEG-008 | M85 CPUWAIT hold/release races; release before image complete | P0 |
| NEG-009 | Debug access while CPU running; security policy | P2 |
| NEG-010 | SRAM upper-half alias (D4); characterize and assert the documented alias; verify software cannot rely on the upper 512 KiB | P0 |

---

## 7. Coverage model

### 7.1 Functional coverage

| Covergroup | Coverpoints / crosses |
|---|---|
| `cg_boot` | Reset source × boot stage × core × image size class × pass/fail |
| `cg_mem` | Master × region × access type × size × burst × response |
| `cg_sram` | Master × address half (lower/upper) × implemented/decoded × strobe × burst |
| `cg_irq_r5` | Source × VIC instance (0/1) × priority × enable/disable × nesting |
| `cg_irq_m85` | Source × priority × WFI state × nesting |
| `cg_reset` | Source × scope × active traffic × cause × ack |
| `cg_dma` | Channel × direction × burst × size × error/abort |
| `cg_mhu` | Direction × channel × doorbell/mailbox × error/fault |
| `cg_axi` | Master × channel × burst/size/len × response × outstanding |
| `cg_ahb`/`cg_apb` | Transfer type × size × wait states × error |
| `cg_qspi` | Command × mode (single/dual/quad/QPI) × cache hit/miss × error |
| `cg_u85` | Config access × command × IRQ × AXI port |
| `cg_debug` | AP × access type × security × target region |

### 7.2 Structural coverage

* Line, branch, condition, FSM, toggle for **milliSoC-owned RTL**:
  `millisoc_system`, `millisoc_cpu_ss`, `millisoc_rt_cpu_subsystem`,
  `millisoc_peripheral_subsystem`, `millisoc_rt_peripheral_subsystem`,
  `millisoc_sys_ctrl`, `millisoc_reset_ctrl`, `millisoc_sram_wrapper`,
  `millisoc_ai_subsystem` wrapper, `millisoc_debug_subsystem` wrapper.
* Exclude Arm IP internal implementation from structural coverage with
  documented waivers (D1); include integration wrappers, decode/mux logic, and
  SoC-visible functional coverage.
* Initial targets: 100% functional coverpoints; ≥90% line; ≥85% branch;
  ≥80% toggle on milliSoC-owned RTL; zero unwaived lint errors; all assertions
  exercised.

### 7.3 Assertions

* AXI4/AXI3/AHB/APB protocol assertions on every DUT interface.
* Reset: no transaction while reset asserted; reset pulse width; cause bits
  stable.
* Interrupt: IRQ only from enabled source; vector address valid; no lost edge.
* Memory map: no decode overlap; default slave for unmapped; address boundary.
* Boot: CPUWAIT only released after both DMA copies complete; image sizes within
  TCM.
* DMA: no transfer when disabled; completion only after last beat; error
  response propagated.

---

## 8. Pass/fail and exit criteria

A test passes only when all of the following are true:

1. The simulator exits with the expected status and no `$fatal`, timeout, or
   assertion failure.
2. Every expected UART log contains exactly one terminal marker:
   `*** TEST PASS ***` or `*** TEST FAIL ***`.
3. No unexpected `*** TEST FAIL ***`, UART error, or protocol violation is
   logged.
4. No X/Z on monitored handshakes or control signals.
5. The test’s required coverage points are hit (for coverage-closure tests).

A regression is green only when:

* all P0 tests pass, and all P1/P2 tests pass or have an approved waiver;
* the test manifest is complete (no missing result, no skipped test without an
  approved waiver; U85 tests are never skipped, D7);
* coverage thresholds in §7.2 are met or have approved exclusions;
* lint/CDC/DRC have no unwaived errors;
* the regression has run clean three consecutive times with the same seed set,
  plus one seed sweep.

Exit criteria for the plan:

* Boot after every reset source works in simulation.
* Every firmware-visible interrupt is delivered on the correct VIC/NVIC source.
* Address-map and interrupt-map consistency is machine-checked; R5 and M85 maps
  are separate and each matches its RTL view (D5); the 512 KiB SRAM
  implementation within the 1 MiB decode is documented and guarded (D4).
* Shared SRAM, DMA, QSPI, MHU, peripherals, debug, and U85 integration each have
  directed tests and coverage.
* Local regression publishes pass/fail and coverage per run; CI is deferred
  (D6).

---

## 9. Regression (local) and future CI

### 9.1 Test manifest

A single manifest (e.g. `verif/regress/tests.yaml` or a Make variable list)
defines each test:

```yaml
- id: FW-BOOT-001
  kind: firmware
  app: hello
  timeout_ns: 1000000
  seed: 1
  priority: P0
  requires: [bootrom, image]
- id: UT-SYSCTRL-001
  kind: unit
  top: millisoc_sys_ctrl_tb
  timeout_ns: 10000
  priority: P0
```

The runner derives build commands, plusargs, log paths, and expected result from
the manifest.

### 9.2 Local regression stages (D6)

1. **Static:** lint, CDC/RDC, address/interrupt consistency scripts.
2. **Compile:** RTL compile + bootrom + all selected SDK apps.
3. **Smoke:** `hello`, boot, reset smoke, unit `sys_ctrl`/`reset_ctrl`.
4. **Regression:** P0/P1 tests, fixed seeds.
5. **Extended:** P0/P1/P2, seed sweep, coverage merge, report.
6. **Report:** JUnit XML, HTML report, coverage dashboard, artifact bundle.

CI is deferred by D6. These local targets are the contract a future CI job will
call, but the current plan does not depend on a CI runner.

### 9.3 Runtime budget

* Smoke: ≤10 minutes.
* P0 regression: ≤1 hour.
* Extended: ≤6 hours (parallel per test; VCS licences permitting).
* Any test exceeding its manifest timeout is a failure, not a skip.

---

## 10. Staged implementation roadmap

Each stage leaves the repository in a working state and is independently
testable.

> **Stage 0 is pending review of this plan.** D1–D8 are accepted. No
> implementation has started.

### Stage 0 — Verification infrastructure (1–1.5 weeks)

* Add `*** TEST PASS ***`/`*** TEST FAIL ***` UART reporting, a log parser,
  global timeout, and `$finish` on pass (D2).
* Add local `flows/regression.mk` with smoke targets and a marker parser (D6).
* Wire `verif/unit` TBs into a `unit` target.
* Fix `make testcode` fail-fast; document `SIMULATOR=vcs`.
* Add `lint` target invocation; baseline lint/DRC.
* Deliverable: `make regress_smoke` reliably passes/fails; `hello` has a
  machine-checked result.

### Stage 1 — Boot, reset, interrupts, DMA (2–2.5 weeks)

* IT-BOOT-001/002/003, IT-RESET-001/002, IT-IRQ-001/002/003,
  IT-VIC-001, FW-IRQ-001/002, NEG-001/006/008.
* Add VIC1 driver support and directed VIC1 tests (D3).
* Align the R5 IRQ header with `irq_map.h` (D5).
* Complete `reset_control` watchdog stage (G6).
* Add reset/interrupt monitors and assertions.
* Deliverable: every reset source boots; every used IRQ is delivered.

### Stage 2 — Memory, peripherals, MHU, shared SRAM (2–2.5 weeks)

* UT-SRAM-001, UT-PERIPH-001, UT-UART/TIMER/WDOG/GPIO, UT-MHU-001.
* IT-MEM-001/002/003, IT-SRAM-001, IT-PERIPH-001, IT-MHU-001.
* Characterize the accepted SRAM alias and enforce the `0x3007FFFF` software
  limit (D4); correct the R5-specific memory map (D5).
* Implement `bus_access`, extend `sram_tests` and `mhu_tests`.
* Deliverable: full memory map and peripheral/MHU matrix passes.

### Stage 3 — U85, debug, QSPI, contention, stress (3–4 weeks)

* IT-QSPI-001, IT-U85-001, IT-DEBUG-001, IT-TRACE-001.
* NEG-002/003/004/005/007/009/010.
* FW-STRESS-001, FW-PERF-001.
* U85 is always present (D7); do not skip U85 tests.
* Resolve NIC400 DRC warnings (G14).
* Deliverable: U85/debug/QSPI integration tests and stress tests pass.

### Stage 4 — Coverage closure, VC Formal, future CI (2–3 weeks)

* Coverage merge and waivers; VC Formal for `sys_ctrl`/`reset_ctrl`/decode
  (D8).
* Local regression dashboard and artifact bundle; CI deferred (D6).
* Final regression and sign-off report.
* Deliverable: green regression + coverage report + documented waivers.

**Total estimate:** ~8–10 engineer-weeks, assuming one verification engineer
and available VCS licences; parallelizable across Stages 1–3.

---

## 11. Risks, assumptions, and decisions

### 11.1 Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Arm IP licences/tools unavailable | Blocks compile/sim | Keep IP outside repo; document required versions; reproducible local environment image |
| VIC1 driver gap (G2) | Peripheral IRQs ≥32 unusable until the driver is updated | D3: add VIC1 support in Stage 1; directed VIC1 tests |
| SRAM upper-half alias (D4) | Software using `0x3008_0000–0x300F_FFFF` aliases the lower 512 KiB | Accepted current limitation; document the `0x3007_FFFF` software limit; add alias characterization; parameterize the size later |
| R5 memory map/IRQ headers stale (G4/G5) | R5 firmware uses wrong addresses/IRQs | D5: separate R5-specific memory and IRQ maps; align `exectb_mcu.h`; consistency test |
| Watchdog reset incomplete (G6) | Reset scenario unverified | Debug reset controller/watchdog; add timeout |
| No CI yet (D6) | Regressions depend on local discipline | Run local `regress_smoke`/`regress`; add CI later |
| U85 integration incomplete | U85 is always present (D7), so failures block the baseline | Coordinate with `plans/ethos_u85_integration.md`; fix or waive explicitly; do not skip |
| VC Formal licence unavailable | Formal targets blocked (D8) | Confirm licence early; keep properties simulator-checkable; record a waiver if unavailable |
| Debug plan draft | Debug verification blocked | Interface-level tests now; full debug follows debug plan |
| Hierarchical TB refs brittle | Tests break on RTL rename | Centralize paths; prefer interfaces |
| Simulation runtime | Extended regression too slow | Parallelize; split P0/P1; seed sweep only in extended runs |

### 11.2 Assumptions

* VCS is the reference simulator; Questa/cocotb flows are optional and currently
  broken.
* Arm IP is available at `ARM_IP_LIBRARY_PATH`; QSPI/U85/MHU collateral can be
  reused. Arm IP internal implementation is assumed pre-verified (D1), while
  its SoC-visible functionality and integration are verified.
* The R5-first boot flow in `bootloader.c` is the intended architecture.
* The shared SRAM is a 1 MiB decoded window with 512 KiB implemented today
  (D4); the upper half aliases the lower. Software must stay within
  `0x3000_0000–0x3007_FFFF` until the size is parameterized.
* Firmware can be changed to add UART `*** TEST PASS ***`/`*** TEST FAIL ***`
  reporting; this is a verification enabler, not a product feature.
* The Ethos-U85 is always present in the baseline configuration (D7); U85 tests
  are not skipped.
* VC Formal is available for `sys_ctrl`/`reset_ctrl`/decode (D8).
* Regression runs locally for now; CI is deferred (D6).

### 11.3 Decisions

| ID | Decision | Options considered | Resolution |
|---|---|---|---|
| D1 | Verification scope for Arm IP | Full IP verification vs integration-only vs SoC-functional | **ACCEPTED** — assume Arm IP internal implementation is pre-verified; verify the configured IP's SoC-visible functionality and integration |
| D2 | Test-result mechanism | `sys_ctrl.test_status` register vs UART markers + log parsing | **ACCEPTED** — no `test_status`; each test ends with `*** TEST PASS ***` or `*** TEST FAIL ***`; the runner parses the UART log |
| D3 | VIC1 support | Add driver support vs restrict IRQs to 0–31 | **ACCEPTED** — add VIC1 support; IRQ <32 → VIC0, IRQ ≥32 → VIC1 at `VIC_BASE+0x1000`; add directed tests |
| D4 | Shared SRAM size | 512 KiB implemented vs 1 MiB decoded | **ACCEPTED** — keep SRAM/NIC as is; 1 MiB decoded, 512 KiB implemented; document the `0x3007_FFFF` software limit; parameterize later |
| D5 | R5 firmware headers | Keep `exectb_mcu.h` vs `irq_map.h` vs generated | **ACCEPTED** — R5 and M85 keep separate memory/IRQ maps; correct the R5 `sys_memory_map.h` and treat it plus `irq_map.h` as the R5 source of truth; align or remove the stale R5 `exectb_mcu.h` IRQ enum |
| D6 | Regression/CI platform | Local only vs CI runner | **ACCEPTED** — run everything as local regression for now; add CI later |
| D7 | U85 in baseline regression | Always present vs optional `+U85` | **ACCEPTED** — keep U85 always present for now; U85 tests are not skipped |
| D8 | Formal tool | VC Formal vs JasperGold vs none | **ACCEPTED** — use VC Formal for `sys_ctrl`, `reset_ctrl`, and address decode |

---

## 12. Deliverables

1. `plans/verification_plan.md` (this document, once approved).
2. `verif/assertions/` protocol and integration assertions.
3. `verif/checkers/` memory-map, boot, DMA, MHU, reset, interrupt checkers.
4. `verif/coverage/` covergroups and coverage reports.
5. `verif/regress/` manifest, parser, report generator.
6. `flows/regression.mk` real local targets; `flows/lint.mk` `lint` target;
   `flows/formal.mk` VC Formal targets (D8).
7. Firmware: `test_report.h` with UART `*** TEST PASS ***`/`*** TEST FAIL ***`
   reporting (D2); VIC1 support in `vic.h`/`vic.c` (D3); corrected R5-specific
   `sys_memory_map.h`/`irq_map.h` and aligned `exectb_mcu.h` (D5); completed
   `reset_control`; implemented `bus_access`; extended
   `sram_tests`/`mhu_tests`/`u85_tests`; converted `reset_demo`.
8. Updated `README.md` current-status section and `plans/README.md` index,
   including the documented 512 KiB shared-SRAM limit and alias behavior (D4).
9. Local regression/coverage dashboard and sign-off report.

---

## Appendix A — Evidence index

| Claim | Evidence |
|---|---|
| R5-first boot | `millisoc_sdk/bootloader/bootloader.c:31-69`; `README.md` boot section |
| Flash preamble | `millisoc_sdk/tools/concat_hex.py:9-30`; `bootloader.c:51-56` |
| CPUWAIT release | `bootloader.c:61`; `millisoc_tech/logical/millisoc_subsystems/millisoc_sys_ctrl/millisoc_sys_ctrl.sv:17,84-86` |
| VIC0/VIC1 | `millisoc_tech/logical/millisoc_subsystems/millisoc_rt_cpu_subsystem/CR5/millisoc_rt_cpu_subsystem.v:880-881,954,969,991,1006`; `millisoc_tech/logical/millisoc_system/millisoc_system.sv:308-341` |
| VIC driver only VIC0 | `millisoc_sdk/libs/Drivers/Include/vic.h:30-33`; `millisoc_sdk/libs/Drivers/Source/vic.c:17` |
| R5 IRQ map | `millisoc_sdk/libs/Device/R5/Include/irq_map.h:19-85`; `millisoc_system.sv:308-317`; `millisoc_peripheral_subsystem.sv:205-230` |
| R5 stale IRQ map | `millisoc_sdk/libs/Device/R5/Include/exectb_mcu.h:42,45,77` (`QSPI=5`, `GPIO0_0=8`, `TIMER0=40`) |
| R5 stale memory map | `millisoc_sdk/libs/Device/R5/Include/sys_memory_map.h:21,23,25` (`SRAM_BASE 0x20000000`) vs M85 `sys_memory_map.h` (`0x30000000`) |
| Shared SRAM implementation (D4) | `millisoc_tech/logical/millisoc_subsystems/millisoc_sram_wrapper/millisoc_sram_wrapper.sv:31,44,102-104` (`memaddr[15:0]`, `SRAM #(.ADDR_WIDTH(16))`); `millisoc_tech/logical/nic400_millisoc_main/nic400_millisoc_main.xml:177-181` (`0x30000000–0x300FFFFF`). 1 MiB decoded, 512 KiB implemented; upper half aliases and software is limited to `0x3007FFFF`. |
| `$stop` / no timeout | `verif/testbench/millisoc_tb.sv:248-303` (sticky `test_done`/`test_done_M`, `$stop`) |
| UART stop code | `verif/monitors/uart_logger.v:91,183` (`0x04` → `$finish(2)`) |
| `hello` pass | `simulate/sim/hello/logs/run_hello.log:46,132,139-143` |
| `reset_control` incomplete | `simulate/sim/reset_control/logs/run_reset_control.log:161` (ends at “Requesting watchdog system reset”) |
| Empty regression | `flows/regression.mk` (0 bytes) |
| Unit TBs unwired | `verif/unit/millisoc_sys_ctrl_tb.sv`, `verif/unit/millisoc_reset_ctrl_tb.sv`; no make target |
| `reset_demo` build break | `millisoc_sdk/apps/reset_demo/reset_demo.c` (single 14-line file); `all_ds6` expects `_M`/`_R` |
| `bus_access` stub | `millisoc_sdk/apps/bus_access/bus_access_M.c` (16 lines), `bus_access_R.c` (17 lines) |
| U85 test no checks | `millisoc_sdk/apps/u85_tests/u85_tests_M.c` (32 lines) |
| NIC400 DRC warnings | `CheckResults.log:6-20` (U85 40-bit address width); `:453-466` (summary) |

## Appendix B — Commands

```sh
# Environment (source, do not execute)
source set_env.sh

# Build bootrom
make bootrom

# Compile RTL
make compile SIMULATOR=vcs

# Build an SDK app and copy its image
make testcode TESTNAME=hello
make testcode TESTNAME=reset_control

# Run
make run TESTNAME=hello SIMULATOR=vcs
make run TESTNAME=reset_control SIMULATOR=vcs

# Proposed targets (after Stage 0)
make regress_smoke SIMULATOR=vcs
make regress SIMULATOR=vcs
make regress_extended SIMULATOR=vcs
make lint
make coverage
```

## Appendix C — Decision log

| ID | Decision | Status | Date |
|---|---|---|---|
| D1 | Assume Arm IP internal implementation is pre-verified; verify SoC-visible functionality and integration | ACCEPTED | 2026-11-05 |
| D2 | Use UART `*** TEST PASS ***`/`*** TEST FAIL ***` markers and log parsing; no `sys_ctrl.test_status` | ACCEPTED | 2026-11-05 |
| D3 | Add VIC1 driver support (IRQ <32 VIC0, IRQ ≥32 VIC1) | ACCEPTED | 2026-11-05 |
| D4 | Keep SRAM/NIC; 1 MiB decoded, 512 KiB implemented; document limit and parameterize later | ACCEPTED | 2026-11-05 |
| D5 | Separate R5 and M85 memory/IRQ maps; correct the R5-specific headers | ACCEPTED | 2026-11-05 |
| D6 | Run everything as local regression for now; add CI later | ACCEPTED | 2026-11-05 |
| D7 | Keep U85 always present in the baseline; do not skip U85 tests | ACCEPTED | 2026-11-05 |
| D8 | Use VC Formal for `sys_ctrl`, `reset_ctrl`, and address decode | ACCEPTED | 2026-11-05 |
