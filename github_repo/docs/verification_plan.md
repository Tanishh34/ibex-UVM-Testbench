# Ibex UVM Testbench — Verification Plan

## 1. Scope

This verification plan covers functional verification of `ibex_core.sv` from the [lowRISC Ibex](https://github.com/lowRISC/ibex) repository at the **architectural (ISA) level**. The goal is to confirm that every instruction the core retires produces the correct architectural state change as defined by the RISC-V Unprivileged ISA Specification (v20191213) and the RISC-V Privileged Architecture Specification (v20190608).

**In scope:**
- RV32I base integer instruction set (47 instructions)
- RV32M multiply/divide extension (8 instructions)
- Machine-mode CSRs (mstatus, mie, mtvec, mepc, mcause, mtval, mcycle, minstret)
- External interrupt entry and return (MRET)
- Load/store memory interface (OBI protocol)
- Reset behavior

**Out of scope (initial plan):**
- PMP (PMPEnable=0)
- ICache (ICache=0)
- B-extension (RV32BNone)
- Debug module internals (debug_req injection only)
- Physical ECC / integrity faults

---

## 2. Verification Architecture

### 2.1 Why RVFI-based Checking

The RISC-V Formal Interface (RVFI) exposes a retirement port from `ibex_core.sv` when compiled with `+define+RVFI`. Each valid RVFI beat is an atomic, retirement-ordered record containing:

```
rvfi_insn       — the instruction word that retired
rvfi_rs1_rdata  — value of rs1 at the time of execution
rvfi_rs2_rdata  — value of rs2 at the time of execution
rvfi_rd_addr    — destination register address (0 = no write)
rvfi_rd_wdata   — value written to rd
rvfi_pc_rdata   — PC of this instruction
rvfi_pc_wdata   — next PC after this instruction
rvfi_mem_addr   — effective address for loads/stores
rvfi_mem_rmask  — byte read mask (load)
rvfi_mem_wmask  — byte write mask (store)
rvfi_mem_rdata  — data read from memory
rvfi_mem_wdata  — data written to memory
rvfi_trap       — 1 if instruction caused trap/exception
rvfi_intr       — 1 if interrupt was taken before this instruction
rvfi_order      — monotonic 64-bit retirement counter
```

This gives the scoreboard everything it needs to verify ISA correctness without probing any internal pipeline signals. The approach is **microarchitecture-independent** — the same scoreboard works for 2-stage, 3-stage, or any pipeline depth.

### 2.2 Scoreboard Strategy: Predict-and-Check

```
For each RVFI retirement:
  1. Compute expected_result = isa_model.predict(insn, rs1, rs2, pc, mem_rdata)
  2. Compare actual.rd_wdata  vs expected_result.rd_wdata
  3. Compare actual.pc_wdata  vs expected_result.next_pc
  4. Compare actual.mem_addr  vs expected_result.eff_addr  (loads/stores)
  5. Compare actual.mem_wdata vs expected_result.store_data (stores)
```

### 2.3 Memory Model

The driver maintains two associative arrays:
- `instr_mem[addr]` — instruction words loaded by sequences
- `data_mem[addr]`  — data memory, written by store instructions, read by loads

The driver responds to OBI requests using these models with configurable `gnt_delay` and `rvalid_delay` to exercise timing corners.

---

## 3. Verification Plan Table

| ID | Feature | Sequence | Check | Priority |
|----|---------|----------|-------|----------|
| VP-001 | Reset behavior | `ibex_reset_seq` | PC=0 after reset; all GPRs=0 | P0 |
| VP-002 | NOP execution | `ibex_smoke_test` | PC increments +4; rd unchanged | P0 |
| VP-003 | ADD/SUB | `ibex_alu_rtype_seq` | RD_WDATA_CORRECT | P0 |
| VP-004 | SLL/SRL/SRA | `ibex_alu_rtype_seq` | shift amount = rs2[4:0] | P0 |
| VP-005 | SLT/SLTU | `ibex_alu_rtype_seq` | signed vs unsigned | P0 |
| VP-006 | XOR/OR/AND | `ibex_alu_rtype_seq` | bitwise correctness | P0 |
| VP-007 | ADDI sign extension | `ibex_alu_rtype_seq` | imm[11] sign extended | P0 |
| VP-008 | LW | `ibex_load_store_seq` | full word; no extension | P0 |
| VP-009 | LH / LHU | `ibex_load_store_seq` | LH sign-extends bit 15; LHU zero-extends | P0 |
| VP-010 | LB / LBU | `ibex_load_store_seq` | LB sign-extends bit 7; LBU zero-extends | P0 |
| VP-011 | SW | `ibex_load_store_seq` | BE=0xF; all 4 bytes written | P0 |
| VP-012 | SH | `ibex_load_store_seq` | BE=0x3 (low) or 0xC (high) per addr[1] | P0 |
| VP-013 | SB | `ibex_load_store_seq` | BE=1/2/4/8 per addr[1:0] | P0 |
| VP-014 | BEQ taken/not-taken | `ibex_control_flow_seq` | PC_UPDATE_CORRECT | P0 |
| VP-015 | BNE taken/not-taken | `ibex_control_flow_seq` | PC_UPDATE_CORRECT | P0 |
| VP-016 | BLT (signed) | `ibex_control_flow_seq` | negative operands | P0 |
| VP-017 | BGE (signed) | `ibex_control_flow_seq` | signed >= | P0 |
| VP-018 | BLTU / BGEU | `ibex_control_flow_seq` | unsigned compare | P0 |
| VP-019 | JAL | `ibex_control_flow_seq` | target=PC+imm_j; rd=PC+4 | P0 |
| VP-020 | JALR | `ibex_control_flow_seq` | target=(rs1+imm)&~1; rd=PC+4 | P0 |
| VP-021 | LUI | `ibex_alu_rtype_seq` | rd = {imm[31:12], 12'b0} | P0 |
| VP-022 | AUIPC | `ibex_alu_rtype_seq` | rd = PC + {imm[31:12], 12'b0} | P0 |
| VP-023 | x0 always zero (read) | All sequences | RS1/RS2_X0_IS_ZERO | P0 |
| VP-024 | x0 write suppressed | `ibex_hazard_test` | RD_X0_WRITE_IGNORED | P0 |
| VP-025 | EX→EX forwarding | `ibex_hazard_test` | back-to-back RAW | P0 |
| VP-026 | Load-use stall | `ibex_hazard_test` | LW followed immediately by dependent | P0 |
| VP-027 | MEM→EX forwarding | `ibex_hazard_test` | 1-cycle gap RAW | P1 |
| VP-028 | WAW hazard | `ibex_hazard_test` | second write wins | P1 |
| VP-029 | MUL | `ibex_alu_rtype_seq` | lower 32 bits; check overflow wrap | P1 |
| VP-030 | DIV corner cases | `ibex_alu_rtype_seq` | div-by-zero=0xFFFFFFFF; overflow | P1 |
| VP-031 | CSRRW atomicity | `ibex_csr_test` | rd = old CSR value | P1 |
| VP-032 | CSRRS / CSRRC | `ibex_csr_test` | set/clear bits | P1 |
| VP-033 | mcycle increments | `ibex_csr_test` | counter increases each cycle | P1 |
| VP-034 | minstret increments | `ibex_csr_test` | +1 per retired instruction | P1 |
| VP-035 | Interrupt entry | `ibex_interrupt_test` | PC→mtvec; mstatus.MIE cleared | P1 |
| VP-036 | RVFI order monotonic | Monitor assertion | rvfi_order == prev+1 | P0 |
| VP-037 | OBI grant delay 0–N | Driver configuration | core holds req until gnt | P1 |
| VP-038 | OBI rvalid delay | Driver configuration | core stalls until rvalid | P1 |
| VP-039 | PC 4-byte aligned | Interface assertion | pc_rdata[1:0]==0 always | P0 |
| VP-040 | Random instructions | `ibex_random_test` | All scoreboard checks, 1000 instrs | P1 |

---

## 4. Coverage Goals

| Covergroup | Target |
|-----------|--------|
| All opcode bins hit | 100% |
| All funct3 values for loads | 100% |
| Branch taken AND not-taken for all 6 types | 100% |
| rd = x0 through x31 all written | > 80% |
| Memory access at all 4 byte alignments | 100% |
| OBI grant delay 0, 1, 2 cycles | 100% |

---

## 5. Bug Tracking

When a scoreboard check fails, the error message includes:
- The check name (e.g., `RD_WDATA_CORRECT`)
- The PC of the failing instruction (`pc_rdata`)
- The instruction word (`insn`) in hex
- Actual vs expected values

This gives enough context to identify the failing instruction and debug the RTL.

---

## 6. Regression Strategy

- **Nightly regression**: all 9 test classes × 5 random seeds = 45 simulations
- **Directed tests** (VP-001 through VP-036): run with seed=1 for reproducibility
- **Random test** (`ibex_random_test`): 10 different seeds, 1000 instructions each
- **Pass criteria**: 0 UVM_ERROR, 0 UVM_FATAL, scoreboard reports "ALL CHECKS PASSED"

---

## 7. What to Add Next

After this plan is complete, the following extensions are recommended:

1. **RISC-V compliance tests**: Load official riscv-arch-test binaries into the driver memory model and run them through the RVFI scoreboard
2. **Formal verification**: Connect the RVFI output to the [riscv-formal](https://github.com/YosysHQ/riscv-formal) checker properties
3. **PMP verification**: Enable `PMPEnable=1` and add a PMP configuration sequence + access fault injection
4. **ICache verification**: Enable `ICache=1`, add a second agent on the instruction bus, verify cache-hit behavior
5. **Power management**: WFI instruction + interrupt wake-up sequence
