# Arm Ethos-U85 Integration — Implementation Plan

| | |
|---|---|
| **Status** | In progress — regenerated NIC400 and full SoC compile/hello pass; shared-SRAM target is not yet connected |
| **Scope** | `millisoc_tech` RTL, NIC400 configuration/build flow, SDK firmware, simulation, and platform documentation |
| **Demonstrator** | Arm Ethos-U85 behind an accelerator-independent milliSoC integration boundary |
| **Last updated** | 2026-10-23 |

---

## 1. Purpose and scope

Integrate an executable Ethos-U85 demonstrator into milliSoC while keeping the
platform's accelerator interface replaceable by independent research IP. The
integration is complete only when the RTL, interconnect, address map, interrupt
path, memory policy, firmware, build flow, and simulation all agree.

### 1.1 Goals

1. Instantiate the exact licensed U85 deliverable and its required configuration
   and support RTL, using the vendor integration documentation for that release.
2. Define a small platform-facing NPU contract and keep Ethos-specific wiring and
   configuration behind it where practical.
3. Enable the M85 host to configure and launch inference, receive completion and
   error status through its verified interrupt path, and access model/tensor
   storage through legal, verified bus paths.
4. Preserve the existing R5-first boot and the M85 application role, and verify
   that the baseline `hello` test still works.
5. Document how a researcher can replace the U85 implementation without making
   Ethos-specific RTL, firmware, or address assumptions mandatory platform APIs.

### 1.2 Non-goals

* Do not replace the PL192 VIC with a GIC or introduce an unimplemented
  interprocessor communication scheme.
* Do not assume cache coherency, unrestricted TCM visibility, or a shared-memory
  region until each is verified in the RTL and generated interconnect.
* Do not change the existing flash preamble or boot format just to carry model
  data. First determine whether the firmware image and existing memory map can
  contain or load the required assets.
* Do not add a generic accelerator framework beyond the minimum stable
  integration boundary needed for this demonstrator.
* FPGA and ASIC implementation sign-off are follow-on activities unless the
  selected U85 deliverable and target flow are available during this work.

## 2. Current state (repository evidence, 2026-10-23)

* The project architecture calls for an accelerator that is configurable and
  replaceable; U85 is a demonstrator, not a platform dependency
  (`AGENTS.md:20-37`).
* The system declares a 64-bit, 32-bit-address AXI4 interface for DMA350 and
  separate processor AXI interfaces (`millisoc_tech/logical/millisoc_system/millisoc_system.sv:91-125`).
  DMA350's AXI master is instantiated and connected to the NIC400 system fabric
  (`millisoc_tech/logical/millisoc_system/millisoc_system.sv:1033-1108`,
  `:1293`, `:1537-1571`). This is evidence of a current bus-master pattern, not
  evidence that a U85 port can be wired directly without width, ID, protocol,
  security, or fabric changes.
* DMA completion interrupts are connected into the R5 and M85 interrupt vectors;
  the peripheral interrupt vectors are also wired in
  (`millisoc_tech/logical/millisoc_system/millisoc_system.sv:259-294`). The
  actual U85 interrupt source, required polarity, and intended CPU destination
  remain to be checked against the delivered U85 interface and PL192 routing.
* Current system clock, reset, and enable tie-offs are visible in
  `millisoc_tech/logical/millisoc_system/millisoc_system.sv:303-323`. They do not
  establish the U85 clock, reset, low-power, or CDC requirements.
* The top-level RTL filelist includes the current system, NIC400, VIC, DMA350,
  and SoC-400 sources
  (`millisoc_tech/flist/millisoc_top.flist:1-31`). U85 RTL is not currently
  listed there. The simulation filelist reaches it through
  `millisoc_tech/flist/millisoc_BEHAV.flist:1-2`, included by
  `flist/top_BEHAV.flist:1-4`.
* The processor configuration identifies Cortex-M85 and Cortex-R5 Arm IP paths
  (`millisoc.config:3-8`); the project setup notes that licensed Arm IP is
  external to the repository (`AGENTS.md:300-313`). The U85 package is available
  in the configured licensed-IP tree. Its configured RTL and vendor VCS
  execution testbench have now been verified; project-level SoC integration and
  M85 software support remain open.
