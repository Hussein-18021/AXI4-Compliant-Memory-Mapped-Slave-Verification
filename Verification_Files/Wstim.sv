// import enuming::*;
class WTransaction #(parameter int DATA_WIDTH = 32, parameter int ADDR_WIDTH = 16);

    localparam int MEMORY_DEPTH = 1024;

    rand logic [ADDR_WIDTH-1:0] AWADDR;
    rand logic [7:0]  AWLEN;
    rand logic [2:0]  AWSIZE;

    rand logic [DATA_WIDTH-1:0] WDATA[];

    // rand handshake_t aw_handshake_type;
    // rand handshake_t w_handshake_type;

    function new();
        AWSIZE = 3'b010;
    endfunction

    function void post_randomize();
        int burst_len = AWLEN + 1;
        WDATA = new[burst_len];
        foreach (WDATA[i])
            WDATA[i] = $urandom;
    endfunction

    constraint fixed_awsz_c {
        AWSIZE == 3'b010;
    }

    constraint aligned_addr_c {
        AWADDR % (1 << AWSIZE) == 0;
    }

    constraint boundary_4kb_c {
        ((AWADDR & 16'h0FFF) + ((AWLEN + 1) << AWSIZE)) <= 4096;
    }

    constraint memory_range_c {
        ((AWADDR >> 2) + (AWLEN + 1)) < MEMORY_DEPTH;
    }

    // constraint aw_valid_before_ready {
    //     aw_handshake_type == VALID_BEFORE_READY;
    // }

    // constraint w_ready_before_valid {
    //     w_handshake_type == READY_BEFORE_VALID;
    // }

    function void display();
        $display("AWADDR = 0x%0h | AWLEN = %0d | AWSIZE = %0d | Beats = %0d",
                AWADDR, AWLEN, AWSIZE, AWLEN+1);
        // $display("Handshake AW: %s | W: %s",
        //         (aw_handshake_type == VALID_BEFORE_READY) ? "VALID→READY" : "READY→VALID",
        //         (w_handshake_type == VALID_BEFORE_READY) ? "VALID→READY" : "READY→VALID");
        foreach (WDATA[i])
            $display("WDATA[%0d] = 0x%08h", i, WDATA[i]);
    endfunction

endclass