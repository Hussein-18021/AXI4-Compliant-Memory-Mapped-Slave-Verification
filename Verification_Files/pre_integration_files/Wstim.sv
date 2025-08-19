import enuming::*;

class WTransaction #(parameter int DATA_WIDTH = 32, parameter int ADDR_WIDTH = 16);

    localparam int MEMORY_DEPTH = 1024;
    localparam int MAX_BYTE_ADDR = 4 * (MEMORY_DEPTH - 1); 

    rand logic [ADDR_WIDTH-1:0] AWADDR;
    rand logic [7:0] AWLEN;
    logic [2:0] AWSIZE;
    rand logic [DATA_WIDTH-1:0] WDATA[];

    // AXI4 Handshake signals
    rand int awvalid_delay;    // Cycles to delay AWVALID assertion
    rand int wvalid_delay[];   // Cycles to delay each WVALID assertion
    rand bit awvalid_value;    // Randomize AWVALID assertion pattern
    rand bit wvalid_pattern[]; // Randomize WVALID patterns per beat
    rand bit bready_value;     // Randomize BREADY behavior
    rand int reset_cycles;     // Randomize reset duration

    rand test_mode_e test_mode;
    rand data_pattern_e data_pattern;
    rand burst_type_e burst_type;


    covergroup write_address_coverage;
        awaddr_cp: coverpoint AWADDR {
            bins low_addr    = {[0:255]};
            bins mid_addr    = {[256:511]};
            bins high_addr   = {[512:1023]};
            bins alignment[] = {[0:15]} with (item % 4 == 0);
        }

        awlen_cp: coverpoint AWLEN {
            bins single     = {0};         
            bins short      = {[1:7]};     
            bins medium_    = {[8:31]};     
            bins long       = {[32:127]};    
        }
    endgroup

    covergroup write_data_coverage;
        first_data_cp: coverpoint WDATA[0] {
            bins all_zeros   = {32'h00000000};
            bins all_ones    = {32'hFFFFFFFF};
            bins alternating = {32'hAAAAAAAA, 32'h55555555};
            bins random_data = default;
        }

        data_array_size_cp: coverpoint WDATA.size() {
            bins single   = {1};
            bins small_   = {[2:8]};
            bins medium_  = {[9:32]};
            bins large_   = {[33:64]};
        }
    endgroup

    covergroup boundary_coverage;
        crosses_4kb_cp: coverpoint crosses_4KB_boundary() {
            bins no_crossing  = {0};
            bins yes_crossing = {1};
        }

        exceeds_memory_cp: coverpoint exceeds_memory_range() {
            bins within_range = {0};
        }
    endgroup

    covergroup test_mode_coverage;
        test_mode_cp: coverpoint test_mode {
            bins random_mode       = {RANDOM_MODE};
            bins boundary_mode     = {BOUNDARY_CROSSING_MODE};
            bins burst_mode        = {BURST_LENGTH_MODE};
            bins data_pattern_mode = {DATA_PATTERN_MODE};
        }
        
        // Coverage for handshake behaviors
        awvalid_cp: coverpoint awvalid_value {
            bins asserted     = {1};
            bins not_asserted = {0};
        }
        
        bready_cp: coverpoint bready_value {
            bins ready     = {1};
            bins not_ready = {0};
        }
        
        reset_cycles_cp: coverpoint reset_cycles {
            bins short_reset  = {[2:4]};
            bins medium_reset = {[5:6]};
        }
        
        // Cross coverage for transaction scenarios
        transaction_scenario: cross awvalid_cp, bready_cp {
            bins normal_transaction    = binsof(awvalid_cp.asserted) && binsof(bready_cp.ready);
            bins no_response_capture   = binsof(awvalid_cp.asserted) && binsof(bready_cp.not_ready);
            bins aborted_transaction   = binsof(awvalid_cp.not_asserted);
        }
    endgroup

    function new();
        AWSIZE = 3'b010; 
        write_address_coverage = new();
        write_data_coverage    = new();
        boundary_coverage      = new();
        test_mode_coverage     = new();
    endfunction

    constraint test_mode_dist_c {
        test_mode dist {
            RANDOM_MODE            := 40,
            BOUNDARY_CROSSING_MODE := 30,
            BURST_LENGTH_MODE      := 20,
            DATA_PATTERN_MODE      := 10
        };
    }

    constraint burst_length_c {
        if (burst_type == SINGLE_BEAT) { AWLEN == 0;} 
        else if (burst_type == SHORT_BURST) { AWLEN inside {[1:7]};} 
        else if (burst_type == MEDIUM_BURST) { AWLEN inside {[8:31]};} 
        else if (burst_type == LONG_BURST) { AWLEN inside {[32:63]};} 
        else {AWLEN inside {[64:127]};}
    }

    constraint addr_range_targeting_c {
        solve AWLEN before AWADDR;
        if (test_mode == RANDOM_MODE) {
            AWADDR inside {
                [0:255],       // low
                [256:511],     // mid
                [512:1023]     // high
            };
        }
    }

    constraint boundary_targeting_c {
        solve AWLEN before AWADDR;
        if (test_mode == BOUNDARY_CROSSING_MODE) {
            ((AWADDR & 12'hFFF) + ((AWLEN + 1) << AWSIZE)) > 12'hFFF;  // Force boundary crossing
        } 
        
        else {
            ((AWADDR & 12'hFFF) + ((AWLEN + 1) << AWSIZE)) <= 12'hFFF; // Prevent boundary crossing
        }
    }

    constraint memory_range_c {
        (AWADDR >> 2) < MEMORY_DEPTH;
        ((AWADDR >> 2) + AWLEN) < MEMORY_DEPTH;
    }
    
    constraint addr_alignment_c {
        AWADDR % (1 << AWSIZE) == 0;
    }

    constraint data_pattern_dist_c {
        data_pattern dist {
            RANDOM_DATA     := 70,
            ALL_ZEROS       := 10,
            ALL_ONES        := 10,
            ALTERNATING_AA  := 5,
            ALTERNATING_55  := 5
        };
    }

    // AXI4 Handshake delay constraints
    constraint handshake_delay_c {
        awvalid_delay inside {[0:3]};    // 0-3 cycle delay for AWVALID
        reset_cycles inside {[2:5]};     // 2-5 cycle reset duration
        
        wvalid_delay.size() == (AWLEN + 1);
        foreach (wvalid_delay[i]) {
            wvalid_delay[i] inside {[0:2]}; // 0-2 cycle delay per WVALID
        }
        
        wvalid_pattern.size() == (AWLEN + 1);
        
        awvalid_value dist {1 := 90, 0 := 10};     // Usually proceed with transaction
        bready_value dist {1 := 95, 0 := 5};      // Usually ready for response
        
        // AXI4 Protocol Compliance: 
        // According to the protocol flow you provided:
        // 1. If AWVALID=0: No address phase, so no data phase
        // 2. If AWVALID=1: Address phase proceeds, data phase MUST complete all beats
        solve awvalid_value before wvalid_pattern;
        if (awvalid_value == 1) {
            // Address phase accepted -> ALL data beats must be transferred
            foreach (wvalid_pattern[i]) {
                wvalid_pattern[i] == 1;
            }
        } else {
            // No address phase -> No data beats should be sent
            foreach (wvalid_pattern[i]) {
                wvalid_pattern[i] == 0;
            }
        }
    }

    function void post_randomize();
        int burst_len = AWLEN + 1;
        WDATA = new[burst_len];
        
        case (data_pattern)
            ALL_ZEROS:        foreach (WDATA[i]) WDATA[i] = 32'h00000000;
            ALL_ONES:         foreach (WDATA[i]) WDATA[i] = 32'hFFFFFFFF;
            ALTERNATING_AA:   foreach (WDATA[i]) WDATA[i] = 32'hAAAAAAAA;
            ALTERNATING_55:   foreach (WDATA[i]) WDATA[i] = 32'h55555555;
            default:          foreach (WDATA[i]) WDATA[i] = $random;
        endcase

        write_address_coverage.sample();
        write_data_coverage.sample();
        boundary_coverage.sample();
        test_mode_coverage.sample();
    endfunction

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
        $display("=== WRITE TRANSACTION ===");
        $display("AWADDR = 0x%0h | AWLEN = %0d | AWSIZE = %0d | Beats = %0d",
                 AWADDR, AWLEN, AWSIZE, AWLEN+1);
        $display("  Memory range: word_addr %0d to %0d (max: %0d)", 
                 AWADDR >> 2, (AWADDR >> 2) + AWLEN, MEMORY_DEPTH-1);
        $display("  Crosses 4KB boundary: %b | Exceeds memory: %b", 
                 crosses_4KB_boundary(), exceeds_memory_range());
        $display("  Test mode: %s", test_mode.name());
        $display("  Data pattern: %s", data_pattern.name());
        $display("  STOP_ADDR = 0x%0h", AWADDR + total_bytes());
        $display("  Handshake control: AWVALID=%b (delay=%0d), BREADY=%b, Reset=%0d cycles", 
                 awvalid_value, awvalid_delay, bready_value, reset_cycles);
        
        // Determine transaction scenario based on AXI4 protocol flow
        if (!awvalid_value) begin
            $display("  Transaction Scenario: ABORTED - No address phase (AWVALID=0)");
            $display("  Expected Flow: Transaction will not proceed to data or response phases");
        end else if (!bready_value) begin
            $display("  Transaction Scenario: RESPONSE_IGNORED - Address and data phases proceed, response ignored (BREADY=0)");
            $display("  Expected Flow: AW -> W -> B (but master won't acknowledge B response)");
        end else begin
            $display("  Transaction Scenario: NORMAL - Full transaction (AWVALID=1, BREADY=1)");
            $display("  Expected Flow: AW -> W -> B (complete handshake)");
        end
        
        $write("  WVALID delays: ");
        foreach (wvalid_delay[i]) $write("%0d ", wvalid_delay[i]);
        $display("");
        $write("  WVALID patterns: ");
        foreach (wvalid_pattern[i]) $write("%b ", wvalid_pattern[i]);
        $display(" (All should be %s)", awvalid_value ? "1" : "0");
        $display("========================");
    endfunction

    // === Aggregate Coverage ===
    function real get_overall_coverage();
        real total = 0.0;
        total += write_address_coverage.get_coverage();
        total += write_data_coverage.get_coverage();
        total += boundary_coverage.get_coverage();
        total += test_mode_coverage.get_coverage();
        return total / 4.0;
    endfunction

endclass
