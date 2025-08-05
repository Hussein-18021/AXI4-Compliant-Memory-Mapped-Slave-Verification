`timescale 1ns/1ns
import enuming::*;
`include "Wstim.sv"

module axi_write_tb(axi_if axi);

    parameter int DATA_WIDTH = 32;
    parameter int NUM_RANDOM_TESTS = 50;
    parameter int NUM_TARGETED_TESTS = 100;
    parameter real TARGET_COVERAGE = 100.0;
    parameter bit DebugEn = 0; // Enable/disable debug messages
    
    int total_tests = 0;
    int passed_tests = 0;
    int failed_tests = 0;
    int slverr_count = 0;
    int okay_count   = 0;
    WTransaction tx;
    WTransaction expected_queue[$];
    WTransaction actual_queue[$];
    
    real write_addr_coverage_percent;
    real write_data_coverage_percent;
    real boundary_coverage_percent;
    real test_mode_coverage_percent;
    real overall_coverage_percent;

    int test_mode_count[enuming::test_mode_e];
    int boundary_crossing_count = 0;
    int boundary_edge_count = 0;

    initial begin
        axi.AWADDR = 0;
        axi.AWLEN = 0;
        axi.AWSIZE = 0;
        axi.AWVALID = 0;
        axi.WDATA = 0;
        axi.WVALID = 0;
        axi.WLAST = 0;
        axi.BREADY = 0;
    end

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

    task automatic assert_reset();
        $display("Asserting reset via task...");
        axi.ARESTN = 0;
        repeat(3) @(posedge axi.clk);
        axi.ARESTN = 1;
        repeat(2) @(posedge axi.clk);
        $display("Reset task completed");
    endtask

    task automatic assert_randomized_reset(input WTransaction wtxn);
        $display("Asserting randomized reset for %0d cycles...", wtxn.reset_cycles);
        axi.ARESTN = 0;
        repeat(wtxn.reset_cycles) @(posedge axi.clk);
        axi.ARESTN = 1;
        repeat(2) @(posedge axi.clk);
        $display("Randomized reset task completed");
    endtask

    task automatic golden_model(input WTransaction tx);
        WTransaction expected = new();
        expected.AWADDR = tx.AWADDR;
        expected.AWLEN  = tx.AWLEN;
        expected.AWSIZE = tx.AWSIZE;
        expected.WDATA = new[tx.WDATA.size()];
        foreach (tx.WDATA[i])
            expected.WDATA[i] = tx.WDATA[i];
        expected_queue.push_back(expected);
    endtask

    task automatic generate_stimulus();
        tx = new();
        assert(tx.randomize()) else begin
            $display("ERROR: Randomization failed!");
            $stop;
        end
        if (tx.crosses_4KB_boundary()) boundary_crossing_count++;
        tx.display();
    endtask

    task automatic drive_stim(input WTransaction wtxn, ref WTransaction actual_tx);
        logic [1:0] bresp_captured;
        int timeout_counter;
        int MAX_TIMEOUT = 1000; // Maximum cycles to wait for any handshake
        
        actual_tx = new();
        actual_tx.AWADDR = wtxn.AWADDR;
        actual_tx.AWLEN = wtxn.AWLEN;
        actual_tx.AWSIZE = wtxn.AWSIZE;
        actual_tx.WDATA = new[wtxn.WDATA.size()];

        $display("Starting write transaction...");

        assert_randomized_reset(wtxn);

        if (wtxn.awvalid_delay > 0) begin
            if (DebugEn) $display("Delaying AWVALID by %0d cycles", wtxn.awvalid_delay);
            repeat(wtxn.awvalid_delay) @(posedge axi.clk);
            if (DebugEn) $display("AWVALID delay completed");
        end

        $display("Setting AWADDR=0x%h, AWLEN=%0d, AWSIZE=%0d, AWVALID=%b", 
                 wtxn.AWADDR, wtxn.AWLEN, wtxn.AWSIZE, wtxn.awvalid_value);
        
        axi.AWADDR  <= wtxn.AWADDR;
        axi.AWLEN   <= wtxn.AWLEN;
        axi.AWSIZE  <= wtxn.AWSIZE;
        axi.AWVALID <= wtxn.awvalid_value;  

        if (wtxn.awvalid_value) begin
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
        
        if (!wtxn.awvalid_value) begin
            $display("Address phase skipped (AWVALID=0), skipping data phase");
            $display("Transaction aborted - no data transfer");
            return;
        end
        
        $display("Address phase: AWADDR=%d, AWLEN=%0d, AWSIZE=%0d, STOP_ADDR=%d, 4KB_OFFSET=%d, Is it supposed to cross 4KB? %s", 
         wtxn.AWADDR, wtxn.AWLEN, wtxn.AWSIZE,
         wtxn.AWADDR + ((wtxn.AWLEN + 1) << wtxn.AWSIZE),
         (wtxn.AWADDR & 12'hFFF) + ((wtxn.AWLEN + 1) << wtxn.AWSIZE),
         wtxn.crosses_4KB_boundary() ? "YES" : "NO");

        if (wtxn.AWADDR % (1 << wtxn.AWSIZE) != 0) begin
            $warning("Misaligned AWADDR! AWADDR=0x%0h is not aligned to AWSIZE=%0d", wtxn.AWADDR, wtxn.AWSIZE);
        end

        if (DebugEn) $display("Starting data phase with %0d beats...", wtxn.WDATA.size());
        foreach (wtxn.WDATA[i]) begin
            if (DebugEn) $display("[BEAT %0d/%0d] Starting beat processing", i+1, wtxn.WDATA.size());
            
            if (wtxn.wvalid_delay[i] > 0) begin
                if (DebugEn) $display("[BEAT %0d/%0d] Applying WVALID delay of %0d cycles", i+1, wtxn.WDATA.size(), wtxn.wvalid_delay[i]);
                repeat(wtxn.wvalid_delay[i]) @(posedge axi.clk);
                if (DebugEn) $display("[BEAT %0d/%0d] WVALID delay completed", i+1, wtxn.WDATA.size());
            end else begin
                if (DebugEn) $display("[BEAT %0d/%0d] No WVALID delay (delay=0)", i+1, wtxn.WDATA.size());
            end
            
            if (DebugEn) $display("[BEAT %0d/%0d] Setting WDATA=0x%h, WLAST=%b, WVALID=%b", 
                     i+1, wtxn.WDATA.size(), wtxn.WDATA[i], (i == wtxn.WDATA.size() - 1), wtxn.wvalid_pattern[i]);
            
            axi.WDATA  <= wtxn.WDATA[i];
            axi.WLAST  <= (i == wtxn.WDATA.size() - 1);
            axi.WVALID <= wtxn.wvalid_pattern[i];
            
            if (wtxn.wvalid_pattern[i]) begin
                if (DebugEn) $display("[BEAT %0d/%0d] WVALID asserted, waiting for WREADY...", i+1, wtxn.WDATA.size());
                timeout_counter = 0;
                do begin
                    @(posedge axi.clk);
                    timeout_counter++;
                    if (timeout_counter >= MAX_TIMEOUT) begin
                        $error("TIMEOUT: WREADY not received for beat %0d within %0d cycles", i+1, MAX_TIMEOUT);
                        $finish;
                    end
                end while (!axi.WREADY);
                if (DebugEn) $display("[BEAT %0d/%0d] WREADY received, handshake complete", i+1, wtxn.WDATA.size());
            end else begin
                if (DebugEn) $display("[BEAT %0d/%0d] WVALID NOT asserted, skipping WREADY wait", i+1, wtxn.WDATA.size());
                @(posedge axi.clk); // Still advance one clock even if WVALID not asserted
            end
            
            axi.WVALID <= 0;
            actual_tx.WDATA[i] = wtxn.WDATA[i];
            if (DebugEn) $display("[BEAT %0d/%0d] Beat completed, advancing to next", i+1, wtxn.WDATA.size());
            @(posedge axi.clk);
        end

        if (DebugEn) $display("Waiting for write response...");
        
        if (DebugEn) $display("Setting BREADY=%b", wtxn.bready_value);
        axi.BREADY <= wtxn.bready_value;
        
        if (wtxn.bready_value) begin
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

        
    endtask

    task automatic collect_output(input WTransaction actual_tx);
        actual_queue.push_back(actual_tx);
    endtask 

    task automatic check_results();
        int num_checks = (actual_queue.size() < expected_queue.size()) ? actual_queue.size() : expected_queue.size();

        WTransaction actual   = actual_queue[num_checks-1];
        WTransaction expected = expected_queue[num_checks-1];
        total_tests++;
        
        $display("======================================================");
        $display("Test #%0d Result", total_tests);
        $display("  Actual   : AWADDR=0x%h AWLEN=%0d AWSIZE=%0d", actual.AWADDR, actual.AWLEN, actual.AWSIZE);
        $display("  Expected : AWADDR=0x%h AWLEN=%0d AWSIZE=%0d", expected.AWADDR, expected.AWLEN, expected.AWSIZE);

        if (actual.AWADDR == expected.AWADDR && 
            actual.AWLEN == expected.AWLEN && 
            actual.AWSIZE == expected.AWSIZE &&
            actual.WDATA.size() == expected.WDATA.size()) begin
            
            bit data_match = 1;
            foreach (actual.WDATA[i]) begin
                if (actual.WDATA[i] != expected.WDATA[i]) begin
                    data_match = 0;
                    $display("  Data mismatch at beat %0d: actual=0x%h, expected=0x%h", 
                             i, actual.WDATA[i], expected.WDATA[i]);
                    break;
                end
            end
            
            if (data_match) begin
                passed_tests++;
                $display("  TEST PASS");
            end else begin
                failed_tests++;
                $display("  TEST FAIL - Data mismatch");
            end
        end else begin
            failed_tests++;
            $display("  TEST FAIL - Control signal mismatch");
        end
        $display("======================================================");
    endtask

    task automatic collect_coverage_report();
        if (tx != null) begin
            write_addr_coverage_percent = tx.write_address_coverage.get_coverage();
            write_data_coverage_percent = tx.write_data_coverage.get_coverage();
            boundary_coverage_percent = tx.boundary_coverage.get_coverage();
            test_mode_coverage_percent = tx.test_mode_coverage.get_coverage();
            
            overall_coverage_percent = tx.get_overall_coverage();
        end
    endtask

    task automatic display_test_mode_statistics();
        $display("\n======================================================");
        $display("TEST MODE DISTRIBUTION:");
        $display("======================================================");
        $display("RANDOM_MODE           : %0d tests (%0.1f%%)", test_mode_count[enuming::RANDOM_MODE], (real'(test_mode_count[enuming::RANDOM_MODE]) / real'(total_tests)) * 100.0);
        $display("BOUNDARY_CROSSING_MODE: %0d tests (%0.1f%%)", test_mode_count[enuming::BOUNDARY_CROSSING_MODE], (real'(test_mode_count[enuming::BOUNDARY_CROSSING_MODE]) / real'(total_tests)) * 100.0);
        $display("BURST_LENGTH_MODE     : %0d tests (%0.1f%%)", test_mode_count[enuming::BURST_LENGTH_MODE], (real'(test_mode_count[enuming::BURST_LENGTH_MODE]) / real'(total_tests)) * 100.0);
        $display("DATA_PATTERN_MODE     : %0d tests (%0.1f%%)", test_mode_count[enuming::DATA_PATTERN_MODE], (real'(test_mode_count[enuming::DATA_PATTERN_MODE]) / real'(total_tests)) * 100.0);
        $display("------------------------------------------------------");
        $display("Boundary crossings    : %0d tests (%0.1f%%)", boundary_crossing_count,(real'(boundary_crossing_count) / real'(total_tests)) * 100.0);
        $display("======================================================");
    endtask

    task automatic display_coverage_report();
        $display("\nCOVERAGE REPORT:");
        $display("Address Coverage: %6.2f%%", write_addr_coverage_percent);
        $display("Data Coverage   : %6.2f%%", write_data_coverage_percent);
        $display("Boundary Coverage: %6.2f%%", boundary_coverage_percent);
        $display("Test Mode Coverage: %6.2f%%", test_mode_coverage_percent);
        $display("Overall Coverage: %6.2f%%", overall_coverage_percent);
    endtask

    task automatic run_test();
        WTransaction actual_tx;
        generate_stimulus();
        drive_stim(tx, actual_tx);
        golden_model(tx);
        collect_output(actual_tx);
        check_results();
        repeat(3) @(posedge axi.clk);
    endtask

    task automatic run_coverage_driven_tests();
        real current_coverage;
        int iteration = 0;
        int max_iterations = 10000; // Safety limit
        
        $display("=== COVERAGE-DRIVEN TESTING ===");
        
        while (iteration < max_iterations) begin
            collect_coverage_report();
            current_coverage = overall_coverage_percent;
            
            if (current_coverage >= TARGET_COVERAGE) begin
                if (DebugEn) $display("Target coverage %0.1f%% achieved at test %0d", TARGET_COVERAGE, iteration);
                break;
            end
            
            if (test_mode_coverage_percent < TARGET_COVERAGE) begin
                case (iteration % 10)
                    0, 1: begin
                        tx = new();
                        assert(tx.randomize() with {test_mode == RANDOM_MODE;});
                    end
                    2, 3: begin
                        tx = new();
                        assert(tx.randomize() with {test_mode == BOUNDARY_CROSSING_MODE;});
                    end
                    4, 5: begin
                        tx = new();
                        assert(tx.randomize() with {test_mode == BURST_LENGTH_MODE;});
                    end
                    6, 7: begin
                        tx = new();
                        assert(tx.randomize() with {test_mode == DATA_PATTERN_MODE;});
                    end
                    8: begin
                        // Force specific handshake scenarios
                        tx = new();
                        assert(tx.randomize() with {
                            awvalid_value == 0; // Test aborted transactions
                        });
                    end
                    9: begin
                        // Force response ignore scenarios
                        tx = new();
                        assert(tx.randomize() with {
                            awvalid_value == 1;
                            bready_value == 0; // Test response ignored
                        });
                    end
                endcase
            end else if (boundary_coverage_percent < current_coverage) begin
                tx = new();
                assert(tx.randomize() with {test_mode == BOUNDARY_CROSSING_MODE;});
            end else if (write_data_coverage_percent < current_coverage) begin
                tx = new();
                assert(tx.randomize() with {test_mode == DATA_PATTERN_MODE;});
            end else if (write_addr_coverage_percent < current_coverage) begin
                tx = new();
                assert(tx.randomize() with {
                    AWADDR inside {[0:255], [256:511], [512:1023]};
                });
            end else begin
                tx = new();
                assert(tx.randomize());
            end
            
            run_single_test();
            iteration++;
            
            if (iteration % 50 == 0) begin
                if (DebugEn) $display("Test %0d: Coverage = %0.1f%% (TestMode: %0.1f%%)", 
                         iteration, current_coverage, test_mode_coverage_percent);
            end
        end
        
        if (iteration >= max_iterations) begin
            $display("WARNING: Maximum iterations reached");
        end
    endtask

    task automatic run_test_mode_focused_tests();
        $display("=== TEST MODE FOCUSED PHASE ===");
        $display("Targeting all test mode coverage bins...");
        
        // Force each test mode multiple times
        repeat(20) begin
            tx = new();
            assert(tx.randomize() with {test_mode == RANDOM_MODE;});
            run_single_test();
        end
        
        repeat(20) begin
            tx = new();
            assert(tx.randomize() with {test_mode == BOUNDARY_CROSSING_MODE;});
            run_single_test();
        end
        
        repeat(20) begin
            tx = new();
            assert(tx.randomize() with {test_mode == BURST_LENGTH_MODE;});
            run_single_test();
        end
        
        repeat(20) begin
            tx = new();
            assert(tx.randomize() with {test_mode == DATA_PATTERN_MODE;});
            run_single_test();
        end
        
        // Force handshake scenario coverage
        repeat(10) begin
            tx = new();
            assert(tx.randomize() with {
                awvalid_value == 0; // Aborted transactions
            });
            run_single_test();
        end
        
        repeat(10) begin
            tx = new();
            assert(tx.randomize() with {
                awvalid_value == 1;
                bready_value == 0; // Response ignored
            });
            run_single_test();
        end
        
        repeat(10) begin
            tx = new();
            assert(tx.randomize() with {
                awvalid_value == 1;
                bready_value == 1; // Normal transactions
            });
            run_single_test();
        end
        
        // Test different reset cycle patterns
        repeat(5) begin
            tx = new();
            assert(tx.randomize() with {reset_cycles inside {[2:3]};});
            run_single_test();
        end
        
        repeat(5) begin
            tx = new();
            assert(tx.randomize() with {reset_cycles inside {[4:5]};});
            run_single_test();
        end
        
        collect_coverage_report();
        if (DebugEn) $display("After focused testing - Test Mode Coverage: %0.1f%%", test_mode_coverage_percent);
    endtask

    task automatic run_single_test();
        WTransaction actual_tx;
        drive_stim(tx, actual_tx);
        golden_model(tx);
        collect_output(actual_tx);
        check_results();
        repeat(3) @(posedge axi.clk);
    endtask

    function void print_bresp_summary();
        $display("\n---- BRESP Summary ----");
        $display("OKAY   responses: %0d", okay_count);
        $display("SLVERR responses: %0d", slverr_count);
        $display("------------------------\n");
    endfunction

    initial begin
        $display("Starting AXI Write Testbench - Target: 100%% Coverage");
        assert_reset();

        foreach(test_mode_count[i]) test_mode_count[i] = 0;

        $display("=== RANDOM TEST PHASE ===");
        repeat (NUM_RANDOM_TESTS) run_test();

        run_test_mode_focused_tests();
        run_coverage_driven_tests();
        print_bresp_summary();

        collect_coverage_report();

        $display("\nTEST SUMMARY:");
        $display("Total Tests: %0d", total_tests);
        $display("Passed: %0d", passed_tests);
        $display("Failed: %0d", failed_tests);
        $display("Pass Rate: %6.2f%%", (real'(passed_tests) / real'(total_tests)) * 100.0);

        // Display final coverage report
        display_coverage_report();
        
        if (overall_coverage_percent >= 100.0) begin
            $display("100%% COVERAGE ACHIEVED!");
        end else begin
            $display("Coverage: %0.1f%% - Target not reached", overall_coverage_percent);
        end
        
        $finish;
    end

endmodule