//=============================================================================
// File: ibex_env.sv
// Description: UVM Environment - wires agent, scoreboard, coverage together
//=============================================================================

`ifndef IBEX_ENV_SV
`define IBEX_ENV_SV

class ibex_env_cfg extends uvm_object;
  `uvm_object_utils_begin(ibex_env_cfg)
    `uvm_field_object(agent_cfg,   UVM_ALL_ON)
    `uvm_field_int(enable_sb,      UVM_ALL_ON)
    `uvm_field_int(enable_cov,     UVM_ALL_ON)
  `uvm_object_utils_end

  ibex_agent_cfg agent_cfg;
  bit enable_sb  = 1;
  bit enable_cov = 1;

  function new(string name = "ibex_env_cfg");
    super.new(name);
    agent_cfg = ibex_agent_cfg::type_id::create("agent_cfg");
  endfunction

endclass


class ibex_env extends uvm_env;
  `uvm_component_utils(ibex_env)

  // Sub-components
  ibex_agent       agent;
  ibex_scoreboard  scoreboard;
  ibex_env_cfg     cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Get config
    if (!uvm_config_db #(ibex_env_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_info(get_type_name(), "No env cfg, using defaults", UVM_LOW)
      cfg = ibex_env_cfg::type_id::create("cfg");
    end

    // Set agent config
    uvm_config_db #(ibex_agent_cfg)::set(this, "agent*", "cfg", cfg.agent_cfg);

    // Build sub-components
    agent = ibex_agent::type_id::create("agent", this);

    if (cfg.enable_sb)
      scoreboard = ibex_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Connect agent outputs to scoreboard inputs
    if (cfg.enable_sb) begin
      agent.rvfi_ap.connect(scoreboard.rvfi_export);
      agent.mem_ap.connect(scoreboard.mem_export);
    end
  endfunction

endclass

`endif // IBEX_ENV_SV
