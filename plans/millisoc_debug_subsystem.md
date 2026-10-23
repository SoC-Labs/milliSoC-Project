# milliSoC Debug Subsystem — Implementation Plan

| | |
|---|---|
| **Status** | DAP transport, AP0/AP2/AP3 identification, AP1 boot-ROM/TCM/SYS_CTRL accesses, and R5/M85 CPU-to-APBIC accesses are implemented and firmware-tested. AP1 access to the PL192 VIC (`RT_GIC`) remains unresolved; Stage 2 core control is also incomplete. See §5 and §7. |
| **Scope** | `millisoc_tech` RTL, build flow, `verif/` |
| **Primary IP** | Arm CoreSight SoC-400 (`TM100-BU-50000-r3p2-50rel2`) |
| **Last updated** | 2026-10-23 |

---

## 1. Purpose and scope

### 1.1 Goals

1. **Integrate a Debug Access Port (DAP) properly.** A single, standards-compliant
   ADIv5 DAP (Arm CoreSight SWJ-DP) that is reachable over JTAG or SWD from an
   external debugger, integrated into milliSoC as a first-class subsystem with
   connected clock/reset, pads, filelist entry and build target. The current
   implementation shares the system clock/reset rather than using an independent
   debug domain.
2. **Reach both processors' debug ports.** The Cortex-R5 External Debug Interface
   and the Cortex-M85 external debug port (its EPPB) must both be reachable as
   separate Access Ports behind the DAP.
3. **General system-bus access.** An AXI Access Port behind the DAP must be able to
   issue AXI transactions onto the main system interconnect, so a debugger can read
   and write system memory and peripheral registers without stopping the CPUs.
   milliSoC has a NIC400 `DEBUG` port reserved for this; AP1 is connected to it
   and reads/writes to ROM, TCM, and SYS_CTRL are verified. Access to the PL192
   VIC (`RT_GIC`) is not currently exposed through the generated DEBUG decoder.
4. **Trace, later.** Processor trace interfaces (R5 `TRACECLKIN`/`TRACEDATA`, M85
   CTI) are connected in later stages, once the debug path itself is proven.

### 1.2 Non-goals for this plan

* No authentication (ARMv8-M / `spiden` trust-on-boot) implementation. The SoC-400
  AXI-AP has `dbgen`/`spiden` inputs tied to constants in the current RTL; a
  production policy is deferred to Stage 4.
* No silicon-level security hardening. Current constant ties are not a
  production debug-access policy; define and document gating before tapeout.
* No replacement of the existing PL192 VIC-based interrupt scheme.
* No new firmware-visible memory map other than the debug region described in §3.3.

### 1.3 Terminology

