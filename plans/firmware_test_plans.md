# milliSoC Firmware Testcase Plans

| | |
|---|---|
| **Status** | Draft — derived from `plans/verification_plan.md` |
| **Scope** | Board-executable firmware test specifications for the R5, M85, and integrated SoC |
| **Target** | A configured milliSoC FPGA image; board-specific addresses, clocks, pins, and flash policy must be supplied by the platform owner |
| **Last updated** | 2026-11-11 |

This document expands the firmware-test IDs in §6.3 of the
[SoC verification plan](./verification_plan.md) into test designs that can be
implemented and run on an FPGA board. These are specifications, not claims that
the tests or their firmware already exist. They intentionally do not prescribe
reuse or modification of any current SDK application.

The tests target observable SoC behavior at firmware-visible interfaces. They
do not replace RTL protocol tests, prove timing closure, or inspect Arm IP
internals. An FPGA run also cannot substitute for testbench-only error injection
or coverage measurement.

## 1. Test-suite contract

### 1.1 Per-test result

Each test has a unique ID and emits a machine-readable result independently on
every participating core's UART:

```text
TEST_ID=FW-MEM-001 CORE=M85 START
...
TEST_ID=FW-MEM-001 CORE=M85 PASS
```

Failures report the first failing check and a stable numeric or symbolic code,
then emit `TEST_ID=<id> CORE=<core> FAIL`. A test is not a pass if it hangs,
omits a result, emits conflicting results, or returns before all required
cores report. The board runner records raw UART output, firmware/image version,
FPGA bitstream identifier, board revision, reset/power-cycle method, and test
configuration. Where the existing verification-plan marker contract is used,
each participating UART must additionally end with exactly one
`*** TEST PASS ***` or `*** TEST FAIL ***` marker.

Tests that involve both cores use a bounded protocol: each phase has a timeout,
sequence numbers detect stale messages, and the R5 master reports the final
combined result only after collecting each participant's result. Never treat a
missing core response or a timeout as success.

### 1.2 Board-specific inputs required before implementation

Create a versioned board profile alongside the test image, containing:

* FPGA/board revision, clock frequencies, reset and boot controls, UART routing,
  and any external loopback wiring or fixtures.
* The selected RTL configuration and its authoritative R5 and M85 memory and
  interrupt maps. Keep the two core maps separate.
* Implemented SRAM and TCM capacities, the permitted flash image layout, and
  which reset sources are physically triggerable.
* Peripheral capabilities and safe operating policy, especially for flash
  erase/program, watchdog reset, GPIO pins connected to external equipment,
  and SPI.
* The available U85 runtime, model image, input vectors, expected output or
  tolerance, and legal memory route, if U85 inference is to be tested.
* The debugger/host tool and approved access policy for DAP tests.

Do not infer board pinout, device clocks, external loopbacks, memory visibility,
or accelerator support from a simulation plan. If an input is unknown, the
affected test remains blocked until the board owner supplies it; it must not be
silently skipped or reported as passed.

### 1.3 Common safety and correctness rules

* Start with a known-good bitstream and firmware image. Keep recovery through
  the board's documented reset/reprogram path available.
* Do not program or erase QSPI except in a board-owner-designated scratch area
  whose bounds have been independently confirmed. Default QSPI checks are
  read-only.
* Run reset and watchdog tests as isolated cases. Do not request a local reset
  while that core has outstanding bus transactions; the current platform notes
  do not establish that local reset drains traffic.
* Use only documented, implemented memory ranges. The shared-SRAM implementation
  is currently 512 KiB at `0x3000_0000` through `0x3007_FFFF`, despite a 1 MiB
  decoded window. The upper half is documented as an alias, not additional
  storage. Do not allocate test buffers there.
* Do not assume cache coherency. When a processor and DMA/U85 observe the same
  buffer, use the cache-maintenance operations required by the configured
  platform and test visibility explicitly.
* Do not write reserved registers or guess register offsets. Use the
  board-matched headers and integration documentation; read-modify-write only
  where the register semantics permit it.
* Use bounded loops and deadlines. A board-side watchdog or operator recovery
  procedure is not a substitute for firmware timeouts and a reported failure.

## 2. Test catalogue and dependencies

IDs and priorities match the firmware layer of the parent verification plan.
“Both” means each core has its own test image/result and the R5 coordinates the
run; it does not imply a pre-existing interprocessor protocol.

