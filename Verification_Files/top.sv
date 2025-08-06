`timescale 1ns/1ns

module top;
    parameter int DATA_WIDTH = 32;
    parameter int ADDR_WIDTH = 16;
    parameter int MEMORY_DEPTH = 1024;

    bit clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    axi_if #(DATA_WIDTH, ADDR_WIDTH) axi(clk);

    assign axi.ACLK = clk;

    axi4 #( .DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(ADDR_WIDTH), .MEMORY_DEPTH(MEMORY_DEPTH)) dut (
        .ACLK     (axi.ACLK),
        .ARESETn  (axi.ARESTN), 
        .AWADDR   (axi.AWADDR),
        .AWLEN    (axi.AWLEN),
        .AWSIZE   (axi.AWSIZE),
        .AWVALID  (axi.AWVALID),
        .AWREADY  (axi.AWREADY),
        .WDATA    (axi.WDATA),
        .WLAST    (axi.WLAST),
        .WVALID   (axi.WVALID),
        .WREADY   (axi.WREADY),
        .BRESP    (axi.BRESP),
        .BVALID   (axi.BVALID),
        .BREADY   (axi.BREADY),
        .ARADDR   (axi.ARADDR),
        .ARLEN    (axi.ARLEN),
        .ARSIZE   (axi.ARSIZE),
        .ARVALID  (axi.ARVALID),
        .ARREADY  (axi.ARREADY),
        .RDATA    (axi.RDATA),
        .RRESP    (axi.RRESP),
        .RLAST    (axi.RLAST),
        .RVALID   (axi.RVALID),
        .RREADY   (axi.RREADY)
    );

    Testbench tb(axi.TB);

endmodule