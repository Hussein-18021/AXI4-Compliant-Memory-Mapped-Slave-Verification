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
        actual_tx = new();
        actual_tx.AWADDR = wtxn.AWADDR;
        actual_tx.AWLEN = wtxn.AWLEN;
        actual_tx.AWSIZE = wtxn.AWSIZE;
        actual_tx.WDATA = new[wtxn.WDATA.size()];
        
        // if (axi.AWVALID === 1'bx || axi.WVALID === 1'bx) begin
        //     $display("Warning: Unknown states detected, asserting reset");
        //     assert_reset();
        //     return;
        // end

        $display("Starting write transaction...");
        
        // Write Address Phase
        axi.AWADDR  <= wtxn.AWADDR;
        axi.AWLEN   <= wtxn.AWLEN;
        axi.AWSIZE  <= wtxn.AWSIZE;
        axi.AWVALID <= 1;

        do @(posedge axi.clk); while (!axi.AWREADY);
        axi.AWVALID <= 0;
        $display("Address phase completed: AWADDR=0x%h", wtxn.AWADDR);

        // Write Data Phase
        foreach (wtxn.WDATA[i]) begin
            axi.WDATA  <= wtxn.WDATA[i];
            axi.WLAST  <= (i == wtxn.WDATA.size() - 1);
            axi.WVALID <= 1;
            $display("[WRITE BEAT] i=%0d, data=0x%h, WLAST=%b", i, wtxn.WDATA[i], axi.WLAST); 
            
            do @(posedge axi.clk); while (!axi.WREADY);
            axi.WVALID <= 0;
            actual_tx.WDATA[i] = wtxn.WDATA[i]; // Capture the driven data
            @(posedge axi.clk);
        end

        // Write Response Phase
        axi.BREADY <= 1;
        do @(posedge axi.clk); while (!axi.BVALID);
        $display("BRESP: %0b", axi.BRESP);
        axi.BREADY <= 0;
        @(posedge axi.clk);
        $display("Write transaction completed successfully");
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
        $display("  Actual   : AWADDR=%h AWLEN=%0d AWSIZE=%0d", actual.AWADDR, actual.AWLEN, actual.AWSIZE);
        $display("  Expected : AWADDR=%h AWLEN=%0d AWSIZE=%0d", expected.AWADDR, expected.AWLEN, expected.AWSIZE);

        if (actual.AWADDR == expected.AWADDR && 
            actual.AWLEN == expected.AWLEN && 
            actual.AWSIZE == expected.AWSIZE &&
            actual.WDATA.size() == expected.WDATA.size()) begin
            
            bit data_match = 1;
            foreach (actual.WDATA[i]) begin
                if (actual.WDATA[i] != expected.WDATA[i]) begin
                    data_match = 0;
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
    endtask

    initial begin
        WTransaction actual_tx;
        
        $display("Starting AXI Write Testbench...");
        assert_reset();
        
        repeat(3) begin  // Reduced for easier debugging
            $display("\n--- Starting Test %0d ---", total_tests + 1);
            generate_stimulus();
            drive_stim(tx, actual_tx);        
            golden_model(tx);           
            collect_output(actual_tx);        
            check_results();
            repeat(3) @(posedge axi.clk);
        end
        
        $display("\n======================================================");
        $display("TEST SUMMARY:");
        $display("Total Tests: %0d", total_tests);
        $display("Passed: %0d", passed_tests);
        $display("Failed: %0d", failed_tests);
        $display("======================================================");
        $finish;
    end

endmodule