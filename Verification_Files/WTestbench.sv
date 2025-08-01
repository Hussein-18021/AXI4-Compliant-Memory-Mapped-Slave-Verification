`timescale 1ns/1ns
import enuming::*;
`include "Wstim.sv"

module axi_write_tb(axi_if axi);

    int total_tests = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    WTransaction tx;
    WTransaction expected_queue[$];
    WTransaction actual_queue[$];

    task automatic assert_reset();
        axi.ARESTN = 0;
        @(posedge axi.clk);
        check_results();
        axi.ARESTN = 1;
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

    task automatic drive_stim(input WTransaction wtxn, ref logic [axi.DATA_WIDTH-1:0] wdata_captured[]);
        wdata_captured = new[wtxn.WDATA.size()];
        if (axi.AWVALID === 1'bx || axi.WVALID === 1'bx) begin
            assert_reset();
            return;
        end

        axi.AWADDR  <= wtxn.AWADDR;
        axi.AWLEN   <= wtxn.AWLEN;
        axi.AWSIZE  <= wtxn.AWSIZE;
        axi.AWVALID <= 1;

        do @(axi.cb); while (!axi.AWREADY);
        axi.AWVALID <= 0;

        foreach (wtxn.WDATA[i]) begin
            axi.WDATA  <= wtxn.WDATA[i];
            axi.WLAST  <= (i == wtxn.WDATA.size() - 1);
            axi.WVALID <= 1;
            $display("[WRITE BEAT] i=%0d, data=%h, WLAST=%b", i, wtxn.WDATA[i], axi.WLAST); 
            do @(axi.cb); while (!axi.WREADY);
            axi.WVALID <= 0;
            wdata_captured[i] = axi.WDATA;
            @axi.cb;
        end

        axi.BREADY <= 1;
        wait (axi.BVAILD == 1);
        $display("BRESP: %0b", axi.BRESP);
        axi.BREADY <= 0;
        @axi.cb;
    endtask

    task automatic collect_output(input logic [axi.DATA_WIDTH-1:0] wdata_captured[]);
        WTransaction actual = new();
        actual.AWADDR = axi.AWADDR;
        actual.AWLEN  = axi.AWLEN;
        actual.AWSIZE = axi.AWSIZE;
        actual.WDATA  = new[wdata_captured.size()];
        foreach (wdata_captured[i])
            actual.WDATA[i] = wdata_captured[i];
        actual_queue.push_back(actual);
    endtask

    task automatic check_results();
        int num_checks = (actual_queue.size() < expected_queue.size()) ? actual_queue.size() : expected_queue.size();

        total_tests++;
        $display("======================================================");
        $display("Test #%0d Result", total_tests);
        $display("  Actual   : AWADDR=%h AWLEN=%0d AWSIZE=%0d WDATA=%p", actual_queue[num_checks-1].AWADDR, actual_queue[num_checks-1].AWLEN, actual_queue[num_checks-1].AWSIZE, actual_queue[num_checks-1].WDATA);
        $display("  Expected : AWADDR=%h AWLEN=%0d AWSIZE=%0d WDATA=%p", expected_queue[num_checks-1].AWADDR, expected_queue[num_checks-1].AWLEN, expected_queue[num_checks-1].AWSIZE, expected_queue[num_checks-1].WDATA);

        if (actual_queue[num_checks-1] === expected_queue[num_checks-1]) begin
            passed_tests++;
            $display("  TEST PASS");
        end else begin
            failed_tests++;
            $display("  TEST FAIL");
            $finish(1); // stop simulation on failure
        end
    endtask

    initial begin
        logic [axi.DATA_WIDTH-1:0] wdata_captured[];
        repeat(10) begin
            generate_stimulus();
            drive_stim(tx, wdata_captured);        
            golden_model(tx);           
            collect_output(wdata_captured);        
            check_results();
        end
        $finish;
    end

endmodule