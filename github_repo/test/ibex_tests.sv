//=============================================================================
// File: ibex_tests.sv
// Description: UVM Test Classes for Ibex Verification
//   Each test exercises a specific verification scenario.
//=============================================================================

`ifndef IBEX_TESTS_SV
`define IBEX_TESTS_SV

//=============================================================================
// Base Test
//=============================================================================
class ibex_base_test extends uvm_test;
  `uvm_component_utils(ibex_base_test)

  ibex_env      env;
  ibex_env_cfg  env_cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    env_cfg = ibex_env_cfg::type_id::create("env_cfg");
    configure_env(env_cfg);
    uvm_config_db #(ibex_env_cfg)::set(this, "env*", "cfg", env_cfg);

    env = ibex_env::type_id::create("env", this);
  endfunction

  // Override in sub-tests to customize environment
  virtual function void configure_env(ibex_env_cfg cfg);
    cfg.enable_sb  = 1;
    cfg.enable_cov = 1;
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    apply_reset();
    run_test_body(phase);
    drain_time();
    phase.drop_objection(this);
  endtask

  // Apply reset sequence
  virtual task apply_reset();
    ibex_reset_seq reset_seq = ibex_reset_seq::type_id::create("reset_seq");
    reset_seq.reset_cycles = 20;
    reset_seq.start(env.agent.seqr);
    `uvm_info(get_type_name(), "Reset complete", UVM_MEDIUM)
  endtask

  // Override in sub-tests to define test body
  virtual task run_test_body(uvm_phase phase);
  endtask

  // Allow pipeline to drain after last instruction
  virtual task drain_time();
    #500ns;
  endtask

endclass


//=============================================================================
// Test 1: Sanity / Smoke Test
//   Run NOP sled through reset, verify core starts at PC=0
//=============================================================================
class ibex_smoke_test extends ibex_base_test;
  `uvm_component_utils(ibex_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_test_body(uvm_phase phase);
    ibex_random_instr_seq seq = ibex_random_instr_seq::type_id::create("seq");
    seq.num_instructions = 20;
    `uvm_info(get_type_name(), "Running smoke test: 20 NOPs after reset", UVM_MEDIUM)
    seq.start(env.agent.seqr);
  endtask

endclass


//=============================================================================
// Test 2: ALU R-Type Exhaustive
//=============================================================================
class ibex_alu_test extends ibex_base_test;
  `uvm_component_utils(ibex_alu_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_test_body(uvm_phase phase);
    ibex_alu_rtype_seq seq = ibex_alu_rtype_seq::type_id::create("alu_seq");
    `uvm_info(get_type_name(), "Running ALU R-type sequence", UVM_MEDIUM)
    seq.start(env.agent.seqr);
  endtask

endclass


//=============================================================================
// Test 3: Load/Store Test
//=============================================================================
class ibex_lsu_test extends ibex_base_test;
  `uvm_component_utils(ibex_lsu_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_test_body(uvm_phase phase);
    ibex_load_store_seq seq = ibex_load_store_seq::type_id::create("lsu_seq");
    `uvm_info(get_type_name(), "Running load/store sequence", UVM_MEDIUM)
    seq.start(env.agent.seqr);
  endtask

endclass


//=============================================================================
// Test 4: Control Flow (Branches & Jumps)
//=============================================================================
class ibex_branch_test extends ibex_base_test;
  `uvm_component_utils(ibex_branch_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_test_body(uvm_phase phase);
    ibex_control_flow_seq seq = ibex_control_flow_seq::type_id::create("cf_seq");
    `uvm_info(get_type_name(), "Running control flow sequence", UVM_MEDIUM)
    seq.start(env.agent.seqr);
  endtask

endclass


//=============================================================================
// Test 5: Data Hazard / Forwarding
//=============================================================================
class ibex_hazard_test extends ibex_base_test;
  `uvm_component_utils(ibex_hazard_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_test_body(uvm_phase phase);
    ibex_hazard_forwarding_seq seq =
      ibex_hazard_forwarding_seq::type_id::create("haz_seq");
    `uvm_info(get_type_name(), "Running hazard/forwarding sequence", UVM_MEDIUM)
    seq.start(env.agent.seqr);
  endtask

endclass


//=============================================================================
// Test 6: CSR Access
//=============================================================================
class ibex_csr_test extends ibex_base_test;
  `uvm_component_utils(ibex_csr_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_test_body(uvm_phase phase);
    ibex_csr_access_seq seq = ibex_csr_access_seq::type_id::create("csr_seq");
    `uvm_info(get_type_name(), "Running CSR access sequence", UVM_MEDIUM)
    seq.start(env.agent.seqr);
  endtask

endclass


//=============================================================================
// Test 7: Interrupt Injection
//=============================================================================
class ibex_interrupt_test extends ibex_base_test;
  `uvm_component_utils(ibex_interrupt_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_test_body(uvm_phase phase);
    ibex_interrupt_seq seq = ibex_interrupt_seq::type_id::create("irq_seq");
    `uvm_info(get_type_name(), "Running interrupt sequence", UVM_MEDIUM)
    seq.start(env.agent.seqr);
  endtask

endclass


//=============================================================================
// Test 8: Random Regression
//   Randomizes instruction mix to find corner cases
//=============================================================================
class ibex_random_test extends ibex_base_test;
  `uvm_component_utils(ibex_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_test_body(uvm_phase phase);
    ibex_random_instr_seq seq = ibex_random_instr_seq::type_id::create("rand_seq");
    seq.num_instructions = 1000;
    `uvm_info(get_type_name(), "Running 1000-instruction random test", UVM_MEDIUM)
    seq.start(env.agent.seqr);
  endtask

endclass


//=============================================================================
// Test 9: Full Regression (runs all sequences back-to-back)
//=============================================================================
class ibex_full_regression_test extends ibex_base_test;
  `uvm_component_utils(ibex_full_regression_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_test_body(uvm_phase phase);
    `uvm_info(get_type_name(), "Running FULL regression", UVM_MEDIUM)

    begin
      ibex_alu_rtype_seq s = ibex_alu_rtype_seq::type_id::create("alu");
      s.start(env.agent.seqr);
    end
    begin
      ibex_load_store_seq s = ibex_load_store_seq::type_id::create("lsu");
      s.start(env.agent.seqr);
    end
    begin
      ibex_control_flow_seq s = ibex_control_flow_seq::type_id::create("cf");
      s.start(env.agent.seqr);
    end
    begin
      ibex_hazard_forwarding_seq s = ibex_hazard_forwarding_seq::type_id::create("haz");
      s.start(env.agent.seqr);
    end
    begin
      ibex_csr_access_seq s = ibex_csr_access_seq::type_id::create("csr");
      s.start(env.agent.seqr);
    end
    begin
      ibex_interrupt_seq s = ibex_interrupt_seq::type_id::create("irq");
      s.start(env.agent.seqr);
    end
    begin
      ibex_random_instr_seq s = ibex_random_instr_seq::type_id::create("rand");
      s.num_instructions = 500;
      s.start(env.agent.seqr);
    end
  endtask

endclass

`endif // IBEX_TESTS_SV
