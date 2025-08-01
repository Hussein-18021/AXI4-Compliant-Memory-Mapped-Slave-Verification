interface axi_if (input bit clk);
    logic ACLK;
    logic ARESTN;
    logic AWADDR[15:0];
    logic AWLEN[7:0];
    logic AWSIZE[2:0];
    logic AWVALID;
    logic AWREADY;
    logic WDATA[31:0];
    logic WLAST;
    logic WVALID;
    logic WREADY;
    logic BRESP[1:0];
    logic BVAILD;
    logic BREADY;
    logic ARADDR[31:0];
    logic ARLEN[7:0];
    logic ARSIZE[2:0];
    logic ARVALID;
    logic ARREADY;
    logic RDATA[31:0];
    logic RRESP[1:0];
    logic RLAST;
    logic RVAILD;
    logic RREADY;

    modport DUT (
    input ACLK, ARESTN, AWADDR, AWLEN, AWSIZE, AWVALID, WDATA, WLAST, WVALID, BREADY, ARADDR, ARLEN, ARSIZE, ARVALID, RREADY,
    output AWREADY, WREADY, BRESP, BVAILD, ARREADY, RDATA, RRESP, RLAST, RVAILD
    );

    modport WTEST (
    input ACLK, AWREADY, WREADY, BRESP, BVAILD,
    output ARESTN,AWADDR, AWLEN, AWSIZE, AWVALID, WDATA, WLAST, WVALID, BREADY
    );

    modport RTEST (
    input ACLK, ARREADY, RDATA, RRESP, RLAST, RVAILD,
    output ARESTN, ARADDR, ARLEN, ARSIZE, ARVALID, RREADY
    );


endinterface