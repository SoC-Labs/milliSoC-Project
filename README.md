# milliSoC

milliSoC is a reusable, configurable System-on-Chip (SoC) reference platform for real-time Edge AI,
developed as part of SoC Labs at the University of Southampton.

Its purpose is to give researchers, students, and small engineering teams a working SoC foundation —
processors, memory system, boot infrastructure, peripherals, and build/simulation flows — so they can
integrate, evaluate, and eventually tape out novel AI accelerators and application-specific IP without
building an entire SoC from scratch.

The platform is an evolving reference design, not a fixed commercial product. Modularity,
reproducibility, and ease of integration are first-class goals: the NPU subsystem, peripherals,
memory map, and firmware are all intended to be adapted to your own research.

## Architecture

The baseline milliSoC is a heterogeneous multiprocessor SoC with three primary compute elements:

| Element | Role |
|---|---|
| **Arm Cortex-R5** | Master processor: system control, real-time coordination, supervision of other cores |
| **Arm Cortex-M85** | Programmable application core: data handling, signal processing, AI workloads |
| **Configurable NPU / AI accelerator** | Hardware acceleration for neural-network inference (planned: Arm Ethos-U85 demonstrator, replaceable with custom research IP) |

Supporting infrastructure includes a boot ROM, QSPI flash interface, private tightly-coupled
memories (TCMs) for each core, shared memory for inter-processor communication, UART/timer
peripherals, and a PL192 Vectored Interrupt Controller (VIC). The boot path is ROM → QSPI → TCM:
the R5 boots first from boot ROM, preloads both cores' TCMs from a single flash image, and
releases the M85 from CPUWAIT once the platform is initialized. This boot flow is implemented
and passing in RTL simulation (see [Current status](#current-status)).

## Repository layout

This repository is the top-level integration project. Most of the technology lives in git
submodules:

| Directory | Contents |
|---|---|
| `millisoc_tech/` | milliSoC RTL and IP (submodule) |
| `millisoc_sdk/` | Bare-metal software SDK: apps, bootloader, drivers (submodule) |
| `soctools_flow/` | Build/flow scripts: filelist and defines compilation, project setup (submodule) |
| `rtl_primitives_tech/`, `generic_lib_tech/`, `asic_library_tech/`, `asic_flow/` | Library and flow dependencies (submodules) |
| `makefile`, `flows/` | Top-level make glue for simulation, software, and (stubbed) lint/FPGA/ASIC flows |
| `flist/` | Top-level simulation filelists |
| `verif/` | Testbench (`millisoc_tb.sv`), clock/reset control, trace support |
| `top/`, `system/` | Generated defines and generated bootrom (both gitignored) |
| `env/`, `set_env.sh`, `millisoc.config` | Environment and CPU configuration |
| `simulate/` | Simulation build and run output (gitignored) |

## Prerequisites

- **Git submodules** — clone with submodules, or initialise them after cloning (see below).
- **Arm IP library** — a licensed Arm IP tree containing Cortex-M85 (AT640), Cortex-R5 (AT575),
  and Corstone-101 (BP210) components, referenced via the `ARM_IP_LIBRARY_PATH` environment
  variable. None of this IP is included in the repository; builds and simulations fail without it.
- **EDA tools** — Synopsys VCS (default), Siemens Questa, or Cadence Xcelium for RTL simulation.
- **Toolchains** — Arm Development Studio 6 (`armclang`) for software builds.
  The SDK Makefile also has `gcc`/`keil` targets, but they are currently broken
  or placeholder — use the default `ds6` flow.

## Getting started

```sh
# 1. Clone with submodules
git clone --recurse-submodules <repo-url>
cd millisoc_project

# 2. If you cloned without submodules, initialise them once:
#    SOCLABS_SETUP_SUBMODULES=1 source set_env.sh
#    WARNING: this re-checks-out submodule branches and reverts uncommitted
#    submodule work. Never run it (or `source set_env.sh -f`) on a dirty tree.

# 3. Source the environment (do this in every new shell; source, don't execute)
source set_env.sh

# 4. Select the CPU configuration in millisoc.config (defaults: CM85 + CR5)
#    Examples are in millisoc.config_examples/

# 5. Compile the RTL and run the hello-world test
make compile SIMULATOR=vcs
make run TESTNAME=hello SIMULATOR=vcs
```

`set_env.sh` locates the project via the `.slprojroot` marker and exports all `SOCLABS_*_DIR`
environment variables used by the makefiles.

## Common tasks

All commands run from the project root after `source set_env.sh`. **You must pass
`SIMULATOR=vcs` (or `mti`/`xm`)** to the top-level `compile`/`run`/`sim` targets — without it
make fails with "no rule to make target `compile_`".

| Task | Command |
|---|---|
| Compile RTL | `make compile SIMULATOR=vcs` |
| Run a test (batch) | `make run TESTNAME=hello SIMULATOR=vcs` |
| Run a test (GUI) | `make sim TESTNAME=hello SIMULATOR=vcs` |
| Build a test's firmware (both cores) | `make testcode TESTNAME=hello` |
| Generate bootrom from bootloader | `make bootrom` |
| Regenerate defines file | `make gen_defs` (also runs automatically during compile) |
| Build firmware directly | `make -C millisoc_sdk TESTNAME=hello` (default toolchain `ds6`) |

`TESTNAME` must match an application directory in `millisoc_sdk/apps/` (default: `hello`).
Simulation output lands in `simulate/sim/<TESTNAME>/`, with logs in
`simulate/sim/<TESTNAME>/logs/run_<TESTNAME>.log`. The compiled simulation image lives in
`simulate/sim/build/`.

The generated bootrom (`system/src/bootrom/`) and defines file (`top/logical/gen_defines.v`)
are build artifacts and gitignored — never hand-edit or commit them.

## Flash image format

`make testcode` builds two firmware images per application — `<TESTNAME>_M.hex` (Cortex-M85)
and `<TESTNAME>_R.hex` (Cortex-R5) — and combines them into `<TESTNAME>.hex` using
`millisoc_sdk/tools/concat_hex.py` (wired into the `all_ds6` make target). The combined
file is copied to `simulate/sim/<TESTNAME>/image.hex` and preloaded into the QSPI flash
model by the testbench. Layout, with offsets relative to the start of the flash image
(flash address 0):

| Offset | Size | Contents |
|---|---|---|
| `0x00` | 4 bytes | M-class image start offset |
| `0x04` | 4 bytes | M-class image size in 32-bit words |
| `0x08` | 4 bytes | R-class image start offset |
| `0x0C` | 4 bytes | R-class image size in 32-bit words |
| `0x10` | … | M-class image bytes, followed by the R-class image bytes |

All fields are little-endian and every line of the file is a single hex byte, so the whole
image stays `$readmemh`-compatible with the byte-wide flash model. The bootloader reads this
preamble and DMA-copies each image into its core's TCM.

## Current status

milliSoC is under active development. The baseline heterogeneous boot path is working in
RTL simulation.

Working and verified in simulation (VCS, `hello` test, October 2026):

- **Boot process** — the R5-first two-stage boot works end to end: the R5 boots from boot ROM
  and runs the second-stage bootloader, which reads the flash-image preamble (see
  [Flash image format](#flash-image-format)), uses the DMA350 — with its completion interrupt
  serviced through the PL192 VIC — to copy the M-class image into the M85 ITCM
  (`0x00000000`) and the R-class image into the R5 ATCM (`0x80000000`), releases the M85 from
  CPUWAIT by clearing `sysctrl->cpu_mx_wait`, and hands execution over to the loaded images.
  Both cores run their applications: `Hello SoCLabs MilliSoC` is printed from the R5 and M85
  UARTs, and the test ends via `UartEndSimulation`.
- **Cortex-R5** — integrated and working as the system master: boots, services interrupts,
  runs its applications.
- **Cortex-M85** — integrated and running its application firmware from ITCM after release.
- **Memory system** — boot ROM, SRAM, and QSPI flash controller integrated and proven along
  the boot path; UART and timer peripherals working in simulation.
- **Interrupts** — PL192 VIC integrated and driven by firmware (the GIC-400 was dropped in
  its favour).

Still in progress:

- **NPU** — preparation for configurable accelerator integration; no fixed NPU commitment.
- **Applications** — only `hello` has been converted to the dual-core `_M`/`_R` split;
  `reset_demo` still needs converting before `all_ds6` can build it.
- **Flows** — the VCS simulation flow and `ds6` software build flow are the verified paths.
  The lint, regression, FPGA, and ASIC makefile flows at the top level are placeholders, and
  the Questa run flow references an undefined `$(TB_TOP)` and does not work as-is.

Historical analysis of an earlier R5 boot failure (an ISB-ordering sensitivity in bring-up)
is retained in `docs/r5_boot_isb_sensitivity_analysis.md`; it predates the current working
boot and should be read as background, not current status.

Status evolves quickly; always inspect the current repository and latest simulation logs rather
than assuming the state described here.

## Further documentation

- `AGENTS.md` — project context and engineering instructions for AI agents, plus a verified
  repository-specific guide (environment quirks, build gotchas, generated files).
- `millisoc_sdk/AGENTS.md` — SDK notes, but **out of date** (e.g. still says
  DS-5 default, no in-tree CMSIS); trust the SDK Makefiles instead, or the
  SDK section of the root `AGENTS.md`.
- `docs/` — Sphinx documentation skeleton (currently mostly empty).

## License and acknowledgements

Developed for SoC Labs (www.soclabs.org), University of Southampton, under Arm Academic Access
licence. See individual submodules for their own licence and contribution information.
