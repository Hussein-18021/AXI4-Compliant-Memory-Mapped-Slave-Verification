`timescale 1ns/1ns
import enuming::*;
`include "Wstim.sv"

module axi_write_tb(axi_if axi);

    parameter int DATA_WIDTH = 32;
    
    int total_tests = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    WTransaction tx;
    WTransaction expected_queue[$];
    WTransaction actual_queue[$];

    // Using AXI4 Response Types from pkg.sv
    // (assuming you'll add axi_resp_t enum to pkg.sv)

    // Function to decode AXI response
    function string decode_response(logic [1:0] resp);
        case (resp)
            enuming::OKAY:   return "OKAY";
            enuming::EXOKAY: return "EXOKAY";
            enuming::SLVERR: return "SLVERR";
            enuming::DECERR: return "DECERR";
            default: return "UNKNOWN";
        endcase
    endfunction

    // Function to check if response is error
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
        if (tx == null) tx = new();
        assert(tx.randomize()) else begin
            $display("ERROR: Randomization failed!");
            $stop;
        end
        tx.display();
    endtask

    task automatic drive_stim(input WTransaction wtxn, ref WTransaction actual_tx);
        logic [1:0] bresp_captured;
        
        // Create actual transaction to capture the driven values
        actual_tx = new();
        actual_tx.AWADDR = wtxn.AWADDR;
        actual_tx.AWLEN = wtxn.AWLEN;
        actual_tx.AWSIZE = wtxn.AWSIZE;
        actual_tx.WDATA = new[wtxn.WDATA.size()];

        $display("Starting write transaction...");
        
        // Write Address Phase
        axi.AWADDR  <= wtxn.AWADDR;
        axi.AWLEN   <= wtxn.AWLEN;
        axi.AWSIZE  <= wtxn.AWSIZE;
        axi.AWVALID <= 1;

        do @(posedge axi.clk); while (!axi.AWREADY);
        axi.AWVALID <= 0;
        $display("Address phase completed: AWADDR=0x%h, AWLEN=%0d, AWSIZE=%0d", 
                 wtxn.AWADDR, wtxn.AWLEN, wtxn.AWSIZE);

        // Write Data Phase
        $display("Starting data phase with %0d beats...", wtxn.WDATA.size());
        foreach (wtxn.WDATA[i]) begin
            axi.WDATA  <= wtxn.WDATA[i];
            axi.WLAST  <= (i == wtxn.WDATA.size() - 1);
            axi.WVALID <= 1;
            $display("[WRITE BEAT %0d/%0d] data=0x%h, WLAST=%b", 
                     i+1, wtxn.WDATA.size(), wtxn.WDATA[i], axi.WLAST); 
            
            do @(posedge axi.clk); while (!axi.WREADY);
            axi.WVALID <= 0;
            actual_tx.WDATA[i] = wtxn.WDATA[i]; // Capture the driven data
            @(posedge axi.clk);
        end

        $display("Waiting for write response...");
        axi.BREADY <= 1;
        do @(posedge axi.clk); while (!axi.BVALID);
        
        bresp_captured = axi.BRESP;
        $display("BRESP: %s (0b%b)", decode_response(bresp_captured), bresp_captured);
        
        if (is_error_response(bresp_captured)) begin
            $display("WARNING: Transaction completed with error response!");
        end else begin
            $display("Transaction completed successfully");
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

    task automatic test_boundary_cases();
        WTransaction boundary_tx;
        WTransaction actual_tx;
        
        $display("\n--- Testing 4KB Boundary Case ---");
        
        // Create a transaction that should cross 4KB boundary
        boundary_tx = new();
        boundary_tx.AWADDR = 16'h0FF0;  // Close to 4KB boundary (4096 = 0x1000)
        boundary_tx.AWLEN = 8'd7;       // 8 beats 
        boundary_tx.AWSIZE = 3'b010;    // 4 bytes per beat
        boundary_tx.post_randomize();   // Generate WDATA
        
        $display("Boundary test: AWADDR=0x%h, total_bytes=%0d, crosses_boundary=%b", 
                 boundary_tx.AWADDR, (boundary_tx.AWLEN + 1) << boundary_tx.AWSIZE,
                 boundary_tx.crosses_4KB_boundary());
        
        drive_stim(boundary_tx, actual_tx);
    endtask

    initial begin
        WTransaction actual_tx;
        
        $display("Starting AXI Write Testbench...");
        $display("=====================================");
        assert_reset();
        
        repeat(3) begin
            $display("\n--- Starting Test %0d ---", total_tests + 1);
            generate_stimulus();
            drive_stim(tx, actual_tx);        
            golden_model(tx);           
            collect_output(actual_tx);        
            check_results();
            repeat(3) @(posedge axi.clk);
        end
        
        test_boundary_cases();
        
        $display("\n======================================================");
        $display("FINAL TEST SUMMARY:");
        $display("======================================================");
        $display("Total Tests: %0d", total_tests);
        $display("Passed: %0d", passed_tests);
        $display("Failed: %0d", failed_tests);
        if (failed_tests == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("%0d TESTS FAILED", failed_tests);
        end
        $display("======================================================");
        $finish;
    end

endmodule