package R_STIM;
    class Rtransaction #(
        parameter int DATA_WIDTH  = 32,
        parameter int ADDR_WIDTH  = 16,
        parameter int MEMORY_DEPTH = 1024
    );
        randc logic [ADDR_WIDTH-1:0] ARADDR;
        randc logic [7:0] ARLEN;
        randc logic [2:0] ARSIZE;
        
        
        rand int arvalid_delay;        
        rand int arvalid_duration;
        rand int rready_delay;         
        rand int rready_deassert_prob; 

        
        rand int reset_duration_cycles;
        rand int reset_delay_cycles;

        constraint fixed_ARSIZE_c {
            ARSIZE == 3'b010;
        }
        
        constraint Boundry_4KB_c {
            (ARADDR & 16'h0FFF) + ((ARLEN + 1) << 2) < 4096;
        }
        
        constraint MEMO_RANGE_C {
            (ARADDR >> 2) < MEMORY_DEPTH;
            ((ARADDR >> 2) + ARLEN) < MEMORY_DEPTH;
        }

        
        constraint arvalid_timing_c {
            arvalid_delay inside {[0:5]};        
            arvalid_duration inside {[1:3]};    
        }
        
        constraint rready_timing_c {
            rready_delay inside {[0:3]};        
            rready_deassert_prob inside {[0:30]}; 
        }

        
        constraint reset_duration_c {
            reset_duration_cycles inside {[2:10]};
        }
        
        constraint reset_delay_c {
            reset_delay_cycles inside {[5:25]};
        }

        function void cross_boundary();
            $display("boundary = %0d", ((ARADDR & 16'h0FFF) + ((ARLEN + 1) << 2)));
        endfunction

       
        covergroup cg; 
            coverpoint ARADDR {
                bins low_range  = {[0:16'h0FFF]};
                bins mid_range  = {[16'h1000:16'h2FFF]};
                bins high_range = {[16'h3000:16'hFFFF]};
            }
            coverpoint ARLEN {
                bins single   = {0};
                bins short    = {[1:7]};
                bins mid   = {[8:15]};
                bins long     = {[16:255]};
            }
            coverpoint ARSIZE {
                bins word_transfer = {2};
                bins other_sizes   = {[0:1], [3:7]};
            }
            cross ARADDR, ARLEN;
        endgroup

        function new (); 
            ARSIZE = 3'b010;
            cg = new();
        endfunction

    endclass
endpackage