| ID | Test | Cores | Priority | Key prerequisite |
|---|---|---|---|---|
| FW-BOOT-001 | Cold boot and core release | R5 + M85 | P0 | Known-good flash image and both UARTs |
| FW-BOOT-002 | Repeated boot after supported reset | R5 + M85 | P1 | Documented system-reset trigger |
| FW-MEM-001 | Shared SRAM capacity, boundaries, and alias | R5 + M85 | P0 | Correct 512 KiB map and exclusive test window |
| FW-MEM-002 | CPU and DMA memory-access matrix | R5 + M85 | P0 | Verified region/access matrix and fault policy |
| FW-IRQ-001 | Core interrupt behavior and priority | R5 + M85 | P0 | Correct VIC/NVIC maps and peripheral sources |
| FW-IRQ-002 | R5 VIC1 peripheral interrupt delivery | R5 | P0 | VIC1 driver support and safe peripheral configuration |
| FW-RESET-001 | Local, system, and watchdog reset behavior | R5 + M85 | P0 | Reset-cause map and supervised reset/recovery |
| FW-MHU-001 | Bidirectional MHU and shared-memory handshake | R5 + M85 | P1 | MHU channel map and bounded coordination protocol |
| FW-DMA-001 | DMA transfer, completion, error, and abort | R5 | P1 | DMA map, permitted transfer regions, and error policy |
| FW-QSPI-001 | Read-only QSPI/XIP and warm-reset retention | R5 | P1 | Flash map and board recovery path |
| FW-PERIPH-001 | Peripheral function and interrupt checks | R5 + M85 | P1 | Board wiring, safe pins, peripheral clocks |
| FW-U85-001 | U85 configuration, memory, IRQ, and inference | M85 (+ R5) | P1 | Working U85 integration, runtime, model, reference outputs |
| FW-DEBUG-001 | Firmware debug targets plus external DAP checks | R5 + external host | P1 | Authorized debugger and interface access |
| FW-STRESS-001 | Bounded concurrent-load and recovery test | R5 + M85 | P2 | All participating P0/P1 tests stable |
| FW-PERF-001 | Baseline latency and throughput characterization | R5 + M85 | P2 | Calibrated timer and repeatable board conditions |

Suggested implementation order: FW-BOOT-001; FW-MEM-001 and FW-MEM-002;
FW-IRQ-001 and FW-IRQ-002; FW-RESET-001; then MHU, DMA, QSPI, peripherals,
U85, debug, stress, and performance. A prerequisite failure blocks dependent
tests; it does not justify weakening their expected results.

## 3. Individual testcase specifications

### FW-BOOT-001 — Cold boot and core release

**Purpose:** Verify the real board's ROM-to-QSPI-to-TCM path and R5-first startup
from a cold power-on.

**Participants:** R5 and M85. **Priority:** P0.

**Setup and procedure**

1. Build a single image containing distinct build IDs and nontrivial
   initialization data in the R5 and M85 payloads. Include checksums or
   signatures in test-owned data where the boot format supports them; do not
   change the production image format solely for this test.
2. Program the image through the approved board process, power-cycle, and
   capture both UARTs from before reset release.
3. R5 reports its startup identity, verifies its expected local execution
   location and writable test data, and records the bootloader's documented
   image/preload outcome if exposed.
4. R5 releases M85 only after the normal bootloader preload sequence. M85
   reports its independent build ID, validates its initialized data, and
   acknowledges startup to R5 using a bounded test handshake.
5. Each core writes a distinct signature to a reserved test-owned shared-SRAM
   word, reads back its own signature, and confirms the other core's signature
   only if that shared-memory route is verified for both masters.

**Checks and pass criteria**

* The R5 executes and reports first; M85 does not report application startup
  before release.
* Both core build IDs and payload checks match the programmed image.
* M85 reaches its application without external intervention; both cores finish
  their bounded handshake and report PASS.
* No unexpected reset, exception, bus fault, or timeout is observed.

**Evidence:** Both UART logs, image hash, board/bitstream identity, reset method,
and per-core results.

### FW-BOOT-002 — Repeated boot after supported reset

**Purpose:** Confirm that a warm system reset re-enters the intended boot flow
without requiring a manual flash reprogram.

**Participants:** R5 and M85. **Priority:** P1.

**Setup and procedure**

1. Run after FW-BOOT-001 passes. Use only a system reset source documented for
   this board and configuration; do not substitute a local-core reset.
