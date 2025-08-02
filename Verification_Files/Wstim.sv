// import enuming::*;
class WTransaction #(parameter int DATA_WIDTH = 32, parameter int ADDR_WIDTH = 16);

    localparam int MEMORY_DEPTH = 1024;
    localparam int MAX_BYTE_ADDR = 4 * (MEMORY_DEPTH - 1); 
    rand logic [ADDR_WIDTH-1:0] AWADDR;
    rand logic [7:0]  AWLEN;
    rand logic [2:0]  AWSIZE;

    rand logic [DATA_WIDTH-1:0] WDATA[];

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

    constraint avoid_4kb_crossing_c {
        ((AWADDR & 12'hFFF) + total_bytes()) <= 12'hFFF;
    }

    // constraint force_4kb_crossing_c {
    //     ((AWADDR & 12'hFFF) + total_bytes()) > 12'hFFF;
    // }

    constraint memory_range_c {
        (AWADDR >> 2) < MEMORY_DEPTH;
        ((AWADDR >> 2) + AWLEN) < MEMORY_DEPTH;
    }
    
    function int total_bytes();
        return (AWLEN + 1) << AWSIZE;
    endfunction

    function bit crosses_4KB_boundary();
        return ((AWADDR & 12'hFFF) + total_bytes()) > 12'hFFF;
    endfunction

    function bit exceeds_memory_range();
        return ((AWADDR >> 2) + (AWLEN + 1)) > MEMORY_DEPTH;
    endfunction

    function void display();
        $display("AWADDR = 0x%0h | AWLEN = %0d | AWSIZE = %0d | Beats = %0d",
                AWADDR, AWLEN, AWSIZE, AWLEN+1);
        $display("  Memory range: word_addr %0d to %0d (max: %0d)", 
                AWADDR >> 2, (AWADDR >> 2) + AWLEN, MEMORY_DEPTH-1);
        $display("  Byte range: 0x%0h to 0x%0h (max: 0x%0h)", 
                AWADDR, AWADDR + ((AWLEN+1) << AWSIZE) - 1, MAX_BYTE_ADDR);
        $display("  Crosses 4KB boundary: %b | Exceeds memory: %b", 
                crosses_4KB_boundary(), exceeds_memory_range());
    endfunction

endclass