| Term | Meaning |
|------|---------|
| DP | Debug Port — the SWJ-DP, the SWD/JTAG-facing end of the DAP |
| AP | Access Port — a slave of the DAP that offers a debug/register access mechanism |
| DAPBUS | The internal interconnect of the SoC-400 connecting the DP to the APs |
| ADIv5 | Arm Debug Interface v5, the DAP programming model |
| EDI | External Debug Interface (the R5's APB-style debug port) |
| CTI | Cross Trigger Interface |
| NIC400 DEBUG | The NIC400 slave port reserved for debug traffic |

---

## 2. Current state (verified 2026-10-23)

The implementation has progressed beyond the original skeleton/proposal. The
following status is based on the current RTL, build integration, BFM source, and
the VCS `hello` run in `simulate/sim/hello/logs/run_hello.log`.

### 2.1 Implemented and simulation-verified

* SoC-400 static RTL and generic cells are brought in by the build scripts;
  configurable DAPBUS/APBIC/AXI-AP components have Socrates configurations,
  generated RTL is included in the filelists, and `build_soc400` is available.
* `millisoc_debug_subsystem.v` is instantiated in `millisoc_system.sv` with four
  APs: AP0 APB fabric, AP1 AXI-AP to NIC400 `DEBUG`, AP2 APB-AP to R5 EDI, and
  AP3 AHB-AP to M85 EPPB.
* The DAP clock is `FCLK`; `ACLK` is also assigned `FCLK`, and the DAP reset is
  connected directly to `nPORESET`. There is no separate debug clock domain or
  CDC bridge in this configuration.
* JTAG and SWD pads are connected through the generic PHY. The testbench
  provides SWDIO pull-up and SWCLK pull-down models. JTAG TAP IDCODE, SWD
  DPIDR, DP power-up status, AP0 identification, R5 debug-component ID
  registers, and the M85 ROM-table entry/CIDs all pass.
* The R5 EDI path and M85 EPPB path are wired and the tested AP2/AP3 reads
  complete. `PCLKENDBG` is asserted.
* The latest `make compile SIMULATOR=vcs` completed, and
  `make run TESTNAME=hello SIMULATOR=vcs` exited successfully. The run reports
  `ALL TESTS PASSED` from the BFM and preserves the existing R5/M85 boot and
  UART output.

### 2.2 Incomplete or not yet verified

* AP1 reads the first boot-ROM word and SYS_CTRL `cpu_mx_wait` at
  `0x44030004`, and performs write/readback checks at safe, unused locations in
  M85 ITCM and R5 ATCM through NIC400 `DEBUG`. The generated
  decode now includes `0x80000000`–`0x8FFFFFFF` → `CPU_Rx_S` and
  `0x44030000`–`0x44030FFF` → `SYS_CTRL`. APB peripheral coverage, transfer-size
  behavior, and AXI error handling remain unverified. An AP1 route to
  `RT_GIC` at `0x44020000`–`0x4402FFFF` remains unresolved: adding it to the
  DEBUG address map initially failed NIC400 validation. Declaring a parent
  bus/bridge allowed the build to complete, but the regenerated DEBUG decoder
  and testbench address map still omitted the range. The nonfunctional mapping
  attempt was removed; AP1 access to the VIC has not been tested.
* `make -C millisoc_tech build_nic400` was rerun after the map edits. It reports
  `Build IP Operation: Done` with only existing validator-version warnings.
  The generated DEBUG decoder contains the new ATCM and SYS_CTRL ranges. The
  VCS `hello` regression passes with AP1 readback checks and both CPU banners.
* The NIC400 `DEBUG_S` APB4 route is connected to the APBIC. External DAP AP0,
  the NIC400 path, and the M85 EPPB APB master share its single APB slave
  through an arbiter. The R5 startup MPU now maps
  `0xE00F0000`–`0xE00F3FFF` as 16 KiB of device memory; the `debug_access` VCS
  run returned the expected APBIC CIDs (`0x0D`, `0x10`, `0x05`, `0xB1`) and
  printed `R5 DEBUG APBIC PASS`. The M85 EPPB APB master is wired directly to
  the APBIC input (not through NIC400). The M85 test returned the same four
  CIDs and printed `M85 DEBUG APBIC PASS`. Its APB address is reconstructed as
  `{PADDR31, 11'b0, PADDR[19:2], 2'b00}` per the M85 interface.
* The root VCS and Questa compile targets now invoke `build_soc400` before
  compiling, so the ignored SoC-400 sources are regenerated as part of the
  normal compile flow. This was exercised in the latest compile.
* Core control is not demonstrated. AP2 reads R5 CoreSight identification
  registers, not architectural registers or halt/single-step state. The R5
  `DBGROMADDR`/`DBGROMADDRV`, `DBGSELFADDR0`/`DBGSELFADDRV0`, and `DBGEN0`
  remain tied off/disabled in `millisoc_system.sv`.
* AP3 has demonstrated access to the M85 EPPB ROM table and component IDs, but
  not M85 halt, resume, single-step, or core-register access.
* The SoC-level APBIC ROM table has not been populated and verified as a
  coherent enumeration of APs/components.
* The BFM is a single SystemVerilog module; the planned `dap_swd_bfm_pkg.sv`
  and separate scoreboard were not added. SWD read parity is not checked,
  WAIT/FAULT retry behavior is not exercised, byte/halfword transfers are not
  covered, and the BFM only checks `STICKYERR`. The latest final DP status is
  `0xB0000040`, with `STICKYORUN` set; this is not currently treated as a test
  failure.
* No hardware debugger/OpenOCD run or physical pad/package validation has been
  performed. Trace, authentication/security policy, production debug gating,
  and post-silicon debugger documentation remain future work.

### 2.3 Verified SoC-400 facts that constrain the design

These are the non-obvious properties that the plan depends on. They were read from
the Arm sources under `/research/AAA/ip_library/SoC-400/coresight_soc/shared/logical/`.

**Component availability — static vs configurable:**

| Component | Kind | Evidence |
|-----------|------|----------|
| `cxdapswjdp` | **static RTL** | `cxdapswjdp/verilog/cxdapswjdp.v` exists; no `.xsl` |
| `cxdapapbap` | **static RTL** | `cxdapapbap/verilog/cxdapapbap.v` exists; no `.xsl` |
| `cxdapaxiap` | **configurable** | `cxdapaxiap/verilog/*.v.xsl` only — **must be rendered** |
| `cxdapbusic` | configurable | already rendered in repo |
| `cxapbic` | configurable | already rendered in repo |

Socrates catalog availability (`/apps/ARM-Socrates/catalog/ip/SystemIP/DebugAndTrace/SoC400/`):
`cxdapaxiap` r1p1_0, `cxdapswjdp` r2p0_0, `cxdapapbap` r1p0_0, `cxdapbusic` r1p0_1,
`cxapbic` r0p2_0.

**Generic cells required by the SoC-400** (Integration Manual §6.1) must be copied
from `shared/logical/models/cells/generic/`: `cx_sync.v`, `cx_en_sync.v`,
`cx_en_sync_high.v`, `cx_cdc_corrupt_gry.v`, `cx_en_cdc_corrupt_gry.v`,
`cx_comb_mux2.v`, `cxdapswjdp_dp_sync.v`, `cxdapswjdp_clk_inverter.v`.

**DAPBUS address decode** — the current generated
`cxdapbusic_decoder_1.v` has four master selects: `ap_sel` 0/1/2/3 routes to
AP0/AP1/AP2/AP3, and values above 3 select the default response (ready, no
error, no AP responds). AP2/AP3 routing is also exercised by the current BFM.

* The slave address from the SWJ-DP is `dapcaddrs[15:2]` (14 bits).
* **AP selection uses `dapcaddrs[15:8]`**, which is the 8-bit `ap_sel` field
  loaded from DP `SELECT[31:24]`. Values `0..3` select the corresponding
  master; `ap_sel > 3` selects the default response (ready, no error, **no AP
  responds**).
* The AP-local address presented to each AP is `dapcaddrs[7:2]`
  (`cxdapbusic_1.v:131,138`) — 6 bits, i.e. 64 AP registers.

**Consequence:** the number of usable APs is fixed at render time by
`NUM_MASTER_INTF` in `cxdapbusic_1.xml` (now **4**). The generated DAPBUS has
been re-rendered; the source configuration and build flow preserve this setting.

**SWJ-DP identity values** (from `cxdapswjdp_sw_dp_constants.v:24-25` and
`cxdapswjdp_jtag_dp_constants.v:73-74`):

| Mode | IDCODE |
|------|--------|
| SW-DP | `0x6BA02477` (`{SWDP_REV=4'h6, SWDP_ID=28'hBA02477}`) |
| JTAG-DP, 4-bit IR | `0x6BA00477` |
| JTAG-DP, 8-bit IR | `0x0BA03477` |

The existing skeleton uses `IRLEN8(0)` → 4-bit IR → JTAG IDCODE `0x6BA00477`.

**`cxdapapbap` behaviour** — `cxdapapbap/verilog/cxdapapbap.v`:
ports at lines 41-72. The APB address comes from the AP's **TAR register**, not from
the DAP address: `paddr_ap` is 30 bits (line 78) and is mapped to `paddr[31:2]`
(line 149). The DAP-local address `dapcaddr[7:2]` selects the *AP register*
(line 50). There is **no `PSTRB` output** — byte strobes must be derived by the
integrator.

**`cxdapaxiap` behaviour** — `cxdapaxiap/verilog/cxdapaxiap_xmlcfg.v.xsl:73-148`:
* DAP-side ports are `dapcaddr[7:2]`, `dapsel`, `dapenable`, `dapwrite`, `dapwdata[31:0]`,
  `dapabort`; responses `dapready`, `dapslverr`, `daprdata[31:0]`.
* Authentication inputs `dbgen`, `spiden`.
* AXI4 master side has **no ID signals at all** (verified: zero occurrences of
  `awid`/`arid`/`bid`/`rid` in the XSL). The AXI port is single-outstanding.
* AXI4-only extras present and requiring tie-off against the NIC400: `awdomain[1:0]`,
  `awsnoop[2:0]`, `awbar[1:0]`, `ardomain[1:0]`, `arsnoop[3:0]`, `arbar[1:0]`.
* `awlen[7:0]`, `awsize[2:0]`, `awburst[1:0]`, `awlock`, `awcache[3:0]`, `awprot[2:0]`
  and the AR equivalents exist — matching the NIC400 DEBUG port exactly.

**`cxapbic_1` configuration** (`socrates/soc400/cxapbic_1/cxapbic_1.xml`):
`NUM_MASTER_INTF=2`, `NUM_SLAVE_INTF=1`, `IS_TOP_LEVEL_APBIC=true`,
`SLAVE_INTF_ADDR_WIDTH=14`, `MASTER_INTF0_BASE_ADDR=0x00001`,
`MASTER_INTF1_BASE_ADDR=0x00002`, `MASTER_INTFn_SIZE=0`.
Masters expose `paddrm0/1[11:2]` (10-bit, 4 KB window each); the slave exposes
`paddrs0[13:2]`. The APBIC also carries the top-level ROM table and `targetid[31:0]`.

**CPU debug interfaces (verified against the Arm RTL):**

*Cortex-R5* (bare `CORTEXR5` core — note milliSoC instantiates the raw core, not
`CORTEXR5INTEGRATION`, see `millisoc_rt_cpu_subsystem.v`):
`PADDRDBG0[11:2]` (10-bit — a 4 KB window; this is correct for the R5 and **not** a
bug), `PADDRDBG310`, `DBGROMADDR[31:12]`, `DBGROMADDRV`, `DBGSELFADDR0[31:12]`,
`DBGSELFADDRV0`; in: `PSELDBG0`, `PENABLEDBG0`, `PWRITEDBG0`, `PWDATADBG0[31:0]`,
`DBGEN0`, `NIDEN0`, `EDBGRQ0`, `DBGRESTART0`, `PCLKENDBG`, `DBGNOCLKSTOP`;
out: `PRDATADBG0[31:0]`, `PREADYDBG0`, `PSLVERRDBG0`, `DBGACK0`, `DBGTRIGGER0`,
`DBGRESTARTED0`, `DBGRSTREQ0`, `COMMRX0`, `COMMTX0`.

*Cortex-M85* (`OLYMPUS_MCU.sv`): MCU debug APB master outputs `PSEL`, `PENABLE`,
`PWRITE`, `PADDR[19:2]`, `PADDR31`, `PSTRB[3:0]`, `PWDATA[31:0]`; inputs `PREADY`,
`PRDATA[31:0]`, `PSLVERR`. The M85's CTI pins (`CTICHIN`, `CTICHOUT`, `CTIIRQ`) are
left open. The M85 also contains an **integrated `olympus_dap`** (SWJ-DP + AHB
master); its DP registers and MCU ROM table are reachable through the MCU debug
APB at `MCUROMADDR` = `0xE00FE000`.

**NIC400 DEBUG port** — `nic400_millisoc_main.v:558-592`:
AXI4, `WDATA/RDATA[63:0]`, `AWADDR/ARADDR[31:0]`, and **`AWID/ARID/BID/RID[1:0]`
(2-bit)**. The generated port is an **AXI slave** port on the NIC400
(`AWVALID`/`AWADDR`/`WDATA` are *inputs* to the NIC400; `AWREADY`/`BVALID`/`RDATA`
are outputs), i.e. it is the ingress for an *external* AXI master. The DAP's
AXI-AP is therefore the master and the NIC400 `DEBUG` port is the slave; the
NIC400 then decodes the address and forwards to its internal slaves.

**NIC400 `DEBUG` port decode map (`adp_map`)** —
`socrates/nic400_millisoc_main/nic400_millisoc_main.xml`:

| Range | Target |
|-------|--------|
| `0x44000000`–`0x44001FFF` | `DMA_CFG` |
| `0x44010000`–`0x4401FFFF` | `QSPI_CFG` |
| `0x60000000`–`0x603FFFFF` | `QSPI` |
| `0xFFFF0000`–`0xFFFFFFFF` | `ROM` (boot ROM) |
| `0x00000000`–`0x3FFFFFFF` | `CPU_S` (the CPU subsystem port) |
| `0x80000000`–`0x8FFFFFFF` | `CPU_Rx_S` (R5 ATCM route) |
| `0x44030000`–`0x44030FFF` | `SYS_CTRL` |

There is no default range. `RT_GIC` (`0x44020000`–`0x4402FFFF`) is not
currently mapped on AP1: adding it as a DEBUG target failed NIC400 validation
because no valid DEBUG path to that target exists in the current topology.
The UARTs and PL192 VIC are not covered by the ranges above and remain
inaccessible through AP1 until their correct routes and address windows are
identified and validated.

---

## 3. Target architecture

### 3.1 Topology

```
                       SWD/JTAG pads
                             │
                    ┌────────▼─────────┐
                    │   cxdapswjdp     │   SWJ-DP (SW-DP + JTAG-DP)
                    │   (IRLEN8 = 0)   │   IDCODE 0x6BA00477 / 0x6BA02477
                    └────────┬─────────┘
                             │ DAPBUS slave, dapcaddr[15:2]
                    ┌────────▼─────────┐
                    │  cxdapbusic_1    │   NUM_MASTER_INTF = 4
                    │  (DAPBUS fabric) │   AP select = dapcaddrs[15:8]
                    └──┬────┬────┬─────┘
        AP0 (sel 0)   │    │    │  AP3 (sel 3)
                       │    │    └──────────────┐
        AP1 (sel 1)   │    │                   │
                       │    │         ┌─────────▼─────────┐
                       │    │         │ cxdapahbap (AP3)  │  AHB master
                       │    │         │  → M85 EPPB       │
                       │    │         │  (olympus_dbg)    │
                       │    │         └───────────────────┘
                       │    │
                       │    └────────────────┐
                       │                     │  ┌──────────────────┐
                       │                     │  │ cxdapapbap (AP2) │
                       │                     │  │ → R5 External     │
                       │                     │  │   Debug Interface │
                       │                     │  └──────────────────┘
                       │
                       │  ┌──────────────────┐
                       │  │ cxdapapbap (AP0) │  → cxapbic_1 (top-level APBIC)
                       │  │ → debug APB bus  │      → APB peripherals (CTI, ETF, …)
                       │  └──────────────────┘
                       │
                       │  ┌──────────────────┐
                       └─▶│ cxdapaxiap (AP1) │  AXI4 master, 64-bit, no ID
                          └────────┬─────────┘
                                   │ AXI4 (AW/W/B/AR/R)
                          ┌────────▼─────────┐
                          │  NIC400           │  slave port "DEBUG"
                          │  (existing)       │  id_width = 2, adp_map
                          └────────┬─────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │  milliSoC system bus         │
                    │  (CPU_S, QSPI, DMA, ROM, …)  │
                    └──────────────────────────────┘
```

### 3.2 Access Port map

| AP | `ap_sel` | Component | Target | Requirement served |
|----|----------|-----------|--------|--------------------|
| AP0 | 0 | `cxdapapbap` | `cxapbic_1` → debug APB fabric | CoreSight APB peripherals (CTI/ETF/TPIU in Stage 3) |
| AP1 | 1 | `cxdapaxiap` | NIC400 `DEBUG` AXI4 port (64-bit data) | **General system-bus access** |
| AP2 | 2 | `cxdapapbap` | R5 External Debug Interface (APB slave) | **R5 core debug** |
| AP3 | 3 | `cxdapahbap` | M85 EPPB (AHB slave of `olympus_dbg`) | **M85 core debug** |

AP ordering is a choice, not a constraint. Putting the AXI-AP at AP1 means a
debugger that only knows the "system bus" concept can find it at `ap_sel = 1`.

### 3.3 Debug region address map

The CoreSight APBIC is reachable by external DAP AP0, the NIC400 `DEBUG_S` APB4
port, and the M85 EPPB's dedicated APB master interface. The R5 and other
system-bus masters use the system-visible region
`0xE00F_0000`–`0xE00F_3FFF`, present in the R5 `main_map` and M85 `mclass_map`.
The APBIC ROM table is selected in the first 4 KB of that region; its CoreSight
component identification registers are at `0xE00F_0FF0`–`0xE00F_0FFC`.

All three requesters feed the APBIC's single APB slave through a round-robin
arbiter. The M85 APB address is reconstructed from its compressed EPPB address
as `{PADDR31, 11'b0, PADDR[19:2], 2'b00}`. The APBIC `ROM_BASE_APBIC` value advertises
`0xE00F_0000`. The APBIC's two downstream APB master ports remain unimplemented
and return zero/ready, so this mapping currently exposes the ROM table rather
than additional CoreSight peripherals. The DP registers remain accessible over
the SWD/JTAG transport, not as part of this CPU-visible APB region.
The R5 MPU configures the 16 KiB region as non-shared device memory with full
access and execution disabled. The M85 EPPB APB route was exercised by its
firmware test, which read all four APBIC component-ID registers successfully.

### 3.4 Clocks, resets and power

| Domain | Clock | Reset | Notes |
|--------|-------|-------|-------|
| DAP | `FCLK` | `nPORESET` | Current RTL uses the system clock and reset directly; independent debug operation while system clock/reset are stopped is not provided. |
| Debug APB / AXI-AP / AHB-AP | `FCLK` | `nPORESET` | Same clock/reset as the DAP. |
| R5 debug | R5 `ACLK` (`FCLK` in this system) | `nPORESET` / `PRESETDBG0n` | `ACLK` is assigned from `FCLK`; no asynchronous bridge is currently used. |
| M85 debug | M85 `ACLK` (`FCLK` in this system) | M85 reset | The EPPB interface is connected to the AHB-AP. |

Power: the current simulation ties `cdbgpwrupack`/`csyspwrupack` and
`cdbgrstack` to constants so the DP can run. Revisit these ties when the
platform has a real power/reset controller.

---

## 4. Architectural decisions

Each decision lists the alternatives considered and the reason for the choice.
Decisions marked **[NEEDS SIGN-OFF]** must be agreed before the corresponding stage
starts.

### D1 — Use the SoC-400 SWJ-DP as the single system DAP

**Choice.** One `cxdapswjdp` serves the whole system.

**Alternatives.** (a) Use the M85's built-in `olympus_dap` for the M85 and add a
separate SoC-400 for the rest — rejected, it duplicates the SWD pad interface and
gives two incompatible debugger targets. (b) Use the CSS600 `daplite2_m` — same
duplication problem, plus it is not currently instantiated and is not in the M85
flist.

**Rationale.** The SoC-400 SWJ-DP is already wired up in the skeleton with correct
port names, supports both JTAG and SWD, and is the natural host for multiple APs.

### D2 — AP1 is an AXI-AP onto the NIC400 `DEBUG` port

**Choice.** `cxdapaxiap` (AXI4, 64-bit data, 32-bit address) → NIC400 `DEBUG`
slave port. The AXI-AP is the AXI **master**; the NIC400 `DEBUG` port is the
AXI **slave** that accepts the transaction and decodes it via `adp_map`.

**Alternatives.** (a) An AHB-AP onto a dedicated AHB debug port — rejected: the
system interconnect is AXI, so an AHB master would need a bridge anyway.
(b) Route the debug APB fabric to CPU_S via the CPU AXI port — rejected: that
would require the debug master to be a CPU AXI master, contending with the CPUs
and complicating arbitration.

**Consequences.** The AXI-AP is single-outstanding with no ID, so the NIC400
`DEBUG` port must be driven with `AWID = ARID = 0` and `BID`/`RID` ignored. The
NIC400 `DEBUG` port's `adp_map` must be extended to cover the regions the
debugger needs (see §2.3 and risk **R3**) — this requires a NIC400 config change
and a NIC400 re-render.

### D3 — AP2 targets the R5 External Debug Interface via an APB-AP plus address-slicing glue

**Choice.** `cxdapapbap` → a small address decoder → R5 EDI (`PSELDBG0`,
`PENABLEDBG0`, `PWRITEDBG0`, `PWDATADBG0`, `PADDRDBG0[11:2]`, `PADDRDBG310`, …).

**Why glue is needed.** The R5 EDI takes a 10-bit `PADDRDBG0[11:2]` — a 4 KB
window — plus a separate `PADDRDBG310` bit. The `cxdapapbap` drives a 30-bit
`paddr[31:2]` from the AP's TAR register. So the integrator must select which
4 KB slice of TAR is presented to the R5.

**Design.** The R5's own debug map (defined by `DBGROMADDR`/`DBGROMADDRV` and
`DBGSELFADDR0`/`DBGSELFADDRV0`, which milliSoC currently ties off) must be
defined first; the R5's `DBGSELFADDR` should point at the R5's own debug
registers so that a debugger can find them, and `DBGROMADDR` should point at a
ROM table that the R5 uses to locate its debug components.

