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
peripherals, and a PL192 Vectored Interrupt Controller (VIC). The intended boot path is ROM → QSPI → SRAM/TCM,
with the R5 booting first and releasing the M85 from reset once the platform is initialized.

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
| Build a test's firmware only | `make testcode TESTNAME=hello` |
| Generate bootrom from bootloader | `make bootrom` |
| Regenerate defines file | `make gen_defs` (also runs automatically during compile) |
| Build firmware directly | `make -C millisoc_sdk TESTNAME=hello` (default toolchain `ds6`) |

`TESTNAME` must match an application directory in `millisoc_sdk/apps/` (default: `hello`).
Simulation output lands in `simulate/sim/<TESTNAME>/`, with logs in
`simulate/sim/<TESTNAME>/logs/run_<TESTNAME>.log`. The compiled simulation image lives in
`simulate/sim/build/`.

The generated bootrom (`system/src/bootrom/`) and defines file (`top/logical/gen_defines.v`)
are build artifacts and gitignored — never hand-edit or commit them.

## Current status

milliSoC is under active RTL integration and simulation bring-up.

Current work includes:

- **Cortex-M85** — integrated; firmware execution, boot/startup code, and simulation debugging
  are working and actively developed.
- **Memory system** — boot ROM and SRAM integrated; QSPI flash controller implemented.
- **Buses and peripherals** — bus infrastructure and memory mapping in place; UART and timers
  available in simulation.
- **Cortex-R5** — being integrated as the system master.
- **Interrupts** — PL192 VIC integration in progress as part of the transition to the
  heterogeneous multiprocessor system.
- **NPU** — preparation for configurable accelerator integration; no fixed NPU commitment.
- **Flows** — simulation (VCS/Questa/Xcelium) and software build flows are functional; the
  lint, regression, FPGA, and ASIC makefile flows at the top level are placeholders.

A known open issue: initializing the PL192 VIC from the R5 requires proper integration of the RTL and firmware driver to ensure correct interrupt handling.
function, around an MMIO read of `0x44021084` (identified as GIC distributor register
`GICD_IGROUPR1`). This is an active debugging lead, not a confirmed root cause — verify against
the actual RTL and address map before drawing conclusions.

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