2. On the first boot, preserve a reset-test cookie in a location documented to
   survive the selected reset. Request a system reset while both cores are
   quiescent and all test-owned DMA/peripheral operations are complete.
3. On reboot, validate the reset cause and cookie, increment a bounded boot
   counter, and repeat the two-core startup handshake.
4. Repeat for a small fixed count selected by the board profile. Do not rely on
   unbounded reset loops.

**Checks and pass criteria**

* Every requested reset produces one fresh boot generation from the same
  programmed image.
* Reset cause agrees with the requested source; QSPI remains usable under the
  configured warm-reset retention behavior.
* Each generation has one result from every participating core, with no stale
  handshake accepted as a current result.
* Failure to boot within the per-generation deadline is a failure requiring
  operator recovery, not a pass.

**Notes:** Exhaustive source/scope coverage is FW-RESET-001. Cold POR belongs to
FW-BOOT-001. A watchdog-triggered reboot belongs to FW-RESET-001.

### FW-MEM-001 — Shared SRAM capacity, boundaries, and alias

**Purpose:** Exercise the implemented shared SRAM from both processors without
mistaking the decoded 1 MiB window for 1 MiB of physical storage.

**Participants:** R5 and M85. **Priority:** P0.

**Address constraints:** Use only `0x3000_0000–0x3007_FFFF` for allocations.
Probe the documented upper-window alias at `0x3008_0000` only as a deliberate,
reversible alias characterization, with no other core or bus master using the
corresponding lower address.

**Procedure**

1. Reserve a mutually exclusive test window and save its contents if the
   application could be running on a live system. Prefer a dedicated test
   image with no production data in the region.
2. Each core runs address-dependent patterns, walking bits, inverse patterns,
   and pseudorandom words over the entire 512 KiB region in bounded chunks.
   Include first/last words, aligned and supported unaligned accesses, and
   documented byte strobes if the CPU interface permits them.
3. Perform address-distinct writes followed by readback and an address-alias
   check. Do not infer independence from a single repeated-value pattern.
4. In a separate quiescent phase, R5 writes a sequence-numbered block and M85
   verifies it; reverse writer and reader. Apply required cache maintenance
   and memory barriers. Do not claim coherency from a cache-enabled test unless
   that property is explicitly implemented.
5. If the upper alias is present in the selected RTL, save the lower-window
   word, write a test value through `0x3008_0000`, confirm the corresponding
   value at `0x3000_0000`, and restore the saved word. Avoid alias probing on a
   live image or when the mapping is not confirmed.

**Checks and pass criteria**

* All in-range patterns pass on each core and both cores observe the explicit
  cross-core handoff after cache maintenance.
* First and last implemented bytes are accessible; no access crosses outside
  the documented implemented range during ordinary testing.
* Alias behavior matches the board's documented implementation. Upper-window
  storage is never counted as additional capacity.
* Any mismatch reports core, address, expected/actual value, pattern, and
  iteration.

**Evidence:** Address range/size, pattern seed, cache mode and maintenance
sequence, alias result, error details, and elapsed time.

### FW-MEM-002 — CPU and DMA memory-access matrix

**Purpose:** Validate firmware-visible read/write and DMA access paths across
the memory regions supported by the configured system.

**Participants:** R5 and M85; R5 configures the DMA350. **Priority:** P0.

**Setup:** Before coding, produce a per-master table from the generated
interconnect and processor maps covering R5, M85, DMA350, and—where relevant—
U85/debug. For each region record read/write permission, local versus bus
address, cacheability, error behavior, and whether writes are safe. Do not
derive a DMA or peer-core address by copying another core's address.

**Procedure**

1. On each CPU, read safe identification/status registers and perform
   non-destructive write/readback only in documented scratch memory/registers.
2. Verify legal CPU paths to each documented region, including processor-local
   TCM via that processor's own view and shared SRAM. Keep R5 ATCM, its
   bootloader/DMA-visible view, and M85 ITCM views distinct.
3. Configure DMA transfers only for matrix entries marked legal. Use unique
   source/destination patterns and verify data at the destination with the
   CPU that owns that address view.
4. Use required cache clean/invalidate and barriers; run a control case with
   cache disabled only if supported and safe.
5. For a documented unmapped or forbidden region, use a recoverable fault
   handler and a bounded access. Confirm the documented bus error/CPU fault
   without corrupting unrelated state. If the platform has no recoverable
   response, do not probe it from a production board image; verify that case
   in RTL simulation instead.

