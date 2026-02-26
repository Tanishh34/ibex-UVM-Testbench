//=============================================================================
// File: ibex_monitor.sv
// Description: UVM Monitor for Ibex Core
//   Uses RVFI (RISC-V Formal Interface) to observe retired instructions.
//   RVFI gives us a ground-truth retirement stream independent of pipeline.
//   Also monitors memory interface activity and alert signals.
//=============================================================================

`ifndef IBEX_MONITOR_SV
`define IBEX_MONITOR_SV

// Analysis port transaction - enriched with RVFI data
class ibex_rvfi_transaction extends uvm_sequence_item;
  `uvm_object_utils_begin(ibex_rvfi_transaction)
    `uvm_field_int(order,       UVM_ALL_ON)
    `uvm_field_int(insn,        UVM_ALL_ON)
    `uvm_field_int(trap,        UVM_ALL_ON)
    `uvm_field_int(halt,        UVM_ALL_ON)
    `uvm_field_int(intr,        UVM_ALL_ON)
    `uvm_field_int(rs1_addr,    UVM_ALL_ON)
    `uvm_field_int(rs2_addr,    UVM_ALL_ON)
    `uvm_field_int(rs1_rdata,   UVM_ALL_ON)
    `uvm_field_int(rs2_rdata,   UVM_ALL_ON)
    `uvm_field_int(rd_addr,     UVM_ALL_ON)
    `uvm_field_int(rd_wdata,    UVM_ALL_ON)
    `uvm_field_int(pc_rdata,    UVM_ALL_ON)
    `uvm_field_int(pc_wdata,    UVM_ALL_ON)
    `uvm_field_int(mem_addr,    UVM_ALL_ON)
    `uvm_field_int(mem_rmask,   UVM_ALL_ON)
    `uvm_field_int(mem_wmask,   UVM_ALL_ON)
    `uvm_field_int(mem_rdata,   UVM_ALL_ON)
    `uvm_field_int(mem_wdata,   UVM_ALL_ON)
    `uvm_field_int(ext_mcycle,  UVM_ALL_ON)
  `uvm_object_utils_end

  logic [63:0] order;        // Retirement order (monotonic counter)
  logic [31:0] insn;         // Retired instruction word
  logic        trap;         // Instruction caused trap
  logic        halt;         // Core halted
  logic        intr;         // Interrupt was taken
  logic [ 1:0] mode;         // Privilege mode
  logic [ 4:0] rs1_addr;     // Source register 1 address
  logic [ 4:0] rs2_addr;     // Source register 2 address
  logic [31:0] rs1_rdata;    // Source register 1 value (before instruction)
  logic [31:0] rs2_rdata;    // Source register 2 value (before instruction)
  logic [ 4:0] rd_addr;      // Destination register address
  logic [31:0] rd_wdata;     // Value written to rd (actual hardware result)
  logic [31:0] pc_rdata;     // PC of this instruction
  logic [31:0] pc_wdata;     // Next PC after this instruction
  logic [31:0] mem_addr;     // Memory address accessed (load/store)
  logic [ 3:0] mem_rmask;    // Memory read byte mask
  logic [ 3:0] mem_wmask;    // Memory write byte mask
  logic [31:0] mem_rdata;    // Data read from memory
  logic [31:0] mem_wdata;    // Data written to memory
  logic [63:0] ext_mcycle;   // mcycle CSR value at retirement

  function new(string name = "ibex_rvfi_transaction");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf(
      "RVFI[%0d] PC=0x%08h INSN=0x%08h rd[%0d]=0x%08h pc'=0x%08h%s%s",
      order, pc_rdata, insn, rd_addr, rd_wdata, pc_wdata,
      trap ? " TRAP" : "",
      intr ? " INTR" : ""
    );
  endfunction

endclass


//=============================================================================
// Main Monitor Class
//=============================================================================
class ibex_monitor extends uvm_monitor;
  `uvm_component_utils(ibex_monitor)

  // Virtual interface
  virtual ibex_if vif;

  // Analysis ports
  uvm_analysis_port #(ibex_rvfi_transaction) rvfi_ap;      // Retired instructions
  uvm_analysis_port #(ibex_transaction)      mem_ap;       // Memory transactions
  uvm_analysis_port #(ibex_transaction)      alert_ap;     // Alert signals

  // Coverage
  ibex_rvfi_coverage  cov;

  //-------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual ibex_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "Could not get vif from config DB")

    rvfi_ap  = new("rvfi_ap",  this);
    mem_ap   = new("mem_ap",   this);
    alert_ap = new("alert_ap", this);

    cov = ibex_rvfi_coverage::type_id::create("cov", this);
  endfunction

  //-------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    fork
      monitor_rvfi();
      monitor_memory_interface();
      monitor_alerts();
    join
  endtask

  //-------------------------------------------------------------------------
  // Monitor RVFI retirement port - primary verification interface
  //   Every valid RVFI beat represents one retired instruction
  //-------------------------------------------------------------------------
  task monitor_rvfi();
    ibex_rvfi_transaction rvfi_tr;

    forever begin
      @(vif.monitor_cb);

      // Skip if in reset
      if (!vif.monitor_cb.rst_ni) continue;

      // Check for valid retirement
      if (vif.monitor_cb.rvfi_valid) begin
        rvfi_tr = ibex_rvfi_transaction::type_id::create("rvfi_tr");

        rvfi_tr.order     = vif.monitor_cb.rvfi_order;
        rvfi_tr.insn      = vif.monitor_cb.rvfi_insn;
        rvfi_tr.trap      = vif.monitor_cb.rvfi_trap;
        rvfi_tr.halt      = vif.monitor_cb.rvfi_halt;
        rvfi_tr.intr      = vif.monitor_cb.rvfi_intr;
        rvfi_tr.mode      = vif.monitor_cb.rvfi_mode;
        rvfi_tr.rs1_addr  = vif.monitor_cb.rvfi_rs1_addr;
        rvfi_tr.rs2_addr  = vif.monitor_cb.rvfi_rs2_addr;
        rvfi_tr.rs1_rdata = vif.monitor_cb.rvfi_rs1_rdata;
        rvfi_tr.rs2_rdata = vif.monitor_cb.rvfi_rs2_rdata;
        rvfi_tr.rd_addr   = vif.monitor_cb.rvfi_rd_addr;
        rvfi_tr.rd_wdata  = vif.monitor_cb.rvfi_rd_wdata;
        rvfi_tr.pc_rdata  = vif.monitor_cb.rvfi_pc_rdata;
        rvfi_tr.pc_wdata  = vif.monitor_cb.rvfi_pc_wdata;
        rvfi_tr.mem_addr  = vif.monitor_cb.rvfi_mem_addr;
        rvfi_tr.mem_rmask = vif.monitor_cb.rvfi_mem_rmask;
        rvfi_tr.mem_wmask = vif.monitor_cb.rvfi_mem_wmask;
        rvfi_tr.mem_rdata = vif.monitor_cb.rvfi_mem_rdata;
        rvfi_tr.mem_wdata = vif.monitor_cb.rvfi_mem_wdata;
        rvfi_tr.ext_mcycle = vif.monitor_cb.rvfi_ext_mcycle;

        `uvm_info(get_type_name(), rvfi_tr.convert2string(), UVM_HIGH)

        // Send to scoreboard and coverage
        rvfi_ap.write(rvfi_tr);
        cov.sample(rvfi_tr);
      end
    end
  endtask

  //-------------------------------------------------------------------------
  // Monitor data memory interface transactions
  //-------------------------------------------------------------------------
  task monitor_memory_interface();
    ibex_transaction mem_tr;
    logic [31:0] pending_addr;
    logic [31:0] pending_wdata;
    logic [ 3:0] pending_be;
    logic        pending_we;
    logic        req_pending = 1'b0;

    forever begin
      @(vif.monitor_cb);
      if (!vif.monitor_cb.rst_ni) begin
        req_pending = 1'b0;
        continue;
      end

      // Capture request
      if (vif.monitor_cb.data_req_o && !req_pending) begin
        pending_addr  = vif.monitor_cb.data_addr_o;
        pending_wdata = vif.monitor_cb.data_wdata_o;
        pending_be    = vif.monitor_cb.data_be_o;
        pending_we    = vif.monitor_cb.data_we_o;
        req_pending   = 1'b1;
      end

      // Capture response
      if (vif.monitor_cb.data_rvalid_i && req_pending) begin
        mem_tr = ibex_transaction::type_id::create("mem_tr");
        mem_tr.data_addr  = pending_addr;
        mem_tr.data_wdata = pending_wdata;
        mem_tr.data_rdata = vif.monitor_cb.data_rdata_i;
        mem_tr.data_be    = pending_be;
        mem_tr.data_we    = pending_we;
        mem_tr.data_req   = 1'b1;
        mem_tr.trans_type = pending_we ?
                            ibex_transaction::DATA_STORE :
                            ibex_transaction::DATA_LOAD;

        mem_ap.write(mem_tr);
        req_pending = 1'b0;
      end
    end
  endtask

  //-------------------------------------------------------------------------
  // Monitor alert signals (security violations)
  //-------------------------------------------------------------------------
  task monitor_alerts();
    forever begin
      @(vif.monitor_cb);
      if (!vif.monitor_cb.rst_ni) continue;

      if (vif.monitor_cb.alert_minor_o ||
          vif.monitor_cb.alert_major_internal_o ||
          vif.monitor_cb.alert_major_bus_o) begin

        ibex_transaction alert_tr = ibex_transaction::type_id::create("alert");
        `uvm_error(get_type_name(), $sformatf(
          "ALERT detected! minor=%0b major_int=%0b major_bus=%0b",
          vif.monitor_cb.alert_minor_o,
          vif.monitor_cb.alert_major_internal_o,
          vif.monitor_cb.alert_major_bus_o))

        alert_ap.write(alert_tr);
      end
    end
  endtask