**Open sub-decision.** How the 4 KB R5 window is chosen from the 30-bit TAR:
* *Option A (simple):* dedicate one AP register (or one TAR bit field) to select
  the slice, and hard-wire the rest. Simple, but the debugger must know the
  convention.
* *Option B (mirrored):* present TAR bits `[13:2]` to `PADDRDBG0` and use
  `PADDRDBG310` = TAR bit `[14]`, i.e. a 32 KB window mapped onto the R5's 4 KB
  + `PADDRDBG310` structure. Matches the R5's own addressing more closely.

Recommend **Option B** if the R5 TRM confirms `PADDRDBG310` is the "window 1"
select; otherwise Option A. This must be checked against
`CoreSight_SoC400`/`Cortex-R5` TRM before Stage 2 begins.

### D4 — AP3 is an AHB-AP onto the M85 EPPB (rather than the M85's native `olympus_dap`) — **decided**

**Decision.** AP3 is a CoreSight `cxdapahbap` whose AHB master drives the M85's
External Private Peripheral Bus (EPPB). The M85's own `olympus_dap` is left
unconnected and the SoC keeps exactly one SWD/JTAG pad interface.

**Why an AHB-AP and not an APB-AP.** The interface that `olympus` actually
exposes at the SoC boundary is the EPPB — an AHB subordinate
(`DBG_HADDR`, `DBG_HTRANS`, `DBG_HWRITE`, `DBG_HSIZE`, `DBG_HPROT`, `DBG_HWDATA`
→ `DBG_HRDATA`, `DBG_HREADY`, `DBG_HRESP`). The M85's debug APB
(`dbg_ext_padbg_psel` and friends) is decoded *inside* `olympus_dbg` from those
AHB transfers and is not brought out as a pin-level APB port. Driving the EPPB
with `cxdapahbap` is therefore the natural CoreSight integration and removes the
`PSTRB` problem that an APB-AP would have had (D9 no longer applies to AP3).

