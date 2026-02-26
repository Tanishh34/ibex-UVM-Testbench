//=============================================================================
// File: ibex_if.sv
// Description: SystemVerilog Interface for Ibex Core Ports
//   Mirrors ibex_core.sv top-level ports exactly
//=============================================================================

`ifndef IBEX_IF_SV
`define IBEX_IF_SV

interface ibex_if (input logic clk_i);

  //-------------------------------------------------------------------------
  // Clock and Reset
  //-------------------------------------------------------------------------
  logic        rst_ni;

  //-------------------------------------------------------------------------
  // Instruction Memory Interface (OBI-like)
  //-------------------------------------------------------------------------
  logic        instr_req_o;
  logic        instr_gnt_i;
  logic        instr_rvalid_i;
  logic [31:0] instr_addr_o;
  logic [31:0] instr_rdata_i;
  logic [31:0] instr_rdata_intg_i;  // Integrity bits (ECC)
  logic        instr_err_i;

  //-------------------------------------------------------------------------
  // Data Memory Interface (OBI-like)
  //-------------------------------------------------------------------------
  logic        data_req_o;
  logic        data_gnt_i;
  logic        data_rvalid_i;
  logic        data_we_o;
  logic [ 3:0] data_be_o;
  logic [31:0] data_addr_o;
  logic [31:0] data_wdata_o;
  logic [31:0] data_wdata_intg_o;   // Integrity bits
  logic [31:0] data_rdata_i;
  logic [31:0] data_rdata_intg_i;   // Integrity bits
  logic        data_err_i;

  //-------------------------------------------------------------------------
  // Interrupt Interface
  //-------------------------------------------------------------------------
  logic [14:0] irq_software_i;
  logic [14:0] irq_timer_i;
  logic [14:0] irq_external_i;
  logic [ 3:0] irq_fast_i;
  logic        irq_nm_i;            // Non-maskable interrupt

  //-------------------------------------------------------------------------
  // Debug Interface
  //-------------------------------------------------------------------------
  logic        debug_req_i;
  logic        crash_dump_valid_o;

  //-------------------------------------------------------------------------
  // RISC-V Formal IF
  //-------------------------------------------------------------------------
  // These expose retired instruction info - critical for scoreboard
  logic        rvfi_valid;
  logic [63:0] rvfi_order;
  logic [31:0] rvfi_insn;
  logic        rvfi_trap;
  logic        rvfi_halt;
  logic        rvfi_intr;
  logic [ 1:0] rvfi_mode;
  logic [ 1:0] rvfi_ixl;
  logic [ 4:0] rvfi_rs1_addr;
  logic [ 4:0] rvfi_rs2_addr;
  logic [31:0] rvfi_rs1_rdata;
  logic [31:0] rvfi_rs2_rdata;
  logic [ 4:0] rvfi_rd_addr;
  logic [31:0] rvfi_rd_wdata;
  logic [31:0] rvfi_pc_rdata;        // PC at instruction retirement
  logic [31:0] rvfi_pc_wdata;        // Next PC after this instruction
  logic [31:0] rvfi_mem_addr;
  logic [ 3:0] rvfi_mem_rmask;
  logic [ 3:0] rvfi_mem_wmask;
  logic [31:0] rvfi_mem_rdata;
  logic [31:0] rvfi_mem_wdata;
  logic [31:0] rvfi_ext_mip;
  logic        rvfi_ext_nmi;
  logic        rvfi_ext_debug_req;
  logic [63:0] rvfi_ext_mcycle;

  //-------------------------------------------------------------------------
  // Core Status
  //-------------------------------------------------------------------------
  logic        core_sleep_o;
  logic        alert_minor_o;
  logic        alert_major_internal_o;
  logic        alert_major_bus_o;

  //-------------------------------------------------------------------------
  // Clocking Blocks
  //-------------------------------------------------------------------------

  // Driver clocking block (synchronize inputs to DUT)
  clocking driver_cb @(posedge clk_i);
    default input #1step output #1ns;
    // Reset
    output rst_ni;
    // Instruction memory responses
    output instr_gnt_i;
    output instr_rvalid_i;
    output instr_rdata_i;
    output instr_rdata_intg_i;
    output instr_err_i;
    // Data memory responses
    output data_gnt_i;
    output data_rvalid_i;
    output data_rdata_i;
    output data_rdata_intg_i;
    output data_err_i;
    // Interrupts
    output irq_software_i;
    output irq_timer_i;
    output irq_external_i;
    output irq_fast_i;
    output irq_nm_i;
    // Debug
    output debug_req_i;
    // Observe DUT outputs
    input  instr_req_o;
    input  instr_addr_o;
    input  data_req_o;
    input  data_we_o;
    input  data_be_o;
    input  data_addr_o;
    input  data_wdata_o;
  endclocking

  // Monitor clocking block (sample DUT activity)
  clocking monitor_cb @(posedge clk_i);
    default input #1step;
    // All signals as inputs for observation
    input rst_ni;
    input instr_req_o;
    input instr_gnt_i;
    input instr_rvalid_i;
    input instr_addr_o;
    input instr_rdata_i;
    input instr_err_i;
    input data_req_o;
    input data_gnt_i;
    input data_rvalid_i;
    input data_we_o;
    input data_be_o;
    input data_addr_o;
    input data_wdata_o;
    input data_rdata_i;
    input data_err_i;
    // RVFI retirement signals
    input rvfi_valid;
    input rvfi_order;
    input rvfi_insn;
    input rvfi_trap;
    input rvfi_halt;
    input rvfi_intr;
    input rvfi_rs1_addr;
    input rvfi_rs2_addr;
    input rvfi_rs1_rdata;
    input rvfi_rs2_rdata;
    input rvfi_rd_addr;
    input rvfi_rd_wdata;
    input rvfi_pc_rdata;
    input rvfi_pc_wdata;
    input rvfi_mem_addr;
    input rvfi_mem_rmask;
    input rvfi_mem_wmask;
    input rvfi_mem_rdata;
    input rvfi_mem_wdata;
    // Alerts
    input alert_minor_o;
    input alert_major_internal_o;
    input alert_major_bus_o;
    input core_sleep_o;
    // Interrupts observed
    input irq_software_i;
    input irq_nm_i;
    input debug_req_i;
  endclocking

  //-------------------------------------------------------------------------
  // Modports
  //-------------------------------------------------------------------------
  modport driver_mp  (clocking driver_cb,  input clk_i);
  modport monitor_mp (clocking monitor_cb, input clk_i);

  //-------------------------------------------------------------------------
  // Assertions (Protocol Checks)
  //-------------------------------------------------------------------------

  // Instruction address must be 4-byte aligned when request is active
  property instr_addr_aligned;
    @(posedge clk_i) disable iff (!rst_ni)
    instr_req_o |-> (instr_addr_o[1:0] == 2'b00);
  endproperty
  assert property (instr_addr_aligned)
    else `uvm_error("IF_ASSERT", "Instruction address not 4-byte aligned!")

  // Data request must not fire on same cycle as reset deassertion
  // (Allow 1 cycle after reset for core to start)
  property no_req_in_reset;
    @(posedge clk_i)
    (!rst_ni) |-> (!instr_req_o && !data_req_o);
  endproperty
  assert property (no_req_in_reset)
    else `uvm_error("IF_ASSERT", "Request seen during reset!")

  // RVFI ordering: instruction order must be monotonically increasing
  property rvfi_order_monotonic;
    @(posedge clk_i) disable iff (!rst_ni)
    (rvfi_valid && $past(rvfi_valid)) |->
      (rvfi_order == ($past(rvfi_order) + 1));
  endproperty
  assert property (rvfi_order_monotonic)
    else `uvm_error("RVFI_ASSERT", "RVFI order not monotonically increasing!")

  // RVFI: PC write data must be 4-byte aligned (no compressed support assumed)
  property rvfi_pc_aligned;
    @(posedge clk_i) disable iff (!rst_ni)
    rvfi_valid |-> (rvfi_pc_wdata[1:0] == 2'b00);
  endproperty
  assert property (rvfi_pc_aligned)
    else `uvm_error("RVFI_ASSERT", "RVFI next PC not aligned!")

endinterface

`endif // IBEX_IF_SV