**Checks and pass criteria**

* Every legal matrix entry performs the expected access and readback.
* Illegal entries are not accessed unless their error recovery is documented;
  when safely exercised, the expected fault is observed and execution
  continues to report the result.
* DMA completion, destination contents, and CPU visibility agree; no transfer
  is considered successful based on a completion flag alone.

**Evidence:** Versioned access matrix, address/view used, cache policy,
transaction dimensions, DMA status, and fault details.

### FW-IRQ-001 — Core interrupt behavior and priority

**Purpose:** Check representative interrupt delivery, acknowledgement, priority,
and wake-up behavior on both the R5 PL192 VIC and M85 NVIC.

**Participants:** R5 and M85. **Priority:** P0.

**Procedure**

1. Install handlers using the selected core's authoritative interrupt map.
   Initialize data shared with handlers before enabling interrupts; clear
   pending state and configure only the sources under test.
2. Trigger a low-rate timer interrupt on each core. Verify one handler entry
   per programmed event, source identity, acknowledgement/clear behavior, and
   return to the interrupted context.
3. Exercise one R5 source routed through VIC0 and at least one source routed
   through VIC1. Verify VIC vector/dispatch and daisy-chain behavior through
   the production driver.
4. Exercise representative M85 NVIC sources, including a peripheral IRQ and
   MHU IRQ. Test pending while disabled followed by enable only where the
   peripheral's documented semantics make this deterministic.
5. Exercise two sources at different configured priorities; verify the higher
   priority handler can preempt only when the architecture and masking policy
   permit it. Test nesting with bounded depth and no shared-state race.
6. Enter WFI only after the source and wake policy are configured; verify the
   intended interrupt wakes the core.

**Checks and pass criteria**

* The observed source, handler, vector, and count match the configured source
  on each core. No unrelated or duplicate interrupt is accepted.
* IRQs are disabled/masked during setup and reliably quiesced at teardown.
* VIC0 and VIC1 are both exercised; an R5 interrupt ≥32 is never handled as a
  VIC0-local source.
* Priority, nesting, and WFI expectations match the selected core and driver
  configuration.

**Limit:** This is representative source behavior; FW-IRQ-002 checks the
firmware-visible R5 VIC1 peripheral sources. Every IRQ-number mapping still
requires map consistency and directed source coverage from the verification
plan.

### FW-IRQ-002 — R5 VIC1 peripheral interrupt delivery

**Purpose:** Specifically prove that the R5 driver can enable, dispatch, and
clear IRQs routed to VIC1 at `VIC_BASE + 0x1000`.

**Participants:** R5. **Priority:** P0.

**Sources:** Timer0/1, UART0/1, watchdog, RTC, and SPI where implemented and safe.
Use authoritative `irq_map.h`; do not copy the M85 IRQ numbering. Verify the
source-to-IRQ routing against the selected RTL before the run.

**Procedure**

1. For each available safe source, configure one event at a time with all other
   sources masked. Read back the source's status and VIC enable/priority/vector
   programming where registers support readback.
2. Trigger the event using a documented stimulus: timer expiry, UART
   transmit/receive with a physical or internal loopback, RTC alarm using a
   valid board timebase, or SPI transfer with approved loopback/fixture.
3. For each event, check correct IRQ number, VIC1 dispatch, handler count,
   peripheral status clear, VIC end-of-interrupt behavior, and source deassert.
4. For watchdog, use only a separately supervised run: test interrupt-only
   behavior if supported; otherwise isolate the reset case under
   FW-RESET-001. Never let a watchdog expire unexpectedly during another test.
5. Exercise two enabled VIC1 sources with distinct priorities and check the
   documented arbitration order. Include rapid enable/disable only if the
   peripheral and VIC programming sequence is defined.

**Checks and pass criteria**

* Every source claimed by the board profile is delivered once on VIC1 and
  acknowledged without leaving the interrupt line asserted.
* Sources not present or not wired are explicitly marked unavailable in the
  signed board profile, not silently counted as passed.
* If GPIO combined IRQs are part of the intended R5 map, test them separately.
  The verification plan identifies a possible dropped combined-GPIO route;
  failure is a platform integration issue, not a firmware workaround.

**Evidence:** Source, configured IRQ, observed VIC instance/vector, handler
count, peripheral status before/after, and board loopback details.

### FW-RESET-001 — Local, system, and watchdog reset behavior

