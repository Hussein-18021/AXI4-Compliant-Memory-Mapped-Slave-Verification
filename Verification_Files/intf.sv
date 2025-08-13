interface axi_if #(
    parameter int DATA_WIDTH  = 32,
    parameter int ADDR_WIDTH  = 16
    ) (input bit clk);

    logic ACLK;
    logic ARESTN;

    logic [ADDR_WIDTH-1:0] AWADDR;
    logic [7:0]  AWLEN;
    logic [2:0]  AWSIZE;
    logic       AWVALID;
    logic       AWREADY;

    logic [DATA_WIDTH-1:0] WDATA;
    logic       WLAST;
    logic       WVALID;
    logic       WREADY;

    logic [1:0]  BRESP;
    logic       BVALID;
    logic       BREADY;

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




    modport DUT (
        input  ACLK, ARESTN, AWADDR, AWLEN, AWSIZE, AWVALID, WDATA, WLAST, WVALID, BREADY,
               ARADDR, ARLEN, ARSIZE, ARVALID, RREADY,
        output AWREADY, WREADY, BRESP, BVALID, ARREADY, RDATA, RRESP, RLAST, RVALID
    );

    modport TB (
        input   ACLK, AWREADY, WREADY, BRESP, BVALID, ARREADY, RDATA, RRESP, RLAST, RVALID,
        output ARESTN, AWADDR, AWLEN, AWSIZE, AWVALID, WDATA, WLAST, WVALID, BREADY,
               ARADDR, ARLEN, ARSIZE, ARVALID, RREADY
    );
    // Keep for backward compatibility
    // // Write testbench modport
    // modport WTEST (
    //     input  ACLK, AWREADY, WREADY, BRESP, BVALID,
    //     output ARESTN, AWADDR, AWLEN, AWSIZE, AWVALID, WDATA, WLAST, WVALID, BREADY
    // );

    // // Read testbench modport
    // modport RTEST (
    //     clocking cb;
    //     input  ACLK, ARREADY, RDATA, RRESP, RLAST, RVALID,  
    //     output ARESTN, ARADDR, ARLEN, ARSIZE, ARVALID, RREADY
    // );
    
endinterface
