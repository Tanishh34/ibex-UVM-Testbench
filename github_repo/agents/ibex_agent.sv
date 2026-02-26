//=============================================================================
// File: ibex_agent.sv
// Description: UVM Agent for Ibex Core
//   Contains: Sequencer, Agent, Agent Config
//=============================================================================

`ifndef IBEX_AGENT_SV
`define IBEX_AGENT_SV

//=============================================================================
// Sequencer (pass-through - no special functionality needed)
//=============================================================================
class ibex_sequencer extends uvm_sequencer #(ibex_transaction);
  `uvm_component_utils(ibex_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass


//=============================================================================
// Agent Configuration Object
//=============================================================================
class ibex_agent_cfg extends uvm_object;
  `uvm_object_utils_begin(ibex_agent_cfg)
    `uvm_field_int(is_active,            UVM_ALL_ON)
    `uvm_field_int(instr_gnt_delay_max,  UVM_ALL_ON)
    `uvm_field_int(data_gnt_delay_max,   UVM_ALL_ON)
    `uvm_field_int(instr_rvalid_delay,   UVM_ALL_ON)
    `uvm_field_int(data_rvalid_delay,    UVM_ALL_ON)
    `uvm_field_int(inject_errors,        UVM_ALL_ON)
  `uvm_object_utils_end

  // Is the agent active (has driver) or passive (monitor only)
  uvm_active_passive_enum is_active       = UVM_ACTIVE;

  // Memory timing parameters
  int unsigned instr_gnt_delay_max  = 2;
  int unsigned data_gnt_delay_max   = 3;
  int unsigned instr_rvalid_delay   = 1;
  int unsigned data_rvalid_delay    = 2;

  // Error injection enable
  bit inject_errors = 0;

  function new(string name = "ibex_agent_cfg");
    super.new(name);
  endfunction

endclass


//=============================================================================
// Agent
//=============================================================================
class ibex_agent extends uvm_agent;
  `uvm_component_utils(ibex_agent)

  // Sub-components
  ibex_sequencer  seqr;
  ibex_driver     drv;
  ibex_monitor    mon;
  ibex_agent_cfg  cfg;

  // Analysis port (forwarded from monitor)
  uvm_analysis_port #(ibex_rvfi_transaction) rvfi_ap;
  uvm_analysis_port #(ibex_transaction)      mem_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Get config
    if (!uvm_config_db #(ibex_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_info(get_type_name(),
        "No agent config found, using defaults", UVM_LOW)
      cfg = ibex_agent_cfg::type_id::create("cfg");
    end

    // Build monitor (always)
    mon = ibex_monitor::type_id::create("mon", this);

    // Build driver and sequencer only if ACTIVE
    if (cfg.is_active == UVM_ACTIVE) begin
      seqr = ibex_sequencer::type_id::create("seqr", this);
      drv  = ibex_driver::type_id::create("drv",  this);

      // Pass timing config to driver
      drv.instr_gnt_delay_max = cfg.instr_gnt_delay_max;
      drv.data_gnt_delay_max  = cfg.data_gnt_delay_max;
      drv.instr_rvalid_delay  = cfg.instr_rvalid_delay;
      drv.data_rvalid_delay   = cfg.data_rvalid_delay;
    end

    // Create forwarded analysis ports
    rvfi_ap = new("rvfi_ap", this);
    mem_ap  = new("mem_ap",  this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Connect driver to sequencer
    if (cfg.is_active == UVM_ACTIVE) begin
      drv.seq_item_port.connect(seqr.seq_item_export);
    end

    // Forward monitor analysis ports
    mon.rvfi_ap.connect(rvfi_ap);
    mon.mem_ap.connect(mem_ap);
  endfunction

endclass

`endif // IBEX_AGENT_SV