**EPPB address decode (verified in `olympus_dbg.sv`).** `dap_pdd_eppb_sel`
requires `dbg_haddr[31:20] == 12'hE00` **and** `|dbg_haddr[19:18]`, and the M85
ROM table is selected when the internal APB address matches
`paddr[19:12] == 8'hFF`. Consequently the M85 ROM table base seen through AP3 is
**`0xE00F_F000`** (not `0x000F_F000`), with the standard CoreSight layout:

| Offset | Contents |
|--------|----------|
| `0xE00F_F000` | ROM table entry 0 (`0xFFF0F003`: SCS present, base `0xE000_E000`) |
| `0xE00F_FF0..FFC` | Component ID: `0x0D`, `0x10`, `0x05`, `0xB1` |

Note that `CID1 = 0x10` for the M85 ROM table against `0x90` for the R5's,
which makes an AP2/AP3 mix-up immediately visible in a test log.

**Pros.** Single SWD/JTAG pad interface, single debugger target, single ROM
table; the M85's internal DP registers and ROM table remain fully reachable
through the EPPB; consistent with the R5, which has no internal DAP at all.

**Cons.** The debugger sees the M85 as an access port behind the SoC-400 rather
than as a DAP of its own. A debugger that expects to find the M85's native DAP
must be pointed at AP3 instead.

**Rejected alternative.** Use the M85's native `daplite2_m` / `olympus_dap` and
give the SoC-400 a second set of pads. This needs two physical pad sets (wasting
pins and complicating the board) or a mux in front of both (which means the
debugger must be told which DAP to talk to); the SoC-400 would then not be able
to reach the M85 at all, breaking the "one debugger, one target" model.

**M85 debug power.** `olympus_dbg` gates its EPPB selects with
`dpc_dbg_drunning`, which is derived from the Q-channel handshakes
`dpc_pwr_lpi.qacceptn` and `dpc_clk_lpi.qacceptn`. Both Q-channel requests are
tied high in `millisoc_cpu_ss.v`, so `drunning` is asserted and the EPPB answers
immediately; no separate debug power-up handshake is required for AP3.

### D5 — Re-render `cxdapbusic` with `NUM_MASTER_INTF = 4`

**Choice.** Update `millisoc_tech/socrates/soc400/cxdapbusic_1/cxdapbusic_1.xml`
to `NUM_MASTER_INTF=4` and re-render.

**Alternatives.** (a) Keep 2 and add a hand-written decode fan-out in
`millisoc_debug_subsystem.v`; rejected — duplicates Arm IP and breaks the
"use the vendor interconnect" principle. (b) Use `NUM_MASTER_INTF=3` and drop the
APB-fabric AP; rejected — the APB fabric AP is needed for the trace components
in Stage 3, and `cxapbic_1` already provides the APB crossbar.

**Cost.** `cxdapbusic` must be re-rendered, which changes its generated RTL in
`millisoc_tech/logical/soc400/` (gitignored, so no source churn in the repo).

### D6 — NIC400 `DEBUG` AXI ID width — **IMPLEMENTED**

`DEBUG_AXI` uses `ID_W(2)` to match the NIC400 port. The AXI-AP emits no IDs, so
`AWID`/`ARID` are tied to `2'b00`; `BID`/`RID` are connected at the NIC400
interface but are not used by the AXI-AP. Add transaction-level validation with
the AP1 functional tests.

### D7 — Clock and reset strategy for the debug domain — **RESOLVED FOR CURRENT RTL**

**Implemented choice.** The DAP/APs use `FCLK` and `nPORESET` directly.
`millisoc_system.sv` assigns `ACLK = FCLK`, so the R5 EDI and M85 EPPB are in
the same synchronous clock domain; no CDC bridge is currently required.

**Limitation.** This does not provide an always-on debug clock or an independent
reset path. If later power/reset architecture requires debug access while
`FCLK` is stopped or `nPORESET` is asserted, revisit this decision and add the
required isolation/CDC/reset strategy.

### D8 — Debug pads

**Status.** Debug pad signals and a simulation-friendly tristate model are
implemented in `millisoc_chip_pads` / `millisoc_chip_phy`; JTAG and SWD are both
exercised in simulation. This does not yet select physical pad cells or board
pin assignments.

**Note.** The existing DAP-LITE signal names are reused:
`ntrst`, `swclktck`, `swditms`, `tdi`, `tdo`, `ntdoen`, `swdo`, `swdoen`. In SWD
mode only `swclktck`, `swditms` (bidirectional SWDIO) and `ntrst` are used;
`swdo`/`swdoen` model the SWDIO output enable.

**Simulation result.** SWDIO is modeled bidirectionally with separate
`swditms` input and `swdo`/`swdoen` output/enable, and the BFM passes in
simulation. Electrical behavior with target pad cells, pull devices, and board
loading remains to be validated on the selected hardware.

### D9 — `PSTRB` tie-off (superseded by D4)

This decision applied to the rejected "AP3 as an APB-AP onto the M85 MCU debug
APB" option: the SoC-400 APB-AP (`cxdapapbap`) has no `PSTRB` output, so the M85
APB strobes would have had to be tied to `4'b1111`. Because AP3 is realised as
`cxdapahbap` on the M85 EPPB (D4), the M85's AHB interface carries byte strobes
natively and this tie-off is not needed. It does **not** apply to AP0 or AP2,
whose APB targets have no byte strobes either.

---

## 5. Staged implementation

Each stage ends in a demonstrable, testable state and leaves the system working.

### Stage 0 — Groundwork — **COMPLETE (simulation)**

This stage establishes the integrated debug transport, pad path, and AP/component
identification checks. It does not establish system-bus memory access or CPU
halt/register-control functionality.

#### 0.1 Vendor the SoC-400 RTL into the build

New directory `millisoc_tech/logical/soc400/` (already gitignored) will hold:

```
logical/soc400/
├── static/                       <- copied from $ARM_IP_LIBRARY_PATH
│   ├── cxdapswjdp/verilog/*.v
│   ├── cxdapapbap/verilog/*.v
│   └── models/cells/generic/*.v
└── logical/                      <- Socrates-generated (already gitignored)
    ├── cxapbic_1/verilog/
    ├── cxdapbusic_1/verilog/
    └── cxdapaxiap/verilog/       <- new
```

Copy script: `millisoc_tech/tools/copy_soc400_static.sh` (new), invoked from a new
`build_soc400` target in `millisoc_tech/makefile`:

```make
build_soc400: build_soc400_render build_soc400_static

build_soc400_render:
	socrates_cli --project millisoc_tech -data ../ --flow build.configured.component configuredComponentName=cxdapbusic_1
	socrates_cli --project millisoc_tech -data ../ --flow build.configured.component configuredComponentName=cxdapaxiap_1

build_soc400_static:
	$(SOCLABS_MILLISOC_TECH_DIR)/tools/copy_soc400_static.sh
```

`SOCLABS_SOC400_DIR` must be added to `env/dependency_env.sh` pointing at
`$ARM_IP_LIBRARY_PATH/SoC-400/coresight_soc/shared/logical`; the copy script
reads it and writes to
`$(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/static/`.

> Note: the `socrates_cli` invocation above is a *proposal*. The existing
> `build_nic400` target uses exactly this form, so it should work, but the
> `cxdapaxiap` component must first be **added to the Socrates project** (see 0.2)
> and the generated component name may differ from `cxdapaxiap_1`.

#### 0.2 Socrates configuration

* Add `cxdapaxiap` (catalog r1p1_0) to the Socrates project as a configured
  component, e.g. `millisoc_tech/socrates/soc400/cxdapaxiap_1/cxdapaxiap_1.xml`:
  * `AXI_DATA_WIDTH = 64`
  * `AXI_ADDR_WIDTH = 32`
  * `AXI4 = 1`
  * `DAPCADDR_WIDTH = 6`
  * `Exclusive_Accesses = 0` (so `awdomain`/`ardomain`/`awsnoop`/`arsnoop` are
    tied off internally rather than needing real values — **verify** against the
    XSL whether these are outputs regardless; if they remain outputs they are
    simply tied off in the integration wrapper).
  * `AuthenticationInterface = 0` (`dbgen`/`spiden` tied to constants).