**Purpose:** Verify reset scope, reset cause, boot/release behavior, and
documented retention across supported reset sources.

**Participants:** R5 and M85. **Priority:** P0.

**Procedure**

1. Establish a baseline with both cores running a quiescent handshake. Record
   reset-cause bits and a test cookie in each state-retention location that the
   selected reset is documented to preserve.
2. Request an M85-local reset from the approved control path. Verify R5 remains
   active, M85 restarts according to its configured reset/CPUWAIT behavior, and
   the R5 observes the expected cause and handshake generation.
3. In a separate run, request an R5-local reset where implemented. Verify M85
   remains active and the R5 restart sequence is consistent with the boot
   architecture. Do not presume a local reset re-runs ROM or reloads TCM; record
   the actual documented behavior.
4. In a separate quiescent run, request system reset through the documented
   software path. Verify both cores restart and the boot path reloads/releases
   M85 as specified. Check reset cause and QSPI retention.
5. In a supervised isolated run, configure the watchdog using the authorized
   key/lock sequence and allow the intended reset. Capture the pre-reset
   watchdog event and post-reset cause. Ensure external recovery is available.
6. If the board exposes POR or DAP reset as part of this firmware suite, record
   them separately; firmware cannot itself prove the physical POR/DAP source.

**Checks and pass criteria**

* Each reset source has the documented scope: intended processors reset,
  unaffected processors and retained resources behave as specified.
* Reset-cause reporting identifies the initiating source and is cleared or
  retained according to the documented register semantics.
* The R5-first boot and M85 release work after system reset; local-reset
  behavior matches explicit architecture requirements.
* No reset is issued during active DMA/QSPI/U85 traffic in this testcase.
* Each stage has a bounded timeout and a board recovery procedure.

**Notes:** Local-reset transactions are performed only while the reset target
is quiescent until outstanding-transaction drain behavior is verified.

### FW-MHU-001 — Bidirectional MHU and shared-memory handshake

**Purpose:** Verify R5↔M85 doorbell, mailbox, interrupt, and synchronization
behavior without relying on an undocumented interprocessor protocol.

**Participants:** R5 and M85. **Priority:** P1.

**Procedure**

1. Define a test-only message structure with magic, protocol version, sequence,
   length, payload pattern, and integrity check. Place payloads in a reserved,
   legal shared-SRAM region; keep mailbox/doorbell programming to documented
   registers.
2. Initialize both endpoints, clear stale doorbell/mailbox state, and exchange
   a bounded ready handshake.
3. Send small, maximum-documented, and alternating-pattern payloads in each
   direction. Receiver validates sequence, length, contents, and integrity
   before acknowledging.
4. Exercise each documented channel or doorbell direction, one at a time, and
   then run a bounded sequence of back-to-back messages with distinct
   sequence numbers. Check IRQ source and clear semantics on both cores.
5. Test error/fault reporting only using a documented firmware-safe mechanism.
   Do not corrupt a live channel or invent invalid register writes to provoke
   hardware errors.
6. Reset endpoints only after all messages are acknowledged; test stale-state
   handling after reboot if reset behavior is specified.

**Checks and pass criteria**

* No lost, duplicated, reordered, or stale message is accepted.
* Each interrupt corresponds to a pending message and is cleared after service.
* Both directions complete before deadlines; any error/fault status is
  reported and handled as documented.
* Shared-memory visibility uses explicit barriers and cache maintenance where
  required.

**Evidence:** Per-direction message counts, sequence/error totals, payload
sizes, IRQ mapping, and reset generation.

### FW-DMA-001 — DMA transfer, completion, error, and abort

**Purpose:** Verify DMA350 configuration and SoC-visible data movement,
completion IRQ, error reporting, and safe abort handling.

**Participants:** R5 configures DMA; M85 may validate shared buffers. **Priority:**
P1.

**Procedure**

1. Build the transfer matrix from the configured DMA master map. Begin with
   aligned, bounded transfers between a known-readable QSPI image region and
   legal TCM/shared-SRAM destinations; include shared-to-shared and TCM paths
   only when the actual address views are confirmed.
2. Use several legal lengths around documented alignment/burst boundaries.
   Fill sources with address- and sequence-dependent data, initialize
   destinations to a sentinel, and verify every destination byte/word after
   completion.
3. Enable only the intended DMA completion/error interrupt. Check channel
   status, transferred length, destination contents, and interrupt clear.
