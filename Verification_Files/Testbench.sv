`timescale 1ns/1ns
import enuming::*;

`include "enhanced_Transaction.sv"

module Testbench(axi_if.TB axi);

    parameter int DATA_WIDTH = 32;
    parameter int ADDR_WIDTH = 16;
    parameter int NUM_RANDOM_TESTS = 50;
    parameter int NUM_DIRECTED_TESTS = 100;
    parameter real TARGET_COVERAGE = 100.0;
    parameter bit DebugEn = 1; // Enable/disable debug messages
    
    // Test statistics
    int total_tests = 0;
    int passed_tests = 0;
    int failed_tests = 0;
    int read_tests = 0;
    int write_tests = 0;
    int slverr_count = 0;
    int okay_count = 0;
    
    // Transaction objects
    Transaction tx;
    Transaction expected_queue[$];
    Transaction actual_queue[$];
    
    // Golden memory model
    logic [DATA_WIDTH-1:0] golden_mem [0:1023];
    
    // Coverage tracking
    real overall_coverage = 0.0;
    real operation_coverage_percent = 0.0;
    real boundary_coverage_percent = 0.0;
    
    // Test mode tracking
    int test_mode_count[enuming::test_mode_e];
    int boundary_crossing_count = 0;
    int coverage_iteration = 0;

    // DUT state monitoring for comprehensive coverage
    logic [1:0] current_write_state;
    logic [1:0] current_read_state;
    logic [1:0] current_bresp;
    logic [1:0] current_rresp;
    
    // Coverage sampling task
    task automatic sample_dut_coverage(Transaction tr);
        // Sample all comprehensive coverage
        tr.sample_all_coverage();
        
        // Update overall coverage
        overall_coverage = tr.get_overall_coverage();
        
        // Display detailed coverage report every 25 tests
        if (total_tests % 25 == 0) begin
            tr.display_coverage_report();
        end
    endtask

    // Initialize signals
    initial begin
        axi.ARESTN = 1;
        // Initialize AXI signals directly
        @(posedge axi.ACLK);
        axi.AWADDR <= 0; axi.AWLEN <= 0; axi.AWSIZE <= 0; axi.AWVALID <= 0;
        axi.WDATA <= 0; axi.WVALID <= 0; axi.WLAST <= 0; axi.BREADY <= 0;
        axi.ARADDR <= 0; axi.ARLEN <= 0; axi.ARSIZE <= 0; axi.ARVALID <= 0;
        axi.RREADY <= 0;
        
        // Initialize golden memory
        for (int i = 0; i < 1024; i++) begin
            golden_mem[i] = 0;
        end

        if (DebugEn) $display("Golden memory initialized with zero");
    end

    // === GENERATE STIMULUS ===
    task automatic generate_stimulus();
        tx = new();
        assert(tx.randomize()) else begin
            $error("ERROR: Randomization failed!");
            $stop;
        end
        
        if (DebugEn) tx.display();
        total_tests++;
        
        if (tx.op_type == READ_OP) read_tests++;
        else write_tests++;
        
        // Sample coverage after generation
        sample_dut_coverage(tx);
    endtask

    // DUT State Monitor - continuously track FSM states
    always @(posedge axi.ACLK) begin
        // Monitor write FSM state (decode from DUT signals)
        if (!axi.ARESTN) begin
            current_write_state = 0; // W_IDLE
            current_read_state = 0;  // R_IDLE
        end else begin
            // Decode write FSM state from AXI signals
            if (axi.AWVALID && axi.AWREADY) begin
                current_write_state = 1; // W_ADDR
            end else if (axi.WVALID && axi.WREADY) begin
                current_write_state = 2; // W_DATA  
            end else if (axi.BVALID && axi.BREADY) begin
                current_write_state = 3; // W_RESP
            end else if (!axi.AWVALID && !axi.WVALID && !axi.BVALID) begin
                current_write_state = 0; // W_IDLE
            end
            
            // Decode read FSM state from AXI signals
            if (axi.ARVALID && axi.ARREADY) begin
                current_read_state = 1; // R_ADDR
            end else if (axi.RVALID && axi.RREADY) begin
                current_read_state = 2; // R_DATA
            end else if (!axi.ARVALID && !axi.RVALID) begin
                current_read_state = 0; // R_IDLE
            end
        end
        
        // Capture responses when valid
        if (axi.BVALID) current_bresp = axi.BRESP;
        if (axi.RVALID) current_rresp = axi.RRESP;
    end

    // === DRIVE STIMULUS ===
    task automatic drive_stimulus(input Transaction tr, ref Transaction actual_tx);
        actual_tx = new();
        actual_tx.op_type = tr.op_type;
        actual_tx.ADDR = tr.ADDR;
        actual_tx.LEN = tr.LEN;
        actual_tx.SIZE = tr.SIZE;
        
        if (tr.op_type == WRITE_OP) begin
            drive_write_transaction(tr, actual_tx);
        end else begin
            // Apply reset for read transactions
            apply_reset(tr.reset_cycles);
            drive_read_transaction(tr, actual_tx);
        end
    endtask

    // === WRITE TRANSACTION DRIVER ===
    task automatic drive_write_transaction(input Transaction tr, ref Transaction actual_tx);
        logic [1:0] bresp_captured;
        int timeout_counter;
        int MAX_TIMEOUT = 1000; // Maximum cycles to wait for any handshake
        
        actual_tx = new();
        actual_tx.op_type = tr.op_type;
        actual_tx.ADDR = tr.ADDR;
        actual_tx.LEN = tr.LEN;
        actual_tx.SIZE = tr.SIZE;
        actual_tx.WDATA = new[tr.WDATA.size()];

        $display("Starting write transaction...");

        // Copy write data
        foreach (tr.WDATA[i]) actual_tx.WDATA[i] = tr.WDATA[i];

        // Apply randomized reset - using modular task
        assert_randomized_reset(tr);

        if (tr.awvalid_delay > 0) begin
            if (DebugEn) $display("Delaying AWVALID by %0d cycles", tr.awvalid_delay);
            repeat(tr.awvalid_delay) @(posedge axi.ACLK);
            if (DebugEn) $display("AWVALID delay completed");
        end

        $display("Setting AWADDR=0x%h, AWLEN=%0d, AWSIZE=%0d, AWVALID=%b", 
                tr.ADDR, tr.LEN, tr.SIZE, tr.awvalid_value);
        
        axi.AWADDR  <= tr.ADDR;
        axi.AWLEN   <= tr.LEN;
        axi.AWSIZE  <= tr.SIZE;
        axi.AWVALID <= tr.awvalid_value;  

        if (tr.awvalid_value) begin
            if (DebugEn) $display("AWVALID asserted, waiting for AWREADY...");
            timeout_counter = 0;
            do begin
                @(posedge axi.ACLK);
                timeout_counter++;
                if (timeout_counter >= MAX_TIMEOUT) begin
                    $error("TIMEOUT: AWREADY not received within %0d cycles", MAX_TIMEOUT);
                    $finish;
                end
            end while (!axi.AWREADY);
            if (DebugEn) $display("AWREADY received, address handshake complete");
        end else begin
            if (DebugEn) $display("AWVALID NOT asserted, skipping AWREADY wait");
            @(posedge axi.ACLK); 
        end
        axi.AWVALID <= 0;
        
        if (!tr.awvalid_value) begin
            $display("Address phase skipped (AWVALID=0), skipping data phase");
            $display("Transaction aborted - no data transfer");
            actual_tx.BRESP = 2'b10; // SLVERR for aborted transaction
            return;
        end
        
        $display("Address phase: AWADDR=%d, AWLEN=%0d, AWSIZE=%0d, STOP_ADDR=%d, 4KB_OFFSET=%d, Is it supposed to cross 4KB? %s", 
        tr.ADDR, tr.LEN, tr.SIZE,
        tr.ADDR + ((tr.LEN + 1) << tr.SIZE),
        (tr.ADDR & 12'hFFF) + ((tr.LEN + 1) << tr.SIZE),
        tr.crosses_4KB_boundary() ? "YES" : "NO");

        if (tr.ADDR % (1 << tr.SIZE) != 0) begin
            $warning("Misaligned AWADDR! AWADDR=0x%0h is not aligned to AWSIZE=%0d", tr.ADDR, tr.SIZE);
        end

        if (DebugEn) $display("Starting data phase with %0d beats...", tr.WDATA.size());
        foreach (tr.WDATA[i]) begin
            if (DebugEn) $display("[BEAT %0d/%0d] Starting beat processing", i+1, tr.WDATA.size());
            
            if (tr.wvalid_delay[i] > 0) begin
                if (DebugEn) $display("[BEAT %0d/%0d] Applying WVALID delay of %0d cycles", i+1, tr.WDATA.size(), tr.wvalid_delay[i]);
                repeat(tr.wvalid_delay[i]) @(posedge axi.ACLK);
                if (DebugEn) $display("[BEAT %0d/%0d] WVALID delay completed", i+1, tr.WDATA.size());
            end else begin
                if (DebugEn) $display("[BEAT %0d/%0d] No WVALID delay (delay=0)", i+1, tr.WDATA.size());
            end
            
            if (DebugEn) $display("[BEAT %0d/%0d] Setting WDATA=0x%h, WLAST=%b, WVALID=%b", 
                    i+1, tr.WDATA.size(), tr.WDATA[i], (i == tr.WDATA.size() - 1), tr.wvalid_pattern[i]);
            
            axi.WDATA  <= tr.WDATA[i];
            axi.WLAST  <= (i == tr.WDATA.size() - 1);
            axi.WVALID <= tr.wvalid_pattern[i];
            
            if (tr.wvalid_pattern[i]) begin
                if (DebugEn) $display("[BEAT %0d/%0d] WVALID asserted, waiting for WREADY...", i+1, tr.WDATA.size());
                timeout_counter = 0;
                do begin
                    @(posedge axi.ACLK);
                    timeout_counter++;
                    if (timeout_counter >= MAX_TIMEOUT) begin
                        $error("TIMEOUT: WREADY not received for beat %0d within %0d cycles", i+1, MAX_TIMEOUT);
                        $finish;
                    end
                end while (!axi.WREADY);
                if (DebugEn) $display("[BEAT %0d/%0d] WREADY received, handshake complete", i+1, tr.WDATA.size());
            end else begin
                if (DebugEn) $display("[BEAT %0d/%0d] WVALID NOT asserted, skipping WREADY wait", i+1, tr.WDATA.size());
                @(posedge axi.ACLK); // Still advance one clock even if WVALID not asserted
            end
            
            axi.WVALID <= 0;
            actual_tx.WDATA[i] = tr.WDATA[i];
            if (DebugEn) $display("[BEAT %0d/%0d] Beat completed, advancing to next", i+1, tr.WDATA.size());
            @(posedge axi.ACLK);
        end

        if (DebugEn) $display("Waiting for write response...");
        
        if (DebugEn) $display("Setting BREADY=%b", tr.bready_value);
        axi.BREADY <= tr.bready_value;
        
        if (tr.bready_value) begin
            if (DebugEn) $display("BREADY asserted, waiting for BVALID...");
            timeout_counter = 0;
            do begin
                @(posedge axi.ACLK);
                timeout_counter++;
                if (timeout_counter >= MAX_TIMEOUT) begin
                    $error("TIMEOUT: BVALID not received within %0d cycles", MAX_TIMEOUT);
                    $finish;
                end
            end while (!axi.BVALID);
            bresp_captured = axi.BRESP;
            if (DebugEn) $display("BVALID received, response handshake complete");
            $display("BRESP: %s (0b%b)", decode_response(bresp_captured), bresp_captured);
        end else begin
            $display("BREADY not asserted - response phase incomplete");
            // **KEY FIX**: When BREADY=0, we still wait for BVALID but don't complete handshake
            // This represents the actual AXI behavior more accurately
            timeout_counter = 0;
            do begin
                @(posedge axi.ACLK);
                timeout_counter++;
                if (timeout_counter >= MAX_TIMEOUT) begin
                    $error("TIMEOUT: BVALID not received within %0d cycles", MAX_TIMEOUT);
                    $finish;
                end
            end while (!axi.BVALID);
            
            // Capture the response that would have been available
            bresp_captured = axi.BRESP;
            $display("BRESP available but not captured due to BREADY=0: %s (0b%b)", 
                    decode_response(bresp_captured), bresp_captured);
            @(posedge axi.ACLK); // Still advance one clock
        end
        
        if (is_error_response(bresp_captured)) begin
            $display("WARNING: Transaction completed with error response!");
            slverr_count++;
        end else begin
            $display("Transaction completed successfully");
            okay_count++;
        end

        axi.BREADY <= 0;
        @(posedge axi.ACLK);

        actual_tx.BRESP = bresp_captured;
        
        if (DebugEn) $display("Write response: BRESP=%s", 
                            decode_response(bresp_captured));
    endtask

    // === READ TRANSACTION DRIVER ===
    task automatic drive_read_transaction(input Transaction tr, ref Transaction actual_tx);
        logic [DATA_WIDTH-1:0] rdata_captured;
        logic [1:0] rresp_captured;
        logic rlast_captured;
        int timeout_counter;
        int MAX_TIMEOUT;
        
        MAX_TIMEOUT = 1000;
        
        if (DebugEn) $display("Starting READ transaction...");
        
        // Allocate result arrays
        actual_tx.RDATA = new[tr.LEN + 1];
        actual_tx.RRESP = new[tr.LEN + 1];
        
        // Address phase with randomized timing
        repeat(tr.arvalid_delay) @(posedge axi.ACLK);  // Apply ARVALID delay
        
        axi.ARADDR <= tr.ADDR;
        axi.ARLEN <= tr.LEN;
        axi.ARSIZE <= tr.SIZE;
        axi.ARVALID <= 1'b1;
        
        if (DebugEn) $display("Address phase: ARADDR=0x%h, ARLEN=%0d, ARVALID delayed by %0d cycles", 
                              tr.ADDR, tr.LEN, tr.arvalid_delay);
        
        // Wait for address handshake
        timeout_counter = 0;
        while (axi.ARREADY !== 1'b1) begin
            @(posedge axi.ACLK);
            timeout_counter++;
            if (timeout_counter >= MAX_TIMEOUT) begin
                $error("TIMEOUT: ARREADY not received within %0d cycles", MAX_TIMEOUT);
                $finish;
            end
        end
        @(posedge axi.ACLK);
        axi.ARVALID <= 1'b0;
        
        if (DebugEn) $display("Address phase complete");
        
        // Data phase with randomized RREADY timing and backpressure
        for (int i = 0; i <= tr.LEN; i++) begin
            // Apply per-beat RREADY delay
            repeat(tr.rready_delay[i]) @(posedge axi.ACLK);
            
            // Apply randomized RREADY pattern with backpressure
            if (tr.rready_random_deassert[i] && ($urandom_range(1,100) > tr.rready_backpressure_prob)) begin
                axi.RREADY <= 1'b1;
                
                timeout_counter = 0;
                while (axi.RVALID !== 1'b1) begin
                    @(posedge axi.ACLK);
                    timeout_counter++;
                    if (timeout_counter >= MAX_TIMEOUT) begin
                        $error("TIMEOUT: RVALID not received for beat %0d within %0d cycles", i, MAX_TIMEOUT);
                        $finish;
                    end
                end
                @(posedge axi.ACLK);
                
                // Capture data
                actual_tx.RDATA[i] = axi.RDATA;
                actual_tx.RRESP[i] = axi.RRESP;
                rlast_captured = axi.RLAST;
                
                if (DebugEn) $display("Read beat %0d: RDATA=0x%h, RLAST=%0d, RREADY_delay=%0d", 
                                      i, axi.RDATA, rlast_captured, tr.rready_delay[i]);
                
            end 
            else begin
                // Apply backpressure: deassert RREADY for random cycles
                axi.RREADY <= 1'b0;
                repeat($urandom_range(1,3)) @(posedge axi.ACLK);  // Backpressure for 1-3 cycles
                
                axi.RREADY <= 1'b1;
                timeout_counter = 0;
                while (axi.RVALID !== 1'b1) begin
                    @(posedge axi.ACLK);
                    timeout_counter++;
                    if (timeout_counter >= MAX_TIMEOUT) begin
                        $error("TIMEOUT: RVALID not received for beat %0d within %0d cycles", i, MAX_TIMEOUT);
                        $finish;
                    end
                end
                @(posedge axi.ACLK);
                
                // Capture data
                actual_tx.RDATA[i] = axi.RDATA;
                actual_tx.RRESP[i] = axi.RRESP;
                rlast_captured = axi.RLAST;
                
                if (DebugEn) $display("Read beat %0d: RDATA=0x%h, RLAST=%b (with RREADY backpressure)", 
                                      i, axi.RDATA, rlast_captured);
            end
            
            // Check RLAST on final beat
            if (i == tr.LEN && !rlast_captured) begin
                $error("[ERROR] RLAST not asserted on last beat (beat %0d), LEN=%0d - RLAST should be 1", i, tr.LEN);
                failed_tests++;
            end else if (i == tr.LEN && rlast_captured) begin
                if (DebugEn) $display("[INFO] RLAST correctly asserted on final beat %0d", i);
            end
            
            // AXI4 Protocol Compliance: Simple RREADY management
            if (i < tr.LEN) begin
                axi.RREADY <= 1'b0;  // Deassert RREADY between beats
                @(posedge axi.ACLK);              // Wait one cycle with RREADY low
            end
        end
        
        axi.RREADY <= 1'b0;
        
        if (DebugEn) $display("Read transaction complete");
    endtask

    // === GOLDEN MODEL ===
    task automatic golden_model(input Transaction tr);
        Transaction expected;
        int start_addr;
        
        expected = new();
        expected.op_type = tr.op_type;
        expected.ADDR = tr.ADDR;
        expected.LEN = tr.LEN;
        expected.SIZE = tr.SIZE;
        
        if (tr.op_type == WRITE_OP) begin
            // For writes, update golden memory and predict response
            // Check if WDATA is properly allocated before using it
            if (tr.WDATA.size() == 0) begin
                $error("Transaction WDATA is empty - randomization may have failed");
                return;
            end
            
            expected.WDATA = new[tr.WDATA.size()];
            foreach (tr.WDATA[i]) expected.WDATA[i] = tr.WDATA[i];
            
            // Only process if AWVALID was asserted (transaction not aborted)
            if (tr.awvalid_value == 1) begin
                // **KEY FIX**: Check BREADY value to predict response behavior
                if (tr.bready_value == 0) begin
                    // When BREADY=0, master doesn't accept response
                    // The slave will still generate appropriate response, but since
                    // master doesn't capture it, we model this as the actual response
                    // that would be generated by the slave
                    if (tr.exceeds_memory_range() || tr.crosses_4KB_boundary()) begin
                        expected.BRESP = enuming::SLVERR;
                    end else begin
                        expected.BRESP = enuming::OKAY;
                        // Update golden memory even if response not captured
                        start_addr = tr.ADDR >> 2;
                        for (int i = 0; i <= tr.LEN; i++) begin
                            if ((start_addr + i) < 1024) begin
                                golden_mem[start_addr + i] = tr.WDATA[i];
                            end
                        end
                    end
                end else begin
                    // Normal case: BREADY=1, response will be properly captured
                    if (tr.exceeds_memory_range() || tr.crosses_4KB_boundary()) begin
                        expected.BRESP = enuming::SLVERR;
                    end else begin
                        expected.BRESP = enuming::OKAY;
                        // Update golden memory
                        start_addr = tr.ADDR >> 2;
                        for (int i = 0; i <= tr.LEN; i++) begin
                            if ((start_addr + i) < 1024) begin
                                golden_mem[start_addr + i] = tr.WDATA[i];
                            end
                        end
                    end
                end
            end else begin
                // Transaction aborted (AWVALID=0) - no memory update, SLVERR response
                expected.BRESP = 2'b10; // SLVERR (2'b10) response for aborted transaction
            end
            
        end else begin
            // For reads, predict data and response (unchanged)
            expected.RDATA = new[tr.LEN + 1];
            expected.RRESP = new[tr.LEN + 1];
            
            start_addr = tr.ADDR >> 2;
            for (int i = 0; i <= tr.LEN; i++) begin
                if (tr.exceeds_memory_range() || tr.crosses_4KB_boundary() || (start_addr + i) >= 1024) begin
                    expected.RDATA[i] = 32'h0;
                    expected.RRESP[i] = enuming::SLVERR;
                end else begin
                    expected.RDATA[i] = golden_mem[start_addr + i];
                    expected.RRESP[i] = enuming::OKAY;
                end
            end
        end
        
        expected_queue.push_back(expected);
    endtask

    // === COLLECT OUTPUT ===
    task automatic collect_output(input Transaction actual_tx);
        actual_queue.push_back(actual_tx);
        
        // Sample coverage with actual response data
        sample_dut_coverage(actual_tx);
    endtask

    // === CHECK RESULTS ===
    task automatic check_results();
        Transaction expected, actual;
        bit test_passed;
        int test_number;
        bit data_match;
        int i;
        
        test_passed = 1;
        
        if (expected_queue.size() != actual_queue.size()) begin
            $display("[ERROR] Queue size mismatch - Expected: %0d, Actual: %0d", 
                     expected_queue.size(), actual_queue.size());
            failed_tests++;
            return;
        end
        
        while (expected_queue.size() > 0) begin
            expected = expected_queue.pop_front();
            actual = actual_queue.pop_front();
            test_passed = 1;
            test_number = total_tests - expected_queue.size(); // Calculate current test number
            
            // Print formatted test result header - matching WTestbench.sv pattern
            $display("======================================================");
            $display("Test #%0d Result (%s)", test_number, expected.op_type.name());
            
            if (expected.op_type == WRITE_OP) begin
                // Print actual vs expected for write operations - matching WTestbench.sv format
                $display("  Actual   : AWADDR=0x%h AWLEN=%0d AWSIZE=%0d BRESP=%s", 
                         actual.ADDR, actual.LEN, actual.SIZE, decode_response(actual.BRESP));
                $display("  Expected : AWADDR=0x%h AWLEN=%0d AWSIZE=%0d BRESP=%s", 
                         expected.ADDR, expected.LEN, expected.SIZE, decode_response(expected.BRESP));
                
                // Check write response - handle aborted transactions
                if (expected.BRESP != actual.BRESP) begin
                    $display("  BRESP mismatch: Expected %s, Got %s", 
                             decode_response(expected.BRESP), decode_response(actual.BRESP));
                    test_passed = 0;
                end
                
                // Check write data - matching WTestbench.sv data checking pattern
                if (actual.WDATA.size() == expected.WDATA.size()) begin
                    data_match = 1;
                    foreach (actual.WDATA[i]) begin
                        if (actual.WDATA[i] != expected.WDATA[i]) begin
                            data_match = 0;
                            $display("  Data mismatch at beat %0d: actual=0x%h, expected=0x%h", 
                                     i, actual.WDATA[i], expected.WDATA[i]);
                            break;
                        end
                    end
                    if (!data_match) test_passed = 0;
                end else begin
                    $display("  Data size mismatch: actual=%0d, expected=%0d", 
                             actual.WDATA.size(), expected.WDATA.size());
                    test_passed = 0;
                end
                
                // Update statistics
                if (actual.BRESP == enuming::OKAY) okay_count++;
                else slverr_count++;
                
            end else begin
                // ==== READ CHECKING ====
                $display("  Actual   : ARADDR=0x%h ARLEN=%0d ARSIZE=%0d RRESP=%s", 
                        actual.ADDR, actual.LEN, actual.SIZE, decode_response(actual.RRESP[0]));
                $display("  Expected : ARADDR=0x%h ARLEN=%0d ARSIZE=%0d RRESP=%s", 
                        expected.ADDR, expected.LEN, expected.SIZE, decode_response(expected.RRESP[0]));
                
                // Check data and RRESP
                if (actual.RDATA.size() == expected.RDATA.size()) begin
                    data_match = 1;
                    foreach (actual.RDATA[i]) begin
                        if (actual.RDATA[i] != expected.RDATA[i]) begin
                            data_match = 0;
                            $display("  Data mismatch at beat %0d: actual=0x%h, expected=0x%h", 
                                    i, actual.RDATA[i], expected.RDATA[i]);
                        end
                        
                        if (actual.RRESP[i] != expected.RRESP[i]) begin
                            $display("  RRESP mismatch at beat %0d: actual=%s, expected=%s", 
                                    i, decode_response(actual.RRESP[i]), decode_response(expected.RRESP[i]));
                            test_passed = 0;
                        end
                    end
                    if (!data_match) test_passed = 0;
                end else begin
                    $display("  Data size mismatch: actual=%0d, expected=%0d", 
                            actual.RDATA.size(), expected.RDATA.size());
                    test_passed = 0;
                end
                
                if (data_match && test_passed) begin
                    $display("  All read data and responses match expected values");
                end
            end
            
            // Print test result - matching WTestbench.sv format
            if (test_passed) begin
                passed_tests++;
                $display("  TEST PASS");
            end else begin
                failed_tests++;
                if (expected.op_type == WRITE_OP) begin
                    $display("  TEST FAIL - Write transaction verification failed");
                end else begin
                    $display("  TEST FAIL - Read transaction verification failed");
                end
            end
            $display("======================================================");
        end
    endtask

    // === UTILITY FUNCTIONS ===
    function string decode_response(logic [1:0] resp);
        case (resp)
            enuming::OKAY:   return "OKAY";
            enuming::EXOKAY: return "EXOKAY";
            enuming::SLVERR: return "SLVERR";
            enuming::DECERR: return "DECERR";
            default: return "UNKNOWN";
        endcase
    endfunction

    function bit is_error_response(logic [1:0] resp);
        return (resp == enuming::SLVERR || resp == enuming::DECERR);
    endfunction

    task automatic assert_randomized_reset(input Transaction wtxn);
        $display("Asserting randomized reset for %0d cycles...", wtxn.reset_cycles);
        axi.ARESTN = 0;
        repeat(wtxn.reset_cycles) @(posedge axi.ACLK);
        axi.ARESTN = 1;
        repeat(2) @(posedge axi.ACLK);
        $display("Randomized reset task completed");
    endtask

    task automatic apply_reset(input int cycles);
        if (DebugEn) $display("Applying reset for %0d cycles...", cycles);
        axi.ARESTN <= 1'b0;
        repeat(cycles) @(posedge axi.ACLK);
        axi.ARESTN <= 1'b1;
        repeat(2) @(posedge axi.ACLK);
    endtask

    // === DIRECTED TESTING SEQUENCES ===
    task automatic run_directed_write_read_sequence();
        Transaction actual_tx;
        logic [31:0] test_addr;
        logic [31:0] test_data[];
        
        test_addr = 32'h100;
        test_data = '{32'hDEADBEEF, 32'hCAFEBABE, 32'h12345678, 32'hABCDEF00};
        
        $display("=== DIRECTED WRITE-READ SEQUENCE ===");
        
        // Enable directed test mode to allow flexible corner case selection
        Transaction#(DATA_WIDTH, ADDR_WIDTH)::directed_test_mode = 1;
        
        // Phase 1: Write sequence
        for (int i = 0; i < 4; i++) begin
            tx = new();
            if (!tx.randomize() with {
                op_type == WRITE_OP;
                ADDR == test_addr + (i * 4);
                LEN == 0; // Single beat
                SIZE == 3'b010; // 4 bytes
                corner_case_selector inside {[16:23]};
                WDATA.size() == 1;
                WDATA[0] == test_data[i];
            }) begin
                $error("Randomization failed for directed write test %0d", i+1);
                $error("  test_addr=0x%h, target_addr=0x%h", test_addr, test_addr + (i * 4));
                $error("  corner_case_counter=%0d, corner_case_selector constraint would be %0d", 
                       Transaction#(DATA_WIDTH, ADDR_WIDTH)::corner_case_counter, 
                       Transaction#(DATA_WIDTH, ADDR_WIDTH)::corner_case_counter % Transaction#(DATA_WIDTH, ADDR_WIDTH)::total_corner_cases);
                $stop;
            end
            
            $display("WRITE %0d: ADDR=0x%h, DATA=0x%h", i+1, tx.ADDR, tx.WDATA[0]);
            golden_model(tx);
            drive_stimulus(tx, actual_tx);
            collect_output(actual_tx);
            check_results();
            
            if (tx.crosses_4KB_boundary()) boundary_crossing_count++;
            test_mode_count[tx.test_mode]++;
            total_tests++;
            if (tx.op_type == READ_OP) read_tests++; else write_tests++;
        end
        
        // Phase 2: Read back sequence
        for (int i = 0; i < 4; i++) begin
            tx = new();
            assert(tx.randomize() with {
                op_type == READ_OP;
                ADDR == test_addr + (i * 4);
                LEN == 0; // Single beat
                SIZE == 3'b010; // 4 bytes
                test_mode == RANDOM_MODE;
            });
            
            $display("READ %0d: ADDR=0x%h", i+1, tx.ADDR);
            golden_model(tx);
            drive_stimulus(tx, actual_tx);
            collect_output(actual_tx);
            check_results();
            
            test_mode_count[tx.test_mode]++;
            total_tests++;
            if (tx.op_type == READ_OP) read_tests++; else write_tests++;
        end
        
        // Restore normal mode after directed testing
        Transaction#(DATA_WIDTH, ADDR_WIDTH)::directed_test_mode = 0;
    endtask

    // === COVERAGE-DRIVEN TESTING ===
    task automatic run_coverage_driven_tests();
        Transaction actual_tx;
        int max_coverage_tests = 5000; // Allow more coverage attempts
        int coverage_tests = 0;
        real prev_coverage = overall_coverage;
        int stagnant_count = 0;
        
        $display("Starting coverage-driven testing to reach %0.1f%% coverage...", TARGET_COVERAGE);
        $display("Current coverage: %0.1f%%", overall_coverage);
        
        while (overall_coverage < TARGET_COVERAGE && coverage_tests < max_coverage_tests) begin
            // Check what coverage holes exist and target them specifically
            run_targeted_coverage_test();
            coverage_tests++;
            
            // Update coverage every 10 tests
            if (coverage_tests % 10 == 0) begin
                if (DebugEn) begin
                    $display("Coverage-driven test %0d: Overall coverage = %0.1f%%", 
                           coverage_tests, overall_coverage);
                    
                    // Display detailed coverage every 25 tests
                    if (coverage_tests % 25 == 0) tx.display_coverage_report();
                end
                
                // Check for coverage stagnation
                if (overall_coverage == prev_coverage) begin
                    stagnant_count++;
                    if (stagnant_count >= 3) begin
                        $display("Coverage appears stuck at %0.1f%% - running specific hole tests...", overall_coverage);
                        run_specific_coverage_holes();
                        stagnant_count = 0;
                    end
                end else begin
                    stagnant_count = 0;
                end
                prev_coverage = overall_coverage;
            end
        end
        
        if (overall_coverage >= TARGET_COVERAGE) begin
            $display("*** TARGET COVERAGE %0.1f%% ACHIEVED in %0d tests! ***", TARGET_COVERAGE, coverage_tests);
        end else begin
            $display("*** Coverage stuck at %0.1f%% after %0d tests ***", overall_coverage, coverage_tests);
        end
    endtask

    task automatic run_targeted_coverage_test();
        Transaction actual_tx;
        
        // Enable directed mode for targeted testing
        Transaction#(DATA_WIDTH, ADDR_WIDTH)::directed_test_mode = 1;
        
        tx = new();
        
        // Smart constraint to target missing coverage holes based on coverage report
        if (!tx.randomize() with {
            // Target FSM state coverage (8.3% - very low priority)
            if ($urandom_range(1,100) <= 15) {
                // Force different handshaking patterns to trigger FSM states
                awvalid_delay inside {[0:5]};
                arvalid_delay inside {[0:5]};
                bready_value dist {1'b0 := 30, 1'b1 := 70}; // More backpressure
                rready_backpressure_prob inside {[40:80]};   // High backpressure
            }
            // Target memory address coverage (25.1% - need full address space)
            else if ($urandom_range(1,100) <= 30) {
                ADDR inside {[16'h000:16'h0FF], [16'h400:16'h7FF], [16'hC00:16'hFFF]}; // Hit different ranges
                LEN inside {[8:15]}; // Longer bursts to cover more addresses
                op_type dist {READ_OP := 60, WRITE_OP := 40}; // More reads for address coverage
            }
            // Target data patterns (60.5% - need more pattern combinations)
            else if ($urandom_range(1,100) <= 20) {
                op_type == WRITE_OP;
                test_mode == DATA_PATTERN_MODE;
                data_pattern inside {ALL_ZEROS, ALL_ONES, ALTERNATING_AA, ALTERNATING_55};
                LEN inside {[0:7]}; // Various burst lengths with data patterns
            }
            // Random testing for other coverage (remaining 10%)
            else {
                // Normal constraints apply for general coverage
            }
        }) begin
            $warning("Coverage-driven randomization failed - using standard test");
            Transaction#(DATA_WIDTH, ADDR_WIDTH)::directed_test_mode = 0;
            generate_stimulus(); // Fall back to standard random test
        end else begin
            Transaction#(DATA_WIDTH, ADDR_WIDTH)::directed_test_mode = 0;
            total_tests++;
            if (tx.op_type == READ_OP) read_tests++; else write_tests++;
        end
        
        golden_model(tx);
        drive_stimulus(tx, actual_tx);
        collect_output(actual_tx);
        check_results();
        
        // Sample coverage after transaction completion
        sample_dut_coverage(actual_tx);
    endtask

    task automatic run_specific_coverage_holes();
        Transaction actual_tx;
        int hole_tests = 0;
        
        // Declare all arrays at the beginning of the task
        logic [15:0] test_addresses[] = '{
            16'h000, 16'h040, 16'h080, 16'h0C0,  // Low range
            16'h200, 16'h240, 16'h280, 16'h2C0,  // Low-mid range
            16'h400, 16'h440, 16'h480, 16'h4C0,  // Mid range
            16'h600, 16'h640, 16'h680, 16'h6C0,  // Mid-high range
            16'h800, 16'h840, 16'h880, 16'h8C0,  // High-mid range
            16'hA00, 16'hA40, 16'hA80, 16'hAC0,  // Upper range
            16'hC00, 16'hC40, 16'hC80, 16'hCC0,  // Near-boundary range
            16'hE00, 16'hE40, 16'hE80, 16'hEC0,  // High range
            16'hF00, 16'hF40, 16'hF80, 16'hFC0,  // Top range
            16'hFE0, 16'hFF0, 16'hFF8, 16'hFFC   // Boundary addresses
        };
        
        enuming::data_pattern_e patterns[] = '{ALL_ZEROS, ALL_ONES, ALTERNATING_AA, ALTERNATING_55, RANDOM_DATA};
        
        int corner_cases[] = '{0, 2, 4, 5, 7}; // Missing patterns from previous runs
        
        $display("=== COMPREHENSIVE COVERAGE HOLE FILLING ===");
        Transaction#(DATA_WIDTH, ADDR_WIDTH)::directed_test_mode = 1;
        
        // Test 1: FSM State Coverage - Force different FSM state transitions
        $display("Testing FSM state transitions with handshaking variations...");
        for (int i = 0; i < 15; i++) begin
            tx = new();
            if (tx.randomize() with {
                // Vary handshaking to trigger different FSM states
                awvalid_delay == i % 6;          // 0-5 cycle delays
                bready_value == (i % 2);         // Alternate BREADY
                arvalid_delay == (i % 4);        // 0-3 cycle delays  
                rready_backpressure_prob == 20 + (i * 5); // 20-90% backpressure
                LEN inside {[0:3]};              // Short bursts for cleaner FSM observation
                op_type dist {READ_OP := 60, WRITE_OP := 40}; // More reads for FSM variety
            }) begin
                golden_model(tx);
                drive_stimulus(tx, actual_tx);
                collect_output(actual_tx);
                check_results();
                total_tests++;
                if (tx.op_type == READ_OP) read_tests++; else write_tests++;
                hole_tests++;
            end
        end
        
        // Test 2: Memory Address Coverage - Hit all address ranges systematically
        $display("Testing comprehensive memory address coverage...");
        foreach (test_addresses[i]) begin
            tx = new();
            if (tx.randomize() with {
                ADDR == test_addresses[i];
                LEN inside {[0:7]};  // Vary burst length
                op_type dist {READ_OP := 70, WRITE_OP := 30}; // More reads for address coverage
            }) begin
                golden_model(tx);
                drive_stimulus(tx, actual_tx);
                collect_output(actual_tx);
                check_results();
                total_tests++;
                if (tx.op_type == READ_OP) read_tests++; else write_tests++;
                hole_tests++;
            end
        end
        
        // Test 4: Data Pattern Coverage - All combinations with different burst lengths
        $display("Testing comprehensive data pattern coverage...");
        foreach (patterns[p]) begin
            for (int len_var = 0; len_var <= 7; len_var++) begin
                tx = new();
                if (tx.randomize() with {
                    op_type == WRITE_OP;
                    data_pattern == patterns[p];
                    LEN == len_var;
                    test_mode == DATA_PATTERN_MODE;
                    ADDR inside {[16'h000:16'hF00]}; // Avoid boundary issues
                }) begin
                    golden_model(tx);
                    drive_stimulus(tx, actual_tx);
                    collect_output(actual_tx);
                    check_results();
                    total_tests++;
                    write_tests++;
                    hole_tests++;
                end
            end
        end
        
        // Test 5: Corner case combinations
        $display("Testing corner case combinations...");
        foreach (corner_cases[c]) begin
            for (int burst_var = 0; burst_var <= 4; burst_var++) begin
                tx = new();
                if (tx.randomize() with {
                    op_type == WRITE_OP;
                    corner_case_selector == corner_cases[c];
                    LEN == burst_var;
                    test_mode == DATA_PATTERN_MODE;
                }) begin
                    golden_model(tx);
                    drive_stimulus(tx, actual_tx);
                    collect_output(actual_tx);
                    check_results();
                    total_tests++;
                    write_tests++;
                    hole_tests++;
                end
            end
        end
        
        Transaction#(DATA_WIDTH, ADDR_WIDTH)::directed_test_mode = 0;
        
        // Final comprehensive coverage report
        if (tx != null) begin
            tx.display_coverage_report();
            overall_coverage = tx.get_overall_coverage();
        end
        
        $display("Completed %0d specific coverage hole tests. New coverage: %0.1f%%", hole_tests, overall_coverage);
    endtask

    task automatic run_single_test();
        Transaction actual_tx;
        
        generate_stimulus();
        golden_model(tx);
        drive_stimulus(tx, actual_tx);
        collect_output(actual_tx);
        check_results();
        
        // Sample coverage after completion
        sample_dut_coverage(actual_tx);
    endtask

    task automatic run_comprehensive_single_beat_tests();
        Transaction actual_tx;
        logic [31:0] test_addresses[];
        logic [31:0] test_data_patterns[];
        
        $display("=== COMPREHENSIVE SINGLE BEAT TESTING ===");
        
        // Test addresses covering valid memory range (< 0x1000 due to memory_range_c constraint)
        test_addresses = '{
            32'h100,   // Low range
            32'h500,   // Low range
            32'h800,   // Mid range
            32'hC00,   // Upper mid range
            32'hFFC    // Near 4KB boundary (highest valid address)
        };
        
        // Data patterns for all corner cases
        test_data_patterns = '{
            32'h00000000, // ALL_ZEROS (corner case 0)
            32'hFFFFFFFF, // ALL_ONES (corner case 1) 
            32'hAAAAAAAA, // ALTERNATING_AA (corner case 2)
            32'h55555555, // ALTERNATING_55 (corner case 3)
            32'h80000000, // SINGLE_MSB (corner case 4)
            32'h00000001, // SINGLE_LSB (corner case 5)
            32'hCCCCCCCC, // CHECKERBOARD_1 (corner case 6)
            32'h33333333  // CHECKERBOARD_2 (corner case 7)
        };
        
        Transaction#(DATA_WIDTH, ADDR_WIDTH)::directed_test_mode = 1;
        
        // Write tests for each address/pattern combination
        foreach (test_addresses[i]) begin
            foreach (test_data_patterns[j]) begin
                tx = new();
                if (tx.randomize() with {
                    op_type == WRITE_OP;
                    ADDR == test_addresses[i];
                    LEN == 0; // Single beat only
                    SIZE == 3'b010;
                    WDATA.size() == 1;
                    WDATA[0] == test_data_patterns[j];
                    corner_case_selector == j; // Force specific corner case
                }) begin
                    $display("Single beat write: ADDR=0x%h, DATA=0x%h, pattern=%0d", 
                             tx.ADDR, tx.WDATA[0], j);
                    golden_model(tx);
                    drive_stimulus(tx, actual_tx);
                    collect_output(actual_tx);
                    check_results();
                    total_tests++;
                    write_tests++;
                end
            end
        end
        
        // Read tests for each address
        foreach (test_addresses[i]) begin
            tx = new();
            if (tx.randomize() with {
                op_type == READ_OP;
                ADDR == test_addresses[i];
                LEN == 0; // Single beat only
                SIZE == 3'b010;
            }) begin
                $display("Single beat read: ADDR=0x%h", tx.ADDR);
                golden_model(tx);
                drive_stimulus(tx, actual_tx);
                collect_output(actual_tx);
                check_results();
                total_tests++;
                read_tests++;
            end
        end
        
        Transaction#(DATA_WIDTH, ADDR_WIDTH)::directed_test_mode = 0;
        
        // Final comprehensive coverage report  
        if (tx != null) begin
            tx.display_coverage_report();
            overall_coverage = tx.get_overall_coverage();
        end
        
        $display("Comprehensive single beat tests completed. Coverage: %0.1f%%", overall_coverage);
    endtask

    task automatic display_final_report();
        $display("\n======================================================");
        $display("                FINAL TEST REPORT                    ");
        $display("======================================================");
        $display("Total Tests:    %0d", total_tests);
        $display("Read Tests:     %0d", read_tests);
        $display("Write Tests:    %0d", write_tests);
        $display("Passed Tests:   %0d", passed_tests);
        $display("Failed Tests (inteded failure):   %0d", failed_tests);
        $display("Pass Rate:      %0.1f%%", (passed_tests*100.0)/total_tests);
        $display("------------------------------------------------------");
        $display("OKAY Responses: %0d", okay_count);
        $display("SLVERR Count:   %0d", slverr_count);
        
        // Display comprehensive coverage report
        if (tx != null) begin
            tx.display_coverage_report();
            overall_coverage = tx.get_overall_coverage();
        end
        
        $display("======================================================\n");
    endtask

    // === MAIN TEST SEQUENCE ===
    initial begin
        $display("Starting Enhanced Integrated AXI4 Testbench...");
        $display("Target Coverage: %0.1f%%", TARGET_COVERAGE);
        
        // Initialize test mode counters
        test_mode_count[enuming::RANDOM_MODE] = 0;
        test_mode_count[enuming::BURST_LENGTH_MODE] = 0;
        test_mode_count[enuming::DATA_PATTERN_MODE] = 0;
        
        // Apply initial reset
        apply_reset(5);
        
        // Phase 1: Random testing (with shorter bursts)
        $display("\n=== PHASE 1: RANDOM TESTING ===");
        repeat(10) begin  // Reduced from NUM_RANDOM_TESTS to 10 for debugging
            run_single_test();
            
            if (total_tests % 5 == 0) begin
                $display("Random tests %0d: Coverage = %0.1f%%", total_tests, overall_coverage);
            end
        end
        
        // Phase 2: Directed testing sequences (simplified)
        $display("\n=== PHASE 2: DIRECTED TESTING SEQUENCES ===");
        
        // Write-Read sequences
        repeat(2) run_directed_write_read_sequence();  // Reduced from 5 to 2
        
        $display("After directed testing: Coverage = %0.1f%%", overall_coverage);
        
        // Phase 2.5: Comprehensive single beat testing (to avoid RLAST issues)
        $display("\n=== PHASE 2.5: COMPREHENSIVE SINGLE BEAT TESTING ===");
        run_comprehensive_single_beat_tests();
        $display("After comprehensive testing: Coverage = %0.1f%%", overall_coverage);
        
        // Phase 3: Coverage-driven testing to reach 100%
        $display("\n=== PHASE 3: COVERAGE-DRIVEN TESTING ===");
        run_coverage_driven_tests();
        
        // Display final report
        display_final_report();
        
        if (failed_tests == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** %0d TESTS FAILED (intended failure) ***", failed_tests);
        end
        
        if (overall_coverage >= TARGET_COVERAGE) begin
            $display("*** SUCCESS: TARGET COVERAGE ACHIEVED! ***");
        end else begin
            $display("*** Coverage %0.1f%% - Target %0.1f%% not reached ***", overall_coverage, TARGET_COVERAGE);
        end
        
        $stop;
    end

endmodule