* The configured licensed-IP tree contains Ethos-U85 release
  `ETHOSU85-ML009-r0p0-00eac0` under
  `$ARM_IP_LIBRARY_PATH/Ethos-U85/ethosu85`, including the configuration and
  integration manual, generic RTL RAM/cell models, the execution testbench,
  and an integration kit. The hand-maintained `logical/ethosu85/verilog/ETHOSU85.sv`
  is an unconfigured template (`CFG = <UNCONFIGURED>`); the supplied default
  config is 256 MACs. The integration manual requires the supplied
  `$ARM_IP_LIBRARY_PATH/Ethos-U85/ethosu85/logical/generate` script to configure
  RTL and IP-XACT. The generator requires Perl 5.36.0 and Python 3.7 or later.
  Perl 5.36.0 was built under a user-local prefix and Python 3.11 was used for
  IP-XACT generation. The configured 256-MAC output was generated and tested
  from a private user-local copy because the generator rewrites a RAM-testbench
  source file in its input tree. The shared licensed-IP tree and repository
  remain free of generated U85 RTL. The `socrates_cli` command is available for
  the separate NIC400 build.
* The U85 integration manual specifies 128-bit ACE-Lite memory interfaces
  (usable as AXI when domain signals are not used), a level-high IRQ, an 8 KiB
  APB completer window, and required clock/reset and Q-channel integration.
  With the default 256-MAC config, the release configuration helper removes
  SRAM2/3 and EXT1, leaving SRAM0/1 and EXT0. These are materially different
  from the current 64-bit, 32-bit-address NIC400 system
  (`nic400_millisoc_main.xml`). The generated ports are 128-bit data,
  40-bit address, and 6-bit ID; a 32-bit NIC400-facing boundary must reject
  nonzero address bits [39:32] before any narrowing conversion.
* The generated U85 execution testbench compiled with VCS. Its
  `initial_checktest`, `config_check` (reported `NUM_MACS=256`), and
  `power_indicative_typical` tests all passed. The shared vendor source tree was
  not modified.
* The supplied firmware integration kit's build rules enumerate Cortex-M33,
  Cortex-M55, and Cortex-A53 host configurations, not Cortex-M85. An M85 host
  port or another supported host strategy is therefore unverified.
* The documented baseline has now been run in this worktree: after sourcing
  `set_env.sh`, `make compile SIMULATOR=vcs` exited successfully; then
  `make run TESTNAME=hello SIMULATOR=vcs` exited successfully. The simulation
  log showed the DAP BFM `ALL TESTS PASSED`, the R5 bootloader and both R5/M85
  `Hello SoCLabs MilliSoC` banners, `Test Ended`, and `TPIU PASS`. Existing
  build/runtime warnings were present; they were not introduced or addressed
  by this plan update.
* The documented baseline is a working R5-first boot that preloads M85 and R5
  TCM images and releases the M85 through `CPUWAIT`
  (`AGENTS.md:61-83`, `README.md:132-157`). The existing image format contains
  M-class and R-class payloads only (`README.md:111-129`).
  Do not imply that U85 firmware, model loading, or inter-core coordination
  already exists.
* The available firmware build path is Arm Development Studio 6; the root
  `all_ds6` image-building flow creates separate M/R images and combines them
  (`AGENTS.md:300-329`). Whether a compatible U85 driver, runtime, compiler, and
  example model are available must be established before committing to a
  software implementation.

## 3. Proposed integration boundary and ownership

### 3.1 Platform contract

Add an Ethos-specific implementation behind a narrow milliSoC NPU integration
boundary. The wrapper boundary should make the following explicit, based on the
actual delivered U85 interface:

* control/status register interface and address decode;
* every memory-master interface, protocol, width, ID behavior, attributes, and
  error response behavior;
* completion/error interrupt signals and acknowledge/clear behavior;
* clock, reset, clock-enable, power/low-power handshakes, and any CDC boundary;
* security, privilege, and protection attributes; and
* tie-offs for optional ports, justified by the vendor documentation.

Do not invent a register map or tie off required interface signals to obtain a
compile. Keep the platform-facing contract small enough to implement with a
research accelerator wrapper later.

### 3.2 Processor and boot ownership

Keep the R5 as system master for platform initialization and supervision. Use
the M85 as the initial inference client if the U85 software stack and bus access
support that model. This is a proposed allocation, not an existing capability:
the baseline does not yet implement M85/R5 shared-memory coordination
(`AGENTS.md:78-83`). The first working inference test should therefore avoid
requiring cross-core synchronization unless that mechanism is separately
designed and tested.

