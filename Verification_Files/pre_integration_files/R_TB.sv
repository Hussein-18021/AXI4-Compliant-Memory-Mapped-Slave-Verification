module R_TB #(
    parameter int DATA_WIDTH  = 32,
    parameter int ADDR_WIDTH  = 16
    ) (axi_if.RTEST bus);

import R_STIM::*;

Rtransaction R_tr;
logic ACLK;
logic ARESTN;

logic [ADDR_WIDTH-1:0] ARADDR;
logic [7:0]  ARLEN;
logic [2:0]  ARSIZE;
logic       ARVALID;
logic       ARREADY;

logic [DATA_WIDTH-1:0] RDATA;
logic [1:0]  RRESP;
logic       RLAST;
logic       RVALID;
logic       RREADY;

logic [DATA_WIDTH-1:0] golden_mem [0:1023];
logic [DATA_WIDTH-1:0]  exp_RDATA [$];
logic [DATA_WIDTH-1:0] act_RDATA [$];

assign ACLK = bus.ACLK;
assign RDATA = bus.RDATA;
assign RRESP = bus.RRESP;
assign RLAST = bus.RLAST;
assign RVALID = bus.RVALID;
assign ARREADY = bus.ARREADY;
assign bus.ARESTN = ARESTN;
assign bus.ARADDR = ARADDR;
assign bus.ARLEN = ARLEN;
assign bus.ARSIZE = ARSIZE;
assign bus.ARVALID = ARVALID;
assign bus.RREADY = RREADY;

task automatic reset(ref logic ARESTN);
    ARESTN = 1;
    @(posedge ACLK);  // Fixed: use posedge ACLK instead of bus.cb
    ARESTN = 0;
    @(posedge ACLK);
    ARESTN = 1;
    @(posedge ACLK);  // Extra cycle to ensure reset is released
endtask 

task automatic gen_R_stim(ref Rtransaction R_tr);
    assert (R_tr.randomize()) 
    else $fatal("Error couldn't randomize");  // Fixed: $fatal not $fatel
endtask

function automatic void reset_queues (ref logic [DATA_WIDTH-1:0]  exp_RDATA [$],
                                      ref logic [DATA_WIDTH-1:0] act_RDATA [$]);
    exp_RDATA = {};
    act_RDATA = {};
endfunction

task automatic R_drive_stim(
    ref Rtransaction tr,
    ref logic [DATA_WIDTH-1:0] RDATA,
    ref logic [1:0] RRESP,
    ref logic RLAST,
    ref logic RVALID,
    ref logic [ADDR_WIDTH-1:0] ARADDR,
    ref logic [7:0] ARLEN,
    ref logic [2:0] ARSIZE,
    ref logic ARVALID,
    ref logic RREADY,
    ref logic [DATA_WIDTH-1:0] act_RDATA [$]);

    // Send address
    @(posedge ACLK);
    ARADDR  = tr.ARADDR;
    ARLEN   = tr.ARLEN;
    ARSIZE  = tr.ARSIZE;
    ARVALID = 1;
    
    // Wait for address to be accepted
    wait (ARREADY === 1);
    @(posedge ACLK);
    ARVALID = 0;

    // Start data reception
    RREADY = 1;
    for (int i = 0; i <= ARLEN; i++) begin  // Fixed: i <= ARLEN (not i < ARLEN + 1)
        wait (RVALID === 1);  // Wait for valid data
        @(posedge ACLK);      // Sample data on clock edge
        collect_out(act_RDATA, RDATA);
        
        // Check RLAST on final beat
        if (i == ARLEN && RLAST !== 1) begin
            $fatal("[ERROR] RLAST not asserted on last beat (beat %0d)", i);
        end
        
        // If not the last beat, wait for RVALID to go low before next iteration
        if (i < ARLEN) begin
            wait (RVALID === 0);
        end
    end
    RREADY = 0;
endtask

task automatic collect_out(ref logic [DATA_WIDTH-1:0] act_RDATA [$], ref logic [DATA_WIDTH-1:0] RDATA);
    act_RDATA.push_back(RDATA);    
endtask 

// Fixed: Initialize golden memory with the expected pattern
task automatic load_golden_memory();
    for (int i = 0; i < 1024; i++) begin
        golden_mem[i] = i;  // This matches your memory.hex pattern (0, 1, 2, 3, ...)
    end
    $display("Golden memory initialized with pattern 0x0, 0x1, 0x2, ...");
endtask

task automatic golden_model (ref Rtransaction tr, ref logic [DATA_WIDTH-1:0] exp_RDATA [$]);
    int addr_word;
    addr_word = tr.ARADDR >> 2;  

    for (int i = 0; i <= tr.ARLEN; i++) begin  // Fixed: i <= tr.ARLEN
        if ((addr_word + i) >= 1024) begin
            exp_RDATA.push_back(32'h0);  // Fixed: use 32'h0 instead of 1'b0
        end else begin
            exp_RDATA.push_back(golden_mem[addr_word + i]);
        end
    end
endtask

task automatic R_check_result (ref logic [DATA_WIDTH-1:0] exp_RDATA [$], ref logic [DATA_WIDTH-1:0] act_RDATA [$]);
    if (exp_RDATA.size() != act_RDATA.size()) begin
        $display("[ERROR]: Queue size mismatch - Expected: %0d, Actual: %0d", exp_RDATA.size(), act_RDATA.size());
    end
    
    foreach(exp_RDATA [i]) begin
        if (i < act_RDATA.size()) begin
            if (exp_RDATA[i] == act_RDATA[i]) begin
                $display("[PASS]: Beat %0d - Actual: 0x%h, Expected: 0x%h", i, act_RDATA[i], exp_RDATA[i]);
            end else begin
                $display("[ERROR]: Beat %0d - Actual: 0x%h, Expected: 0x%h", i, act_RDATA[i], exp_RDATA[i]);
            end
        end else begin
            $display("[ERROR]: Missing actual data for beat %0d", i);
        end
    end 
endtask

initial begin
    // Initialize golden memory instead of loading from file
    load_golden_memory();
    
    reset(ARESTN);
    R_tr = new();

    repeat(4096) begin  // Reduced for debugging - change back to 2048 once working
        reset_queues(exp_RDATA, act_RDATA);
        gen_R_stim(R_tr);
        R_tr.cg.sample();
        $display("=== Test Transaction ===");
        $display("ARADDR = 0x%h, ARLEN = %0d, ARSIZE = %0d", R_tr.ARADDR, R_tr.ARLEN, R_tr.ARSIZE);
        
        R_drive_stim(R_tr, RDATA, RRESP, RLAST, RVALID, ARADDR, ARLEN, ARSIZE, ARVALID, RREADY, act_RDATA);
        golden_model(R_tr, exp_RDATA);
        R_check_result(exp_RDATA, act_RDATA);
        
        $display("========================");
    end
    
    $display("Testbench completed!");
    $stop;
end

endmodule