4. Where the hardware documents abort/disable semantics, start a sufficiently
   long transfer, request abort at a controlled point, and verify terminal
   channel status, no writes beyond the documented completed portion, and
   correct error/abort interrupt behavior.
5. For invalid addresses or bus errors, use a documented safe target and
   recovery path only. If a board fault could hang the fabric, perform that
   negative case in simulation instead.
6. Repeat a small transfer while a CPU operates on a separate buffer. Do not
   overlap buffers until arbitration and coherency requirements are understood.

**Checks and pass criteria**

* Every legal transfer has byte-exact destination data; completion is not
  accepted without independent readback.
* IRQ and status correspond to the correct channel and final outcome.
* Abort/error cases terminate within a deadline and do not masquerade as
  successful completion.
* No out-of-range destination corruption or unexplained CPU stall occurs.

**Evidence:** Channel/configuration, source/destination views, length/alignment,
status/IRQ, data-check result, and abort/error details.

### FW-QSPI-001 — Read-only QSPI/XIP and warm-reset retention

**Purpose:** Verify flash reads used by the boot path, safe memory-mapped/XIP
reads if configured, and the documented warm-reset retention behavior.

**Participants:** R5; M85 participates only if its map grants a legal QSPI view.
**Priority:** P1.

**Procedure**

1. Read the flash preamble and selected known image ranges through the supported
   controller path. Compare against build-time hashes or checksums prepared by
   the image-generation process.
2. Read selected locations repeatedly and, where XIP is enabled, compare
   controller-mediated and XIP results. Include aligned and boundary reads
   supported by the interface; do not fetch beyond the provisioned image.
3. If caches are present and enabled, verify cold and repeated reads, and use
   the documented invalidate procedure before comparing after a mode change.
4. Record the controller configuration, then perform one supported warm reset
   after quiescing accesses. Verify retained configuration and successful
   post-reset reads without relying on undocumented retention.
5. Flash program/erase is out of the default test. Add it only when the board
   profile identifies a disposable scratch region, its erase geometry, and a
   proven restoration/recovery procedure.

**Checks and pass criteria**

* Read data matches independently generated reference data, including at the
  tested range boundaries.
* XIP and controller results agree for equivalent reads.
* Warm-reset configuration behavior matches the configured design; any
  required reinitialization is performed and validated.
* The test makes no writes outside an explicitly authorized scratch range.

**Evidence:** Flash image hash/ranges, access mode, cache state, reset type,
controller state, and read comparison results.

### FW-PERIPH-001 — Peripheral function and interrupt checks

**Purpose:** Validate firmware-visible basic operation of UART, timers, GPIO,
SPI, watchdog, and RTC that are present and safely accessible on the board.

**Participants:** R5 and M85 according to their respective peripheral maps.
**Priority:** P1.

**Procedure**

1. Read identification/status registers where defined; verify reset values
   before enabling a peripheral.
2. UART: transmit a known byte pattern and verify it at the host or a documented
   loopback. Check receive and overrun behavior only when the host/fixture can
   provide controlled input.
3. Timer: program a bounded interval, measure expiry against a calibrated
   reference, verify status/IRQ, clear, and repeat at a second prescale.
4. GPIO: drive and sample only board-approved pins. Use a documented external
   loopback or input fixture; do not drive pins connected to unknown hardware.
   Check configured edge/level event and IRQ clear.
5. SPI: perform a loopback or exchange with an identified, safe peripheral.
   Do not assume an attached device or issue destructive commands.
6. RTC: test counter progression and alarm only if clock source and timebase
   are known.
7. Watchdog: non-reset interrupt behavior may be checked here only if the
   watchdog supports it. Any reset-causing sequence belongs to FW-RESET-001.

**Checks and pass criteria**

* Every tested peripheral produces expected data/status within its deadline;
  each claimed interrupt matches the authoritative core-specific map.
* Interrupts and peripheral status are cleared and the device returns to a
  known quiescent state.
* Unsupported or unwired resources are identified as not applicable in the
  board profile, not reported as passing tests.

**Evidence:** Peripheral instance, register/configuration summary, wiring/
fixture, measured timing, IRQ identity, and result.

### FW-U85-001 — U85 configuration, memory, IRQ, and inference

**Purpose:** Verify end-to-end SoC-visible operation of the configured NPU
demonstrator, including a reference-checked inference—not merely register
writes.

**Participants:** M85 as host; R5 may supervise. **Priority:** P1.