Treat U85 reset/release and post-reset register initialization as explicit
sequencing requirements. Determine whether the existing R5 bootloader must
configure or release the U85, or whether the U85 is available after system reset
and is configured by the M85 application. Preserve the existing image format
unless a verified memory-placement requirement forces a separately reviewed
boot-format change.

### 3.3 Memory and bus policy

Before selecting tensor/model placement, map every U85 master to reachable
targets and prove the chosen target accepts its transaction sizes, bursts,
attributes, and ID behavior. Explicitly distinguish processor-private TCMs from
shared or system memory. If no suitable U85-accessible storage exists, propose
and verify the smallest required memory/fabric change rather than treating
processor-local memory as shared.

Document cache maintenance and ordering requirements for the M85 and R5.
Hardware coherence must not be assumed. Include arbitration and worst-case
contention considerations for the DMA350, processors, and U85, especially if
real-time work shares the system fabric.

## 4. Architectural decisions requiring sign-off

| ID | Decision | Proposed default | Status |
|---|---|---|---|
| D1 | Exact U85 release, configuration, support IP, simulation model, and licensing/build access | Use the versioned release delivered for this project; stop RTL integration if its required source/model is unavailable | **TECHNICALLY VERIFIED** — r0p0 256-MAC RTL generated and its VCS sanity/configuration/typical tests passed; licensing remains governed by the project's existing Arm agreement |
| D2 | Wrapper and replaceable platform-facing contract | Keep U85-specific ports/parameters in a thin wrapper; avoid making the wrapper a large configurable framework | **PROPOSED** |
| D3 | Control interface and register address | Add an 8 KiB APB target through NIC400 at `0x44031000`, immediately after the existing 4 KiB SYS_CTRL window | **APPROVED** — user decision 2026-10-23; generated decode remains unverified |
| D4 | U85 memory masters and accessible memory | Add 1 MiB shared on-chip SRAM at `0x20000000`, accessible by M85, R5, and the three U85 managers through NIC400; reject nonzero U85 address bits [39:32] | **APPROVED** — user decision 2026-10-23; width conversion, upper-address rejection, implementation, and memory visibility remain unverified |
| D5 | Interrupt source, polarity, clearing, and destination | Route the level-high U85 IRQ directly to M85 external IRQ 65; keep the R5 PL192 path separate | **APPROVED** — user decision 2026-10-23; RTL connection and acknowledge/clear behavior remain unverified |
| D6 | Reset, clock, power, and low-power policy | Use the common FCLK domain and system reset; keep Q-channel clock/power requests inactive for the initial always-on demonstrator | **PROPOSED** — matches the current single-clock system and vendor no-Q-channel default tie-offs; connect APB PWAKEUP according to the vendor registered-PSEL requirement |
| D7 | Workload control ownership | M85 submits inference; R5 retains system-init/supervision role; no assumption of existing inter-core messaging | **APPROVED DIRECTION** — user decision 2026-10-23; M85 driver/toolchain support must be demonstrated |
| D8 | Model/weight loading and placement | Keep assets within existing firmware/image and verified memory capacity if feasible; expand boot/image handling only with a separately tested design | **PROPOSED — blocking sizing check** |

## 5. Staged implementation

Each stage must leave the existing baseline buildable and testable. Do not start
a dependent stage while its blocking decisions remain unresolved.

### Stage 0 — IP and baseline readiness

1. Identify the exact U85 release, RTL/configuration generator, integration
   documentation, firmware driver/runtime, and simulation model available to the
   project; record versions and licensed source locations in the implementation
   handoff, not in public source if those paths are sensitive.
2. Check model availability, simulator compatibility, build permissions, and
   any U85-specific build steps. Establish the supported interface and
   configuration before editing the SoC.
3. Run the known-good `hello` firmware and VCS flow as a baseline, recording the
   commands and key R5/M85 boot and UART completion evidence. The project guide
   describes `make compile SIMULATOR=vcs` followed by
   `make run TESTNAME=hello SIMULATOR=vcs`.

