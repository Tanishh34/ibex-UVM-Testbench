//=============================================================================
// File: ibex_tb_top.sv
// Description: Top-level UVM Testbench for Ibex Core
//   - Instantiates DUT (ibex_core)
//   - Instantiates interface
//   - Sets interface in config DB
//   - Runs UVM test
//=============================================================================

`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

// Include all TB files
`include "ibex_transaction.sv"
`include "ibex_if.sv"
`include "ibex_sequences.sv"
`include "ibex_driver.sv"
`include "ibex_monitor.sv"
`include "ibex_agent.sv"
`include "ibex_scoreboard.sv"
`include "ibex_env.sv"
`include "ibex_tests.sv"

module ibex_tb_top;

  //-------------------------------------------------------------------------
  // Clock generation
  //   Ibex typically runs at 100-200 MHz in simulation
  //   Use 10ns period (100 MHz) for reasonable simulation speed
  //-------------------------------------------------------------------------
  logic clk;
  initial clk = 1'b0;
  always #5ns clk = ~clk;  // 100 MHz

  //-------------------------------------------------------------------------
  // Interface instantiation
  //-------------------------------------------------------------------------
  ibex_if dut_if (.clk_i(clk));

  //-------------------------------------------------------------------------
  // DUT: Ibex Core
  //   Parameters match ibex_core.sv defaults for small/fast configuration
  //   PMPEnable=0, MHPMCounterNum=0, RV32M=1, RV32B=0, etc.
  //   Enable RVFI for scoreboard visibility into retired instructions
  //-------------------------------------------------------------------------
  ibex_core #(
    .PMPEnable        ( 1'b0          ),
    .PMPGranularity   ( 0             ),
    .PMPNumRegions    ( 4             ),
    .MHPMCounterNum   ( 0             ),
    .MHPMCounterWidth ( 40            ),
    .RV32E            ( 1'b0          ),  // 32 registers
    .RV32M            ( ibex_pkg::RV32MFast ),  // M-extension
    .RV32B            ( ibex_pkg::RV32BNone ),  // No B-extension
    .RegFile          ( ibex_pkg::RegFileFPGA ),
    .BranchTargetALU  ( 1'b0          ),
    .WritebackStage   ( 1'b0          ),
    .ICache           ( 1'b0          ),
    .ICacheECC        ( 1'b0          ),
    .BranchPredictor  ( 1'b0          ),
    .DbgTriggerEn     ( 1'b1          ),
    .DmHaltAddr       ( 32'h1A11_0800 ),
    .DmExceptionAddr  ( 32'h1A11_0808 )
  ) u_ibex_core (
    // Clock and Reset
    .clk_i                  ( clk                           ),
    .rst_ni                 ( dut_if.rst_ni                 ),

    // Instruction memory interface
    .instr_req_o            ( dut_if.instr_req_o            ),
    .instr_gnt_i            ( dut_if.instr_gnt_i            ),
    .instr_rvalid_i         ( dut_if.instr_rvalid_i         ),
    .instr_addr_o           ( dut_if.instr_addr_o           ),
    .instr_rdata_i          ( dut_if.instr_rdata_i          ),
    .instr_rdata_intg_i     ( dut_if.instr_rdata_intg_i     ),
    .instr_err_i            ( dut_if.instr_err_i            ),

    // Data memory interface
    .data_req_o             ( dut_if.data_req_o             ),
    .data_gnt_i             ( dut_if.data_gnt_i             ),
    .data_rvalid_i          ( dut_if.data_rvalid_i          ),
    .data_we_o              ( dut_if.data_we_o              ),
    .data_be_o              ( dut_if.data_be_o              ),
    .data_addr_o            ( dut_if.data_addr_o            ),
    .data_wdata_o           ( dut_if.data_wdata_o           ),
    .data_wdata_intg_o      ( dut_if.data_wdata_intg_o      ),
    .data_rdata_i           ( dut_if.data_rdata_i           ),
    .data_rdata_intg_i      ( dut_if.data_rdata_intg_i      ),
    .data_err_i             ( dut_if.data_err_i             ),

    // Interrupt interface
    .irq_software_i         ( dut_if.irq_software_i         ),
    .irq_timer_i            ( dut_if.irq_timer_i            ),
    .irq_external_i         ( dut_if.irq_external_i         ),
    .irq_fast_i             ( dut_if.irq_fast_i             ),
    .irq_nm_i               ( dut_if.irq_nm_i               ),

    // Debug interface
    .debug_req_i            ( dut_if.debug_req_i            ),
    .crash_dump_o           (                               ),  // Not used in TB

    // RISC-V Formal Interface (RVFI) - CRITICAL for scoreboard
    .rvfi_valid             ( dut_if.rvfi_valid             ),
    .rvfi_order             ( dut_if.rvfi_order             ),
    .rvfi_insn              ( dut_if.rvfi_insn              ),
    .rvfi_trap              ( dut_if.rvfi_trap              ),
    .rvfi_halt              ( dut_if.rvfi_halt              ),
    .rvfi_intr              ( dut_if.rvfi_intr              ),
    .rvfi_mode              ( dut_if.rvfi_mode              ),
    .rvfi_ixl               ( dut_if.rvfi_ixl               ),
    .rvfi_rs1_addr          ( dut_if.rvfi_rs1_addr          ),
    .rvfi_rs2_addr          ( dut_if.rvfi_rs2_addr          ),
    .rvfi_rs1_rdata         ( dut_if.rvfi_rs1_rdata         ),
    .rvfi_rs2_rdata         ( dut_if.rvfi_rs2_rdata         ),
    .rvfi_rd_addr           ( dut_if.rvfi_rd_addr           ),
    .rvfi_rd_wdata          ( dut_if.rvfi_rd_wdata          ),
    .rvfi_pc_rdata          ( dut_if.rvfi_pc_rdata          ),
    .rvfi_pc_wdata          ( dut_if.rvfi_pc_wdata          ),
    .rvfi_mem_addr          ( dut_if.rvfi_mem_addr          ),
    .rvfi_mem_rmask         ( dut_if.rvfi_mem_rmask         ),
    .rvfi_mem_wmask         ( dut_if.rvfi_mem_wmask         ),
    .rvfi_mem_rdata         ( dut_if.rvfi_mem_rdata         ),
    .rvfi_mem_wdata         ( dut_if.rvfi_mem_wdata         ),
    .rvfi_ext_mip           ( dut_if.rvfi_ext_mip           ),
    .rvfi_ext_nmi           ( dut_if.rvfi_ext_nmi           ),
    .rvfi_ext_debug_req     ( dut_if.rvfi_ext_debug_req     ),
    .rvfi_ext_mcycle        ( dut_if.rvfi_ext_mcycle        ),

    // Status
    .alert_minor_o          ( dut_if.alert_minor_o          ),
    .alert_major_internal_o ( dut_if.alert_major_internal_o ),
    .alert_major_bus_o      ( dut_if.alert_major_bus_o      ),
    .core_sleep_o           ( dut_if.core_sleep_o           )
  );

  //-------------------------------------------------------------------------
  // UVM Setup
  //-------------------------------------------------------------------------
  initial begin
    // Register virtual interface in config DB
    uvm_config_db #(virtual ibex_if)::set(
      null, "uvm_test_top.env.agent*", "vif", dut_if);

    // Dump waveforms
    `ifdef DUMP_VCD
      $dumpfile("ibex_tb.vcd");
      $dumpvars(0, ibex_tb_top);
    `endif

    // Run the test (test name passed via +UVM_TESTNAME=<test>)
    run_test();
  end

  //-------------------------------------------------------------------------
  // Simulation timeout
  //-------------------------------------------------------------------------
  initial begin
    #10ms;
    `uvm_fatal("TB", "Simulation timeout!")
  end

  //-------------------------------------------------------------------------
  // Waveform checkpoint (optional)
  //-------------------------------------------------------------------------
  initial begin
    $shm_open("ibex_waves.shm");
    $shm_probe("AC");
  end

endmodule
