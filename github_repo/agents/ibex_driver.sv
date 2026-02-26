//=============================================================================
// File: ibex_driver.sv
// Description: UVM Driver for Ibex Core
//   Drives instruction and data memory interfaces, handles OBI handshake,
//   models instruction/data memory timing (grant/valid delays)
//=============================================================================

`ifndef IBEX_DRIVER_SV
`define IBEX_DRIVER_SV

class ibex_driver extends uvm_driver #(ibex_transaction);
  `uvm_component_utils(ibex_driver)

  // Virtual interface handle
  virtual ibex_if vif;

  // Simple instruction memory model: address -> data
  logic [31:0] instr_mem [logic [31:0]];
  logic [31:0] data_mem  [logic [31:0]];  // Byte-addressable (word-indexed)

  // Pending OBI transactions
  typedef struct {
    logic [31:0] addr;
    logic        valid;
  } pending_req_t;

  pending_req_t pending_instr_req;
  pending_req_t pending_data_req;

  // Configuration
  int unsigned instr_gnt_delay_max  = 2;   // Max cycles to delay grant
  int unsigned data_gnt_delay_max   = 3;
  int unsigned instr_rvalid_delay   = 1;   // Cycles from gnt to rvalid
  int unsigned data_rvalid_delay    = 2;

  //-------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    pending_instr_req.valid = 1'b0;
    pending_data_req.valid  = 1'b0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual ibex_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "Could not get vif from config DB")
    init_instr_memory();
  endfunction

  //-------------------------------------------------------------------------
  // Initialize instruction memory with NOP sled by default.
  // Sequences will overwrite specific addresses.
  //-------------------------------------------------------------------------
  function void init_instr_memory();
    // Fill first 4KB with NOPs
    for (int i = 0; i < 1024; i++) begin
      instr_mem[32'(i*4)] = 32'h0000_0013;  // ADDI x0, x0, 0
    end
  endfunction

  //-------------------------------------------------------------------------
  // run_phase: main driver loop
  //-------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    ibex_transaction tr;

    // Drive default idle values
    drive_idle();
    wait_negedge_rst();

    fork
      // Handle instruction memory interface
      handle_instr_interface();
      // Handle data memory interface
      handle_data_interface();
      // Get transactions from sequencer
      get_and_drive_transactions();
    join
  endtask

  //-------------------------------------------------------------------------
  // Wait for reset to deassert
  //-------------------------------------------------------------------------
  task wait_negedge_rst();
    @(posedge vif.clk_i);
    while (!vif.driver_cb.rst_ni) begin
      @(vif.driver_cb);
    end
    `uvm_info(get_type_name(), "Reset deasserted, starting normal operation", UVM_MEDIUM)
  endtask

  //-------------------------------------------------------------------------
  // Drive idle/default values on DUT inputs
  //-------------------------------------------------------------------------
  task drive_idle();
    vif.driver_cb.rst_ni          <= 1'b0;
    vif.driver_cb.instr_gnt_i     <= 1'b0;
    vif.driver_cb.instr_rvalid_i  <= 1'b0;
    vif.driver_cb.instr_rdata_i   <= 32'h0;
    vif.driver_cb.instr_rdata_intg_i <= 7'h0;
    vif.driver_cb.instr_err_i     <= 1'b0;
    vif.driver_cb.data_gnt_i      <= 1'b0;
    vif.driver_cb.data_rvalid_i   <= 1'b0;
    vif.driver_cb.data_rdata_i    <= 32'h0;
    vif.driver_cb.data_rdata_intg_i <= 7'h0;
    vif.driver_cb.data_err_i      <= 1'b0;
    vif.driver_cb.irq_software_i  <= 15'h0;
    vif.driver_cb.irq_timer_i     <= 15'h0;
    vif.driver_cb.irq_external_i  <= 15'h0;
    vif.driver_cb.irq_fast_i      <= 4'h0;
    vif.driver_cb.irq_nm_i        <= 1'b0;
    vif.driver_cb.debug_req_i     <= 1'b0;
  endtask

  //-------------------------------------------------------------------------
  // Get transactions from sequencer and process them
  //-------------------------------------------------------------------------
  task get_and_drive_transactions();
    ibex_transaction tr;
    forever begin
      seq_item_port.get_next_item(tr);
      drive_transaction(tr);
      seq_item_port.item_done();
    end
  endtask

  //-------------------------------------------------------------------------
  // Process a single transaction
  //-------------------------------------------------------------------------
  task drive_transaction(ibex_transaction tr);
    case (tr.trans_type)
      ibex_transaction::RESET_TRANS: begin
        vif.driver_cb.rst_ni <= tr.rst_ni;
        @(vif.driver_cb);
      end

      ibex_transaction::INSTR_FETCH: begin
        // Load instruction into memory model
        instr_mem[tr.instr_addr] = tr.instr_data;
        @(vif.driver_cb);  // Advance one clock
      end

      ibex_transaction::IRQ_TRANS: begin
        vif.driver_cb.irq_timer_i    <= tr.irq;
        vif.driver_cb.irq_nm_i       <= tr.irq_nm;
        @(vif.driver_cb);
      end

      ibex_transaction::DEBUG_TRANS: begin
        vif.driver_cb.debug_req_i <= tr.debug_req;
        @(vif.driver_cb);
      end

      default: @(vif.driver_cb);
    endcase
  endtask

  //-------------------------------------------------------------------------
  // Instruction Memory Interface Handler (OBI protocol)
  //   Responds to instr_req_o with grant + rdata
  //-------------------------------------------------------------------------
  task handle_instr_interface();
    logic [31:0] captured_addr;
    int          gnt_delay, rvalid_delay;

    forever begin
      @(vif.driver_cb);

      if (vif.driver_cb.instr_req_o) begin
        captured_addr = vif.driver_cb.instr_addr_o;

        // Random grant delay (0 to max)
        gnt_delay = $urandom_range(0, instr_gnt_delay_max);
        repeat(gnt_delay) @(vif.driver_cb);

        // Grant the request
        vif.driver_cb.instr_gnt_i <= 1'b1;
        @(vif.driver_cb);
        vif.driver_cb.instr_gnt_i <= 1'b0;

        // Random rvalid delay
        rvalid_delay = $urandom_range(instr_rvalid_delay, instr_rvalid_delay + 2);
        repeat(rvalid_delay - 1) @(vif.driver_cb);

        // Return instruction data
        vif.driver_cb.instr_rvalid_i <= 1'b1;
        if (instr_mem.exists(captured_addr))
          vif.driver_cb.instr_rdata_i <= instr_mem[captured_addr];
        else
          vif.driver_cb.instr_rdata_i <= 32'h0000_0013; // Default: NOP

        @(vif.driver_cb);
        vif.driver_cb.instr_rvalid_i <= 1'b0;
        vif.driver_cb.instr_rdata_i  <= 32'h0;
      end
    end
  endtask

  //-------------------------------------------------------------------------
  // Data Memory Interface Handler (OBI protocol)
  //   Handles load and store transactions
  //-------------------------------------------------------------------------
  task handle_data_interface();
    logic [31:0] captured_addr;
    logic [31:0] captured_wdata;
    logic [ 3:0] captured_be;
    logic        captured_we;
    int          gnt_delay, rvalid_delay;
    logic [31:0] word_addr;
    logic [31:0] read_data;

    forever begin
      @(vif.driver_cb);

      if (vif.driver_cb.data_req_o) begin
        captured_addr  = vif.driver_cb.data_addr_o;
        captured_wdata = vif.driver_cb.data_wdata_o;
        captured_be    = vif.driver_cb.data_be_o;
        captured_we    = vif.driver_cb.data_we_o;
        word_addr      = {captured_addr[31:2], 2'b00};  // Align to word

        // Random grant delay
        gnt_delay = $urandom_range(0, data_gnt_delay_max);
        repeat(gnt_delay) @(vif.driver_cb);

        // Grant
        vif.driver_cb.data_gnt_i <= 1'b1;
        @(vif.driver_cb);
        vif.driver_cb.data_gnt_i <= 1'b0;

        if (captured_we) begin
          // --- STORE: Write to memory model ---
          logic [31:0] existing = data_mem.exists(word_addr) ? data_mem[word_addr] : 32'h0;
          logic [31:0] new_word = existing;

          if (captured_be[0]) new_word[ 7: 0] = captured_wdata[ 7: 0];
          if (captured_be[1]) new_word[15: 8] = captured_wdata[15: 8];
          if (captured_be[2]) new_word[23:16] = captured_wdata[23:16];
          if (captured_be[3]) new_word[31:24] = captured_wdata[31:24];

          data_mem[word_addr] = new_word;

          // Stores don't need rvalid in Ibex (write-through, no read data)
          // But OBI requires rvalid for all transactions
          rvalid_delay = $urandom_range(data_rvalid_delay, data_rvalid_delay + 2);
          repeat(rvalid_delay - 1) @(vif.driver_cb);
          vif.driver_cb.data_rvalid_i <= 1'b1;
          vif.driver_cb.data_rdata_i  <= 32'h0;
          @(vif.driver_cb);
          vif.driver_cb.data_rvalid_i <= 1'b0;

        end else begin
          // --- LOAD: Read from memory model ---
          read_data = data_mem.exists(word_addr) ? data_mem[word_addr] : 32'hDEAD_BEEF;

          rvalid_delay = $urandom_range(data_rvalid_delay, data_rvalid_delay + 2);
          repeat(rvalid_delay - 1) @(vif.driver_cb);
          vif.driver_cb.data_rvalid_i <= 1'b1;
          vif.driver_cb.data_rdata_i  <= read_data;
          @(vif.driver_cb);
          vif.driver_cb.data_rvalid_i <= 1'b0;
          vif.driver_cb.data_rdata_i  <= 32'h0;
        end
      end
    end
  endtask

endclass

`endif // IBEX_DRIVER_SV