**Progress (2026-10-23):** The r0p0 RTL, integration manual, configuration
helper, generic simulation models, execution testbench, and software
integration kit were found in the configured licensed-IP tree. The baseline
VCS compile and `hello` simulation both passed; the simulation preserved
R5-first boot and printed the expected R5/M85 banners. A user-local Perl 5.36.0
installation resolved the generator prerequisite; Python 3.11 was used for its
IP-XACT step. The 256-MAC RTL was generated outside the repository and compiled
with VCS; `initial_checktest`, `config_check`, and `power_indicative_typical`
passed. Generation ran from a private copy because the generator rewrites a RAM
testbench source in its input tree; neither the shared release nor repository
was changed by generation.

The generated managers are 128-bit/40-bit-address/6-bit-ID ports. Any
32-bit-address NIC400 boundary must preserve and reject nonzero address bits
[39:32], never alias them by truncation. Source tracing confirms the R5 input
is served through the PL192 path, while the M85 has a separate direct external
IRQ vector at input 65. The user approved an 8 KiB U85 APB window at
`0x44031000`, 1 MiB shared SRAM at `0x20000000`, and direct level-high IRQ 65
to the M85. The software kit supports M33/M55/A53 examples, not M85, so M85
driver/runtime compatibility remains open.

The user approved the M85 host/R5 supervisor roles, 256-MAC configuration,
all three managers through NIC400, and the APB/SRAM/IRQ selections in D3-D5.
Model placement and cache/ordering policy remain to be resolved.

**Exit criteria:** The configured RTL and U85-specific VCS tests run; the
required source/model and build access are available; baseline behavior is
captured. These RTL/build criteria are now passed. M85 host software
compatibility remains open and blocks Stage 3, but does not block the Stage 1
interface and address-map audit.

### Stage 1 — Interface contract and system design

1. Extract and review the delivered U85 subsystem integration requirements:
   clocks, resets, power/low-power controls, interrupts, control bus, memory
   masters, optional ports, supported parameters, and security attributes.
2. Trace current NIC400 master/slave configuration and generated decoders,
   peripheral decode, memory targets, interrupt inputs, and actual TCM/shared
   memory visibility. For the selected 256-MAC configuration, account for all
   three independent U85 memory managers (SRAM0, SRAM1, EXT0); do not assume one
   NIC400 port or a shared target serves every manager. Do not infer the RTL map
   from prose or address labels.
3. Resolve D2-D8. Publish the signal-level boundary, chosen register and memory
   regions, IRQ assignment, startup owner, model location/size, and
   cache/ordering policy before wiring the subsystem.
4. Record expected resource, bandwidth, and timing constraints for U85 traffic
   alongside existing CPU and DMA350 masters.

**Current trace:** The 256-MAC output exposes SRAM0, SRAM1, and EXT0, each with
128-bit data, 40-bit addresses, and 6-bit IDs. The NIC400 uses 64-bit system
data and 32-bit address maps. The hand-edited high-level NIC400 specification
now declares each U85 manager, maps them and both processors to the approved
1 MiB shared-SRAM window, maps the 8 KiB U85 APB window, and splits the DEBUG
CPU_S region around the shared SRAM to avoid an address overlap. The XML parses
and a local range audit found no overlaps. NIC400 has since been reconfigured
and regenerated with `SHARED_SRAM` set to 64 bits to avoid the reported bus
deadlock risk. The generated NIC top confirms 64-bit shared-SRAM data and the
three U85 interfaces. No 128-bit conversion or 40-to-32-bit upper-address
rejection has yet been validated. The R5 interrupt vector is routed through
PL192; M85 external IRQs are direct.

**Exit criteria:** Reviewed interface and map tables are internally consistent
across RTL, firmware, testbench, and build configuration; no required signal or
memory target remains an undocumented assumption.

### Stage 2 — RTL wrapper and build integration

1. Add the minimal wrapper and U85 instance/configuration using the delivered
   RTL and supported parameters. Keep generated/vendor RTL separate from
   hand-maintained platform glue.
2. Connect documented clock, reset, power/idle, and error/status signals.
   Include CDC logic only if the documented domains differ; provide assertions
   or checks for reset release and any required sequencing.
3. Integrate the required control and every configured memory port into the
   actual system fabric. Update NIC400 source configuration and regenerate the
   fabric using its supported build flow; do not hand-edit generated decoder
   RTL.
4. Add U85 source files and prerequisites to the authoritative filelists and
   compile/build targets. Keep simulator-specific models/defines explicit and
   fail clearly when required licensed source or model files are unavailable.