* Modify `millisoc_tech/socrates/soc400/cxdapbusic_1/cxdapbusic_1.xml`:
  `NUM_MASTER_INTF` 2 → **4**.
* Re-render `cxapbic_1` only if the debug APB fabric needs more than 2 master
  interfaces (Stage 3 will likely need 2 CTIs + 1 ETF ⇒ 3). Leave at 2 for
  Stage 1-2 and revisit in Stage 3.

#### 0.3 Filelist

New `millisoc_tech/flist/IP/soc400.flist`:

```
// CoreSight SoC-400 static RTL (copied by `make build_soc400`)
+incdir+$(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/static/cxdapswjdp/verilog
+incdir+$(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/static/cxdapapbap/verilog
+incdir+$(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/static/models/cells/generic
-y $(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/static/cxdapswjdp/verilog
-y $(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/static/cxdapapbap/verilog
-y $(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/static/models/cells/generic

// Rendered (configurable) SoC-400 components
+incdir+$(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/logical/cxdapbusic_1/verilog
-y $(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/logical/cxdapbusic_1/verilog
+incdir+$(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/logical/cxapbic_1/verilog
-y $(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/logical/cxapbic_1/verilog
+incdir+$(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/logical/cxdapaxiap_1/verilog
-y $(SOCLABS_MILLISOC_TECH_DIR)/logical/soc400/logical/cxdapaxiap_1/verilog
```

(Style follows `flist/IP/CortexR5.flist`: `$(VAR)` expansion, `+incdir+` and `-y`
search paths.) Note that `$(SOCLABS_MILLISOC_TECH_DIR)` points at the copied
static RTL, so the flist never references the Arm IP library directly — that
keeps the compile independent of `ARM_IP_LIBRARY_PATH` once the copy has run.

Hook into `millisoc_tech/flist/millisoc_top.flist`:

```
-f $(SOCLABS_MILLISOC_TECH_DIR)/flist/IP/soc400.flist
$(SOCLABS_MILLISOC_TECH_DIR)/logical/millisoc_subsystems/millisoc_debug_subsystem/millisoc_debug_subsystem.v
```

> **Verified filelist chain:** the VCS flow reads the root
> `flist/top_BEHAV.flist` (`makefile:13`, `TBENCH_VC`), which pulls in
> `millisoc_tech/flist/millisoc_BEHAV.flist`, which pulls in
> `millisoc_tech/flist/millisoc_top.flist`. So `millisoc_top.flist` is the single
> place where the debug subsystem and the SoC-400 files must be added.
> `millisoc_tech/flist/millisoc_BEHAV.flist` only adds the behavioural models
> (`millisoc_chip_phy.v`, `dtcm.v`, `itcm.v`) on top.

**Build-order note.** `millisoc_tech/.gitignore` ignores `logical/soc400`
entirely, so the vendored static RTL is *not* in the repository. Every developer
(and CI) must run the copy step before compiling. The `build_soc400` target must
therefore be a prerequisite of `compile`, and it must fail loudly (not silently
skip) if the copy has not happened — otherwise the compile error will be a
confusing "module not found" deep inside the filist.

#### 0.4 Debug subsystem RTL integration

Rewrite `millisoc_debug_subsystem.v` to:

* Instantiate `cxdapswjdp`, `cxdapbusic_1` (4 masters) and the four APs, with
  the AP0-APB-AP → `cxapbic_1` path preserved.
* Expose clean top-level ports:
  * SWD/JTAG pad interface (`swclktck`, `swditms`, `swdo`, `swdoen`, `tdi`, `tdo`,
    `ntdoen`, `ntrst`)
  * AXI4 master to the NIC400 `DEBUG` port
  * R5 EDI signals (APB slave)
  * M85 EPPB signals (AHB master)
  * power-up request/acknowledge and reset request/acknowledge pass-through
* Keep the module name and file path (so the committed skeleton is evolved, not
  replaced by an unrelated file).

#### 0.5 Pads, clock and reset in `millisoc_system.sv`

* Add `DAPCLK` and `nDAPRESET`:
  * `DAPCLK` ← `FCLK` (or `ACLK`, per D7).
  * `nDAPRESET` ← `nPORESET` through a 2-FF synchroniser, or directly if the DAP
    domain is already reset by `nPORESET`.
* Add the debug pads to `millisoc_chip_pads.v` / `millisoc_chip_phy.v` and connect
  them to the debug subsystem.
* Instantiate `millisoc_debug_subsystem` in `millisoc_system.sv`.
* Remove the `DEBUG_AXI` tie-offs (`millisoc_system.sv:1318-1322`) and connect
  the AXI port.

#### 0.6 SWD/JTAG bus-functional model

Build the BFM described in §6.1 **in Stage 0**, not Stage 1, so that the Stage 0
exit criterion below is self-checking:

* `verif/monitors/dap_swd_bfm.sv` — drives `swclktck` / `swditms` / `swdo` /
  `swdoen` / `ntrst`, and exposes tasks for:
  * `dp_read_idcode()` → 32'h
  * `dp_write_ctrl_stat(value)` / `dp_read_ctrl_stat()`
  * `dp_select(ap_sel)`
  * `ap_read(ap, addr)` / `ap_write(ap, addr, data)` — full ADIv5 AP transaction
    (`SELECT`, `TAR`/`TAR_HI`, `CSR`/`RDBUFF`/`DRW`), including byte-lane `TAR`
    handling.
* `verif/monitors/dap_swd_bfm_pkg.sv` — transaction helpers and a simple
  scoreboard/checker.
* Instantiate it in `verif/testbench/millisoc_tb.sv`.

The BFM is pure verification code with no Arm IP dependency, so it is the one
piece of the debug work that can be written and reviewed before any SoC-400
RTL is rendered.

#### Stage 0 exit criteria

* `make compile SIMULATOR=vcs` succeeds with the SoC-400 files in the flist.
* `make run TESTNAME=hello SIMULATOR=vcs` still passes (the `hello` test is the
  regression guard for the whole platform).
* The SWJ-DP powers up and presents a DP IDCODE to the SWD BFM: `0x6BA02477`
  in SWD mode (`0x6BA00477` in JTAG mode with `IRLEN8 = 0`).

#### Stage 0 results (verified in VCS)

The three stated simulation exit criteria are met in the current checkout. The latest
`make compile SIMULATOR=vcs` completed, and
`make run TESTNAME=hello SIMULATOR=vcs` exited successfully, printing the R5
bootloader banner and both `Hello SoCLabs MilliSoC` banners. The BFM log contains
**49 PASS checks / 0 FAIL**, finishing with `ALL TESTS PASSED` at ~101.2 µs.
The latest compile also ran the root `build_soc400` prerequisite, which copied
the static RTL, rendered all three configured components, applied the vendor
source fix, and then compiled. VCS printed a non-fatal `cfs_ident_exec`
segmentation fault from its Verdi/TAPI helper, but reported 0 compile/elaboration
errors and produced an executable simulation.

Checks performed by `verif/monitors/dap_swd_bfm.sv`:

| Mode | Check | Observed |
|------|-------|----------|
| JTAG | TAP IDCODE (IR = IDCODE) | `0x6BA00477` |
| JTAG | DP CTRL/STAT after `CDBGPWRUPREQ` | `0xB0000000` |
| JTAG | DP ADDR readback | `0x00000000` |
| JTAG | AP0 CSW / IDR | `0x80000042` / `0x54770002` |
| JTAG | AP1 NIC400 `DEBUG` boot-ROM read | `0xE59FF018` at `0xFFFF0000` |
| JTAG | AP2 (R5) IDR / CSW | `0x54770002` / `0x80000042`, `pdbg = 1` |
| JTAG | AP2 R5 `COMP0..3`, `DEVTYPE` | `0x0D`, `0x90`, `0x05`, `0xB1`, `0x15` |
| JTAG | AP3 (M85) IDR / CSW | `0x84770001` / `0x43000042` |
| JTAG | AP3 M85 ROM `SCS entry`, `CID0..3` | `0xFFF0F003`, `0x0D`, `0x10`, `0x05`, `0xB1` |
| SWD | DPIDR | `0x6BA02477`, ACK OK |
| SWD | DP CTRL write / STAT read | `CDBGPWRUPREQ` and `CDBGPWRUPACK` set |
| SWD | DP ADDR write/readback | `0x00000000` |
| SWD | AP0 IDR | `0x54770002` |
| SWD | AP2 R5 `COMP0`, `DEVTYPE` | `0x0D`, `0x15` |
| SWD | Final DP `CTRL/STAT` | `0xB0000040` (`STICKYERR` clear; `STICKYORUN` set and not checked) |

### 5.1 Integration findings from Stage 0

