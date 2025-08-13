`timescale 1ns/1ns

// ============================================================================
// AXI4 VERIFICATION ASSERTIONS MODULE
// ============================================================================
// This module contains comprehensive SystemVerilog assertions (SVA) for 
// verifying AXI4 protocol compliance and design-specific behaviors
// ============================================================================

module axi4_assertions #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 16,
    parameter int MEMORY_DEPTH = 1024,
    parameter int MAX_BURST_LENGTH = 16
)(
    // Clock and Reset
    input logic clk,
    input logic ARESTN,
    
    // Write Address Channel
    input logic [ADDR_WIDTH-1:0] AWADDR,
    input logic [7:0] AWLEN,
    input logic [2:0] AWSIZE,
    input logic [1:0] AWBURST,
    input logic AWVALID,
    input logic AWREADY,
    
    // Write Data Channel
    input logic [DATA_WIDTH-1:0] WDATA,
    input logic [(DATA_WIDTH/8)-1:0] WSTRB,
    input logic WLAST,
    input logic WVALID,
    input logic WREADY,
    
    // Write Response Channel
    input logic [1:0] BRESP,
    input logic BVALID,
    input logic BREADY,
    
    // Read Address Channel
    input logic [ADDR_WIDTH-1:0] ARADDR,
    input logic [7:0] ARLEN,
    input logic [2:0] ARSIZE,
    input logic [1:0] ARBURST,
    input logic ARVALID,
    input logic ARREADY,
    
    // Read Data Channel
    input logic [DATA_WIDTH-1:0] RDATA,
    input logic [1:0] RRESP,
    input logic RLAST,
    input logic RVALID,
    input logic RREADY
);

    // ========================================================================
    // HELPER SIGNALS AND COUNTERS
    // ========================================================================
    
    // Transaction counters for burst tracking
    logic [7:0] write_beat_count;
    logic [7:0] read_beat_count;
    logic [7:0] expected_write_beats;
    logic [7:0] expected_read_beats;
    
    // Transaction tracking flags
    logic write_addr_phase_active;
    logic write_data_phase_active;
    logic write_resp_phase_active;
    logic read_addr_phase_active;
    logic read_data_phase_active;
    
    // Boundary and validity checking
    logic write_crosses_4kb_boundary;
    logic read_crosses_4kb_boundary;
    logic write_addr_in_memory_range;
    logic read_addr_in_memory_range;
    
    // Beat counters and expected values
    always_ff @(posedge clk or negedge ARESTN) begin
        if (!ARESTN) begin
            write_beat_count <= 0;
            read_beat_count <= 0;
            expected_write_beats <= 0;
            expected_read_beats <= 0;
            write_addr_phase_active <= 0;
            write_data_phase_active <= 0;
            write_resp_phase_active <= 0;
            read_addr_phase_active <= 0;
            read_data_phase_active <= 0;
        end else begin
            // Write address phase tracking
            if (AWVALID && AWREADY) begin
                write_addr_phase_active <= 1;
                write_data_phase_active <= 1;
                expected_write_beats <= AWLEN + 1;
                write_beat_count <= 0;
            end
            
            // Write data phase tracking
            if (WVALID && WREADY) begin
                write_beat_count <= write_beat_count + 1;
                if (WLAST) begin
                    write_data_phase_active <= 0;
                    write_resp_phase_active <= 1;
                end
            end
            
            // Write response phase tracking
            if (BVALID && BREADY) begin
                write_addr_phase_active <= 0;
                write_resp_phase_active <= 0;
            end
            
            // Read address phase tracking
            if (ARVALID && ARREADY) begin
                read_addr_phase_active <= 1;
                read_data_phase_active <= 1;
                expected_read_beats <= ARLEN + 1;
                read_beat_count <= 0;
            end
            
            // Read data phase tracking
            if (RVALID && RREADY) begin
                read_beat_count <= read_beat_count + 1;
                if (RLAST) begin
                    read_addr_phase_active <= 0;
                    read_data_phase_active <= 0;
                end
            end
        end
    end
    
    // Boundary crossing detection
    always_comb begin
        write_crosses_4kb_boundary = ((AWADDR & 12'hFFF) + ((AWLEN + 1) << AWSIZE)) > 12'hFFF;
        read_crosses_4kb_boundary = ((ARADDR & 12'hFFF) + ((ARLEN + 1) << ARSIZE)) > 12'hFFF;
        write_addr_in_memory_range = ((AWADDR >> 2) + (AWLEN + 1)) <= MEMORY_DEPTH;
        read_addr_in_memory_range = ((ARADDR >> 2) + (ARLEN + 1)) <= MEMORY_DEPTH;
    end

    // ========================================================================
    // AXI4 PROTOCOL COMPLIANCE ASSERTIONS
    // ========================================================================

    // ------------------------------------------------------------------------
    // RESET BEHAVIOR ASSERTIONS
    // ------------------------------------------------------------------------
    
    // All valid signals must be low during reset
    property reset_valid_signals_low;
        @(posedge clk) !ARESTN |-> (!AWVALID && !WVALID && !BVALID && !ARVALID && !RVALID);
    endproperty
    assert_reset_valid_signals_low: assert property (reset_valid_signals_low)
        else $error("ASSERTION FAILED: Valid signals not deasserted during reset");
    
    // All ready signals behavior during reset (implementation dependent)
    property reset_ready_signals_defined;
        @(posedge clk) !ARESTN |-> (!$isunknown(AWREADY) && !$isunknown(WREADY) && 
                                   !$isunknown(BREADY) && !$isunknown(ARREADY) && !$isunknown(RREADY));
    endproperty
    assert_reset_ready_signals_defined: assert property (reset_ready_signals_defined)
        else $error("ASSERTION FAILED: Ready signals have unknown values during reset");

    // ------------------------------------------------------------------------
    // WRITE ADDRESS CHANNEL ASSERTIONS
    // ------------------------------------------------------------------------
    
    // AWVALID once asserted, must remain high until AWREADY
    property awvalid_stable_until_awready;
        @(posedge clk) disable iff (!ARESTN)
        (AWVALID && !AWREADY) |=> AWVALID;
    endproperty
    assert_awvalid_stable: assert property (awvalid_stable_until_awready)
        else $error("ASSERTION FAILED: AWVALID deasserted before AWREADY handshake");
    
    // AWADDR must remain stable when AWVALID is high until handshake
    property awaddr_stable_during_valid;
        @(posedge clk) disable iff (!ARESTN)
        (AWVALID && !AWREADY) |=> $stable(AWADDR);
    endproperty
    assert_awaddr_stable: assert property (awaddr_stable_during_valid)
        else $error("ASSERTION FAILED: AWADDR changed during valid period");
    
    // AWLEN must remain stable when AWVALID is high until handshake
    property awlen_stable_during_valid;
        @(posedge clk) disable iff (!ARESTN)
        (AWVALID && !AWREADY) |=> $stable(AWLEN);
    endproperty
    assert_awlen_stable: assert property (awlen_stable_during_valid)
        else $error("ASSERTION FAILED: AWLEN changed during valid period");
    
    // AWSIZE must remain stable when AWVALID is high until handshake  
    property awsize_stable_during_valid;
        @(posedge clk) disable iff (!ARESTN)
        (AWVALID && !AWREADY) |=> $stable(AWSIZE);
    endproperty
    assert_awsize_stable: assert property (awsize_stable_during_valid)
        else $error("ASSERTION FAILED: AWSIZE changed during valid period");
    
    // AWLEN should not exceed maximum burst length (AXI4: 255, but design may have lower limit)
    property awlen_within_limits;
        @(posedge clk) disable iff (!ARESTN)
        AWVALID |-> (AWLEN < MAX_BURST_LENGTH);
    endproperty
    assert_awlen_limits: assert property (awlen_within_limits)
        else $error("ASSERTION FAILED: AWLEN exceeds maximum burst length");

    // AWSIZE should be valid (0, 1, 2, 3 for byte, halfword, word, doubleword)
    property awsize_valid_encoding;
        @(posedge clk) disable iff (!ARESTN)
        AWVALID |-> (AWSIZE inside {3'b000, 3'b001, 3'b010, 3'b011});
    endproperty
    assert_awsize_valid: assert property (awsize_valid_encoding)
        else $error("ASSERTION FAILED: AWSIZE has invalid encoding");

    // ------------------------------------------------------------------------
    // WRITE DATA CHANNEL ASSERTIONS
    // ------------------------------------------------------------------------
    
    // WVALID once asserted, must remain high until WREADY
    property wvalid_stable_until_wready;
        @(posedge clk) disable iff (!ARESTN)
        (WVALID && !WREADY) |=> WVALID;
    endproperty
    assert_wvalid_stable: assert property (wvalid_stable_until_wready)
        else $error("ASSERTION FAILED: WVALID deasserted before WREADY handshake");
    
    // WDATA must remain stable when WVALID is high until handshake
    property wdata_stable_during_valid;
        @(posedge clk) disable iff (!ARESTN)
        (WVALID && !WREADY) |=> $stable(WDATA);
    endproperty
    assert_wdata_stable: assert property (wdata_stable_during_valid)
        else $error("ASSERTION FAILED: WDATA changed during valid period");
    
    // WLAST must remain stable when WVALID is high until handshake
    property wlast_stable_during_valid;
        @(posedge clk) disable iff (!ARESTN)
        (WVALID && !WREADY) |=> $stable(WLAST);
    endproperty
    assert_wlast_stable: assert property (wlast_stable_during_valid)
        else $error("ASSERTION FAILED: WLAST changed during valid period");
    
    // WLAST must be asserted on the last data beat
    property wlast_asserted_on_last_beat;
        @(posedge clk) disable iff (!ARESTN)
        (WVALID && WREADY && write_data_phase_active && (write_beat_count == (expected_write_beats - 1))) 
        |-> WLAST;
    endproperty
    assert_wlast_on_last_beat: assert property (wlast_asserted_on_last_beat)
        else $error("ASSERTION FAILED: WLAST not asserted on last write beat");
    
    // WLAST must not be asserted before the last beat
    property wlast_not_early;
        @(posedge clk) disable iff (!ARESTN)
        (WVALID && WREADY && write_data_phase_active && (write_beat_count < (expected_write_beats - 1)))
        |-> !WLAST;
    endproperty
    assert_wlast_not_early: assert property (wlast_not_early)
        else $error("ASSERTION FAILED: WLAST asserted before last write beat");
    
    // Write data must follow write address (can't have WVALID without prior AWVALID acceptance)
    property write_data_follows_address;
        @(posedge clk) disable iff (!ARESTN)
        (WVALID && !write_data_phase_active) |-> $past(AWVALID && AWREADY);
    endproperty
    assert_write_data_follows_address: assert property (write_data_follows_address)
        else $error("ASSERTION FAILED: Write data phase started without address phase completion");

    // ------------------------------------------------------------------------
    // WRITE RESPONSE CHANNEL ASSERTIONS  
    // ------------------------------------------------------------------------
    
    // BVALID once asserted, must remain high until BREADY
    property bvalid_stable_until_bready;
        @(posedge clk) disable iff (!ARESTN)
        (BVALID && !BREADY) |=> BVALID;
    endproperty
    assert_bvalid_stable: assert property (bvalid_stable_until_bready)
        else $error("ASSERTION FAILED: BVALID deasserted before BREADY handshake");
    
    // BRESP must remain stable when BVALID is high until handshake
    property bresp_stable_during_valid;
        @(posedge clk) disable iff (!ARESTN)
        (BVALID && !BREADY) |=> $stable(BRESP);
    endproperty
    assert_bresp_stable: assert property (bresp_stable_during_valid)
        else $error("ASSERTION FAILED: BRESP changed during valid period");
    
    // Write response must follow completion of write data phase
    property write_response_follows_data;
        @(posedge clk) disable iff (!ARESTN)
        (BVALID && !write_resp_phase_active) |-> $past(WVALID && WREADY && WLAST);
    endproperty
    assert_write_response_follows_data: assert property (write_response_follows_data)
        else $error("ASSERTION FAILED: Write response phase started without data phase completion");

    // BRESP should be valid (OKAY, EXOKAY, SLVERR, DECERR)
    property bresp_valid_encoding;
        @(posedge clk) disable iff (!ARESTN)
        BVALID |-> (BRESP inside {2'b00, 2'b01, 2'b10, 2'b11});
    endproperty
    assert_bresp_valid: assert property (bresp_valid_encoding)
        else $error("ASSERTION FAILED: BRESP has invalid encoding");

    // ------------------------------------------------------------------------
    // READ ADDRESS CHANNEL ASSERTIONS
    // ------------------------------------------------------------------------
    
    // ARVALID once asserted, must remain high until ARREADY
    property arvalid_stable_until_arready;
        @(posedge clk) disable iff (!ARESTN)
        (ARVALID && !ARREADY) |=> ARVALID;
    endproperty
    assert_arvalid_stable: assert property (arvalid_stable_until_arready)
        else $error("ASSERTION FAILED: ARVALID deasserted before ARREADY handshake");
    
    // ARADDR must remain stable when ARVALID is high until handshake
    property araddr_stable_during_valid;
        @(posedge clk) disable iff (!ARESTN)
        (ARVALID && !ARREADY) |=> $stable(ARADDR);
    endproperty
    assert_araddr_stable: assert property (araddr_stable_during_valid)
        else $error("ASSERTION FAILED: ARADDR changed during valid period");
    
    // ARLEN must remain stable when ARVALID is high until handshake
    property arlen_stable_during_valid;
        @(posedge clk) disable iff (!ARESTN)
        (ARVALID && !ARREADY) |=> $stable(ARLEN);
    endproperty
    assert_arlen_stable: assert property (arlen_stable_during_valid)
        else $error("ASSERTION FAILED: ARLEN changed during valid period");
    
    // ARSIZE must remain stable when ARVALID is high until handshake
    property arsize_stable_during_valid;
        @(posedge clk) disable iff (!ARESTN)
        (ARVALID && !ARREADY) |=> $stable(ARSIZE);
    endproperty
    assert_arsize_stable: assert property (arsize_stable_during_valid)
        else $error("ASSERTION FAILED: ARSIZE changed during valid period");

    // ARLEN should not exceed maximum burst length
    property arlen_within_limits;
        @(posedge clk) disable iff (!ARESTN)
        ARVALID |-> (ARLEN < MAX_BURST_LENGTH);
    endproperty
    assert_arlen_limits: assert property (arlen_within_limits)
        else $error("ASSERTION FAILED: ARLEN exceeds maximum burst length");

    // ARSIZE should be valid 
    property arsize_valid_encoding;
        @(posedge clk) disable iff (!ARESTN)
        ARVALID |-> (ARSIZE inside {3'b000, 3'b001, 3'b010, 3'b011});
    endproperty
    assert_arsize_valid: assert property (arsize_valid_encoding)
        else $error("ASSERTION FAILED: ARSIZE has invalid encoding");

    // ------------------------------------------------------------------------
    // READ DATA CHANNEL ASSERTIONS
    // ------------------------------------------------------------------------
    
    // RVALID once asserted, must remain high until RREADY
    property rvalid_stable_until_rready;
        @(posedge clk) disable iff (!ARESTN)
        (RVALID && !RREADY) |=> RVALID;
    endproperty
    assert_rvalid_stable: assert property (rvalid_stable_until_rready)
        else $error("ASSERTION FAILED: RVALID deasserted before RREADY handshake");
    
    // RDATA must remain stable when RVALID is high until handshake
    property rdata_stable_during_valid;
        @(posedge clk) disable iff (!ARESTN)
        (RVALID && !RREADY) |=> $stable(RDATA);
    endproperty
    assert_rdata_stable: assert property (rdata_stable_during_valid)
        else $error("ASSERTION FAILED: RDATA changed during valid period");
    
    // RRESP must remain stable when RVALID is high until handshake
    property rresp_stable_during_valid;
        @(posedge clk) disable iff (!ARESTN)
        (RVALID && !RREADY) |=> $stable(RRESP);
    endproperty
    assert_rresp_stable: assert property (rresp_stable_during_valid)
        else $error("ASSERTION FAILED: RRESP changed during valid period");
    
    // RLAST must remain stable when RVALID is high until handshake
    property rlast_stable_during_valid;
        @(posedge clk) disable iff (!ARESTN)
        (RVALID && !RREADY) |=> $stable(RLAST);
    endproperty
    assert_rlast_stable: assert property (rlast_stable_during_valid)
        else $error("ASSERTION FAILED: RLAST changed during valid period");
    
    // RLAST must be asserted on the last data beat
    property rlast_asserted_on_last_beat;
        @(posedge clk) disable iff (!ARESTN)
        (RVALID && RREADY && read_data_phase_active && (read_beat_count == (expected_read_beats - 1)))
        |-> RLAST;
    endproperty
    assert_rlast_on_last_beat: assert property (rlast_asserted_on_last_beat)
        else $error("ASSERTION FAILED: RLAST not asserted on last read beat");
    
    // RLAST must not be asserted before the last beat
    property rlast_not_early;
        @(posedge clk) disable iff (!ARESTN)
        (RVALID && RREADY && read_data_phase_active && (read_beat_count < (expected_read_beats - 1)))
        |-> !RLAST;
    endproperty
    assert_rlast_not_early: assert property (rlast_not_early)
        else $error("ASSERTION FAILED: RLAST asserted before last read beat");
    
    // Read data must follow read address
    property read_data_follows_address;
        @(posedge clk) disable iff (!ARESTN)
        (RVALID && !read_data_phase_active) |-> $past(ARVALID && ARREADY);
    endproperty
    assert_read_data_follows_address: assert property (read_data_follows_address)
        else $error("ASSERTION FAILED: Read data phase started without address phase completion");

    // RRESP should be valid
    property rresp_valid_encoding;
        @(posedge clk) disable iff (!ARESTN)
        RVALID |-> (RRESP inside {2'b00, 2'b01, 2'b10, 2'b11});
    endproperty
    assert_rresp_valid: assert property (rresp_valid_encoding)
        else $error("ASSERTION FAILED: RRESP has invalid encoding");

    // ========================================================================
    // DESIGN-SPECIFIC ASSERTIONS
    // ========================================================================

    // ------------------------------------------------------------------------
    // MEMORY BOUNDARY ASSERTIONS
    // ------------------------------------------------------------------------
    
    // Address should be within memory range for OKAY response
    property write_addr_in_range_okay_response;
        @(posedge clk) disable iff (!ARESTN)
        (BVALID && (BRESP == 2'b00) && $past(AWVALID && AWREADY)) 
        |-> $past(write_addr_in_memory_range);
    endproperty
    assert_write_addr_range_okay: assert property (write_addr_in_range_okay_response)
        else $error("ASSERTION FAILED: OKAY response for out-of-range write address");
    
    property read_addr_in_range_okay_response;
        @(posedge clk) disable iff (!ARESTN)
        (RVALID && (RRESP == 2'b00) && $past(ARVALID && ARREADY))
        |-> $past(read_addr_in_memory_range);
    endproperty
    assert_read_addr_range_okay: assert property (read_addr_in_range_okay_response)
        else $error("ASSERTION FAILED: OKAY response for out-of-range read address");

    // 4KB boundary crossing should generate SLVERR
    property write_4kb_boundary_error;
        @(posedge clk) disable iff (!ARESTN)
        (BVALID && $past(AWVALID && AWREADY) && $past(write_crosses_4kb_boundary))
        |-> (BRESP == 2'b10);
    endproperty
    assert_write_4kb_boundary_error: assert property (write_4kb_boundary_error)
        else $error("ASSERTION FAILED: 4KB boundary crossing should generate SLVERR for write");
    
    property read_4kb_boundary_error;
        @(posedge clk) disable iff (!ARESTN)
        (RVALID && $past(ARVALID && ARREADY) && $past(read_crosses_4kb_boundary))
        |-> (RRESP == 2'b10);
    endproperty
    assert_read_4kb_boundary_error: assert property (read_4kb_boundary_error)
        else $error("ASSERTION FAILED: 4KB boundary crossing should generate SLVERR for read");

    // ------------------------------------------------------------------------
    // ADDRESS ALIGNMENT ASSERTIONS
    // ------------------------------------------------------------------------
    
    // Address should be aligned to transfer size
    property write_addr_alignment;
        @(posedge clk) disable iff (!ARESTN)
        (AWVALID && AWREADY) |-> ((AWADDR & ((1 << AWSIZE) - 1)) == 0);
    endproperty
    assert_write_addr_alignment: assert property (write_addr_alignment)
        else $warning("WARNING: Write address not aligned to transfer size");
    
    property read_addr_alignment;
        @(posedge clk) disable iff (!ARESTN)
        (ARVALID && ARREADY) |-> ((ARADDR & ((1 << ARSIZE) - 1)) == 0);
    endproperty
    assert_read_addr_alignment: assert property (read_addr_alignment)
        else $warning("WARNING: Read address not aligned to transfer size");

    // ------------------------------------------------------------------------
    // BURST LENGTH CONSISTENCY ASSERTIONS
    // ------------------------------------------------------------------------
    
    // Number of write data beats should match AWLEN + 1
    property write_beats_match_awlen;
        @(posedge clk) disable iff (!ARESTN)
        (WVALID && WREADY && WLAST) |-> (write_beat_count == (expected_write_beats - 1));
    endproperty
    assert_write_beats_match_awlen: assert property (write_beats_match_awlen)
        else $error("ASSERTION FAILED: Number of write beats doesn't match AWLEN + 1");
    
    // Number of read data beats should match ARLEN + 1  
    property read_beats_match_arlen;
        @(posedge clk) disable iff (!ARESTN)
        (RVALID && RREADY && RLAST) |-> (read_beat_count == (expected_read_beats - 1));
    endproperty
    assert_read_beats_match_arlen: assert property (read_beats_match_arlen)
        else $error("ASSERTION FAILED: Number of read beats doesn't match ARLEN + 1");

    // ------------------------------------------------------------------------
    // TIMEOUT AND LIVELOCK PREVENTION ASSERTIONS
    // ------------------------------------------------------------------------
    
    // AWREADY should not remain low indefinitely when AWVALID is high
    property awready_timeout_prevention;
        @(posedge clk) disable iff (!ARESTN)
        AWVALID |-> ##[1:100] AWREADY;
    endproperty
    assert_awready_timeout: assert property (awready_timeout_prevention)
        else $error("ASSERTION FAILED: AWREADY timeout - potential livelock");
    
    // WREADY should not remain low indefinitely when WVALID is high
    property wready_timeout_prevention;
        @(posedge clk) disable iff (!ARESTN)
        WVALID |-> ##[1:100] WREADY;
    endproperty
    assert_wready_timeout: assert property (wready_timeout_prevention)
        else $error("ASSERTION FAILED: WREADY timeout - potential livelock");
    
    // ARREADY should not remain low indefinitely when ARVALID is high
    property arready_timeout_prevention;
        @(posedge clk) disable iff (!ARESTN)
        ARVALID |-> ##[1:100] ARREADY;
    endproperty
    assert_arready_timeout: assert property (arready_timeout_prevention)
        else $error("ASSERTION FAILED: ARREADY timeout - potential livelock");

    // ========================================================================
    // COVERAGE ASSERTIONS AND MONITORS
    // ========================================================================

    // ------------------------------------------------------------------------
    // FUNCTIONAL COVERAGE MONITORS
    // ------------------------------------------------------------------------
    
    // Monitor successful write transactions
    sequence write_transaction_complete;
        (AWVALID && AWREADY) ##[1:$] (WVALID && WREADY && WLAST) ##[1:$] (BVALID && BREADY);
    endsequence
    
    property write_transaction_completed;
        @(posedge clk) disable iff (!ARESTN) write_transaction_complete;
    endproperty
    cover_write_transaction_complete: cover property (write_transaction_completed);
    
    // Monitor successful read transactions
    sequence read_transaction_complete;
        (ARVALID && ARREADY) ##[1:$] (RVALID && RREADY && RLAST);
    endsequence
    
    property read_transaction_completed;
        @(posedge clk) disable iff (!ARESTN) read_transaction_complete;
    endproperty
    cover_read_transaction_complete: cover property (read_transaction_completed);
    
    // Monitor error responses
    property write_error_response;
        @(posedge clk) disable iff (!ARESTN)
        (BVALID && BREADY && (BRESP != 2'b00));
    endproperty
    cover_write_error_response: cover property (write_error_response);
    
    property read_error_response;
        @(posedge clk) disable iff (!ARESTN)
        (RVALID && RREADY && (RRESP != 2'b00));
    endproperty
    cover_read_error_response: cover property (read_error_response);
    
    // Monitor different burst lengths
    property single_beat_write;
        @(posedge clk) disable iff (!ARESTN)
        (AWVALID && AWREADY && (AWLEN == 0));
    endproperty
    cover_single_beat_write: cover property (single_beat_write);
    
    property burst_write;
        @(posedge clk) disable iff (!ARESTN)
        (AWVALID && AWREADY && (AWLEN > 0));
    endproperty
    cover_burst_write: cover property (burst_write);
    
    // Monitor boundary crossing scenarios
    property boundary_crossing_write;
        @(posedge clk) disable iff (!ARESTN)
        (AWVALID && AWREADY && write_crosses_4kb_boundary);
    endproperty
    cover_boundary_crossing_write: cover property (boundary_crossing_write);
    
    property boundary_crossing_read;
        @(posedge clk) disable iff (!ARESTN)
        (ARVALID && ARREADY && read_crosses_4kb_boundary);
    endproperty
    cover_boundary_crossing_read: cover property (boundary_crossing_read);

    // ------------------------------------------------------------------------
    // ASSERTION CONTROL AND REPORTING
    // ------------------------------------------------------------------------
    
    // Assertion counter for debugging
    int assertion_pass_count = 0;
    int assertion_fail_count = 0;
    
    // Final report task (to be called at end of simulation)
    task display_assertion_report();
        $display("========================================");
        $display("AXI4 ASSERTION VERIFICATION REPORT");
        $display("========================================");
        $display("Total Assertions Passed: %0d", assertion_pass_count);
        $display("Total Assertions Failed: %0d", assertion_fail_count);
        $display("Overall Pass Rate: %0.1f%%", 
                 (assertion_pass_count * 100.0) / (assertion_pass_count + assertion_fail_count));
        $display("========================================");
    endtask

endmodule

// ============================================================================
// BIND STATEMENT FOR CONNECTING ASSERTIONS TO DUT
// ============================================================================
// This bind statement should be included in your testbench or top-level module
// to connect the assertions to your AXI4 DUT signals

/*
bind your_axi4_dut_module_name axi4_assertions #(
    .DATA_WIDTH(32),
    .ADDR_WIDTH(16), 
    .MEMORY_DEPTH(1024),
    .MAX_BURST_LENGTH(16)
) u_axi4_assertions (
    .clk(your_clock_signal),
    .ARESTN(your_reset_signal),
    .AWADDR(your_awaddr_signal),
    .AWLEN(your_awlen_signal),
    .AWSIZE(your_awsize_signal),
    .AWBURST(your_awburst_signal),
    .AWVALID(your_awvalid_signal),
    .AWREADY(your_awready_signal),
    .WDATA(your_wdata_signal),
    .WSTRB(your_wstrb_signal),
    .WLAST(your_wlast_signal),
    .WVALID(your_wvalid_signal),
    .WREADY(your_wready_signal),
    .BRESP(your_bresp_signal),
    .BVALID(your_bvalid_signal),
    .BREADY(your_bready_signal),
    .ARADDR(your_araddr_signal),
    .ARLEN(your_arlen_signal),
    .ARSIZE(your_arsize_signal),
    .ARBURST(your_arburst_signal),
    .ARVALID(your_arvalid_signal),
    .ARREADY(your_arready_signal),
    .RDATA(your_rdata_signal),
    .RRESP(your_rresp_signal),
    .RLAST(your_rlast_signal),
    .RVALID(your_rvalid_signal),
    .RREADY(your_rready_signal)
);
*/