**Blocking prerequisites:** The FPGA image includes a configured, clocked, and
reset-connected U85; an M85-compatible driver/runtime and build path are
available; the allowed U85 memory regions and DMA visibility are verified; the
model and reference inputs/outputs are versioned. The U85 integration plan
identifies outstanding runtime, memory-route, and integration work. Until these
prerequisites are demonstrated on the board, this testcase is **blocked**, not
passed.

**Procedure**

1. Read U85 identification/configuration registers and verify reset/idle state
   using the official configured integration definitions.
2. Configure only documented control, QBASE/QSIZE, and memory settings. Verify
   legal address width/range and reject any model/tensor allocation outside
   the accessible region.
3. Run a small deterministic inference with fixed input vectors. Check command
   acceptance, bounded completion, completion/error IRQ to M85, and output
   against a versioned reference using exact or documented tolerance criteria.
4. Run a second inference with changed input and confirm the result changes as
   expected; validate output buffer ownership and cache maintenance.
5. If shared SRAM access by U85 is part of the intended design, run a separate
   legal shared-memory case and verify the data path. Do not assume the U85
   master is connected to that memory.
6. Check a documented software-visible error result if one is safely
   reproducible; otherwise leave error injection to the RTL testbench.

**Checks and pass criteria**

* Identification/configuration and memory range checks pass.
* Inference completes before timeout, the correct IRQ/status is observed, and
  output matches the reference criteria.
* No undocumented memory route, coherency behavior, or presence-based skip is
  used to claim a pass. U85 remains in the baseline as required by the
  verification-plan decision.

**Evidence:** RTL/IP configuration, runtime/driver/model versions, input and
reference hashes, memory route, IRQ/status, output comparison, latency.

### FW-DEBUG-001 — Firmware debug targets and external DAP checks

**Purpose:** Provide safe firmware state for an external debugger to validate
DAP access, and verify end-to-end debug operations without claiming firmware
alone can test SWD/JTAG.

**Participants:** R5 firmware plus authorized external debug host. **Priority:**
P1.

**Procedure**

1. Firmware initializes deterministic, non-sensitive scratch locations in
   shared SRAM and (where safe) each core's documented debug-visible memory.
   It records expected values and enters a bounded wait state without
   continually modifying those locations.
2. From the external host, connect using the documented SWD/JTAG procedure.
   Read identification/component IDs and the test signatures through each
   supported AP. Verify exact data and address behavior.
3. Test only debug memory/register accesses authorized for this board. Exercise
   writes solely to dedicated scratch locations; verify readback through
   firmware after the debugger resumes execution.
4. If core halt/resume or reset is part of the approved policy and is
   implemented, test each operation in isolation with a recovery path. Do not
   infer core-control support from successful ROM-table reads.
5. Record whether R5, M85, system-bus access, and APB access are actually
   exposed in the FPGA build. Report unsupported paths as blocked.

**Checks and pass criteria**

* External host access returns the expected IDs and signatures on each tested
  AP/path.
* Firmware confirms debugger writes only in scratch and resumes with state
  intact, if write access is part of the authorized test.
* Halt/resume/reset pass only if explicitly implemented and authorized.
* Security/authentication limitations are documented; no production security
  claim is made from a development-board test.

**Evidence:** Host/tool version, transport, AP and address tested, access
results, authorization configuration, and firmware post-check.

### FW-STRESS-001 — Bounded concurrent-load and recovery

**Purpose:** Exercise normal concurrency and forward progress across processors,
shared SRAM, DMA, peripherals, and U85 when available.

**Participants:** R5 and M85; DMA/U85 only after their individual tests pass.
**Priority:** P2.

**Prerequisites:** All participating component tests pass. Use a known-safe
board configuration with temperature/power monitoring and a reliable reset
path. This is not a substitute for electrical, timing, or protocol stress
sign-off.

**Procedure**

1. Assign non-overlapping shared-SRAM buffers and bounded workloads to each
   core. Include sequence-numbered MHU messages and timer/UART activity.
2. Run legal DMA copies concurrently on disjoint buffers; add U85 inference
   only when FW-U85-001 has passed and its memory route is verified.
3. Maintain per-agent progress counters and deadlines. Verify final buffer
   checksums and message sequence counts. Use deterministic seeds/configuration
   for reproducing failures; optionally sweep a published seed set.
4. Repeat with cache-maintenance sequences enabled. Do not intentionally
   provoke reset during active transactions here. Reset-during-traffic remains
   a simulation/RTL negative test until safe behavior is established.
