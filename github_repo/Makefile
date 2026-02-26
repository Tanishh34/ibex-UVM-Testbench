#=============================================================================
# Makefile: Ibex UVM Testbench Build and Run
# Supports: VCS, Xcelium (xrun), Questa (vsim)
#=============================================================================

IBEX_RTL    := ../rtl
UVM_HOME    ?= /tools/uvm/1.2
SIM_DIR     := sim_out
WAVES       := 0
TEST        ?= ibex_smoke_test
SEED        ?= 1
VERBOSITY   ?= UVM_MEDIUM

# Source file lists
RTL_FILES := \
  $(IBEX_RTL)/ibex_pkg.sv \
  $(IBEX_RTL)/ibex_alu.sv \
  $(IBEX_RTL)/ibex_branch_predict.sv \
  $(IBEX_RTL)/ibex_compressed_decoder.sv \
  $(IBEX_RTL)/ibex_controller.sv \
  $(IBEX_RTL)/ibex_cs_registers.sv \
  $(IBEX_RTL)/ibex_decoder.sv \
  $(IBEX_RTL)/ibex_ex_block.sv \
  $(IBEX_RTL)/ibex_fetch_fifo.sv \
  $(IBEX_RTL)/ibex_id_stage.sv \
  $(IBEX_RTL)/ibex_if_stage.sv \
  $(IBEX_RTL)/ibex_load_store_unit.sv \
  $(IBEX_RTL)/ibex_multdiv_slow.sv \
  $(IBEX_RTL)/ibex_multdiv_fast.sv \
  $(IBEX_RTL)/ibex_prefetch_buffer.sv \
  $(IBEX_RTL)/ibex_register_file_fpga.sv \
  $(IBEX_RTL)/ibex_wb_stage.sv \
  $(IBEX_RTL)/ibex_core.sv

TB_FILES := \
  tb/ibex_transaction.sv \
  tb/ibex_if.sv \
  sequences/ibex_sequences.sv \
  agents/ibex_driver.sv \
  agents/ibex_monitor.sv \
  agents/ibex_agent.sv \
  scoreboard/ibex_scoreboard.sv \
  env/ibex_env.sv \
  test/ibex_tests.sv \
  tb/ibex_tb_top.sv

#=============================================================================
# VCS Targets
#=============================================================================
VCS_FLAGS := \
  -sverilog \
  -ntb_opts uvm-1.2 \
  -full64 \
  -timescale=1ns/1ps \
  -debug_access+all \
  +define+RVFI \
  +incdir+$(IBEX_RTL) \
  +incdir+tb \
  +incdir+agents \
  +incdir+sequences \
  +incdir+scoreboard \
  +incdir+env \
  +incdir+test

VCS_RUN_FLAGS := \
  +UVM_TESTNAME=$(TEST) \
  +UVM_VERBOSITY=$(VERBOSITY) \
  +ntb_random_seed=$(SEED)

vcs_compile:
	mkdir -p $(SIM_DIR)
	vcs $(VCS_FLAGS) $(RTL_FILES) $(TB_FILES) -o $(SIM_DIR)/simv 2>&1 | tee $(SIM_DIR)/compile.log

vcs_run: vcs_compile
	cd $(SIM_DIR) && ./simv $(VCS_RUN_FLAGS) 2>&1 | tee run_$(TEST)_$(SEED).log

vcs_waves:
	$(MAKE) vcs_run WAVES=1 VCS_RUN_FLAGS+=" +DUMP_VCD"

#=============================================================================
# Xcelium (Cadence) Targets
#=============================================================================
XRUN_FLAGS := \
  -sv \
  -uvm \
  -uvmhome CDNS-1.2 \
  -timescale 1ns/1ps \
  -define RVFI \
  -incdir $(IBEX_RTL) \
  -incdir tb \
  -incdir agents \
  -incdir sequences \
  -incdir scoreboard \
  -incdir env \
  -incdir test \
  -access +rwc

XRUN_RUN_FLAGS := \
  +UVM_TESTNAME=$(TEST) \
  +UVM_VERBOSITY=$(VERBOSITY) \
  -svseed $(SEED)

xrun:
	mkdir -p $(SIM_DIR)
	xrun $(XRUN_FLAGS) $(RTL_FILES) $(TB_FILES) $(XRUN_RUN_FLAGS) \
	  -log $(SIM_DIR)/xrun_$(TEST)_$(SEED).log

#=============================================================================
# Questa (Mentor/Siemens) Targets
#=============================================================================
VLOG_FLAGS := \
  -sv \
  +define+RVFI \
  +incdir+$(IBEX_RTL) \
  +incdir+tb +incdir+agents +incdir+sequences \
  +incdir+scoreboard +incdir+env +incdir+test

questa_compile:
	mkdir -p $(SIM_DIR)
	cd $(SIM_DIR) && vlib work
	cd $(SIM_DIR) && vlog $(VLOG_FLAGS) $(RTL_FILES) $(TB_FILES)

questa_run: questa_compile
	cd $(SIM_DIR) && vsim -c ibex_tb_top \
	  +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) \
	  -sv_seed $(SEED) \
	  -do "run -all; quit"

#=============================================================================
# Regression: run all tests with multiple seeds
#=============================================================================
TESTS := \
  ibex_smoke_test \
  ibex_alu_test \
  ibex_lsu_test \
  ibex_branch_test \
  ibex_hazard_test \
  ibex_csr_test \
  ibex_interrupt_test \
  ibex_random_test

SEEDS := 1 2 3 4 5

regression:
	@echo "Running regression with $(words $(TESTS)) tests x $(words $(SEEDS)) seeds"
	@for test in $(TESTS); do \
	  for seed in $(SEEDS); do \
	    echo "Running $$test seed=$$seed"; \
	    $(MAKE) vcs_run TEST=$$test SEED=$$seed || true; \
	  done; \
	done
	@echo "Regression complete. Check $(SIM_DIR)/*.log for results"

regression_summary:
	@echo "====== REGRESSION SUMMARY ======"
	@grep -l "UVM_ERROR" $(SIM_DIR)/*.log | wc -l | xargs echo "Tests with errors:"
	@grep -l "UVM_FATAL" $(SIM_DIR)/*.log | wc -l | xargs echo "Tests with fatals:"
	@grep -rh "ALL SCOREBOARD CHECKS PASSED" $(SIM_DIR)/*.log | wc -l | xargs echo "Tests passed scoreboard:"

clean:
	rm -rf $(SIM_DIR) csrc simv* *.log DVEfiles ucli.key *.fsdb *.vcd

.PHONY: vcs_compile vcs_run xrun questa_compile questa_run regression clean