These were all found by running the BFM against the integrated RTL; they are
recorded here because each one cost real debugging time and each is easy to
reintroduce.

1. **`PCLKENDBG` must be high.** The Cortex-R5 external debug interface is
   clock-gated by `PCLKENDBG`. It was tied `1'b0`, so every APB access to the R5
   EDI hung. It is now `1'b1` in `millisoc_system.sv`.

2. **AP response wires must be connected.** In `millisoc_debug_subsystem.v` the
   AP2 return signals (`apb_prdata2`, `apb_pready2`, `apb_pslverr2`) were
   declared but never driven. An undriven `pready` makes the APB-AP
   `apb_tr_done` unknown, which propagates through `next_dap_slv_err` into
   `dapslverr`/`dapready`, permanently hangs the DAPBUS (`dapsel` stuck high)
   and makes every later AP access return stale data. Any AP added later must
   have both directions of its bus wired.

3. **`ntdoen` is active low.** The JTAG TDO pad is only driven when `ntdoen` is
   low: `assign dap_tdo_pad = ntdoen ? 1'bz : tdo;`.

4. **SWDIO needs a pull-up (and SWCLK a pull-down).** The SW-DP detects a line
   reset with `reset_count_reg`, fed from `dbg_di_masked = dbgdi | mask_dbg_di`.
   `mask_dbg_di` only covers the `SLETRNW*` turnaround states, so during the
   acknowledge phase the port can briefly be driven by neither the probe nor the
   target. With no pull-up the line is `z`, `z | 0` evaluates to `x`, the reset
   counter becomes `x`, `wirereset` becomes `x` and the SWJ-DP mode watcher
   leaves Serial Wire mode for good. The testbench therefore models the board
   pull-ups with `pullup (DAP_SWDIO)` / `pulldown (DAP_SWCLK)`. **This is a
   board-level requirement, not just a simulation artefact** — the pull-up on
   SWDIO is mandatory for the SWJ-DP.

5. **The SW-DP posts AP reads.** An AP read transfer issues the bus transaction
   and returns the bus read data of the *previous* transfer; the result is
   collected from DP `RDBUFF` (`A = 0b11`). Reading an AP register once returns
   stale data, and issuing the next request without draining the pending
   transfer leaves the DP reporting protocol errors (`ACK = 0b111`).

6. **The Arm SoC-400 delivery has a typo.** `cxdapaxiapfsm_1.v` uses `` `RDY ``
   as if it were a macro, which is a compile error. `millisoc_tech/tools/
   patch_soc400.sh` rewrites it to `RDY`; it is invoked from
   `build_soc400.sh` so the fix survives a re-render and is never hand-applied
   to the gitignored generated tree.

### 5.2 Stage 0 limitations

* The transport, AP identification, selected component-identification paths,
  and AP1 boot-ROM/TCM accesses are exercised. No core is halted and no
  architectural core register is read or written. AP1 SYS_CTRL and peripheral
  accesses are untested; `RT_GIC`, UART, and VIC routes remain unavailable or
  unresolved.
* The protocol is switched JTAG → SWD once. Switching back (SWD → JTAG select
  pattern `0x3CE7`) is not exercised, and neither is the dormant mode.
* SWD `WAIT`/`FAULT` acknowledgements are handled by retrying, but only the OK
  path is reached, so retry/error handling is unverified. Read payload parity
  is not checked.
* Byte transfers and `CSW.SIZE` variations are not exercised; every access is a
  32-bit word. The BFM checks `STICKYERR`, but does not check/clear
  `STICKYCMP`/`STICKYORUN`; the latest final `CTRL/STAT` is `0xB0000040`.
* The testbench now fails if the BFM has not completed successfully within
  200 us. This guards against a stuck BFM before the overall `hello` simulation
  reaches its later `$stop`.

### Stage 1 — DAP bring-up and general system-bus access — **IN PROGRESS**

*This stage delivers requirement (1) and requirement (3).*

#### 1.1 Bring up the SWJ-DP

**Status: implemented and verified in simulation.** SWD/JTAG pads, the simple
pad model, power-up acknowledgements, JTAG IDCODE, SWD DPIDR, `CTRL/STAT`,
`SELECT`, and basic AP accesses pass the current BFM. Physical pad timing and
board-level pull devices are not verified.

#### 1.2 Bring up AP1 (AXI-AP) → NIC400 `DEBUG`

**Status: partially verified.** The AXI-AP is connected to `DEBUG_AXI`, the ID
width is 2 bits, `AWID`/`ARID` are tied to zero, and unused AXI attributes are
tied off. JTAG reads of boot ROM and SYS_CTRL `cpu_mx_wait`, plus write/readback checks at
safe unused locations in M85 ITCM and R5 ATCM, pass. `RT_GIC` is not exposed
because the proposed DEBUG route failed NIC400 validation. Remaining work:

* Test AP1 access to additional SYS_CTRL registers and representative APB
  peripherals.
* Investigate a supported NIC400 route for RT_GIC before adding it to the
  debugger-visible map.
* Add transfer-size and AXI response/error-path tests.

#### 1.3 Verify the system-bus path end to end

**Status: basic AP1 path passes; full system-bus verification remains.** The
BFM checks the first boot-ROM word at `0xFFFF0000`, reads `cpu_mx_wait` at
`0x44030004`, and writes/reads unused locations at `0x0000FFFC` (M85 ITCM) and
`0x80003FFC` (R5 ATCM). Both CPUs later complete the existing boot and `hello`
output. The map was regenerated and its generated decode inspected. Other
peripheral access, transfer sizes, AXI response/error behavior, and the
excluded RT_GIC path still need testing.

### Stage 2 — Core debug: R5 and M85 — **PARTIALLY IMPLEMENTED**

*Delivers requirement (2).*

#### 2.1 R5 (AP2)

**Status: AP2 reaches the R5 EDI identification registers; core debug is not
verified.** The TAR-to-EDI address slicing is present and BFM reads of
`COMP0..3` and `DEVTYPE` pass. Remaining work:

* Define the R5's debug address map:
  * `DBGROMADDR` / `DBGROMADDRV` — base of the R5's debug ROM table.
  * `DBGSELFADDR0` / `DBGSELFADDRV0` — base of the R5's own debug registers.
  They are still tied off, and `DBGEN0` is still low.
* Establish a deliberate debug-enable/security policy before enabling `DBGEN0`.
* Implement and verify halt, resume, single-step, core-register access, and
  debug reset/acknowledgement behavior. `PCLKENDBG` is already asserted.

#### 2.2 M85 (AP3)

**Status: AP3 reaches the M85 EPPB ROM table and identification registers; core
debug is not verified.** The AHB path is connected and the BFM reads the ROM
table entry and CIDs. Remaining work is to test M85 core halt, resume,
single-step, and architectural register access.

* The EPPB decode inside `olympus_dbg` requires `haddr[31:20] == 12'hE00` and
  `|haddr[19:18]`; the M85 ROM table therefore appears at **`0xE00F_F000`**
  (`paddr[19:12] == 8'hFF`). This resolves risk R5 below.

#### 2.3 ROM table

**Status: not complete.** AP0/APBIC is present and its AP ID register reads, but
the SoC-level ROM table entries have not been populated and validated as a
coherent debugger-visible enumeration of the APs and components.

### Stage 3 — Trace — **NOT STARTED**

*Out of scope for detailed planning here; sketched for completeness.*

* R5: connect `TRACECLKIN` (currently undriven at `millisoc_system.sv:187`) and
  the R5's `TRACEDATA[7:0]` to a CoreSight funnel. The raw `CORTEXR5` core
  exposes `TRACECLKIN`/`TRACEDATA`; the `CORTEXR5INTEGRATION` wrapper is not
  instantiated, so the trace pins must be located on the core instance.
* M85: `CTICHIN`/`CTICHOUT`/`CTIIRQ` are currently left open
  (`millisoc_cpu_ss.v`); the M85 config has `ETM: FALSE`, `ETB: FALSE`,
  `TPIUM: FALSE`, so enabling trace requires changing `m85_config.yaml` and
  re-running `build_m85`.
* Add `cxcti` per core, a `cxatbfunnel`, a `cxetb` (ETF), and a `cxtpiu`.
* This will require `cxapbic_1` to be re-rendered with more master interfaces
  (see §0.2) and the debug APB fabric (AP0) to actually be populated.

### Stage 4 — Hardening, discovery and documentation — **NOT STARTED**

* Populate and verify the full ROM table.
* Authentication: wire `dbgen`/`spiden` to a real policy (e.g. a bit in the
  system control register that software can set) instead of constants.
* Security note: an always-enabled `DBGEN` on a real ASIC is a debug-access
  backdoor. Document this prominently and add a build-time option
  (`DEBUG_ACCESS` parameter) that removes the debug path in production builds.
* Update `README.md` and `AGENTS.md` with the debug architecture, the AP map, and
  the debugger bring-up procedure.

---

## 6. Verification strategy

### 6.1 Test infrastructure

