module R_TB #(
    parameter int DATA_WIDTH  = 32,
    parameter int ADDR_WIDTH  = 16
    ) (axi_if.RTEST bus);

import R_STIM::*;
import R_enums::*;

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
assign bus.ARESTN = ARESTN;
assign bus.ARADDR = ARADDR;
assign bus.ARLEN = ARLEN;
assign bus.ARSIZE = ARSIZE;
assign bus.ARVALID = ARVALID;
assign bus.RREADY = RREADY;

task automatic reset(ref logic ARESTN);
    ARESTN = 1;
    @bus.cb;
    ARESTN = 0;
    @bus.cb;
    ARESTN = 1;
endtask 

task automatic gen_R_stim(ref Rtransaction R_tr);
    assert (R_tr.randomize()) 
    else    $fatel("Error couldn't randomize");
endtask

task automatic R_drive_stim(ref Rtransaction tr,
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
    @(bus.cb)
    ARADDR = tr.ARADDR;
    ARLEN = tr.ARLEN;
    ARSIZE = tr.ARSIZE;
    ARVALID = 1;
    @(ARREADY && ARVALID)
    for(int i = 0; i < ARLEN+1; i++) begin
        @(bus.cb)
        RREADY = 1;
        @(RVALID && RVALID)
        collect_out(act_RDATA, RDATA);
        @(bus.cb)
        RREADY = 0;
    end
endtask 

task automatic collect_out(ref logic [DATA_WIDTH-1:0] act_RDATA [$], ref logic [DATA_WIDTH-1:0] RDATA);
    @(bus.cb)
    act_RDATA.push_back(RDATA);    
endtask 

task automatic load_memory_from_file(string filename);
    int fd;
    int idx = 0;
    string line;
    fd = $fopen(filename, "r");
    if (fd == 0) begin
        $fatal("Cannot open file: %s", filename);
    end

    while (!$feof(fd) && idx < 1024) begin
        void'($fscanf(fd, "%h\n", golden_mem[idx]));
        idx++;
    end
    $fclose(fd);
    $display("Memory loaded from %s", filename);
endtask


task automatic golden_model (ref Rtransaction tr, ref logic [DATA_WIDTH-1:0] exp_RDATA [$]);
    int addr_word;
    addr_word = tr.ARADDR >> 2;  

    for (int i = 0; i < tr.ARLEN + 1; i++) begin
        if ((addr_word + i) >= 1024) begin
            exp_RDATA.push_back(1'b0);
        end else begin
            exp_RDATA.push_back(golden_mem[addr_word + i]);
        end
    end
endtask

task automatic R_check_result (ref logic [DATA_WIDTH-1:0] exp_RDATA [$], ref logic [DATA_WIDTH-1:0] act_RDATA [$]);
    foreach(exp_RDATA [i]) begin
        if (exp_RDATA [i] == act_RDATA [i]) begin
            $display("[PASS]: Actual read data : %h, Expectd read data : %h\n", act_RDATA[i], exp_RDATA[i]);
        end else begin
            $fatal("[ERROR]: Actual read data : %h, Expectd read data : %h\n", act_RDATA[i], exp_RDATA[i]);
        end

    end 
endtask

initial begin
    reset(ARESTN);
    R_tr = new();

    repeat(2048) begin
        gen_R_stim(R_tr);
        R_drive_stim(R_tr, RDATA, RRESP,  RLAST,  RVALID, ARADDR,  ARLEN,  ARSIZE,  ARVALID, RREADY, act_RDATA);
        golden_model(R_tr, exp_RDATA);
        R_check_result (exp_RDATA, act_RDATA);
    end

    $stop;
end

endmodule