5. Add or update interrupt wiring to the M85 external IRQ input, and to the
   PL192 only if a separately defined R5-supervision route is needed. Confirm
   signal polarity, pending, mask, acknowledge, and clear semantics against
   both U85 integration documentation and the relevant processor interrupt
   controller.

**Progress (2026-10-23):** Added `millisoc_ai_subsystem.sv` with direct
connections for all 151 ports of the generated 256-MAC U85, including its
three 128-bit/40-bit/6-bit AXI managers and APB control interface. The system
now instantiates that subsystem, routes its IRQ to M85 external IRQ 65, and
maps its bus channels to the expected NIC400 `U85_SRAM0`, `U85_SRAM1`,
`U85_EXT0`, and `U85_CFG` ports. Always-on clock, Q-channel, test, and
configuration tie-offs match the vendor execution-testbench setup; APB
PWAKEUP is registered in the system. Added an RTL filelist that expects
`SOCLABS_ETHOS_U85_DIR` to point at the configured generated package root.
NIC400 was reconfigured and regenerated by the user, with its shared-SRAM
target changed to 64 bits. Refreshed the simulation NIC400 filelist from the
generated manifest, including the added U85 bus components and current
default-slave instances; excluded the NIC's colliding `ApbPC` library from
module search. Full VCS compile now succeeds, and the `hello` simulation passes
with the R5/M85 banners and TPIU trace checks. VCS still reports the
`SHARED_SRAM` target ports unconnected: the actual 64-bit shared-memory target
is not instantiated or connected yet. U85 memory transactions, address
conversion behavior, and inference therefore remain unverified.

**Exit criteria:** RTL compiles with the real configured U85 deliverable;
fabric build validates; an isolated directed test demonstrates register access,
legal memory reads/writes, response/error handling, interrupt assertion and
clear, and reset/idle behavior.

### Stage 3 — Firmware and inference workload

1. Add the U85 control/driver integration to the SDK using the supported
   software package. Keep device registers, IRQ identifiers, and cache
   maintenance definitions aligned with the RTL address and interrupt maps.
2. Add a minimal M85 test application that initializes the U85, prepares input
   and output buffers in verified U85-accessible memory, launches one
   deterministic example model, waits for completion with a bounded timeout,
   and reports completion, error status, and checked output.
3. Determine how model weights and runtime data fit the existing
   `concat_hex.py` M/R image flow and linker/scatter regions. If a new asset or
   boot-loading mechanism is unavoidable, design it as an explicit and tested
   extension; do not silently alter the four-word flash preamble.
4. Define timeout and error handling so an absent interrupt, U85 fault, or
   invalid transaction fails the test visibly instead of hanging or printing a
   success-shaped result.

**Exit criteria:** The real U85 model executes from firmware and produces
expected, tolerance-defined output; error and timeout paths are observed;
register definitions, memory placement, cache maintenance, and interrupt
handling agree with the hardware.

### Stage 4 — SoC-level regression and contention

1. Run the U85 test end to end through the normal firmware-image and simulation
   flow; confirm R5 boot and M85 release remain unchanged.
2. Re-run `hello` without U85 workload and test the U85 workload alongside
   relevant processor and DMA350 traffic. Check for deadlock, starvation,
   response-ID mismatches, decode faults, and unexpected IRQ retriggering.
3. Exercise reset during idle and completion, repeated inferences, maximum
   supported transfer sizes, buffer boundary conditions, and documented error
   responses.
4. Inspect AXI logger output and simulator diagnostics for stalls and incomplete
   handshakes. Add assertions/checkers for integration invariants that can be
   observed reliably.
5. If the project environment supports them, run synthesis/lint and FPGA
   implementation checks on the exact target. Report unavailable flows
   accurately; the root lint/FPGA flows are currently stubs
   (`AGENTS.md:348-352`).

**Exit criteria:** Baseline and U85 regressions pass repeatedly, failure cases
are bounded and observable, and no unreviewed warnings or protocol errors
remain.

### Stage 5 — Reuse documentation and handoff

1. Update the root `README.md` status, architecture, software prerequisites,
   build/run steps, and known U85 limitations from verified results only.
2. Document the NPU wrapper contract, memory/IRQ assignments, cache policy,
   startup behavior, required proprietary artifacts, and a path to substitute a
   research accelerator.
