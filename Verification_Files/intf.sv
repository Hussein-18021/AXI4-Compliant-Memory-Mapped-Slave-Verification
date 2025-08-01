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
    logic       BVAILD;
    logic       BREADY;

    logic [ADDR_WIDTH-1:0] ARADDR;
    logic [7:0]  ARLEN;
    logic [2:0]  ARSIZE;
    logic       ARVALID;
    logic       ARREADY;

    logic [DATA_WIDTH-1:0] RDATA;
    logic [1:0]  RRESP;
    logic       RLAST;
    logic       RVAILD;
    logic       RREADY;


    clocking cb @(posedge clk);
        default input #1step output negedge;
        // Write channel
        output AWADDR, AWLEN, AWSIZE, AWVALID, WDATA, WLAST, WVALID, BREADY;
        input  AWREADY, WREADY, BRESP, BVAILD;

        // Read channel
        output ARADDR, ARLEN, ARSIZE, ARVALID, RREADY;
        input  ARREADY, RDATA, RRESP, RLAST, RVAILD;
    endclocking


    modport DUT (
        input  ACLK, ARESTN, AWADDR, AWLEN, AWSIZE, AWVALID, WDATA, WLAST, WVALID, BREADY,
               ARADDR, ARLEN, ARSIZE, ARVALID, RREADY,
        output AWREADY, WREADY, BRESP, BVAILD, ARREADY, RDATA, RRESP, RLAST, RVAILD
    );

    // Write testbench modport
    modport WTEST (
        input  ACLK, AWREADY, WREADY, BRESP, BVAILD,
        output ARESTN, AWADDR, AWLEN, AWSIZE, AWVALID, WDATA, WLAST, WVALID, BREADY
    );

    // Read testbench modport
    modport RTEST (
        input  ACLK, ARREADY, RDATA, RRESP, RLAST, RVAILD,
        output ARESTN, ARADDR, ARLEN, ARSIZE, ARVALID, RREADY
    );
endinterface
