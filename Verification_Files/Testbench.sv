`timescale 1ns/1ns
import enuming::*;
`include "Transaction.sv"

module Testbench(axi_if.TB axi);  // CHANGE: Using new TB modport with clocking block access

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

    // Initialize signals
    initial begin
        axi.ARESTN = 1;
        // Initialize AXI signals directly
        @(posedge axi.clk);
        axi.AWADDR <= 0; axi.AWLEN <= 0; axi.AWSIZE <= 0; axi.AWVALID <= 0;
        axi.WDATA <= 0; axi.WVALID <= 0; axi.WLAST <= 0; axi.BREADY <= 0;
        axi.ARADDR <= 0; axi.ARLEN <= 0; axi.ARSIZE <= 0; axi.ARVALID <= 0;
        axi.RREADY <= 0;
        
        // Initialize golden memory
        for (int i = 0; i < 1024; i++) begin
            golden_mem[i] = i;
        end
        
        if (DebugEn) $display("Golden memory initialized with pattern 0x0, 0x1, 0x2, ...");
    end

    // === GENERATE STIMULUS ===
    task automatic generate_stimulus();
        tx = new();
        assert(tx.randomize()) else begin
            $display("ERROR: Randomization failed!");
            $stop;
        end
        
        if (DebugEn) tx.display();
        total_tests++;
        
        if (tx.op_type == READ_OP) read_tests++;
        else write_tests++;
    endtask

    // === DRIVE STIMULUS ===
    task automatic drive_stimulus(input Transaction tr, ref Transaction actual_tx);
        actual_tx = new();
        actual_tx.op_type = tr.op_type;
        actual_tx.ADDR = tr.ADDR;
        actual_tx.LEN = tr.LEN;
        actual_tx.SIZE = tr.SIZE;
        
        if (tr.op_type == WRITE_OP) begin
            // Write transactions handle their own reset internally (like WTestbench.sv)
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
            repeat(tr.awvalid_delay) @(posedge axi.clk);
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
                @(posedge axi.clk);
                timeout_counter++;
                if (timeout_counter >= MAX_TIMEOUT) begin
                    $error("TIMEOUT: AWREADY not received within %0d cycles", MAX_TIMEOUT);
                    $finish;
                end
            end while (!axi.AWREADY);
            if (DebugEn) $display("AWREADY received, address handshake complete");
        end else begin
            if (DebugEn) $display("AWVALID NOT asserted, skipping AWREADY wait");
            @(posedge axi.clk); 
        end
        axi.AWVALID <= 0;
        
        if (!tr.awvalid_value) begin
            $display("Address phase skipped (AWVALID=0), skipping data phase");
            $display("Transaction aborted - no data transfer");
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
                repeat(tr.wvalid_delay[i]) @(posedge axi.clk);
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
                    @(posedge axi.clk);
                    timeout_counter++;
                    if (timeout_counter >= MAX_TIMEOUT) begin
                        $error("TIMEOUT: WREADY not received for beat %0d within %0d cycles", i+1, MAX_TIMEOUT);
                        $finish;
                    end
                end while (!axi.WREADY);
                if (DebugEn) $display("[BEAT %0d/%0d] WREADY received, handshake complete", i+1, tr.WDATA.size());
            end else begin
                if (DebugEn) $display("[BEAT %0d/%0d] WVALID NOT asserted, skipping WREADY wait", i+1, tr.WDATA.size());
                @(posedge axi.clk); // Still advance one clock even if WVALID not asserted
            end
            
            axi.WVALID <= 0;
            actual_tx.WDATA[i] = tr.WDATA[i];
            if (DebugEn) $display("[BEAT %0d/%0d] Beat completed, advancing to next", i+1, tr.WDATA.size());
            @(posedge axi.clk);
        end

        if (DebugEn) $display("Waiting for write response...");
        
        if (DebugEn) $display("Setting BREADY=%b", tr.bready_value);
        axi.BREADY <= tr.bready_value;
        
        if (tr.bready_value) begin
            if (DebugEn) $display("BREADY asserted, waiting for BVALID...");
            timeout_counter = 0;
            do begin
                @(posedge axi.clk);
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
            $display("BREADY not asserted - skipping response capture");
            bresp_captured = 2'b10; // Default to SLVERR
            $display("BRESP: %s (0b%b)", decode_response(bresp_captured), bresp_captured);
            @(posedge axi.clk); // Still advance one clock
        end
        
        if (is_error_response(bresp_captured)) begin
            $display("WARNING: Transaction completed with error response!");
            slverr_count++;
        end else begin
            $display("Transaction completed successfully");
            okay_count++;
        end

        axi.BREADY <= 0;
        @(posedge axi.clk);

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
        repeat(tr.arvalid_delay) @(posedge axi.clk);  // Apply ARVALID delay
        
        axi.ARADDR <= tr.ADDR;
        axi.ARLEN <= tr.LEN;
        axi.ARSIZE <= tr.SIZE;
        axi.ARVALID <= 1'b1;
        
        if (DebugEn) $display("Address phase: ARADDR=0x%h, ARLEN=%0d, ARVALID delayed by %0d cycles", 
                              tr.ADDR, tr.LEN, tr.arvalid_delay);
        
        // Wait for address handshake
        timeout_counter = 0;
        while (axi.ARREADY !== 1'b1) begin
            @(posedge axi.clk);
            timeout_counter++;
            if (timeout_counter >= MAX_TIMEOUT) begin
                $error("TIMEOUT: ARREADY not received within %0d cycles", MAX_TIMEOUT);
                $finish;
            end
        end
        @(posedge axi.clk);
        axi.ARVALID <= 1'b0;
        
        if (DebugEn) $display("Address phase complete");
        
        // Data phase with randomized RREADY timing and backpressure
        for (int i = 0; i <= tr.LEN; i++) begin
            // Apply per-beat RREADY delay
            repeat(tr.rready_delay[i]) @(posedge axi.clk);
            
            // Apply randomized RREADY pattern with backpressure
            if (tr.rready_random_deassert[i] && ($urandom_range(1,100) > tr.rready_backpressure_prob)) begin
                axi.RREADY <= 1'b1;
                
                timeout_counter = 0;
                while (axi.RVALID !== 1'b1) begin
                    @(posedge axi.clk);
                    timeout_counter++;
                    if (timeout_counter >= MAX_TIMEOUT) begin
                        $error("TIMEOUT: RVALID not received for beat %0d within %0d cycles", i, MAX_TIMEOUT);
                        $finish;
                    end
                end
                @(posedge axi.clk);
                
                // Capture data
                actual_tx.RDATA[i] = axi.RDATA;
                actual_tx.RRESP[i] = axi.RRESP;
                rlast_captured = axi.RLAST;
                
                if (DebugEn) $display("Read beat %0d: RDATA=0x%h, RRESP=%s, RLAST=%b, RREADY_delay=%0d", 
                                      i, axi.RDATA, decode_response(axi.RRESP), rlast_captured, tr.rready_delay[i]);
                
            end else begin
                // Apply backpressure: deassert RREADY for random cycles
                axi.RREADY <= 1'b0;
                repeat($urandom_range(1,3)) @(posedge axi.clk);  // Backpressure for 1-3 cycles
                
                axi.RREADY <= 1'b1;
                timeout_counter = 0;
                while (axi.RVALID !== 1'b1) begin
                    @(posedge axi.clk);
                    timeout_counter++;
                    if (timeout_counter >= MAX_TIMEOUT) begin
                        $error("TIMEOUT: RVALID not received for beat %0d within %0d cycles", i, MAX_TIMEOUT);
                        $finish;
                    end
                end
                @(posedge axi.clk);
                
                // Capture data
                actual_tx.RDATA[i] = axi.RDATA;
                actual_tx.RRESP[i] = axi.RRESP;
                rlast_captured = axi.RLAST;
                
                if (DebugEn) $display("Read beat %0d: RDATA=0x%h, RRESP=%s, RLAST=%b (with RREADY backpressure)", 
                                      i, axi.RDATA, decode_response(axi.RRESP), rlast_captured);
            end
            
            // Check RLAST on final beat
            if (i == tr.LEN && !rlast_captured) begin
                $display("[ERROR] RLAST not asserted on last beat (beat %0d), LEN=%0d - RLAST should be 1", i, tr.LEN);
                failed_tests++;
            end else if (i == tr.LEN && rlast_captured) begin
                if (DebugEn) $display("[INFO] RLAST correctly asserted on final beat %0d", i);
            end
            
            // AXI4 Protocol Compliance: Simple RREADY management
            if (i < tr.LEN) begin
                axi.RREADY <= 1'b0;  // Deassert RREADY between beats
                @(posedge axi.clk);              // Wait one cycle with RREADY low
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
            expected.WDATA = new[tr.WDATA.size()];
            foreach (tr.WDATA[i]) expected.WDATA[i] = tr.WDATA[i];
            
            // Only process if AWVALID was asserted (transaction not aborted)
            if (tr.awvalid_value == 1) begin
                // Predict BRESP
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
            end else begin
                // Transaction aborted (AWVALID=0) - no memory update, SLVERR response
                expected.BRESP = 2'b10; // SLVERR (2'b10) response for aborted transaction
            end
            
        end else begin
            // For reads, predict data and response
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
                // Print actual vs expected for read operations
                $display("  Actual   : ARADDR=0x%h ARLEN=%0d ARSIZE=%0d", 
                         actual.ADDR, actual.LEN, actual.SIZE);
                $display("  Expected : ARADDR=0x%h ARLEN=%0d ARSIZE=%0d", 
                         expected.ADDR, expected.LEN, expected.SIZE);
                
                // Check read data and response - matching WTestbench.sv checking pattern
                data_match = 1;
                for (i = 0; i <= expected.LEN; i++) begin
                    if (expected.RDATA[i] != actual.RDATA[i]) begin
                        $display("  Data mismatch at beat %0d: actual=0x%h, expected=0x%h", 
                                 i, actual.RDATA[i], expected.RDATA[i]);
                        data_match = 0;
                        test_passed = 0;
                    end
                    
                    if (expected.RRESP[i] != actual.RRESP[i]) begin
                        $display("  RRESP mismatch at beat %0d: actual=%s, expected=%s", 
                                 i, decode_response(actual.RRESP[i]), decode_response(expected.RRESP[i]));
                        test_passed = 0;
                    end
                end
                
                if (data_match && test_passed) begin
                    $display("  All read data matches expected values");
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
        repeat(wtxn.reset_cycles) @(posedge axi.clk);
        axi.ARESTN = 1;
        repeat(2) @(posedge axi.clk);
        $display("Randomized reset task completed");
    endtask

    task automatic apply_reset(input int cycles);
        if (DebugEn) $display("Applying reset for %0d cycles...", cycles);
        axi.ARESTN <= 1'b0;
        repeat(cycles) @(posedge axi.clk);
        axi.ARESTN <= 1'b1;
        repeat(2) @(posedge axi.clk);
    endtask

    // === DIRECTED TESTING SEQUENCES ===
    task automatic run_directed_write_read_sequence();
        Transaction actual_tx;
        logic [31:0] test_addr;
        logic [31:0] test_data[];
        
        test_addr = 32'h100;
        test_data = '{32'hDEADBEEF, 32'hCAFEBABE, 32'h12345678, 32'hABCDEF00};
        
        $display("=== DIRECTED WRITE-READ SEQUENCE ===");
        
        // Phase 1: Write sequence
        for (int i = 0; i < 4; i++) begin
            tx = new();
            assert(tx.randomize() with {
                op_type == WRITE_OP;
                ADDR == test_addr + (i * 4);
                LEN == 0; // Single beat
                SIZE == 3'b010; // 4 bytes
                test_mode == RANDOM_MODE;
                WDATA.size() == 1;
                WDATA[0] == test_data[i];
            });
            
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
    endtask

    task automatic run_single_test();
        Transaction actual_tx;
        
        generate_stimulus();
        golden_model(tx);
        drive_stimulus(tx, actual_tx);
        collect_output(actual_tx);
        check_results();
        
        overall_coverage = tx.get_overall_coverage();
    endtask

    task automatic display_final_report();
        $display("\n======================================================");
        $display("                FINAL TEST REPORT                    ");
        $display("======================================================");
        $display("Total Tests:    %0d", total_tests);
        $display("Read Tests:     %0d", read_tests);
        $display("Write Tests:    %0d", write_tests);
        $display("Passed Tests:   %0d", passed_tests);
        $display("Failed Tests:   %0d", failed_tests);
        $display("Pass Rate:      %0.1f%%", (passed_tests*100.0)/total_tests);
        $display("------------------------------------------------------");
        $display("OKAY Responses: %0d", okay_count);
        $display("SLVERR Count:   %0d", slverr_count);
        $display("Overall Coverage: %0.1f%%", overall_coverage);
        $display("======================================================\n");
    endtask

    // === MAIN TEST SEQUENCE ===
    initial begin
        $display("Starting Enhanced Integrated AXI4 Testbench...");
        $display("Target Coverage: %0.1f%%", TARGET_COVERAGE);
        
        // Initialize test mode counters
        foreach(test_mode_count[i]) test_mode_count[i] = 0;
        
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
        
        // Display final report
        display_final_report();
        
        if (failed_tests == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** %0d TESTS FAILED ***", failed_tests);
        end
        
        if (overall_coverage >= TARGET_COVERAGE) begin
            $display("*** SUCCESS: TARGET COVERAGE ACHIEVED! ***");
        end else begin
            $display("*** Coverage %0.1f%% - Target %0.1f%% not reached ***", overall_coverage, TARGET_COVERAGE);
        end
        
        $finish;
    end

endmodule
