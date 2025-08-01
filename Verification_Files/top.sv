`timescale 1ns/1ns

module top;
    parameter int DATA_WIDTH = 32;
    parameter int ADDR_WIDTH = 16;
    parameter int MEMORY_DEPTH = 1024;

    bit clk;
    logic rstn;

    axi_if #(DATA_WIDTH, ADDR_WIDTH) axi(clk);

    axi4 #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .MEMORY_DEPTH(MEMORY_DEPTH)
    ) dut (
        .ACLK     (axi.DUT.ACLK),
        .ARESETn  (axi.DUT.ARESTN),
        .AWADDR   (axi.DUT.AWADDR),
        .AWLEN    (axi.DUT.AWLEN),
        .AWSIZE   (axi.DUT.AWSIZE),
        .AWVALID  (axi.DUT.AWVALID),
        .AWREADY  (axi.DUT.AWREADY),
        .WDATA    (axi.DUT.WDATA),
        .WLAST    (axi.DUT.WLAST),
        .WVALID   (axi.DUT.WVALID),
        .WREADY   (axi.DUT.WREADY),
        .BRESP    (axi.DUT.BRESP),
        .BVALID   (axi.DUT.BVAILD),
        .BREADY   (axi.DUT.BREADY),
        .ARADDR   (axi.DUT.ARADDR),
        .ARLEN    (axi.DUT.ARLEN),
        .ARSIZE   (axi.DUT.ARSIZE),
        .ARVALID  (axi.DUT.ARVALID),
        .ARREADY  (axi.DUT.ARREADY),
        .RDATA    (axi.DUT.RDATA),
        .RRESP    (axi.DUT.RRESP),
        .RLAST    (axi.DUT.RLAST),
        .RVALID   (axi.DUT.RVAILD),
        .RREADY   (axi.DUT.RREADY)
    );

    axi_write_tb tb(axi);

endmodule
