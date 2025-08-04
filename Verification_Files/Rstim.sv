package R_STIM;
    class Rtransaction #(
    parameter int DATA_WIDTH  = 32,
    parameter int ADDR_WIDTH  = 16
    );
        rand logic ARESTN;
        rand logic [ADDR_WIDTH-1:0] ARADDR;
        rand logic [7:0] ARLEN;
        rand logic [2:0] ARSIZE;
        rand logic ARVALID;
        rand logic ARREADY;
        rand logic [DATA_WIDTH-1:0] RDATA;
        rand logic [1:0] RRESP;
        rand logic RLAST;
        rand logic RVAILD;
        rand logic RREADY;

        function new (); 
            ARSIZE = 3'b010;
        endfunction

        constraint fixed_ARSIZE_C {
            ARSIZE == 3'b010;
        }
        constraint   Boundry_4KB_c {
            (ARADDR & 16'h0FFF) + ((ARLEN + 1) << 2) < 4096;
        }
        constraint MEMO_RANGE_C {
            (ARADDR >> 2) + (ARLEN + 1) < 4096;  
        }

        function void cross_boundary();
            $display("boundary = %0d", ((ARADDR & 16'h0FFF) + ((ARLEN + 1) << 2)));
        endfunction

    endclass
endpackage