3. Record unresolved implementation, licensing, performance, and
   hardware-validation risks. Keep U85-specific details out of stable platform
   interfaces unless they are genuinely part of the common contract.

**Exit criteria:** A new project user can reproduce the simulation, understand
what IP is required and licensed, and identify the minimum boundary to replace
the U85.

## 6. Verification strategy

| Area | Required evidence |
|---|---|
| Build closure | Filelist and NIC400 generation include the delivered U85 RTL/configuration; clean RTL compile succeeds in the supported simulator |
| Reset/clock | U85 starts in a documented reset state; release, clock enables, idle/low-power controls, and CDC behavior match the integration guide |
| Control | Firmware can read documented identity/status, configure, start, and observe/clear a completion or error; invalid accesses produce expected failures |
| Memory access | U85 can read/write the selected buffers in legal ranges with supported burst/size/attributes; out-of-range or unsupported transfers fail observably |
| Interrupt | Completion and error IRQs reach the selected PL192 input and intended CPU; masking, servicing, and clearing prevent lost or repeated events |
| Firmware result | A fixed small model produces expected outputs using an explicit comparison/tolerance and bounded completion timeout |
| Boot compatibility | Existing R5 bootloader, preamble, DMA preload, M85 release, and `hello` output still pass |
| Traffic interaction | Simultaneous CPU, DMA350, and U85 traffic completes without deadlock, protocol errors, or unreviewed starvation |
| Cache/order | Input/output visibility is correct under the documented maintenance and memory-order rules; no coherence is presumed |
| Implementation readiness | Synthesis/FPGA checks are run if available; tool, license, and flow limitations are recorded rather than reported as passes |

## 7. Risks, assumptions, and open questions

| ID | Risk / open question | Mitigation / required evidence | Status |
|---|---|---|---|
| R1 | Exact licensed U85 subsystem source, integration package, and simulator model may not be available in the configured Arm IP tree | Confirm delivery and license before RTL work; record exact release and supported compile flow | Open; blocks Stage 2 |
| R2 | U85 control, AXI master count/width/ID, security, and optional signals are release/configuration-specific | Derive the contract from that release's integration documentation and generated configuration; no guessed tie-offs | Open |
| R3 | No suitable shared memory may be reachable by the U85 master; M85/R5 TCMs are private resources unless RTL proves otherwise | Audit generated NIC400 map and actual target ports; allocate or add shared memory only with full RTL/firmware/testbench map updates | Open |
| R4 | The existing flash image carries only the two CPU payloads; model size may exceed available firmware memory | Measure runtime/model footprint early; keep the current image format unless a reviewed boot extension is required | Open |
| R5 | Data caches and cross-master visibility may require explicit maintenance; coherent behavior is not established | Document cacheability and maintenance rules from actual core/fabric setup; verify with data-pattern tests | Open |
| R6 | Added U85 traffic may contend with real-time CPU and DMA traffic | Measure/inspect arbitration and stalls under mixed traffic; state deterministic-latency limitations | Open |
| R7 | U85 interrupt routing or reset sequencing may not match existing simple tie-offs | Check U85 requirements and PL192 wiring; test polarity, clear, reset, and repeated events | Open |
| R8 | U85 software/runtime and model-generation tools may have independent versions and licensing | Confirm compatible runtime/toolchain artifacts and include reproducible version/build details | Open |
| R9 | The selected 256-MAC configuration has three independent 128-bit managers | Route SRAM0, SRAM1, and EXT0 through NIC400 to the approved shared SRAM; give each port a valid transaction path and common verified address window | Routing direction approved; NIC400 width/build support and SRAM implementation remain open |

## 8. Decision log

| Date | Decision | Evidence / remaining condition |
|---|---|---|
| 2026-10-23 | Approved initial demonstrator direction: M85 host, R5 system supervisor, 256-MAC U85, new host-visible shared on-chip SRAM, all three U85 memory managers routed through NIC400, and a 128-bit/32-bit-address NIC400 manager interface | User decision in this implementation session. Must still verify NIC400 width support, configured U85 interface details, address-range guard behavior, memory capacity, and M85 driver compatibility before claiming the integration works. |

The U85 remains a replaceable NPU implementation. Do not start RTL integration
using the unconfigured source template; first make the vendor configuration
generator available and run the configured-U85 execution test.
