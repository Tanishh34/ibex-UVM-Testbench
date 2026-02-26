//=============================================================================
// File: ibex_transaction.sv
// Description: UVM Transaction for Ibex RISC-V Core Verification
//   Captures instruction fetch, data memory, and register file activity
//=============================================================================

`ifndef IBEX_TRANSACTION_SV
`define IBEX_TRANSACTION_SV

class ibex_transaction extends uvm_sequence_item;
  `uvm_object_utils_begin(ibex_transaction)
    `uvm_field_int(instr_addr,      UVM_ALL_ON)
    `uvm_field_int(instr_data,      UVM_ALL_ON)
    `uvm_field_int(data_addr,       UVM_ALL_ON)
    `uvm_field_int(data_wdata,      UVM_ALL_ON)
    `uvm_field_int(data_rdata,      UVM_ALL_ON)
    `uvm_field_int(data_we,         UVM_ALL_ON)
    `uvm_field_int(data_be,         UVM_ALL_ON)
    `uvm_field_int(data_req,        UVM_ALL_ON)
    `uvm_field_int(instr_req,       UVM_ALL_ON)
    `uvm_field_int(rst_ni,          UVM_ALL_ON)
    `uvm_field_int(pc_id,           UVM_ALL_ON)
    `uvm_field_int(pc_if,           UVM_ALL_ON)
    `uvm_field_enum(trans_type_e, trans_type, UVM_ALL_ON)
  `uvm_object_utils_end

  //-------------------------------------------------------------------------
  // Transaction Types
  //-------------------------------------------------------------------------
  typedef enum {
    INSTR_FETCH,      // Instruction fetch transaction
    DATA_LOAD,        // Load from memory
    DATA_STORE,       // Store to memory
    RESET_TRANS,      // Reset assertion/deassertion
    IRQ_TRANS,        // Interrupt transaction
    DEBUG_TRANS       // Debug request
  } trans_type_e;

  //-------------------------------------------------------------------------
  // Instruction Fetch Interface Fields
  //-------------------------------------------------------------------------
  rand logic [31:0] instr_addr;           // Instruction fetch address
  rand logic [31:0] instr_data;           // Instruction word (RISC-V encoding)
       logic        instr_req;            // Instruction fetch request
       logic        instr_gnt;            // Instruction fetch grant
       logic        instr_rvalid;         // Instruction fetch data valid
       logic        instr_err;            // Instruction fetch error

  //-------------------------------------------------------------------------
  // Data Memory Interface Fields
  //-------------------------------------------------------------------------
  rand logic [31:0] data_addr;            // Data memory address
  rand logic [31:0] data_wdata;           // Write data
       logic [31:0] data_rdata;           // Read data
  rand logic        data_we;             // Write enable
  rand logic [ 3:0] data_be;             // Byte enable
       logic        data_req;            // Data memory request
       logic        data_gnt;            // Data memory grant
       logic        data_rvalid;         // Data memory read valid
       logic        data_err;            // Data memory error

  //-------------------------------------------------------------------------
  // Control/Status Fields
  //-------------------------------------------------------------------------
       logic        rst_ni;              // Active-low reset
       logic [31:0] pc_if;              // PC in IF stage
       logic [31:0] pc_id;              // PC in ID stage
       trans_type_e trans_type;         // Transaction classification

  //-------------------------------------------------------------------------
  // Interrupt and Debug Fields
  //-------------------------------------------------------------------------
  rand logic [14:0] irq;               // Interrupts
  rand logic        irq_nm;            // Non-maskable interrupt
  rand logic        debug_req;         // Debug request

  //-------------------------------------------------------------------------
  // Expected Results (filled by predictor/scoreboard)
  //-------------------------------------------------------------------------
       logic [31:0] exp_rd_data;        // Expected register write-back data
       logic [ 4:0] exp_rd_addr;        // Expected destination register
       logic        exp_rd_we;          // Expected register write enable
       logic [31:0] exp_next_pc;        // Expected next PC value

  //-------------------------------------------------------------------------
  // Constraints
  //-------------------------------------------------------------------------
  // RISC-V instructions must be 4-byte aligned
  constraint instr_aligned_c {
    instr_addr[1:0] == 2'b00;
  }

  // Data addresses within a reasonable memory map (avoid peripherals)
  constraint data_addr_range_c {
    data_addr inside {[32'h0000_0000 : 32'h0FFF_FFFF]};
  }

  // Only allow valid byte enables for different access widths
  constraint data_be_valid_c {
    data_be inside {4'b0001, 4'b0011, 4'b1111,
                    4'b0010, 4'b0100, 4'b1000,
                    4'b1100, 4'b0110};
  }

  //-------------------------------------------------------------------------
  // Helper Functions
  //-------------------------------------------------------------------------
  // Decode RISC-V opcode from instruction data
  function logic [6:0] get_opcode();
    return instr_data[6:0];
  endfunction

  // Check if instruction is R-type
  function logic is_r_type();
    return (instr_data[6:0] == 7'b0110011);
  endfunction

  // Check if instruction is I-type (LOAD)
  function logic is_load();
    return (instr_data[6:0] == 7'b0000011);
  endfunction

  // Check if instruction is S-type (STORE)
  function logic is_store();
    return (instr_data[6:0] == 7'b0100011);
  endfunction

  // Check if instruction is branch
  function logic is_branch();
    return (instr_data[6:0] == 7'b1100011);
  endfunction

  // Check if instruction is JAL
  function logic is_jal();
    return (instr_data[6:0] == 7'b1101111);
  endfunction

  // Check if instruction is JALR
  function logic is_jalr();
    return (instr_data[6:0] == 7'b1100111);
  endfunction

  // Extract rs1
  function logic [4:0] get_rs1();
    return instr_data[19:15];
  endfunction

  // Extract rs2
  function logic [4:0] get_rs2();
    return instr_data[24:20];
  endfunction

  // Extract rd
  function logic [4:0] get_rd();
    return instr_data[11:7];
  endfunction

  // Extract funct3
  function logic [2:0] get_funct3();
    return instr_data[14:12];
  endfunction

  // Extract funct7
  function logic [6:0] get_funct7();
    return instr_data[31:25];
  endfunction

  // Sign-extended I-type immediate
  function logic signed [31:0] get_imm_i();
    return {{20{instr_data[31]}}, instr_data[31:20]};
  endfunction

  // Sign-extended S-type immediate
  function logic signed [31:0] get_imm_s();
    return {{20{instr_data[31]}}, instr_data[31:25], instr_data[11:7]};
  endfunction

  // Sign-extended B-type immediate (branch offset)
  function logic signed [31:0] get_imm_b();
    return {{19{instr_data[31]}}, instr_data[31], instr_data[7],
            instr_data[30:25], instr_data[11:8], 1'b0};
  endfunction

  // U-type immediate
  function logic [31:0] get_imm_u();
    return {instr_data[31:12], 12'b0};
  endfunction

  // Sign-extended J-type immediate (JAL offset)
  function logic signed [31:0] get_imm_j();
    return {{11{instr_data[31]}}, instr_data[31], instr_data[19:12],
            instr_data[20], instr_data[30:21], 1'b0};
  endfunction

  function new(string name = "ibex_transaction");
    super.new(name);
  endfunction

  // Custom print for debugging
  function string convert2string();
    return $sformatf(
      "TRANS[%s] PC=0x%08h INSTR=0x%08h DATA_ADDR=0x%08h DATA=%0s",
      trans_type.name(), instr_addr, instr_data, data_addr,
      data_we ? $sformatf("WR=0x%08h BE=%04b", data_wdata, data_be)
              : $sformatf("RD=0x%08h", data_rdata)
    );
  endfunction

endclass

`endif // IBEX_TRANSACTION_SV