There is **no debugger in the repository**. The realistic options are:

| Option | Description | Cost | Suitability |
|--------|-------------|------|-------------|
| **A. SWD/JTAG BFM (recommended)** | Write a SystemVerilog bus-functional model in `verif/monitors/` that drives the SWD pins and performs DP/AP transactions, checking responses. | ~400-600 lines, no external deps | Best for CI and for regression; directly tests the SoC-400 integration. |
| B. Arm CXDT | Arm's CoreSight eXternal Debug Tool, present at `/research/AAA/ip_library/SoC-400/coresight_soc/shared/validation/{models/cxdt,tests/cxdt}`. | Unknown — likely requires Arm-internal tooling/licences | Probably not runnable here. Keep as a reference. |
| C. OpenOCD | Real debugger over the SWD pads. | Needs a board or a socket-based harness | The best *end* goal; out of reach until there is hardware. |
| D. Arm protocol checkers | `shared/validation/protocol_checkers/{apbpc,atbpc}` — APB/ATB protocol checkers shipped with SoC-400. | Low | Should be instantiated in the TB for APB and ATB (Stage 3). |

**Status:** Option A is implemented as
`verif/monitors/dap_swd_bfm.sv` (one module with inline transaction/check
tasks; no separate package). It currently covers JTAG and SWD identification,
DP setup, AP IDs, R5 component IDs, and the M85 ROM table. APB/AXI protocol
checkers and a real debugger are not part of the current verified coverage.
Option C remains the eventual hardware goal.

### 6.2 Test list

| ID | Test | Stage | Pass criterion | Current status |
|----|------|-------|----------------|----------------|
| T0.1 | SoC-400 files compile and the `hello` regression still passes | 0 | `make run TESTNAME=hello SIMULATOR=vcs` completes with expected UART output. | **Pass** — compile and latest `hello` run completed. |
| T0.2 | SWJ-DP powers up | 0 | DP `IDCODE` reads `0x6BA02477` (SWD), with JTAG IDCODE also checked. | **Pass** — both transport identification checks pass. |
| T1.1 | DP register access | 1 | `CTRL/STAT`, `SELECT`, `RDBUFF`/`RDATA` reads/writes behave per ADIv5. | **Partial pass** — basic setup/reads work; sticky overrun and error paths remain unverified. |
| T1.2 | AP1 (AXI-AP) read of system memory | 1 | Known ROM, TCM, and peripheral words read through AP1. | **Partial pass** — boot-ROM, M85/R5 TCM readbacks, and SYS_CTRL `cpu_mx_wait` read pass; other peripheral windows remain. |
| T1.3 | AP1 write to system memory | 1 | Writes to safe TCM locations read back through AP1. | **Pass** — M85 ITCM and R5 ATCM write/read checks pass; firmware-consumed writes are not tested. |
| T1.4 | AP1 burst/byte access | 1 | `TAR` + `DRW` performs correct 8/16/32-bit transfers. | **Not tested.** |
| T1.5 | AXI ID width | 1 | No X-propagation on `DEBUG` AXI ID channels. | **RTL fixed; transaction-level check pending.** |
| T2.1 | R5 halt via AP2 | 2 | R5 stops fetching after a halt request. | **Not tested.** |
| T2.2 | R5 register access via AP2 | 2 | R5 architectural debug registers read expected values. | **Not tested** — only component ID registers were read. |
| T2.3 | R5 single-step | 2 | PC advances one instruction per step request. | **Not tested.** |
| T2.4 | M85 halt via AP3 | 2 | M85 stops fetching after a halt request. | **Not tested.** |
| T2.5 | M85 `MCUROMADDR` reachable | 2 | `0xE00FE000` returns expected M85 internal debug values. | **Not tested** — current checks target the EPPB ROM table at `0xE00FF000`. |
| T2.6 | Memory view via AP1 while cores run | 2 | TCM/SRAM reads are consistent and do not disturb running cores. | **Partial pass** — safe ITCM/ATCM write/read checks complete and the normal boot/hello output follows; broader coherence/traffic testing remains. |

### 6.3 Debugger bring-up (post-silicon)

Not executable in this repo, but the plan should produce the artefacts it needs:
the ROM table contents, the `DBGROMADDR`/`DBGSELFADDR` values, the recommended
OpenOCD config (target `cortex-m85` / `cortex-r5` behind the SoC-400 APs), and a
documented SWD pin-out.

---

## 7. Risks, assumptions and open questions

| ID | Item | Impact | Mitigation / owner |
|----|------|--------|--------------------|
| R1 | `cxdapaxiap` had not been rendered or configured. | Stage 1 blocked until the component is added. | **Resolved:** Socrates configuration, build scripts, filelist, and RTL instantiation are present; AP1 ROM, TCM, and SYS_CTRL transactions pass simulation. |
| R2 | AXI-AP sideband attributes and NIC400 ID width must match the bus. | Compile warnings or unintended bus attributes. | **RTL addressed:** `DEBUG_AXI` uses a 2-bit ID and AP sidebands are tied off. Keep transaction-level ID validation in T1.5. |
| R3 | NIC400 `DEBUG` map has incomplete peripheral reachability. The direct RT_GIC route first failed validation; parent-bus variants built, but the generated DEBUG decoder still omitted the route. | AP1 cannot currently access RT_GIC, UART, or VIC windows. | AP1 reaches ROM, the existing CPU_S range, R5 ATCM, and SYS_CTRL (`cpu_mx_wait` read verified). Determine a supported RT_GIC/peripheral route, confirm it appears in the generated decoder, then add tests and document the permitted regions. |
| R4 | NIC400 `DEBUG` port arbitration/QoS: the `DEBUG` slave port has `QoSTypeAXI = fixed`, `QoSValue = 0` (`xml:185-186`), whereas the CPU-side ports use `from_master` (`xml:103-104`). Debug accesses may be starved by CPU traffic on `CPU_S`. | Debug accesses stall behind CPU traffic. | Compare the `DEBUG` port's QoS against the `CPU_Mx`/`CPU_S` ports and raise it if necessary; this is a NIC400 config change and re-render. |
| R5 | ~~The M85 MCU debug APB decodes `PADDR[19:2]` + `PADDR31`; `0xE00FE000` may not be representable.~~ **Resolved.** AP3 is an AHB-AP on the EPPB; the M85 ROM table is at `0xE00F_F000` and was read successfully in Stage 0 (`SCS entry 0xFFF0F003`, CIDs `0x0D/0x10/0x05/0xB1`). | — | Closed. |
| R6 | R5 EDI has a 4 KB address window; `PADDRDBG310` slicing/meaning must match the R5 integration contract. | AP2 component-ID reads do not prove all intended R5 debug registers are addressable. | The current code maps TAR bits into EDI pins. Validate `PADDRDBG310` semantics and the selected window against the R5 TRM before implementing core debug. |
| R7 | SWDIO pad model and board pull devices. | SWD may fail electrically or with different pad timing on hardware. | Simulation passes with pull-up/down primitives; validate the physical I/O/pad and board pull-up before hardware use. |
| R8 | The SoC-400 generic cells (`cx_sync`, `cx_en_sync`, `cx_cdc_corrupt_gry`, `cxdapswjdp_dp_sync`, `cxdapswjdp_clk_inverter`) are not in the repo. | Compile errors. | **Resolved for this build:** static-cell copy script/filelist exist and the VCS compile/run pass. |
| R9 | Debug subsystem elaboration and integration. | Unknown compile errors or disconnected paths. | **Resolved for simulation baseline:** module is instantiated and the VCS `hello` run passes. Extend regression checks as Stage 1/2 proceed. |
| R10 | `flows/simulate.mk`'s `run_cocotb` target references `verif/cocotb/`, which does not exist in this repo. | Cannot use the project's cocotb flow as-is. | The plan writes the BFM in SystemVerilog (§0.6) and drives it from the existing testbench, so the broken cocotb target is not on the critical path. Creating `verif/cocotb/` is a viable alternative if the team prefers Python. |
| R11 | `TRACECLKIN` is an undriven wire (`millisoc_system.sv:187`) — a latent X-propagation hazard if it is ever connected to a simulated trace component. | Trace component sees X on the clock. | Resolve in Stage 3 by giving it a real source. |
| R12 | Debug access is a security exposure if left permanently enabled. | Inappropriate for a production ASIC. | Build-time `DEBUG_ACCESS` parameter (Stage 4); document prominently. |

### Resolved decisions and remaining questions

**Resolved:** The M85 uses AP3 as an AHB-AP onto its EPPB; the DAP and processor
interfaces currently share `FCLK`/`nPORESET`; both JTAG and SWD are implemented
and exercised in simulation.

1. **R5 EDI address slicing (D3/R6):** confirm `PADDRDBG310` semantics and the
   TAR-to-EDI mapping against the R5 TRM. Component-ID reads do not establish
   that the complete R5 debug register map is addressable.