endclass


//=============================================================================
// Coverage Collector
//=============================================================================
class ibex_rvfi_coverage extends uvm_component;
  `uvm_component_utils(ibex_rvfi_coverage)

  // Instruction type bins
  covergroup instr_type_cg;
    cp_opcode: coverpoint curr_tr.insn[6:0] {
      bins r_type  = {7'b0110011};  // ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND
      bins i_type  = {7'b0010011};  // ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI
      bins load    = {7'b0000011};  // LW/LH/LB/LHU/LBU
      bins store   = {7'b0100011};  // SW/SH/SB
      bins branch  = {7'b1100011};  // BEQ/BNE/BLT/BGE/BLTU/BGEU
      bins jal     = {7'b1101111};
      bins jalr    = {7'b1100111};
      bins lui     = {7'b0110111};
      bins auipc   = {7'b0010111};
      bins system  = {7'b1110011};  // CSR / ECALL / EBREAK
    }

    cp_funct3: coverpoint curr_tr.insn[14:12];

    cp_rd: coverpoint curr_tr.rd_addr {
      bins x0     = {0};
      bins x1_x7  = {[1:7]};
      bins x8_x15 = {[8:15]};
      bins x16_x31= {[16:31]};
    }

    // Cross: instruction type vs destination register
    cx_opcode_rd: cross cp_opcode, cp_rd;
  endgroup

  // PC coverage
  covergroup pc_cg;
    cp_pc: coverpoint curr_tr.pc_rdata {
      bins low_range  = {[32'h0000_0000 : 32'h0000_FFFF]};
      bins mid_range  = {[32'h0001_0000 : 32'h000F_FFFF]};
      bins high_range = {[32'h0010_0000 : 32'hFFFF_FFFF]};
    }
  endgroup

  // Control flow coverage
  covergroup control_flow_cg;
    cp_branch_taken: coverpoint (curr_tr.insn[6:0] == 7'b1100011 &&
                                  curr_tr.pc_wdata != curr_tr.pc_rdata + 4) {
      bins taken     = {1};
      bins not_taken = {0};
    }
    cp_is_jal:  coverpoint (curr_tr.insn[6:0] == 7'b1101111);
    cp_is_jalr: coverpoint (curr_tr.insn[6:0] == 7'b1100111);
    cp_trap:    coverpoint curr_tr.trap;
    cp_intr:    coverpoint curr_tr.intr;
  endgroup

  // Load/Store coverage
  covergroup lsu_cg;
    cp_ls_type: coverpoint curr_tr.insn[6:0] {
      bins load  = {7'b0000011};
      bins store = {7'b0100011};
    }
    cp_ls_funct3: coverpoint curr_tr.insn[14:12] iff
                   (curr_tr.insn[6:0] == 7'b0000011 ||
                    curr_tr.insn[6:0] == 7'b0100011);
    cp_mem_align: coverpoint curr_tr.mem_addr[1:0] iff
                   (curr_tr.mem_rmask != 0 || curr_tr.mem_wmask != 0);
  endgroup

  ibex_rvfi_transaction curr_tr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    instr_type_cg  = new();
    pc_cg          = new();
    control_flow_cg = new();
    lsu_cg         = new();
  endfunction

  function void sample(ibex_rvfi_transaction tr);
    curr_tr = tr;
    instr_type_cg.sample();
    pc_cg.sample();
    control_flow_cg.sample();
    lsu_cg.sample();
  endfunction

endclass

`endif // IBEX_MONITOR_SV
