# Ibex RISC-V Core — UVM Testbench

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![UVM](https://img.shields.io/badge/UVM-1.2-blue.svg)](https://www.accellera.org/downloads/standards/uvm)
[![RISC-V](https://img.shields.io/badge/RISC--V-RV32IMC-brightgreen.svg)](https://riscv.org)

A production-grade **UVM 1.2** testbench for the [lowRISC Ibex](https://github.com/lowRISC/ibex) RV32IMC processor core, built to demonstrate CPU Design Verification methodology at the architectural level.

The scoreboard uses the **RISC-V Formal Interface (RVFI)** — Ibex's built-in retirement port — to compare every retired instruction against a software ISA golden model, without probing any internal pipeline signals.

---

## Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────┐
│                        ibex_tb_top                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                     ibex_env                         │   │
│  │  ┌───────────────────────┐  ┌──────────────────────┐ │   │
│  │  │      ibex_agent       │  │   ibex_scoreboard    │ │   │
│  │  │  ┌────────────────┐   │  │                      │ │   │
│  │  │  │ ibex_sequencer │   │  │  ibex_isa_model      │ │   │
│  │  │  └───────┬────────┘   │  │  (software RV32IM    │ │   │
│  │  │          │            │  │   reference)         │ │   │
│  │  │  ┌───────▼────────┐   │  │                      │ │   │
│  │  │  │  ibex_driver   │   │  │  Checks per retire:  │ │   │
│  │  │  │  (OBI memory   │   │  │  ✓ rd_wdata          │ │   │
│  │  │  │   model)       │   │  │  ✓ next PC           │ │   │
│  │  │  └────────────────┘   │  │  ✓ mem addr/data     │ │   │
│  │  │                       │  │  ✓ x0 invariant      │ │   │
│  │  │  ┌────────────────┐   │──►  ✓ RVFI ordering     │ │   │
│  │  │  │  ibex_monitor  │   │  │                      │ │   │
│  │  │  │  (RVFI + mem   │   │  └──────────────────────┘ │   │
│  │  │  │   + alerts)    │   │                            │   │
│  │  │  └────────────────┘   │                            │   │
│  │  └───────────────────────┘                            │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │   ibex_core (DUT)   ←→   ibex_if (SV Interface)     │   │
│  │   ibex_core.sv           clocking blocks, modports,  │   │
│  │   [lowRISC RTL]          OBI + RVFI assertions       │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
ibex-uvm-tb/
├── tb/
│   ├── ibex_tb_top.sv        # Top module: DUT instantiation + UVM kickoff
│   ├── ibex_if.sv            # SV interface: clocking blocks, modports, assertions
│   └── ibex_transaction.sv   # Sequence item + RISC-V instruction decode helpers
├── sequences/
│   └── ibex_sequences.sv     # 8 directed sequences + base sequence helpers
├── agents/
│   ├── ibex_agent.sv         # Agent + Sequencer + AgentCfg
│   ├── ibex_driver.sv        # OBI driver with inline memory model
│   └── ibex_monitor.sv       # RVFI monitor + coverage collector
├── scoreboard/
│   └── ibex_scoreboard.sv    # ISA golden model + architectural checks
├── env/
│   └── ibex_env.sv           # Environment: wires agent → scoreboard
├── test/
│   └── ibex_tests.sv         # 9 test classes (smoke → full regression)
├── docs/
│   └── verification_plan.md  # Detailed verification plan & methodology
├── Makefile                  # VCS / Xcelium / Questa build targets
└── README.md
```

---

## What's Verified

### Architectural State
| State | Verification Method |
|-------|-------------------|
| x0 (zero register) | RVFI: rs1/rs2_rdata==0 when addr==0; rd_wdata==0 when addr==0 |
| x1–x31 (GPRs) | ISA model computes expected rd_wdata; scoreboard compares vs RVFI |
| PC (sequential) | pc_wdata == pc_rdata + 4 for non-control-flow |
| PC (branch/jump) | Taken/not-taken computed from ISA model; compared with rvfi_pc_wdata |
| CSRs (mstatus, mtvec, mepc, mcause, mcycle, minstret) | CSR access sequence + read-back verification |
| Data memory | Memory monitor cross-checks rvfi_mem_addr/data vs bus-side activity |

### Instruction Coverage
- **R-type**: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
- **I-type**: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
- **Load**: LW, LH, LHU, LB, LBU — sign/zero extension verified
- **Store**: SW, SH, SB — byte enable per address alignment
- **Branch**: BEQ, BNE, BLT, BGE, BLTU, BGEU — taken and not-taken
- **Jump**: JAL (link register + target), JALR (indirect + LSB clear)
- **Upper**: LUI, AUIPC
- **M-ext**: MUL, MULH, MULHU, MULHSU, DIV, DIVU, REM, REMU (corner cases: div-by-zero, overflow)
- **CSR**: CSRRW, CSRRS, CSRRC (atomicity: old value in rd)
- **Hazards**: EX→EX forwarding, MEM→EX forwarding, load-use stall, WAW, x0 write suppression

### Hazard & Forwarding Sequences
```
// EX→EX forwarding test (back-to-back RAW)
ADD x2, x1, x1   // x2 = 20
ADD x3, x2, x2   // x3 = 40  ← x2 must be forwarded, not stale regfile

// Load-use stall test (1-cycle stall required)
LW  x8, 0(x1)    // load
ADD x9, x8, x2   // ← x8 must be stalled until load completes
```

---

## Test Suite

| Test Class | What it exercises |
|-----------|------------------|
| `ibex_smoke_test` | Reset + NOP sled; verifies core starts at PC=0 |
| `ibex_alu_test` | All 13 R-type ALU operations with known operand patterns |
| `ibex_lsu_test` | All load/store widths (LW/LH/LHU/LB/LBU/SW/SH/SB) + load-use hazard |
| `ibex_branch_test` | All 6 branch types (taken + not-taken) + JAL + JALR |
| `ibex_hazard_test` | EX→EX, MEM→EX forwarding; WAW; load-use stall; x0 write |
| `ibex_csr_test` | CSRRW/CSRRS/CSRRC on mstatus, mie, mtvec, mcycle, minstret |
| `ibex_interrupt_test` | Timer interrupt injection, IRQ entry, deassertion |
| `ibex_random_test` | 1000 fully randomized legal instructions |
| `ibex_full_regression_test` | All sequences back-to-back in one simulation |

---

## Getting Started

### 1. Clone this repo and Ibex RTL

```bash
git clone https://github.com/YOUR_USERNAME/ibex-uvm-tb.git
cd ibex-uvm-tb

# Clone the Ibex RTL as a submodule (points to lowRISC/ibex)
git submodule update --init --recursive
# RTL will be at: rtl/ibex_core.sv
```

### 2. Run a test (VCS)

```bash
# Compile + run the smoke test
make vcs_run TEST=ibex_smoke_test

# Run with waveform dump
make vcs_waves TEST=ibex_alu_test

# Full regression (all tests × 5 seeds)
make regression

# Regression summary
make regression_summary
```

### 3. Run with Xcelium or Questa

```bash
make xrun TEST=ibex_branch_test SEED=42
make questa_run TEST=ibex_hazard_test
```

### 4. Select verbosity

```bash
make vcs_run TEST=ibex_random_test VERBOSITY=UVM_HIGH   # per-instruction log
make vcs_run TEST=ibex_alu_test    VERBOSITY=UVM_LOW    # summary only
```

> **Important:** All simulators must compile with `+define+RVFI` — this enables the  
> RVFI retirement port in `ibex_core.sv` which the scoreboard depends on.

---

## Scoreboard Design

The scoreboard implements `ibex_isa_model` — a pure SystemVerilog function that recomputes the expected output for every RISC-V instruction from its opcode and input operands. It does **not** run a second RTL simulation.

```
RVFI retirement event
        │
        ▼
ibex_scoreboard.check_rvfi_stream()
        │
        ├─► Invariant checks (x0, PC alignment, RVFI order)
        │
        ├─► ibex_isa_model.predict(actual)
        │         returns: exp_rd_wdata, exp_pc_wdata, exp_mem_addr
        │
        ├─► check("RD_WDATA_CORRECT",  actual.rd_wdata  == exp_rd_wdata)
        ├─► check("PC_UPDATE_CORRECT", actual.pc_wdata  == exp_pc_wdata)
        └─► check("MEM_ADDR_CORRECT",  actual.mem_addr  == exp_mem_addr)
```

**Why RVFI?** The RVFI port gives you retirement-ordered, atomic instruction observations — each beat contains the instruction word, input operand values (rs1_rdata, rs2_rdata), output (rd_wdata), PC before and after, and memory address/data. This is exactly what you need for ISA-level checking without any pipeline internal visibility.

---

## Key Design Decisions

**1. RVFI as the observation interface** — avoids coupling the TB to pipeline internals. The scoreboard is microarchitecture-agnostic; it works regardless of whether Ibex uses 2 stages, 3 stages, or adds a writeback stage.

**2. Predict-and-check, not parallel simulation** — the ISA model is a pure function (`predict()`), not a second RTL model running in lockstep. This is ~100× faster and easier to maintain.

**3. Inline memory model in the driver** — the driver holds an associative array `instr_mem[addr]` and `data_mem[addr]`, populated by sequences. This means no external memory model process is needed for basic tests.

**4. Configurable OBI timing** — `ibex_agent_cfg` exposes `instr_gnt_delay_max`, `data_rvalid_delay`, etc. The regression uses random values to catch timing-sensitive bugs.

---

## Coverage

The monitor includes `ibex_rvfi_coverage` with four covergroups:

| Covergroup | What it measures |
|-----------|-----------------|
| `instr_type_cg` | All 9 opcode bins × rd register bins (cross) |
| `pc_cg` | PC value ranges (low/mid/high memory) |
| `control_flow_cg` | Branch taken/not-taken, JAL, JALR, trap, interrupt |
| `lsu_cg` | Load/store type × funct3 × memory alignment |

---

## Common Bugs This Catches

| Bug | Caught By |
|-----|----------|
| Forwarding mux selects wrong source | `ibex_hazard_test` → `RD_WDATA_CORRECT` mismatch |
| Load-use stall not inserted | `ibex_lsu_test` load-use sequence → wrong rd value |
| BLT uses unsigned comparison | `ibex_branch_test` with negative operands → wrong PC |
| LH sign extension missing | `ibex_lsu_test` with 0x8000 data → rd_wdata wrong |
| SB puts data in wrong byte lane | `ibex_lsu_test` SB test → `STORE_DATA_CORRECT` fail |
| x0 write not suppressed | Every sequence → `RD_X0_WRITE_IGNORED` check |
| JALR LSB not cleared | `ibex_branch_test` JALR test → `PC_UPDATE_CORRECT` fail |
| CSRRW returns new value not old | `ibex_csr_test` → `RD_WDATA_CORRECT` mismatch |
| mcycle not counting | `ibex_csr_test` → counter read-back fails |

---

## Prerequisites

- SystemVerilog simulator: **VCS 2021+**, **Xcelium 20.09+**, or **Questa 2021.1+**
- **UVM 1.2** (bundled with simulator)
- **Python 3.6+** (for any helper scripts)
- Ibex RTL from [lowRISC/ibex](https://github.com/lowRISC/ibex) (added as git submodule)

---

## License

MIT — see [LICENSE](LICENSE). The Ibex RTL submodule is Apache 2.0 (lowRISC).

---

## References

- [Ibex Documentation](https://ibex-core.readthedocs.io/)
- [RISC-V ISA Specification](https://riscv.org/specifications/)
- [RVFI Specification](https://github.com/YosysHQ/riscv-formal/blob/master/docs/rvfi.md)
- [UVM 1.2 Reference](https://www.accellera.org/downloads/standards/uvm)
- [lowRISC Ibex GitHub](https://github.com/lowRISC/ibex)
