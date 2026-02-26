//=============================================================================
// File: ibex_sequences.sv
// Description: UVM Sequences for Ibex Core Verification
//   Covers: Reset, R-type, I-type, Load/Store, Branch, Jump, Hazard,
//           CSR access, Interrupt injection, and more.
//=============================================================================

`ifndef IBEX_SEQUENCES_SV
`define IBEX_SEQUENCES_SV

//=============================================================================
// Base Sequence
//=============================================================================
class ibex_base_seq extends uvm_sequence #(ibex_transaction);
  `uvm_object_utils(ibex_base_seq)

  function new(string name = "ibex_base_seq");
    super.new(name);
  endfunction

  // Build a NOP instruction (ADDI x0, x0, 0)
  function ibex_transaction make_nop(input logic [31:0] pc);
    ibex_transaction tr = ibex_transaction::type_id::create("nop");
    tr.instr_addr  = pc;
    tr.instr_data  = 32'h0000_0013;  // ADDI x0, x0, 0
    tr.trans_type  = ibex_transaction::INSTR_FETCH;
    return tr;
  endfunction

  // Build an R-type instruction
  function ibex_transaction make_r_type(
    input logic [31:0] pc,
    input logic [ 4:0] rd, rs1, rs2,
    input logic [ 2:0] funct3,
    input logic [ 6:0] funct7
  );
    ibex_transaction tr = ibex_transaction::type_id::create("r_type");
    tr.instr_addr = pc;
    tr.instr_data = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
    tr.trans_type = ibex_transaction::INSTR_FETCH;
    return tr;
  endfunction

  // Build an I-type instruction (ADDI/SLTI/ANDI/ORI/XORI/SLLI/SRLI/SRAI)
  function ibex_transaction make_i_type(
    input logic [31:0] pc,
    input logic [ 4:0] rd, rs1,
    input logic [11:0] imm,
    input logic [ 2:0] funct3
  );
    ibex_transaction tr = ibex_transaction::type_id::create("i_type");
    tr.instr_addr = pc;
    tr.instr_data = {imm, rs1, funct3, rd, 7'b0010011};
    tr.trans_type = ibex_transaction::INSTR_FETCH;
    return tr;
  endfunction

  // Build a LOAD instruction (LW/LH/LB/LHU/LBU)
  function ibex_transaction make_load(
    input logic [31:0] pc,
    input logic [ 4:0] rd, rs1,
    input logic [11:0] offset,
    input logic [ 2:0] funct3  // 000=LB, 001=LH, 010=LW, 100=LBU, 101=LHU
  );
    ibex_transaction tr = ibex_transaction::type_id::create("load");
    tr.instr_addr = pc;
    tr.instr_data = {offset, rs1, funct3, rd, 7'b0000011};
    tr.trans_type = ibex_transaction::INSTR_FETCH;
    return tr;
  endfunction

  // Build a STORE instruction (SW/SH/SB)
  function ibex_transaction make_store(
    input logic [31:0] pc,
    input logic [ 4:0] rs1, rs2,
    input logic [11:0] offset,
    input logic [ 2:0] funct3  // 000=SB, 001=SH, 010=SW
  );
    ibex_transaction tr = ibex_transaction::type_id::create("store");
    tr.instr_addr  = pc;
    tr.instr_data  = {offset[11:5], rs2, rs1, funct3, offset[4:0], 7'b0100011};
    tr.trans_type  = ibex_transaction::INSTR_FETCH;
    return tr;
  endfunction

  // Build a BRANCH instruction
  function ibex_transaction make_branch(
    input logic [31:0] pc,
    input logic [ 4:0] rs1, rs2,
    input logic [12:0] offset,  // Byte offset, bit 0 always 0
    input logic [ 2:0] funct3   // 000=BEQ,001=BNE,100=BLT,101=BGE,110=BLTU,111=BGEU
  );
    ibex_transaction tr = ibex_transaction::type_id::create("branch");
    tr.instr_addr = pc;
    tr.instr_data = {offset[12], offset[10:5], rs2, rs1, funct3,
                     offset[4:1], offset[11], 7'b1100011};
    tr.trans_type = ibex_transaction::INSTR_FETCH;
    return tr;
  endfunction

  // Build a LUI instruction
  function ibex_transaction make_lui(
    input logic [31:0] pc,
    input logic [ 4:0] rd,
    input logic [19:0] imm_upper  // Upper 20 bits
  );
    ibex_transaction tr = ibex_transaction::type_id::create("lui");
    tr.instr_addr = pc;
    tr.instr_data = {imm_upper, rd, 7'b0110111};
    tr.trans_type = ibex_transaction::INSTR_FETCH;
    return tr;
  endfunction

  // Build a JAL instruction
  function ibex_transaction make_jal(
    input logic [31:0] pc,
    input logic [ 4:0] rd,
    input logic [20:0] offset  // Byte offset
  );
    ibex_transaction tr = ibex_transaction::type_id::create("jal");
    tr.instr_addr = pc;
    tr.instr_data = {offset[20], offset[10:1], offset[11],
                     offset[19:12], rd, 7'b1101111};
    tr.trans_type = ibex_transaction::INSTR_FETCH;
    return tr;
  endfunction

  // Build a JALR instruction
  function ibex_transaction make_jalr(
    input logic [31:0] pc,
    input logic [ 4:0] rd, rs1,
    input logic [11:0] offset
  );
    ibex_transaction tr = ibex_transaction::type_id::create("jalr");
    tr.instr_addr = pc;
    tr.instr_data = {offset, rs1, 3'b000, rd, 7'b1100111};
    tr.trans_type = ibex_transaction::INSTR_FETCH;
    return tr;
  endfunction

endclass


//=============================================================================
// Reset Sequence
//=============================================================================
class ibex_reset_seq extends ibex_base_seq;
  `uvm_object_utils(ibex_reset_seq)

  int unsigned reset_cycles = 10;

  function new(string name = "ibex_reset_seq");
    super.new(name);
  endfunction

  task body();
    ibex_transaction tr;
    `uvm_info(get_type_name(), "Applying reset sequence", UVM_MEDIUM)

    tr = ibex_transaction::type_id::create("reset_tr");
    tr.trans_type = ibex_transaction::RESET_TRANS;
    tr.rst_ni     = 1'b0;
    start_item(tr);
    finish_item(tr);

    `uvm_info(get_type_name(), $sformatf("Holding reset for %0d cycles", reset_cycles), UVM_LOW)
    repeat(reset_cycles) begin
      tr = ibex_transaction::type_id::create("reset_hold");
      tr.trans_type = ibex_transaction::RESET_TRANS;
      tr.rst_ni     = 1'b0;
      start_item(tr);
      finish_item(tr);
    end

    // Deassert reset
    tr = ibex_transaction::type_id::create("reset_release");
    tr.trans_type = ibex_transaction::RESET_TRANS;
    tr.rst_ni     = 1'b1;
    start_item(tr);
    finish_item(tr);
    `uvm_info(get_type_name(), "Reset released", UVM_MEDIUM)
  endtask

endclass


//=============================================================================
// ALU R-Type Sequence: exercises all ALU operations
//=============================================================================
class ibex_alu_rtype_seq extends ibex_base_seq;
  `uvm_object_utils(ibex_alu_rtype_seq)

  function new(string name = "ibex_alu_rtype_seq");
    super.new(name);
  endfunction

  task body();
    ibex_transaction tr;
    logic [31:0] pc = 32'h0000_0000;

    // Initialize x1 = 0xDEAD_BEEF via LUI + ADDI
    tr = make_lui(pc, 5'd1, 20'hDEADB);   pc += 4;
    send_trans(tr);
    tr = make_i_type(pc, 5'd1, 5'd1, 12'hEEF, 3'b000); pc += 4; // ADDI
    send_trans(tr);

    // Initialize x2 = 0xCAFE_BABE
    tr = make_lui(pc, 5'd2, 20'hCAFEB); pc += 4;
    send_trans(tr);
    tr = make_i_type(pc, 5'd2, 5'd2, 12'hABE, 3'b000); pc += 4;
    send_trans(tr);

    // ADD x3, x1, x2
    tr = make_r_type(pc, 5'd3, 5'd1, 5'd2, 3'b000, 7'b0000000); pc += 4;
    send_trans(tr);

    // SUB x4, x1, x2
    tr = make_r_type(pc, 5'd4, 5'd1, 5'd2, 3'b000, 7'b0100000); pc += 4;
    send_trans(tr);

    // SLL x5, x1, x2 (shift left logical)
    tr = make_r_type(pc, 5'd5, 5'd1, 5'd2, 3'b001, 7'b0000000); pc += 4;
    send_trans(tr);

    // SLT x6, x1, x2 (set less than signed)
    tr = make_r_type(pc, 5'd6, 5'd1, 5'd2, 3'b010, 7'b0000000); pc += 4;
    send_trans(tr);

    // SLTU x7, x1, x2 (set less than unsigned)
    tr = make_r_type(pc, 5'd7, 5'd1, 5'd2, 3'b011, 7'b0000000); pc += 4;
    send_trans(tr);

    // XOR x8, x1, x2
    tr = make_r_type(pc, 5'd8, 5'd1, 5'd2, 3'b100, 7'b0000000); pc += 4;
    send_trans(tr);

    // SRL x9, x1, x2 (shift right logical)
    tr = make_r_type(pc, 5'd9, 5'd1, 5'd2, 3'b101, 7'b0000000); pc += 4;
    send_trans(tr);

    // SRA x10, x1, x2 (shift right arithmetic)
    tr = make_r_type(pc, 5'd10, 5'd1, 5'd2, 3'b101, 7'b0100000); pc += 4;
    send_trans(tr);

    // OR x11, x1, x2
    tr = make_r_type(pc, 5'd11, 5'd1, 5'd2, 3'b110, 7'b0000000); pc += 4;
    send_trans(tr);

    // AND x12, x1, x2
    tr = make_r_type(pc, 5'd12, 5'd1, 5'd2, 3'b111, 7'b0000000); pc += 4;
    send_trans(tr);

    // Pad with NOPs to flush pipeline
    repeat(5) begin
      tr = make_nop(pc); pc += 4;
      send_trans(tr);
    end
  endtask

  task send_trans(ibex_transaction tr);
    start_item(tr);
    finish_item(tr);
  endtask

endclass


//=============================================================================
// Load-Store Sequence
//=============================================================================
class ibex_load_store_seq extends ibex_base_seq;
  `uvm_object_utils(ibex_load_store_seq)

  logic [31:0] base_addr = 32'h0000_1000;

  function new(string name = "ibex_load_store_seq");
    super.new(name);
  endfunction

  task body();
    ibex_transaction tr;
    logic [31:0] pc = 32'h0000_0000;

    // Load base address into x1 = 0x1000
    tr = make_lui(pc, 5'd1, 20'h00001); pc += 4; send(tr);

    // --- STORE Tests ---
    // SW x2, 0(x1)   - Store word
    tr = make_store(pc, 5'd1, 5'd2, 12'h000, 3'b010); pc += 4; send(tr);
    // SH x2, 4(x1)   - Store halfword
    tr = make_store(pc, 5'd1, 5'd2, 12'h004, 3'b001); pc += 4; send(tr);
    // SB x2, 6(x1)   - Store byte
    tr = make_store(pc, 5'd1, 5'd2, 12'h006, 3'b000); pc += 4; send(tr);

    // --- LOAD Tests ---
    // LW x3, 0(x1)   - Load word
    tr = make_load(pc, 5'd3, 5'd1, 12'h000, 3'b010); pc += 4; send(tr);
    // LH x4, 4(x1)   - Load halfword (sign-extend)
    tr = make_load(pc, 5'd4, 5'd1, 12'h004, 3'b001); pc += 4; send(tr);
    // LHU x5, 4(x1)  - Load halfword unsigned
    tr = make_load(pc, 5'd5, 5'd1, 12'h004, 3'b101); pc += 4; send(tr);
    // LB x6, 6(x1)   - Load byte (sign-extend)
    tr = make_load(pc, 5'd6, 5'd1, 12'h006, 3'b000); pc += 4; send(tr);
    // LBU x7, 6(x1)  - Load byte unsigned
    tr = make_load(pc, 5'd7, 5'd1, 12'h006, 3'b100); pc += 4; send(tr);

    // --- Load-Use Hazard: LOAD followed immediately by dependent instruction ---
    // LW x8, 0(x1)
    tr = make_load(pc, 5'd8, 5'd1, 12'h000, 3'b010); pc += 4; send(tr);
    // ADD x9, x8, x2  <-- x8 loaded in previous instruction (1-cycle hazard)
    tr = make_r_type(pc, 5'd9, 5'd8, 5'd2, 3'b000, 7'b0000000); pc += 4; send(tr);

    // Flush pipeline
    repeat(5) begin tr = make_nop(pc); pc += 4; send(tr); end
  endtask

  task send(ibex_transaction tr);
    start_item(tr); finish_item(tr);
  endtask

endclass


//=============================================================================
// Control Flow Sequence: branches and jumps
//=============================================================================
class ibex_control_flow_seq extends ibex_base_seq;
  `uvm_object_utils(ibex_control_flow_seq)

  function new(string name = "ibex_control_flow_seq");
    super.new(name);
  endfunction

  task body();
    ibex_transaction tr;
    logic [31:0] pc = 32'h0000_0000;

    // Set x1 = 5, x2 = 5 (for equality test)
    tr = make_i_type(pc, 5'd1, 5'd0, 12'd5, 3'b000); pc += 4; send(tr); // ADDI x1,x0,5
    tr = make_i_type(pc, 5'd2, 5'd0, 12'd5, 3'b000); pc += 4; send(tr); // ADDI x2,x0,5

    // BEQ x1, x2, +8 (should be TAKEN)
    tr = make_branch(pc, 5'd1, 5'd2, 13'd8, 3'b000); pc += 4; send(tr);

    // This instruction should be skipped (branch target is pc+8)
    tr = make_nop(pc); pc += 4; send(tr);

    // Branch target: ADDI x3, x0, 1
    tr = make_i_type(pc, 5'd3, 5'd0, 12'd1, 3'b000); pc += 4; send(tr);

    // Set x4 = 3, x5 = 7
    tr = make_i_type(pc, 5'd4, 5'd0, 12'd3, 3'b000); pc += 4; send(tr);
    tr = make_i_type(pc, 5'd5, 5'd0, 12'd7, 3'b000); pc += 4; send(tr);

    // BNE x4, x5, +8 (should be TAKEN: 3 != 7)
    tr = make_branch(pc, 5'd4, 5'd5, 13'd8, 3'b001); pc += 4; send(tr);

    // Should be skipped
    tr = make_nop(pc); pc += 4; send(tr);
    // Target
    tr = make_i_type(pc, 5'd6, 5'd0, 12'd2, 3'b000); pc += 4; send(tr);

    // JAL x10, +12 (jump and link, rd=x10 gets PC+4)
    tr = make_jal(pc, 5'd10, 21'd12); pc += 4; send(tr);

    // Should be skipped (target is pc+12)
    tr = make_nop(pc); pc += 4; send(tr);
    tr = make_nop(pc); pc += 4; send(tr);

    // JAL target
    tr = make_i_type(pc, 5'd11, 5'd0, 12'd99, 3'b000); pc += 4; send(tr);

    // JALR x0, x10, 0 (return to after the JAL)
    tr = make_jalr(pc, 5'd0, 5'd10, 12'd0); pc += 4; send(tr);

    repeat(5) begin tr = make_nop(pc); pc += 4; send(tr); end
  endtask

  task send(ibex_transaction tr);
    start_item(tr); finish_item(tr);
  endtask

endclass


//=============================================================================
// Data Hazard / Forwarding Sequence
//   Tests RAW hazards to verify forwarding paths work correctly
//=============================================================================
class ibex_hazard_forwarding_seq extends ibex_base_seq;
  `uvm_object_utils(ibex_hazard_forwarding_seq)

  function new(string name = "ibex_hazard_forwarding_seq");
    super.new(name);
  endfunction

  task body();
    ibex_transaction tr;
    logic [31:0] pc = 32'h0000_0000;

    // Initialize x1 = 10
    tr = make_i_type(pc, 5'd1, 5'd0, 12'd10, 3'b000); pc += 4; send(tr);

    // --- EX-EX Forwarding (back-to-back RAW) ---
    // ADD x2, x1, x1    -> x2 = 20  (x1 used immediately)
    tr = make_r_type(pc, 5'd2, 5'd1, 5'd1, 3'b000, 7'h00); pc += 4; send(tr);
    // ADD x3, x2, x2    -> x3 = 40  (x2 just written - EX-EX forward)
    tr = make_r_type(pc, 5'd3, 5'd2, 5'd2, 3'b000, 7'h00); pc += 4; send(tr);
    // ADD x4, x3, x3    -> x4 = 80  (another EX-EX forward)
    tr = make_r_type(pc, 5'd4, 5'd3, 5'd3, 3'b000, 7'h00); pc += 4; send(tr);

    // --- MEM-EX Forwarding (1-instruction gap) ---
    tr = make_r_type(pc, 5'd5, 5'd1, 5'd1, 3'b000, 7'h00); pc += 4; send(tr); // x5 = 20
    tr = make_nop(pc); pc += 4; send(tr);    // 1-cycle gap
    tr = make_r_type(pc, 5'd6, 5'd5, 5'd1, 3'b000, 7'h00); pc += 4; send(tr); // x6 = 30 (MEM-EX)

    // --- Write-After-Write (WAW) Hazard ---
    // x7 written twice in a row - second write should "win"
    tr = make_i_type(pc, 5'd7, 5'd0, 12'd111, 3'b000); pc += 4; send(tr); // x7 = 111
    tr = make_i_type(pc, 5'd7, 5'd0, 12'd222, 3'b000); pc += 4; send(tr); // x7 = 222 (winner)
    // Read x7 - should get 222
    tr = make_r_type(pc, 5'd8, 5'd7, 5'd0, 3'b000, 7'h00); pc += 4; send(tr);

    // --- Write to x0 (should always read back 0) ---
    tr = make_i_type(pc, 5'd0, 5'd0, 12'hFFF, 3'b000); pc += 4; send(tr); // ADDI x0 = -1 (illegal write)
    tr = make_r_type(pc, 5'd9, 5'd0, 5'd0, 3'b000, 7'h00); pc += 4; send(tr); // x9 = x0+x0 must be 0

    repeat(5) begin tr = make_nop(pc); pc += 4; send(tr); end
  endtask

  task send(ibex_transaction tr);
    start_item(tr); finish_item(tr);
  endtask

endclass


//=============================================================================
// Interrupt Sequence
//=============================================================================
class ibex_interrupt_seq extends ibex_base_seq;
  `uvm_object_utils(ibex_interrupt_seq)

  function new(string name = "ibex_interrupt_seq");
    super.new(name);
  endfunction

  task body();
    ibex_transaction tr;
    logic [31:0] pc = 32'h0000_0000;

    // Run some instructions before interrupt
    repeat(10) begin
      tr = make_nop(pc); pc += 4; send(tr);
    end

    // Assert timer interrupt
    tr = ibex_transaction::type_id::create("irq_tr");
    tr.trans_type  = ibex_transaction::IRQ_TRANS;
    tr.instr_addr  = pc;
    tr.instr_data  = 32'h0000_0013; // NOP
    tr.irq         = 15'h0080;  // Timer interrupt bit
    start_item(tr);
    finish_item(tr);

    // Continue with more NOPs (interrupt should be taken)
    repeat(20) begin
      tr = make_nop(pc); pc += 4; send(tr);
    end

    // De-assert interrupt
    tr = ibex_transaction::type_id::create("irq_clear");
    tr.trans_type  = ibex_transaction::IRQ_TRANS;
    tr.instr_addr  = pc;
    tr.instr_data  = 32'h0000_0013;
    tr.irq         = 15'h0000;
    start_item(tr);
    finish_item(tr);
  endtask

  task send(ibex_transaction tr);
    start_item(tr); finish_item(tr);
  endtask

endclass


//=============================================================================
// Random Instruction Sequence
//   Generates random but legal RISC-V instructions via randomization
//=============================================================================
class ibex_random_instr_seq extends ibex_base_seq;
  `uvm_object_utils(ibex_random_instr_seq)

  int unsigned num_instructions = 100;
  logic [31:0] start_pc         = 32'h0;

  // Weight table for instruction mix
  int unsigned r_type_weight   = 30;
  int unsigned i_type_weight   = 25;
  int unsigned load_weight     = 15;
  int unsigned store_weight    = 15;
  int unsigned branch_weight   = 10;
  int unsigned jal_weight      = 5;

  function new(string name = "ibex_random_instr_seq");
    super.new(name);
  endfunction

  task body();
    ibex_transaction tr;
    logic [31:0] pc = start_pc;
    int          pick;

    repeat(num_instructions) begin
      tr = ibex_transaction::type_id::create("rand_tr");
      assert(tr.randomize()) else `uvm_fatal(get_type_name(), "Randomization failed")
      tr.instr_addr = pc;
      tr.trans_type = ibex_transaction::INSTR_FETCH;
      // Force alignment
      tr.instr_addr[1:0] = 2'b00;

      start_item(tr);
      finish_item(tr);
      pc += 4;
    end

    // Flush
    repeat(10) begin
      tr = make_nop(pc); pc += 4;
      start_item(tr); finish_item(tr);
    end
  endtask

endclass


//=============================================================================
// CSR Access Sequence
//   Tests reads/writes to mstatus, mie, mtvec, mepc, mcause, mip, mcycle, minstret
//=============================================================================
class ibex_csr_access_seq extends ibex_base_seq;
  `uvm_object_utils(ibex_csr_access_seq)

  // CSR addresses (RISC-V spec)
  localparam CSR_MSTATUS  = 12'h300;
  localparam CSR_MISA     = 12'h301;
  localparam CSR_MIE      = 12'h304;
  localparam CSR_MTVEC    = 12'h305;
  localparam CSR_MEPC     = 12'h341;
  localparam CSR_MCAUSE   = 12'h342;
  localparam CSR_MTVAL    = 12'h343;
  localparam CSR_MIP      = 12'h344;
  localparam CSR_MCYCLE   = 12'hB00;
  localparam CSR_MINSTRET = 12'hB02;

  function new(string name = "ibex_csr_access_seq");
    super.new(name);
  endfunction

  // CSRRW rd, csr, rs1
  function ibex_transaction make_csrrw(
    input logic [31:0] pc,
    input logic [ 4:0] rd, rs1,
    input logic [11:0] csr_addr
  );
    ibex_transaction tr = ibex_transaction::type_id::create("csrrw");
    tr.instr_addr = pc;
    tr.instr_data = {csr_addr, rs1, 3'b001, rd, 7'b1110011};
    tr.trans_type = ibex_transaction::INSTR_FETCH;
    return tr;
  endfunction

  // CSRRS rd, csr, rs1 (read-set)
  function ibex_transaction make_csrrs(
    input logic [31:0] pc,
    input logic [ 4:0] rd, rs1,
    input logic [11:0] csr_addr
  );
    ibex_transaction tr = ibex_transaction::type_id::create("csrrs");
    tr.instr_addr = pc;
    tr.instr_data = {csr_addr, rs1, 3'b010, rd, 7'b1110011};
    tr.trans_type = ibex_transaction::INSTR_FETCH;
    return tr;
  endfunction

  // CSRRC rd, csr, rs1 (read-clear)
  function ibex_transaction make_csrrc(
    input logic [31:0] pc,
    input logic [ 4:0] rd, rs1,
    input logic [11:0] csr_addr
  );
    ibex_transaction tr = ibex_transaction::type_id::create("csrrc");
    tr.instr_addr = pc;
    tr.instr_data = {csr_addr, rs1, 3'b011, rd, 7'b1110011};
    tr.trans_type = ibex_transaction::INSTR_FETCH;
    return tr;
  endfunction

  task body();
    ibex_transaction tr;
    logic [31:0] pc = 32'h0000_0000;

    // Initialize x1 with test pattern
    tr = make_lui(pc, 5'd1, 20'hAAAAA); pc += 4; send(tr);

    // CSRRW x2, mtvec, x1  (set trap vector, read old value into x2)
    tr = make_csrrw(pc, 5'd2, 5'd1, CSR_MTVEC); pc += 4; send(tr);

    // CSRRS x3, mstatus, x0  (read mstatus)
    tr = make_csrrs(pc, 5'd3, 5'd0, CSR_MSTATUS); pc += 4; send(tr);

    // CSRRS x4, mie, x1  (set interrupt enables)
    tr = make_csrrs(pc, 5'd4, 5'd1, CSR_MIE); pc += 4; send(tr);

    // CSRRC x5, mie, x1  (clear interrupt enables)
    tr = make_csrrc(pc, 5'd5, 5'd1, CSR_MIE); pc += 4; send(tr);

    // Read cycle counter
    tr = make_csrrs(pc, 5'd6, 5'd0, CSR_MCYCLE); pc += 4; send(tr);

    // Read instret counter
    tr = make_csrrs(pc, 5'd7, 5'd0, CSR_MINSTRET); pc += 4; send(tr);

    repeat(5) begin tr = make_nop(pc); pc += 4; send(tr); end
  endtask

  task send(ibex_transaction tr);
    start_item(tr); finish_item(tr);
  endtask

endclass

`endif // IBEX_SEQUENCES_SV