2. **AP1 access scope (R3):** full system-map access was selected. The R5 ATCM
   and SYS_CTRL windows are now mapped and simulation-tested. NIC400 can build
   with parent-bus metadata for RT_GIC, but the generated DEBUG decoder still
   omits `0x44020000`–`0x4402FFFF`. Determine a supported path for the remaining
   peripheral windows before claiming full-map access.
3. **ROM table ownership:** decide whether AP0's SoC-400 APBIC is the single
   top-level table, then populate and verify its entries.
4. **Physical pads:** board/package pin assignment, pad-cell choice, and
   external pull requirements still need hardware sign-off.

---

## 8. Appendix A — Component reference

### A.1 `cxdapswjdp` — SWJ-DP

Outputs: `swdo`, `swdoen`, `tdo`, `ntdoen`, `dapcaddr[15:2]`, `dapwrite`,
`dapenable`, `dapabort`, `dapsel`, `dapwdata[31:0]`, `cdbgpwrupreq`,
`csyspwrupreq`, `cdbgrstreq`, `jtagnsw`, `jtagtop`.
Inputs: `ntrst`, `npotrst`, `swclktck`, `swditms`, `tdi`, `dapresetn`, `dapclk`,
`dapclken`, `daprdata[31:0]`, `dapready`, `dapslverr`, `cdbgpwrupack`,
`csyspwrupack`, `cdbgrstack`, `targetid[31:0]`, `instanceid[3:0]`.
Parameter: `IRLEN8` (0 ⇒ 4-bit JTAG IR, IDCODE `0x6BA00477`; 1 ⇒ 8-bit IR,
IDCODE `0x0BA03477`).

### A.2 `cxdapbusic_1` — DAPBUS interconnect

Slave: `dapcaddrs[15:2]`, `dapsels`, `dapenables`, `dapwrites`, `dapwdatas[31:0]`,
`dapaborts`, `daprdatas[31:0]`, `dapreadys`, `dapslverrs`.
Masters (×`NUM_MASTER_INTF`): `dapcaddrm[7:2]`, `dapselm`, `dapenablem`,
`dapwritem`, `dapwdatam[31:0]`, `dapabortm`, `daprdatam[31:0]`, `dapreadym`,
`dapslverrm`.
AP select = `dapcaddrs[15:8]`; local address = `dapcaddrs[7:2]`.

### A.3 `cxdapapbap` — APB Access Port

DAP side: `dapclk`, `dapclken`, `dapresetn`, `dapsel`, `dapenable`, `dapwrite`,
`dapabort`, `dapcaddr[7:2]`, `dapwdata[31:0]` → `dapready`, `dapslverr`,
`daprdata[31:0]`.
Configuration: `deviceen`, `rombaseaddr[31:0]`.
APB side: `psel`, `penable`, `pwrite`, `paddr[31:2]`, `pwdata[31:0]` →
`pready`, `pslverr`, `prdata[31:0]`. Also `pdbgswen` (software access enable).
**No `PSTRB` output.**

### A.4 `cxdapaxiap` — AXI4 Access Port

DAP side: `clk`, `resetn`, `dapcaddr[7:2]`, `dapsel`, `dapenable`, `dapwrite`,
`dapwdata[31:0]`, `dapabort` → `daprdata[31:0]`, `dapready`, `dapslverr`.
Authentication: `dbgen`, `spiden`.
AXI side (no IDs): `awaddr[31:0]`, `awlen[7:0]`, `awsize[2:0]`, `awburst[1:0]`,
`awlock`, `awcache[3:0]`, `awprot[2:0]`, `awvalid` → `awready`;
`wdata[63:0]`, `wstrb[7:0]`, `wlast`, `wvalid` → `wready`;
`bresp[1:0]`, `bvalid` → `bready`;
`araddr[31:0]`, `arlen[7:0]`, `arsize[2:0]`, `arburst[1:0]`, `arlock`,
`arcache[3:0]`, `arprot[2:0]`, `arvalid` → `arready`;
`rdata[63:0]`, `rresp[1:0]`, `rlast`, `rvalid` → `rready`.
ACE-lite extras (tie off): `awdomain[1:0]`, `awsnoop[2:0]`, `awbar[1:0]`,
`ardomain[1:0]`, `arsnoop[3:0]`, `arbar[1:0]`.

### A.5 `cxapbic_1` — top-level APB interconnect + ROM table

Slave: `paddrs0[13:2]`, `psels0`, `penables0`, `pwrites0`, `pwdatas0[31:0]`,
`paddr31s0` → `prdatas0[31:0]`, `preadys0`, `pslverrs0`.
Masters (×`NUM_MASTER_INTF`): `paddrm0/1[11:2]`, `paddr31m0/1`, `pselm0/1`,
`penablem0/1`, `pwritem0/1`, `pwdatam0/1`, `prdatam0/1`, `preadym0/1`,
`pslverrm0/1`.
Also `targetid[31:0]`, `dbgswen`.

### A.6 NIC400 `DEBUG` slave port

AXI4, 64-bit data, 32-bit address, **2-bit ID**. Signal suffix `_DEBUG` on all
ports (`AWID_DEBUG`, `AWADDR_DEBUG`, …, `RID_DEBUG`, `RRESP_DEBUG`).
`AWLEN[7:0]`, `AWSIZE[2:0]`, `AWBURST[1:0]`, `AWLOCK`, `AWCACHE[3:0]`,
`AWPROT[2:0]`, `WSTRB[7:0]`, `WLAST`.
Direction: the NIC400 `DEBUG` port is an AXI **slave** (the AXI-AP is the master).
Decode map `adp_map`: `0x00000000–0x3FFFFFFF` → `CPU_S`;
`0x44000000–0x44001FFF` → `DMA_CFG`; `0x44010000–0x4401FFFF` → `QSPI_CFG`;
`0x60000000–0x603FFFFF` → `QSPI`; `0xFFFF0000–0xFFFFFFFF` → `ROM`. No default.

---

## 9. Appendix B — Implementation file index

### Implemented in the current worktree

| Path | Status |
|------|--------|
| `millisoc_tech/logical/millisoc_subsystems/millisoc_debug_subsystem/millisoc_debug_subsystem.v` | Rewritten as the four-AP SoC-400 subsystem. |
| `millisoc_tech/tools/build_soc400.sh`, `build_soc400_component.sh`, `copy_soc400_static.sh`, `patch_soc400.sh` | Render/copy the SoC-400 components and apply the vendor RTL workaround. |
| `millisoc_tech/socrates/soc400/cxdapaxiap_1/cxdapaxiap_1.xml`, `millisoc_tech/flist/IP/soc400.flist` | AXI-AP configuration and SoC-400 filelist. |
| `millisoc_tech/logical/millisoc_system/millisoc_system.sv` | Instantiate/connect the subsystem, pads, R5 EDI, M85 EPPB, and NIC400 `DEBUG` AXI port. |
| `millisoc_tech/logical/millisoc_chip_pads/millisoc_chip_pads.v`, `millisoc_tech/logical/millisoc_chip_pads/generic/millisoc_chip_phy.v` | Expose and model debug pads. |
| `millisoc_tech/logical/millisoc_subsystems/millisoc_cpu_subsystem/CM85/millisoc_cpu_ss.v` | Expose the M85 EPPB debug interface. |
| `millisoc_tech/socrates/soc400/cxdapbusic_1/cxdapbusic_1.xml` | Configure DAPBUS for four APs. |
| `env/dependency_env.sh`, `millisoc_tech/flist/millisoc_top.flist`, `flist/millisoc_tb.flist` | Build environment and filelist integration. |
| `flows/simulate.mk` | Run `build_soc400` before filelist expansion and VCS/Questa compilation. |
| `verif/monitors/dap_swd_bfm.sv`, `verif/testbench/millisoc_tb.sv` | JTAG/SWD BFM, current checks, and testbench debug instrumentation/logging. |
| `millisoc_tech/logical/soc400/static/**`, `millisoc_tech/logical/soc400/logical/**` | Locally copied/rendered SoC-400 sources; generated/vendor sources are not all tracked. |

The BFM helper package shown in the original proposal was not created; the
transaction/check tasks currently live in `dap_swd_bfm.sv`.

### Still planned

* Test AP1 reads/writes to SYS_CTRL and determine valid mappings for the UARTs,
  PL192 VIC, and RT_GIC; add only routes that pass NIC400 validation.
* Add transfer-size and AXI response/error-path coverage for AP1.
* Implement and test R5/M85 halt, resume, single-step, and architectural
  register access; configure the R5 debug ROM/self-addresses and an intentional
  debug-enable policy.
* Populate and validate a coherent SoC-level ROM table.
* Add parity/error-path coverage and sticky-status checks; add debug-traffic
  assertions/protocol checking where useful. BFM completion timeout is now
  enforced by the testbench.
* Implement trace, production debug gating/authentication, physical pad
  integration, and post-silicon debugger documentation.
