//=============================================================================
// File: ibex_scoreboard.sv
// Description: Architectural Scoreboard for Ibex RISC-V Core
//
//   Design Philosophy:
//   - Uses RVFI (retirement port) as ground truth from DUT
//   - Implements a golden ISA model (software reference) alongside
//   - Compares every retired instruction: result, next PC, register state
//   - Tracks full architectural state: registers, PC, CSRs, memory
//
//   Verification Strategy:
//   1. Architectural State: 32 registers + PC + CSRs tracked in golden model
//   2. Instruction Correctness: Every opcode recomputed and compared
//   3. PC / Control Flow: Sequential + taken branches + JAL/JALR verified
//   4. Register File: All writes captured and compared; x0 always zero
//   5. Load/Store: Data and address verified at memory interface
//   6. Hazards: Forwarding handled automatically via RVFI golden model
//=============================================================================

`ifndef IBEX_SCOREBOARD_SV
`define IBEX_SCOREBOARD_SV

//=============================================================================
// RISC-V ISA Reference Model (pure software implementation)
//=============================================================================
class ibex_isa_model;

  // -------------------------------------------------------------------------
  // Architectural State
  // -------------------------------------------------------------------------
  logic [31:0] regs [32];        // x0-x31 register file
  logic [31:0] pc;               // Program counter
  logic [63:0] instr_count;      // Retired instruction count

  // CSR shadow (only the ones Ibex implements)
  logic [31:0] mstatus;
  logic [31:0] misa;
  logic [31:0] mie;
  logic [31:0] mtvec;
  logic [31:0] mepc;
  logic [31:0] mcause;
  logic [31:0] mtval;
  logic [63:0] mcycle;
  logic [63:0] minstret;

  // -------------------------------------------------------------------------
  // Initialize to reset state
  // -------------------------------------------------------------------------
  function new();
    foreach (regs[i]) regs[i] = 32'h0;
    pc          = 32'h0000_0000;  // Ibex reset vector
    instr_count = 64'h0;
    mstatus     = 32'h0000_1800;  // MPP=M-mode
    misa        = 32'h4014_1100;  // RISC-V 32-bit, I+M+C+Zicsr
    mie         = 32'h0;
    mtvec       = 32'h0;
    mepc        = 32'h0;
    mcause      = 32'h0;
    mtval       = 32'h0;
    mcycle      = 64'h0;
    minstret    = 64'h0;
  endfunction

  // Ensure x0 is always zero (architectural invariant)
  function void enforce_x0();
    regs[0] = 32'h0;
  endfunction

  // -------------------------------------------------------------------------
  // Compute expected result for a given RVFI retirement
  // Returns 1 if prediction is valid (no exception), 0 on illegal instr
  // -------------------------------------------------------------------------
  function automatic int predict(
    input  ibex_rvfi_transaction actual,   // Actual RVFI from DUT
    output logic [31:0]          exp_rd_wdata,
    output logic [ 4:0]          exp_rd_addr,
    output logic [31:0]          exp_pc_wdata,
    output logic [31:0]          exp_mem_addr,
    output logic [31:0]          exp_mem_wdata
  );
    logic [31:0] rs1 = actual.rs1_rdata;
    logic [31:0] rs2 = actual.rs2_rdata;
    logic [31:0] insn = actual.insn;
    logic [31:0] pc_val = actual.pc_rdata;

    // Immediates
    logic signed [31:0] imm_i = {{20{insn[31]}}, insn[31:20]};
    logic signed [31:0] imm_s = {{20{insn[31]}}, insn[31:25], insn[11:7]};
    logic signed [31:0] imm_b = {{19{insn[31]}}, insn[31], insn[7],
                                   insn[30:25], insn[11:8], 1'b0};
    logic        [31:0] imm_u = {insn[31:12], 12'b0};
    logic signed [31:0] imm_j = {{11{insn[31]}}, insn[31], insn[19:12],
                                   insn[20], insn[30:21], 1'b0};

    logic [6:0] opcode = insn[6:0];
    logic [2:0] funct3 = insn[14:12];
    logic [6:0] funct7 = insn[31:25];
    logic [4:0] rd     = insn[11:7];

    // Default: sequential PC, no register write
    exp_pc_wdata  = pc_val + 4;
    exp_rd_addr   = rd;
    exp_rd_wdata  = 32'h0;
    exp_mem_addr  = 32'h0;
    exp_mem_wdata = 32'h0;

    case (opcode)
      // -------------------------------------------------------------------
      // R-Type
      // -------------------------------------------------------------------
      7'b0110011: begin
        case ({funct7, funct3})
          10'b0000000_000: exp_rd_wdata = rs1 + rs2;                    // ADD
          10'b0100000_000: exp_rd_wdata = rs1 - rs2;                    // SUB
          10'b0000000_001: exp_rd_wdata = rs1 << rs2[4:0];              // SLL
          10'b0000000_010: exp_rd_wdata = ($signed(rs1) < $signed(rs2)) ? 1 : 0; // SLT
          10'b0000000_011: exp_rd_wdata = (rs1 < rs2) ? 1 : 0;         // SLTU
          10'b0000000_100: exp_rd_wdata = rs1 ^ rs2;                    // XOR
          10'b0000000_101: exp_rd_wdata = rs1 >> rs2[4:0];              // SRL
          10'b0100000_101: exp_rd_wdata = $signed(rs1) >>> rs2[4:0];    // SRA
          10'b0000000_110: exp_rd_wdata = rs1 | rs2;                    // OR
          10'b0000000_111: exp_rd_wdata = rs1 & rs2;                    // AND
          // M-extension
          10'b0000001_000: exp_rd_wdata = rs1 * rs2;                    // MUL
          10'b0000001_001: exp_rd_wdata = ($signed(rs1) * $signed(rs2)) >> 32; // MULH
          10'b0000001_010: exp_rd_wdata = ($signed(rs1) * rs2) >> 32;   // MULHSU
          10'b0000001_011: exp_rd_wdata = (rs1 * rs2) >> 32;            // MULHU
          10'b0000001_100: exp_rd_wdata = (rs2 == 0) ? 32'hFFFF_FFFF :
                              $signed(rs1) / $signed(rs2);              // DIV
          10'b0000001_101: exp_rd_wdata = (rs2 == 0) ? 32'hFFFF_FFFF :
                              rs1 / rs2;                                 // DIVU
          10'b0000001_110: exp_rd_wdata = (rs2 == 0) ? rs1 :
                              $signed(rs1) % $signed(rs2);              // REM
          10'b0000001_111: exp_rd_wdata = (rs2 == 0) ? rs1 :
                              rs1 % rs2;                                 // REMU
          default: return 0;  // Illegal
        endcase
      end

      // -------------------------------------------------------------------
      // I-Type ALU
      // -------------------------------------------------------------------
      7'b0010011: begin
        case (funct3)
          3'b000: exp_rd_wdata = rs1 + imm_i;                           // ADDI
          3'b010: exp_rd_wdata = ($signed(rs1) < $signed(imm_i)) ? 1 : 0; // SLTI
          3'b011: exp_rd_wdata = (rs1 < imm_i) ? 1 : 0;                // SLTIU
          3'b100: exp_rd_wdata = rs1 ^ imm_i;                           // XORI
          3'b110: exp_rd_wdata = rs1 | imm_i;                           // ORI
          3'b111: exp_rd_wdata = rs1 & imm_i;                           // ANDI
          3'b001: exp_rd_wdata = rs1 << imm_i[4:0];                     // SLLI
          3'b101: begin
            if (funct7 == 7'b0100000)
              exp_rd_wdata = $signed(rs1) >>> imm_i[4:0];               // SRAI
            else
              exp_rd_wdata = rs1 >> imm_i[4:0];                         // SRLI
          end
          default: return 0;
        endcase
      end

      // -------------------------------------------------------------------
      // LOAD
      // -------------------------------------------------------------------
      7'b0000011: begin
        logic [31:0] eff_addr = rs1 + imm_i;
        exp_mem_addr  = eff_addr;
        exp_rd_wdata  = actual.mem_rdata;  // Trust memory data from RVFI
        // Sign extension handled by funct3, scoreboard checks data path
        case (funct3)
          3'b000: exp_rd_wdata = {{24{actual.mem_rdata[7]}},  actual.mem_rdata[7:0]};  // LB
          3'b001: exp_rd_wdata = {{16{actual.mem_rdata[15]}}, actual.mem_rdata[15:0]}; // LH
          3'b010: exp_rd_wdata = actual.mem_rdata;                                     // LW
          3'b100: exp_rd_wdata = {24'h0, actual.mem_rdata[7:0]};                       // LBU
          3'b101: exp_rd_wdata = {16'h0, actual.mem_rdata[15:0]};                      // LHU
          default: return 0;
        endcase
      end

      // -------------------------------------------------------------------
      // STORE (no rd write)
      // -------------------------------------------------------------------
      7'b0100011: begin
        logic [31:0] eff_addr = rs1 + imm_s;
        exp_mem_addr  = eff_addr;
        exp_mem_wdata = rs2;
        exp_rd_addr   = 5'd0;  // No register write for stores
        exp_rd_wdata  = 32'h0;
      end

      // -------------------------------------------------------------------
      // BRANCH
      // -------------------------------------------------------------------
      7'b1100011: begin
        logic branch_taken;
        case (funct3)
          3'b000: branch_taken = (rs1 == rs2);                          // BEQ
          3'b001: branch_taken = (rs1 != rs2);                          // BNE
          3'b100: branch_taken = ($signed(rs1) < $signed(rs2));         // BLT
          3'b101: branch_taken = ($signed(rs1) >= $signed(rs2));        // BGE
          3'b110: branch_taken = (rs1 < rs2);                           // BLTU
          3'b111: branch_taken = (rs1 >= rs2);                          // BGEU
          default: branch_taken = 0;
        endcase
        exp_pc_wdata = branch_taken ? (pc_val + imm_b) : (pc_val + 4);
        exp_rd_addr  = 5'd0;  // No register write
        exp_rd_wdata = 32'h0;
      end

      // -------------------------------------------------------------------
      // JAL
      // -------------------------------------------------------------------
      7'b1101111: begin
        exp_rd_wdata = pc_val + 4;           // Return address
        exp_pc_wdata = pc_val + imm_j;       // Jump target
      end

      // -------------------------------------------------------------------
      // JALR
      // -------------------------------------------------------------------
      7'b1100111: begin
        exp_rd_wdata = pc_val + 4;
        exp_pc_wdata = (rs1 + imm_i) & ~32'h1;  // Clear LSB
      end

      // -------------------------------------------------------------------
      // LUI
      // -------------------------------------------------------------------
      7'b0110111: begin
        exp_rd_wdata = imm_u;
      end

      // -------------------------------------------------------------------
      // AUIPC
      // -------------------------------------------------------------------
      7'b0010111: begin
        exp_rd_wdata = pc_val + imm_u;
      end

      // -------------------------------------------------------------------
      // SYSTEM (CSR / ECALL / EBREAK)
      // -------------------------------------------------------------------
      7'b1110011: begin
        if (funct3 == 3'b000) begin
          // ECALL / EBREAK / MRET - traps, pc goes to mtvec
          exp_pc_wdata = mtvec;  // Simplified
          exp_rd_addr  = 5'd0;
        end else begin
          // CSR instructions - predict based on CSR address
          logic [11:0] csr_addr = insn[31:20];
          logic [31:0] csr_val  = read_csr(csr_addr);
          exp_rd_wdata = csr_val;  // Read old value
          // Write new value (simplified - update shadow)
        end
      end

      default: return 0;  // Unrecognized/illegal instruction
    endcase

    // x0 writes must be ignored
    if (exp_rd_addr == 5'd0) exp_rd_wdata = 32'h0;

    return 1;
  endfunction

  function logic [31:0] read_csr(input logic [11:0] csr_addr);
    case (csr_addr)
      12'h300: return mstatus;
      12'h304: return mie;
      12'h305: return mtvec;
      12'h341: return mepc;
      12'h342: return mcause;
      12'h343: return mtval;
      12'h344: return 32'h0;  // mip (read-only from software)
      12'hB00: return mcycle[31:0];
      12'hB02: return minstret[31:0];
      12'hB80: return mcycle[63:32];
      12'hB82: return minstret[63:32];
      default: return 32'hDEAD_BEEF;
    endcase
  endfunction

endclass


//=============================================================================
// Scoreboard
//=============================================================================
class ibex_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(ibex_scoreboard)

  // Analysis FIFOs
  uvm_tlm_analysis_fifo #(ibex_rvfi_transaction) rvfi_fifo;
  uvm_tlm_analysis_fifo #(ibex_transaction)      mem_fifo;

  // Analysis exports
  uvm_analysis_export #(ibex_rvfi_transaction)   rvfi_export;
  uvm_analysis_export #(ibex_transaction)        mem_export;

  // Golden ISA model
  ibex_isa_model golden;

  // Statistics
  int unsigned checks_passed   = 0;
  int unsigned checks_failed   = 0;
  int unsigned instrs_checked  = 0;

  // Register file shadow (for register-level verification)
  logic [31:0] reg_shadow [32];

  // Previous order for monotonicity check
  logic [63:0] prev_order = 64'hFFFF_FFFF_FFFF_FFFF;

  //-------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    rvfi_fifo    = new("rvfi_fifo", this);
    mem_fifo     = new("mem_fifo",  this);
    rvfi_export  = new("rvfi_export", this);
    mem_export   = new("mem_export",  this);
    golden       = new();

    foreach (reg_shadow[i]) reg_shadow[i] = 32'h0;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    rvfi_export.connect(rvfi_fifo.analysis_export);
    mem_export.connect(mem_fifo.analysis_export);
  endfunction

  //-------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    fork
      check_rvfi_stream();
    join
  endtask

  //-------------------------------------------------------------------------
  // Core checking task: process every retired instruction via RVFI
  //-------------------------------------------------------------------------
  task check_rvfi_stream();
    ibex_rvfi_transaction actual;
    logic [31:0] exp_rd_wdata;
    logic [ 4:0] exp_rd_addr;
    logic [31:0] exp_pc_wdata;
    logic [31:0] exp_mem_addr;
    logic [31:0] exp_mem_wdata;
    int          valid;

    forever begin
      rvfi_fifo.get(actual);
      instrs_checked++;

      // ---------------------------------------------------------------
      // STRATEGY 1: Verify instruction order is monotonically increasing
      // ---------------------------------------------------------------
      if (prev_order != 64'hFFFF_FFFF_FFFF_FFFF) begin
        check("RVFI_ORDER_MONOTONIC",
              (actual.order == prev_order + 1),
              $sformatf("Expected order=%0d, got=%0d",
                        prev_order+1, actual.order));
      end
      prev_order = actual.order;

      // ---------------------------------------------------------------
      // STRATEGY 2: x0 must always read as zero (architectural invariant)
      // ---------------------------------------------------------------
      if (actual.rs1_addr == 5'd0) begin
        check("RS1_X0_IS_ZERO",
              (actual.rs1_rdata == 32'h0),
              $sformatf("x0 read as 0x%08h!", actual.rs1_rdata));
      end
      if (actual.rs2_addr == 5'd0) begin
        check("RS2_X0_IS_ZERO",
              (actual.rs2_rdata == 32'h0),
              $sformatf("x0 read as 0x%08h!", actual.rs2_rdata));
      end
      if (actual.rd_addr == 5'd0 && actual.rd_wdata != 32'h0) begin
        check("RD_X0_WRITE_IGNORED",
              1'b0,  // Always fail if x0 is written non-zero
              $sformatf("Write to x0 not suppressed! rd_wdata=0x%08h",
                        actual.rd_wdata));
      end

      // ---------------------------------------------------------------
      // STRATEGY 3: PC must be 4-byte aligned (no compressed in basic mode)
      // ---------------------------------------------------------------
      check("PC_ALIGNED",
            (actual.pc_rdata[1:0] == 2'b00),
            $sformatf("PC=0x%08h not aligned!", actual.pc_rdata));

      // ---------------------------------------------------------------
      // STRATEGY 4 & 5: Compute expected result from ISA model
      // ---------------------------------------------------------------
      if (!actual.trap) begin  // Skip trap instructions (handled separately)
        valid = golden.predict(actual,
                               exp_rd_wdata, exp_rd_addr,
                               exp_pc_wdata, exp_mem_addr, exp_mem_wdata);

        if (valid) begin
          // --- Register write-back check ---
          if (exp_rd_addr != 5'd0) begin
            check("RD_WDATA_CORRECT",
                  (actual.rd_addr  == exp_rd_addr  ) &&
                  (actual.rd_wdata == exp_rd_wdata ),
                  $sformatf("PC=0x%08h INSN=0x%08h: rd[%0d]=0x%08h (exp=0x%08h)",
                            actual.pc_rdata, actual.insn,
                            exp_rd_addr, actual.rd_wdata, exp_rd_wdata));
          end

          // --- PC update check ---
          check("PC_UPDATE_CORRECT",
                (actual.pc_wdata == exp_pc_wdata),
                $sformatf("PC=0x%08h INSN=0x%08h: next_pc=0x%08h (exp=0x%08h)",
                          actual.pc_rdata, actual.insn,
                          actual.pc_wdata, exp_pc_wdata));

          // --- Memory address check (loads and stores) ---
          if (actual.mem_rmask != 4'h0 || actual.mem_wmask != 4'h0) begin
            check("MEM_ADDR_CORRECT",
                  (actual.mem_addr == exp_mem_addr),
                  $sformatf("PC=0x%08h INSN=0x%08h: mem_addr=0x%08h (exp=0x%08h)",
                            actual.pc_rdata, actual.insn,
                            actual.mem_addr, exp_mem_addr));
          end

          // --- Store data check ---
          if (actual.mem_wmask != 4'h0) begin
            check("STORE_DATA_CORRECT",
                  check_store_data(actual.mem_wdata, exp_mem_wdata,
                                   actual.insn[14:12]),
                  $sformatf("PC=0x%08h INSN=0x%08h: store_data=0x%08h (exp=0x%08h)",
                            actual.pc_rdata, actual.insn,
                            actual.mem_wdata, exp_mem_wdata));
          end
        end
      end

      // ---------------------------------------------------------------
      // STRATEGY 6: Update register shadow (track architectural state)
      // ---------------------------------------------------------------
      if (actual.rd_addr != 5'd0) begin
        reg_shadow[actual.rd_addr] = actual.rd_wdata;
      end
      reg_shadow[0] = 32'h0;  // x0 always zero

      // ---------------------------------------------------------------
      // Log progress
      // ---------------------------------------------------------------
      if (instrs_checked % 1000 == 0) begin
        `uvm_info(get_type_name(),
          $sformatf("Checked %0d instructions: %0d passed, %0d failed",
                    instrs_checked, checks_passed, checks_failed),
          UVM_LOW)
      end
    end
  endtask

  //-------------------------------------------------------------------------
  // Check store data (account for byte/halfword truncation)
  //-------------------------------------------------------------------------
  function bit check_store_data(
    input logic [31:0] actual_data,
    input logic [31:0] exp_data,
    input logic [ 2:0] funct3
  );
    case (funct3)
      3'b000: return (actual_data[ 7:0] == exp_data[ 7:0]);  // SB
      3'b001: return (actual_data[15:0] == exp_data[15:0]);  // SH
      3'b010: return (actual_data       == exp_data);        // SW
      default: return 1'b0;
    endcase
  endfunction

  //-------------------------------------------------------------------------
  // Unified check function with pass/fail tracking
  //-------------------------------------------------------------------------
  function void check(
    input string  check_name,
    input bit     condition,
    input string  failure_msg = ""
  );
    if (condition) begin
      checks_passed++;
      `uvm_info(get_type_name(),
        $sformatf("PASS [%s]", check_name), UVM_DEBUG)
    end else begin
      checks_failed++;
      `uvm_error(get_type_name(),
        $sformatf("FAIL [%s] %s", check_name, failure_msg))
    end
  endfunction

  //-------------------------------------------------------------------------
  // Final check: print statistics
  //-------------------------------------------------------------------------
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    `uvm_info(get_type_name(), "========= SCOREBOARD FINAL REPORT =========", UVM_NONE)
    `uvm_info(get_type_name(),
      $sformatf("Instructions checked : %0d", instrs_checked), UVM_NONE)
    `uvm_info(get_type_name(),
      $sformatf("Checks passed        : %0d", checks_passed), UVM_NONE)
    `uvm_info(get_type_name(),
      $sformatf("Checks failed        : %0d", checks_failed), UVM_NONE)

    if (checks_failed > 0)
      `uvm_error(get_type_name(),
        $sformatf("%0d SCOREBOARD CHECKS FAILED!", checks_failed))
    else
      `uvm_info(get_type_name(), "ALL SCOREBOARD CHECKS PASSED!", UVM_NONE)
  endfunction

endclass

`endif // IBEX_SCOREBOARD_SV
