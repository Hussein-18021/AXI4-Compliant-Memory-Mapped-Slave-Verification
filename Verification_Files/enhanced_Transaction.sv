`ifndef TRANSACTION_CLASS_INCLUDED
`define TRANSACTION_CLASS_INCLUDED

import enuming::*;

class Transaction #(parameter int DATA_WIDTH = 32, parameter int ADDR_WIDTH = 16);

    localparam int MEMORY_DEPTH = 1024;  // 1024 words
    localparam int MEMORY_SIZE_BYTES = MEMORY_DEPTH * 4; // 4KB = 4096 bytes
    localparam int MAX_BYTE_ADDR = MEMORY_SIZE_BYTES - 4; // 0x0FFC (last valid word address)

    // Operation type
    rand operation_type_e op_type;
    
    // Common AXI signals
    randc logic [ADDR_WIDTH-1:0] ADDR;
    randc logic [7:0] LEN;
    logic [2:0] SIZE;
    
    // Write-specific signals
    randc logic [DATA_WIDTH-1:0] WDATA[];
    
    // Read-specific signals - for collecting results
    logic [DATA_WIDTH-1:0] RDATA[];
    logic [1:0] RRESP[];
    
    // Response signals
    logic [1:0] BRESP;  // Write response
    
    // Handshake control
    rand int reset_cycles;
    rand int valid_delay;
    rand int ready_delay;
    
    // AXI4 Control Signal Randomization for Write Operations
    rand int awvalid_delay;    // Cycles to delay AWVALID assertion
    rand int wvalid_delay[];   // Cycles to delay each WVALID assertion
    rand bit awvalid_value;    // Randomize AWVALID assertion pattern
    rand bit wvalid_pattern[]; // Randomize WVALID patterns per beat
    rand bit bready_value;     // Randomize BREADY behavior
    
    // AXI4 Control Signal Randomization for Read Operations  
    rand int arvalid_delay;        // Cycles to delay ARVALID assertion
    rand int arvalid_duration;     // Duration to keep ARVALID high
    rand int rready_delay[];       // Delay before each RREADY assertion
    rand bit rready_random_deassert[]; // Random RREADY deassertion pattern
    rand int rready_backpressure_prob; // Probability of applying backpressure
    
    // Test mode controls
    rand test_mode_e test_mode;
    rand data_pattern_e data_pattern;
    rand burst_type_e burst_type;

    // Fixed corner case tracking with proper ranges
    static int corner_case_counter = 0;
    static int total_corner_cases = 12; // Increased to cover more cases
    static bit corner_cases_hit[12] = '{default: 0};
    static bit addr_ranges_hit[3][2] = '{default: 0}; // [range][op_type]  
    static bit data_patterns_hit[4] = '{default: 0};
    static bit boundary_cross_hit[2] = '{default: 0}; // [crosses_boundary]
    
    // Corner case control
    rand int corner_case_selector;
    static bit directed_test_mode = 0;

    // Variables to hold DUT state for coverage sampling
    logic [1:0] write_fsm_state;
    logic [1:0] read_fsm_state; 
    logic [1:0] actual_bresp;
    logic [1:0] actual_rresp;
    
    // Helper variables for coverage (to avoid function calls in coverpoints)
    bit addr_valid;
    bit memory_bounds_ok;
    bit crosses_4kb_boundary;
    int burst_len_int;
    int word_addr; // For coverage sampling

    // BURST COVERAGE
    covergroup burst_coverage_cg;
        
        option.comment = "Burst Coverage";
        
        // Burst lengths - use helper variable
        burst_len_cp: coverpoint burst_len_int {
            bins single = {0};                     // Single transfer
            bins short_burst[] = {[1:3]};          // Short bursts
            bins medium_burst[] = {[4:7]};         // Medium bursts  
            bins long_burst[] = {[8:15]};          // Long bursts
            bins max_burst[] = {[16:255]};         // Maximum AXI4 bursts
        }
    endgroup

    // MEMORY ADDRESS COVERAGE - Fixed to match actual memory space
    covergroup memory_address_cg;
        
        option.comment = "Memory Address Coverage";
        
        // Address coverage within memory bounds (word addresses)
        mem_addr_cp: coverpoint word_addr {
            bins low_addr[] = {[0:341]};                    // Low: 0-341 (0x000-0x555)
            bins mid_addr[] = {[342:681]};                  // Mid: 342-681 (0x556-0xAAA) 
            bins high_addr[] = {[682:1023]};               // High: 682-1023 (0xAAB-0xFFF)
        }
        
        // Boundary crossing coverage
        boundary_cross_cp: coverpoint crosses_4kb_boundary {
            bins no_cross = {0};
        }
    endgroup

    // DATA PATTERN COVERAGE
    covergroup data_patterns_cg;
        
        option.comment = "Data Pattern Coverage";
        
        // Data patterns for write operations
        data_pattern_cp: coverpoint data_pattern {
            bins random_data = {RANDOM_DATA};
            bins all_zeros = {ALL_ZEROS};
            bins all_ones = {ALL_ONES};
            bins alternating_aa = {ALTERNATING_AA};
            bins alternating_55 = {ALTERNATING_55};
        }

    endgroup

    // PROTOCOL COVERAGE
    covergroup protocol_coverage_cg;
        
        option.comment = "AXI4 Protocol Coverage";
        
        // Memory bounds coverage
        memory_bounds_cp: coverpoint memory_bounds_ok {
            bins within_bounds = {1};
        }
    endgroup

    // FIXED: SIZE constraint for 32-bit transfers (should be 2, not 3'b010)
    constraint fixed_size {
        SIZE == 3'b010; // 2^2 = 4 bytes for 32-bit data - this is correct per spec
    }

    // Corner case selector constraint
    constraint corner_case_selector_c {
        if (!directed_test_mode) {
            corner_case_selector inside {[0:11]};
        }
    }

    // Basic operation distribution
    constraint operation_dist_c {
        op_type dist {READ_OP := 50, WRITE_OP := 50};
    }
    
    // Test mode distribution
    constraint test_mode_dist_c {
        test_mode dist {
            RANDOM_MODE := 40,
            BOUNDARY_CROSSING_MODE := 25,
            BURST_LENGTH_MODE := 20,
            DATA_PATTERN_MODE := 15
        };
    }

    // FIXED: Proper memory range constraint for 4KB memory (0x0000-0x0FFF)
    constraint memory_range_c {
        // Valid byte addresses: 0x0000 to 0x0FFC (word-aligned)
        ADDR inside {[16'h0000:16'h0FFC]};
        
        // Ensure word alignment (divisible by 4)
        ADDR[1:0] == 2'b00;
        
        // Ensure burst doesn't exceed memory bounds
        (ADDR + ((LEN + 1) << SIZE)) <= MEMORY_SIZE_BYTES;
    }
    
    // Enhanced address distribution for better coverage
    constraint addr_distribution_c {
        // Distribute addresses across the full 4KB space
        ADDR dist {
            // Low range: 0x000-0x555 (roughly 1/3)
            [16'h0000:16'h0554] := 30,
            // Mid range: 0x558-0xAAC (roughly 1/3) 
            [16'h0558:16'hAAC] := 30,
            // High range: 0xAB0-0xFFC (roughly 1/3)
            [16'hAB0:16'h0FFC] := 30,
            // Boundary cases - addresses near 4KB boundary
            [16'h0FF0:16'h0FFC] := 10
        };
    }

    // LEN constraint for AXI4 compliance
    constraint len_constraint_c {
        // AXI4 supports 0-255 beats
        LEN inside {[0:255]};
        
        // Distribute burst lengths
        LEN dist {
            0 := 20,           // Single transfers
            [1:3] := 30,       // Short bursts
            [4:7] := 25,       // Medium bursts
            [8:15] := 15,      // Long bursts
            [16:31] := 8,      // Very long bursts
            [32:255] := 2      // Maximum bursts
        };
    }

    // Handshake delay constraint
    constraint handshake_delay_c {
        reset_cycles inside {[2:4]};
        valid_delay inside {[0:3]};
        ready_delay inside {[0:3]};
        
        // Control constraints
        awvalid_delay inside {[0:3]};
        awvalid_value dist {1 := 85, 0 := 15};
        bready_value dist {1 := 90, 0 := 10};
        
        // Array sizing
        wvalid_delay.size() == (LEN + 1);
        
        // Read constraints
        arvalid_delay inside {[0:3]};
        arvalid_duration inside {[1:3]};
    }

    // Data pattern constraint
    constraint data_pattern_corner_c {
        data_pattern dist {
            RANDOM_DATA := 60,
            ALL_ZEROS := 15,
            ALL_ONES := 15,
            ALTERNATING_AA := 5,
            ALTERNATING_55 := 5
        };
    }

    function new();
        SIZE = 3'b010; // Fixed to 32-bit transfers (4 bytes)
        
        // Instantiate covergroups
        burst_coverage_cg = new();
        memory_address_cg = new();
        data_patterns_cg = new();
        protocol_coverage_cg = new();
        
        // Initialize helper variables
        burst_len_int = 0;
        word_addr = 0;
        crosses_4kb_boundary = 0;
        memory_bounds_ok = 1;
    endfunction

    function void post_randomize();
        int burst_len;
        int i;
        
        burst_len = LEN + 1;
        
        // Update helper variables for coverage
        burst_len_int = int'(LEN);
        word_addr = int'(ADDR >> 2);
        crosses_4kb_boundary = crosses_4KB_boundary();
        memory_bounds_ok = !exceeds_memory_range();
        
        // Resize control signal arrays based on burst length
        wvalid_delay = new[burst_len];
        wvalid_pattern = new[burst_len];
        rready_delay = new[burst_len];
        rready_random_deassert = new[burst_len];
        
        // Randomize delay elements
        for (i = 0; i < wvalid_delay.size(); i++) begin
            wvalid_delay[i] = $urandom_range(0, 3);
        end
        
        if (awvalid_value == 1) begin
            // Address phase accepted -> ALL data beats must be transferred (WVALID=1)
            for (i = 0; i < wvalid_pattern.size(); i++) begin
                wvalid_pattern[i] = 1'b1;
            end
        end else begin
            // No address phase -> No data beats should be sent (WVALID=0)  
            for (i = 0; i < wvalid_pattern.size(); i++) begin
                wvalid_pattern[i] = 1'b0;
            end
        end
        
        for (i = 0; i < rready_delay.size(); i++) begin
            rready_delay[i] = $urandom_range(0, 3);
        end
        for (i = 0; i < rready_random_deassert.size(); i++) begin
            rready_random_deassert[i] = ($urandom_range(1, 100) <= 85) ? 1 : 0;
        end
        
        // Generate write data with patterns
        if (op_type == WRITE_OP) begin
            WDATA = new[burst_len];
            
            case (data_pattern)
                ALL_ZEROS: begin
                    for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'h00000000;
                    data_patterns_hit[0] = 1;
                end
                ALL_ONES: begin
                    for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'hFFFFFFFF;
                    data_patterns_hit[1] = 1;
                end
                ALTERNATING_AA: begin
                    for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'hAAAAAAAA;
                    data_patterns_hit[2] = 1;
                end
                ALTERNATING_55: begin
                    for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'h55555555;
                    data_patterns_hit[3] = 1;
                end
                default: begin // RANDOM_DATA
                    for (i = 0; i < WDATA.size(); i++) WDATA[i] = $random;
                end
            endcase
        end
        
        // For read operations, allocate result arrays
        if (op_type == READ_OP) begin
            RDATA = new[burst_len];
            RRESP = new[burst_len];
        end

        // Update tracking with FIXED ranges that match coverage bins
        corner_cases_hit[corner_case_selector] = 1;
        
        // Track address range coverage (using word addresses to match coverage)
        if (word_addr inside {[0:341]}) begin
            addr_ranges_hit[0][op_type] = 1; // Low range
        end else if (word_addr inside {[342:681]}) begin
            addr_ranges_hit[1][op_type] = 1; // Mid range  
        end else if (word_addr inside {[682:1023]}) begin
            addr_ranges_hit[2][op_type] = 1; // High range
        end
        
        // Track boundary crossing
        if (crosses_4KB_boundary()) begin
            boundary_cross_hit[1] = 1;
        end else begin
            boundary_cross_hit[0] = 1;
        end
        
        // Increment counter
        corner_case_counter++;
        
        // Display progress every 100 transactions
        if (corner_case_counter % 100 == 0) begin
            display_corner_coverage();
        end

        // Sample all coverage
        sample_all_coverage();
    endfunction

    // Enhanced coverage reporting
    function void display_corner_coverage();
        int data_hit_count;
        int range_hits;
        int total_corner_hits;
        int boundary_hits;
        int i, j;
        
        data_hit_count = 0;
        range_hits = 0;
        total_corner_hits = 0;
        boundary_hits = 0;
        
        // Count data pattern corner cases
        for (i = 0; i < 4; i++) begin
            if (data_patterns_hit[i]) data_hit_count++;
        end
        
        // Count range coverage
        for (i = 0; i < 3; i++) begin
            for (j = 0; j < 2; j++) begin
                if (addr_ranges_hit[i][j]) range_hits++;
            end
        end
        
        // Count boundary coverage
        for (i = 0; i < 2; i++) begin
            if (boundary_cross_hit[i]) boundary_hits++;
        end
        
        // Count total corner cases hit
        for (i = 0; i < total_corner_cases; i++) begin
            if (corner_cases_hit[i]) total_corner_hits++;
        end
        
        $display("=== COVERAGE REPORT (Transaction %0d) ===", corner_case_counter);
        $display("Data Patterns: %0d/4 (%0.1f%%)", data_hit_count, (data_hit_count * 100.0) / 4);
        $display("Address Ranges: %0d/6 (%0.1f%%)", range_hits, (range_hits * 100.0) / 6);
        $display("Boundary Cases: %0d/2 (%0.1f%%)", boundary_hits, (boundary_hits * 100.0) / 2);
        $display("Corner Cases: %0d/%0d (%0.1f%%)", total_corner_hits, total_corner_cases, (total_corner_hits * 100.0) / total_corner_cases);
        $display("===========================================");
    endfunction

    // Enhanced corner case check
    function bit all_corners_covered();
        int data_hit_count;
        int range_hits;
        int boundary_hits;
        int i, j;
        
        data_hit_count = 0;
        range_hits = 0;
        boundary_hits = 0;
        
        for (i = 0; i < 4; i++) if (data_patterns_hit[i]) data_hit_count++;
        for (i = 0; i < 3; i++) for (j = 0; j < 2; j++) if (addr_ranges_hit[i][j]) range_hits++;
        for (i = 0; i < 2; i++) if (boundary_cross_hit[i]) boundary_hits++;
        
        return (data_hit_count >= 3) && (range_hits >= 5) && (boundary_hits >= 1);
    endfunction

    // Utility functions - FIXED for proper 4KB boundary checking
    function int total_bytes();
        return (LEN + 1) << SIZE;
    endfunction

    function bit crosses_4KB_boundary();
        logic [15:0] start_4kb_block;
        logic [15:0] end_4kb_block;
        
        start_4kb_block = ADDR[15:12];
        end_4kb_block = (ADDR + total_bytes() - 1) >> 12;
        
        return (start_4kb_block != end_4kb_block);
    endfunction

    function bit exceeds_memory_range();
        return (ADDR >= MEMORY_SIZE_BYTES) || ((ADDR + total_bytes()) > MEMORY_SIZE_BYTES);
    endfunction

    // display function
    function void display();
        $display("=== %s TRANSACTION ===", op_type.name());
        $display("ADDR = 0x%0h (word_addr = %0d) | LEN = %0d | SIZE = %0d | Beats = %0d",
                 ADDR, word_addr, LEN, SIZE, LEN+1);
        $display("  Total Bytes: %0d", total_bytes());
        $display("  4KB boundary cross: %s", crosses_4KB_boundary() ? "YES" : "NO");
        $display("  Memory bounds OK: %s", !exceeds_memory_range() ? "YES" : "NO");
        
        if (op_type == WRITE_OP) begin
            $display("  Data pattern: %s", data_pattern.name());
            $display("  Control: AWVALID=%b, BREADY=%b", awvalid_value, bready_value);
        end else begin
            $display("  Control: ARVALID_delay=%0d, RREADY_backpressure=%0d%%", 
                     arvalid_delay, rready_backpressure_prob);
        end
        $display("========================");
    endfunction

    // Comprehensive coverage function
    function real get_overall_coverage();
        real burst_cov, memory_cov, data_cov, protocol_cov;
        real total_cov;
        
        burst_cov = burst_coverage_cg.get_coverage();
        memory_cov = memory_address_cg.get_coverage();
        data_cov = data_patterns_cg.get_coverage();
        protocol_cov = protocol_coverage_cg.get_coverage();

        total_cov = (burst_cov + memory_cov + data_cov + protocol_cov) / 4.0;
        
        return total_cov;
    endfunction

    // Function to sample all covergroups
    function void sample_all_coverage();
        burst_coverage_cg.sample();
        memory_address_cg.sample();
        protocol_coverage_cg.sample();
        
        // Only sample data patterns for write operations
        if (op_type == WRITE_OP) begin
            data_patterns_cg.sample();
        end
    endfunction

    // Enhanced coverage report
    function void display_coverage_report();
        $display("=== COMPREHENSIVE COVERAGE REPORT ===");
        $display("Burst Coverage:           %0.1f%%", burst_coverage_cg.get_coverage());
        $display("Memory Address Coverage:  %0.1f%%", memory_address_cg.get_coverage());
        $display("Data Patterns Coverage:   %0.1f%%", data_patterns_cg.get_coverage());
        $display("Protocol Coverage:        %0.1f%%", protocol_coverage_cg.get_coverage());
        $display("-------------------------------------");
        $display("Overall Coverage:         %0.1f%%", get_overall_coverage());
        $display("=====================================");
        
        // Detailed bin information
        $display("\n=== DETAILED COVERAGE BINS ===");
        $display("Address Ranges Hit:");
        $display("  Low (0-341): R=%s, W=%s", addr_ranges_hit[0][0] ? "✓" : "✗", addr_ranges_hit[0][1] ? "✓" : "✗");
        $display("  Mid (342-681): R=%s, W=%s", addr_ranges_hit[1][0] ? "✓" : "✗", addr_ranges_hit[1][1] ? "✓" : "✗");
        $display("  High (682-1023): R=%s, W=%s", addr_ranges_hit[2][0] ? "✓" : "✗", addr_ranges_hit[2][1] ? "✓" : "✗");
        $display("Boundary Cases: No_Cross=%s, Cross=%s", boundary_cross_hit[0] ? "✓" : "✗", boundary_cross_hit[1] ? "✓" : "✗");
        $display("===============================");
    endfunction

endclass

`endif // TRANSACTION_CLASS_INCLUDED