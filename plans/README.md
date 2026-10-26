# milliSoC Plans

Engineering plans for milliSoC features that span RTL, firmware, build scripts and
verification. Each plan is a self-contained proposal with its own scope, decisions,
staged implementation, verification strategy and risks.

Plans are **proposals until the "Decision log" section is signed off**. Work should
not start on a stage whose upstream decisions are still marked `PROPOSED`.

| Plan | Status | Summary |
|------|--------|---------|
| [millisoc_debug_subsystem.md](millisoc_debug_subsystem.md) | Draft — awaiting decision on D4 | CoreSight SoC-400 based debug subsystem: DAP bring-up, system-bus debug access via the NIC400 AXI DEBUG port, R5/M85 core debug, and trace. |
| [ethos_u85_integration.md](ethos_u85_integration.md) | In progress — full SoC compile/hello pass; shared-SRAM target not yet connected | Staged plan to integrate an Ethos-U85 demonstrator behind a replaceable NPU boundary, including RTL, NIC400, memory, host IRQ, firmware, and simulation. |

## Conventions used in these plans

* Every claim about the current repository state is annotated with `file:line`
  evidence so it can be re-checked quickly.
* Claims about Arm IP are annotated with the absolute path into `ARM_IP_LIBRARY_PATH`
  (`/research/AAA/ip_library`).
* "Verified" means the behaviour was read in source; "Assumed" means it is an
  inference that still needs a simulation or hardware check.
* Stages are ordered so that each one is independently testable and leaves the
  system in a working state.