5. Stop all sources cleanly, verify quiescence, then optionally perform a
   supervised watchdog/system-reset recovery as a separate phase.

**Checks and pass criteria**

* Every agent advances before its deadline; no data corruption, lost messages,
  unexpected interrupt, timeout, or unexplained reset occurs.
* Concurrency does not alter the correctness criteria of the individual
  transfers/inferences.
* Any failure includes seed, agent progress, active configuration, and latest
  sequence number.

**Evidence:** Duration, seed, per-agent throughput/progress, buffer checksums,
IRQ/reset counts, and board telemetry.

### FW-PERF-001 — Latency and throughput characterization

**Purpose:** Produce repeatable baseline measurements for shared SRAM, DMA,
QSPI reads, and U85 inference when available; this is characterization, not an
unqualified performance requirement.

**Participants:** R5 and/or M85 per tested path. **Priority:** P2.

**Procedure**

1. Identify and calibrate the timer source, frequency, counter width, and
   wraparound behavior. Record core frequency, memory/cache configuration,
   FPGA build, board revision, and ambient/thermal state.
2. Measure timer overhead and an empty-loop control. For each path, warm up,
   run a fixed set of transfer sizes and iteration counts, then report raw
   samples and summary statistics rather than a single best result.
3. Measure shared-SRAM reads/writes from each core, DMA transfers by legal
   source/destination pair, QSPI sequential/random reads, and U85 inference
   only when its required runtime and memory route are verified.
4. Use separate uncontended and controlled concurrent-load runs. Record cache
   state and maintenance; do not compare unlike configurations.
5. Establish pass/fail performance thresholds only after a stable board
   baseline and product requirement are approved. Until then, this testcase
   passes on valid measurement collection and correctness checks, not on an
   invented latency target.

**Checks and pass criteria**

* Measurements are nonzero where expected, timer wrap is handled, and all
  compared data/results remain correct.
* Reports include units, timer calibration, sample count, min/median/max and
  configuration. Invalid or incomplete measurements fail.
* Performance claims are limited to the recorded FPGA configuration; they do
  not imply ASIC timing or deterministic worst-case latency.

## 4. FPGA execution and reporting

### 4.1 Run stages

1. **Preflight:** verify board profile, bitstream and image IDs, boot media
   hashes, UART capture, reset/recovery path, and external fixtures.
2. **Smoke:** cold boot (FW-BOOT-001), then one bounded shared-SRAM pass
   (FW-MEM-001) and representative IRQ checks (FW-IRQ-001).
3. **Core function:** run P0 memory, IRQ, and reset tests before dependent
   P1 tests. Keep reset- and watchdog-causing tests isolated.
4. **Subsystem function:** run MHU, DMA, QSPI, peripheral, U85, and debugger
   tests only when their board-profile prerequisites are met.
5. **Extended:** run stress and performance tests after functional cases pass.
6. **Archive:** preserve per-core UART logs, test manifest, firmware/bitstream
   hashes, board profile, operator/fixture notes, and all failures.

### 4.2 Result states

Use only:

* **PASS** — all defined checks completed with required evidence.
* **FAIL** — an expected behavior/check failed or a timeout/error occurred.
* **BLOCKED** — a prerequisite, required IP/runtime, fixture, or board access is
  unavailable. Include the missing requirement; blocked is not pass.
* **NOT RUN** — explicitly excluded from this run manifest; report the
  exclusion and reason. P0 tests cannot be silently omitted from a sign-off run.

### 4.3 Sign-off criteria

* Every P0 testcase is PASS on the target FPGA image; failures are fixed and
  rerun, not waived by changing expected output after the fact.
* P1/P2 PASS or have a reviewed, board-specific disposition and rationale.
* Every result is traceable to firmware, bitstream, board profile, and raw logs.
* Map/IRQ discrepancies, unavailable U85/debug paths, SRAM alias behavior, and
  reset-retention behavior are recorded as measured facts.
* No test relies on an undocumented hardware behavior, a simulation-only
  stimulus, or the presence of pre-existing test firmware.

## 5. Relationship to the verification plan

These specifications cover the firmware-level IDs only. They complement,
rather than replace, the parent plan's unit/integration RTL tests for protocol
violations, unmapped-address behavior that may hang a physical bus, reset
during active traffic, flash/DMA error injection, coverage closure, CDC, and
formal properties. Keep the stable IDs in sync if either plan changes.
