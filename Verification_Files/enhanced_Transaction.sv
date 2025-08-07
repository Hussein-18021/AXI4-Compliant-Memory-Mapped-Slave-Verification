import enuming::*;
class Transaction #(parameter int DATA_WIDTH = 32, parameter int ADDR_WIDTH = 16);

    localparam int MEMORY_DEPTH = 1024;

    // Operation type
    rand operation_type_e op_type;
    
    // Common AXI signals
    rand logic [ADDR_WIDTH-1:0] ADDR;
    rand logic [7:0] LEN;
    logic [2:0] SIZE;
    
    // Write-specific signals
    rand logic [DATA_WIDTH-1:0] WDATA[];
    
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

    // Simplified corner case tracking
    static int corner_case_counter = 0;
    static int total_corner_cases = 8; // Reduced to essential cases
    static bit corner_cases_hit[8] = '{default: 0};
    static bit addr_ranges_hit[3][2] = '{default: 0}; // [range][op_type]  
    static bit data_patterns_hit[4] = '{default: 0}; // Only essential patterns
    
    // Simplified corner case control
    rand int corner_case_selector;
    static bit directed_test_mode = 0;

    // Variables to hold DUT state for coverage sampling
    logic [1:0] write_fsm_state;
    logic [1:0] read_fsm_state; 
    logic [1:0] actual_bresp;
    logic [1:0] actual_rresp;
    
    // Helper variables for coverage (to avoid function calls in coverpoints)
    bit boundary_crossing;
    bit addr_valid;
    bit memory_bounds_ok;
    int burst_len_int;

    // ========================================
    // COMPREHENSIVE COVERAGE GROUPS FOR 100% COVERAGE
    // ========================================
    
    // 1. FSM STATE COVERAGE - requires DUT interface access
    covergroup fsm_states_cg;
        option.per_instance = 1;
        option.comment = "FSM State Coverage";
        
        // Write FSM states (will be sampled from DUT via interface)
        write_state_cp: coverpoint write_fsm_state {
            bins w_idle = {0}; // W_IDLE
            bins w_addr = {1}; // W_ADDR  
            bins w_data = {2}; // W_DATA
            bins w_resp = {3}; // W_RESP
        }
        
        // Read FSM states (will be sampled from DUT via interface)
        read_state_cp: coverpoint read_fsm_state {
            bins r_idle = {0}; // R_IDLE
            bins r_addr = {1}; // R_ADDR
            bins r_data = {2}; // R_DATA
        }
        
        // FSM state transitions
        write_transitions: coverpoint write_fsm_state {
            bins idle_to_addr = (0 => 1);
            bins addr_to_data = (1 => 2);
            bins data_to_data = (2 => 2);  // Burst continuation
            bins data_to_resp = (2 => 3);
            bins resp_to_idle = (3 => 0);
            bins resp_to_addr = (3 => 1);  // Back-to-back
        }
        
        read_transitions: coverpoint read_fsm_state {
            bins idle_to_addr = (0 => 1);
            bins addr_to_data = (1 => 2);
            bins data_to_data = (2 => 2);  // Burst continuation
            bins data_to_idle = (2 => 0);
        }
    endgroup

    // 2. BOUNDARY CONDITIONS COVERAGE
    covergroup boundary_conditions_cg;
        option.per_instance = 1;
        option.comment = "Boundary Conditions Coverage";
        
        // Boundary crossing scenarios
        boundary_cross_cp: coverpoint boundary_crossing {
            bins no_cross = {1'b0};
            bins boundary_cross = {1'b1};
        }
        
        // Address validity scenarios  
        addr_validity_cp: coverpoint addr_valid {
            bins valid = {1'b1};
            bins invalid = {1'b0};
        }
        
        // Cross coverage for boundary + validity combinations
        boundary_validity_cross: cross boundary_cross_cp, addr_validity_cp {
            bins valid_no_cross = binsof(boundary_cross_cp.no_cross) && binsof(addr_validity_cp.valid);
            bins valid_with_cross = binsof(boundary_cross_cp.boundary_cross) && binsof(addr_validity_cp.valid);
            bins invalid_no_cross = binsof(boundary_cross_cp.no_cross) && binsof(addr_validity_cp.invalid);
            bins invalid_with_cross = binsof(boundary_cross_cp.boundary_cross) && binsof(addr_validity_cp.invalid);
        }
        
        // Operation type with boundary crossing
        op_boundary_cross: cross op_type, boundary_cross_cp;
    endgroup

    // 3. BURST COVERAGE
    covergroup burst_coverage_cg;
        option.per_instance = 1;
        option.comment = "Burst Coverage";
        
        // Burst lengths - use helper variable
        burst_len_cp: coverpoint burst_len_int {
            bins single = {0};                     // Single transfer
            bins short_burst[] = {[1:3]};          // Short bursts
            bins medium_burst[] = {[4:7]};         // Medium bursts  
            bins long_burst[] = {[8:15]};          // Long bursts
        }
        
        // Burst size coverage
        burst_size_cp: coverpoint SIZE {
            bins byte_size = {3'b000};         // 1 byte
            bins half_word = {3'b001};         // 2 bytes
            bins word_size = {3'b010};         // 4 bytes
            bins double_word = {3'b011};       // 8 bytes
        }
        
        // Cross burst length with operation type
        burst_op_cross: cross burst_len_cp, op_type;
        
        // Cross burst size with length
        burst_size_len_cross: cross burst_size_cp, burst_len_cp;
    endgroup

    // 4. RESPONSE COVERAGE 
    covergroup response_coverage_cg;
        option.per_instance = 1;
        option.comment = "Response Coverage";
        
        // Write response types (sampled from actual response)
        write_resp_cp: coverpoint actual_bresp {
            bins okay = {2'b00};               // OKAY response
            bins slverr = {2'b10};             // SLVERR response
        }
        
        // Read response types (sampled from actual response) 
        read_resp_cp: coverpoint actual_rresp {
            bins okay = {2'b00};
            bins slverr = {2'b10};
        }
        
        // Address validity for response coverage
        resp_addr_validity_cp: coverpoint addr_valid {
            bins valid = {1'b1};
            bins invalid = {1'b0};
        }
        
        // Cross write response with address validity
        write_resp_validity_cross: cross write_resp_cp, resp_addr_validity_cp {
            bins okay_valid = binsof(write_resp_cp.okay) && binsof(resp_addr_validity_cp.valid);
            bins slverr_invalid = binsof(write_resp_cp.slverr) && binsof(resp_addr_validity_cp.invalid);
        }
        
        // Cross response with operation type
        resp_op_cross: cross actual_bresp, op_type {
            ignore_bins read_bresp = binsof(op_type) intersect {READ_OP};
        }
    endgroup

    // 5. MEMORY ADDRESS COVERAGE
    covergroup memory_address_cg;
        option.per_instance = 1;
        option.comment = "Memory Address Coverage";
        
        // Address coverage within memory bounds
        mem_addr_cp: coverpoint (ADDR >> 2) {
            bins low_addr[] = {[0:255]};                    // Low address range
            bins mid_addr[] = {[256:MEMORY_DEPTH/2-1]};     // Middle range
            bins high_addr[] = {[MEMORY_DEPTH/2:MEMORY_DEPTH-1]}; // High range
            bins max_addr = {MEMORY_DEPTH-1};               // Maximum valid address
        }
        
        // Address alignment coverage
        addr_align_cp: coverpoint ADDR[1:0] {
            bins aligned = {2'b00};            // Word aligned
            bins misaligned[] = {[2'b01:2'b11]}; // Misaligned addresses
        }
        
        // Cross address with operation type
        addr_op_cross: cross mem_addr_cp, op_type;
        
        // Cross alignment with burst length
        align_burst_cross: cross addr_align_cp, burst_len_int;
    endgroup

    // 6. HANDSHAKING COVERAGE
    covergroup handshaking_cg;
        option.per_instance = 1;
        option.comment = "Handshaking Coverage";
        
        // Write handshaking patterns
        awvalid_pattern_cp: coverpoint awvalid_value {
            bins asserted = {1'b1};
            bins not_asserted = {1'b0};
        }
        
        bready_pattern_cp: coverpoint bready_value {
            bins ready = {1'b1};
            bins not_ready = {1'b0};
        }
        
        // Delay patterns
        awvalid_delay_cp: coverpoint awvalid_delay {
            bins no_delay = {0};
            bins short_delay = {[1:2]};
            bins medium_delay = {[3:5]};
        }
        
        // Cross handshaking with operation type
        handshake_op_cross: cross awvalid_pattern_cp, bready_pattern_cp, op_type {
            ignore_bins read_handshake = binsof(op_type) intersect {READ_OP};
        }
        
        // Read handshaking
        arvalid_delay_cp: coverpoint arvalid_delay {
            bins no_delay = {0};
            bins short_delay = {[1:2]};
            bins medium_delay = {[3:5]};
        }
        
        rready_backpressure_cp: coverpoint rready_backpressure_prob {
            bins low_backpressure = {[0:20]};
            bins medium_backpressure = {[21:50]};
            bins high_backpressure = {[51:100]};
        }
    endgroup

    // 7. ERROR CONDITION COVERAGE
    covergroup error_conditions_cg;
        option.per_instance = 1;
        option.comment = "Error Conditions Coverage";
        
        // Address bounds scenarios
        addr_bounds_cp: coverpoint memory_bounds_ok {
            bins within_bounds = {1'b1};
        }
        
        // Boundary crossing with different burst lengths
        boundary_burst_cross: cross boundary_crossing, burst_len_int {
            bins boundary_single = binsof(boundary_crossing) intersect {1'b1} && binsof(burst_len_int) intersect {0};
            bins boundary_short = binsof(boundary_crossing) intersect {1'b1} && binsof(burst_len_int) intersect {[1:7]};
            bins boundary_long = binsof(boundary_crossing) intersect {1'b1} && binsof(burst_len_int) intersect {[8:15]};
        }
        
        // Error response scenarios
        error_resp_scenarios: cross memory_bounds_ok, op_type;
    endgroup

    // 8. DATA PATTERN COVERAGE
    covergroup data_patterns_cg;
        option.per_instance = 1;
        option.comment = "Data Pattern Coverage";
        
        // Data patterns for write operations
        data_pattern_cp: coverpoint data_pattern {
            bins random_data = {RANDOM_DATA};
            bins all_zeros = {ALL_ZEROS};
            bins all_ones = {ALL_ONES};
            bins alternating_aa = {ALTERNATING_AA};
            bins alternating_55 = {ALTERNATING_55};
        }
        
        // Cross data patterns with burst length
        data_burst_cross: cross data_pattern_cp, burst_len_int {
            ignore_bins long_pattern = binsof(burst_len_int) intersect {[8:15]} && 
                                     binsof(data_pattern_cp) intersect {ALL_ZEROS, ALL_ONES};
        }
        
        // Cross data patterns with operation (only for writes)
        data_op_cross: cross data_pattern_cp, op_type {
            ignore_bins read_data = binsof(op_type) intersect {READ_OP};
        }
    endgroup

    // 9. TEST MODE COVERAGE
    covergroup test_mode_cg;
        option.per_instance = 1;
        option.comment = "Test Mode Coverage";
        
        test_mode_cp: coverpoint test_mode;
        
        // Cross test mode with operation type
        mode_op_cross: cross test_mode_cp, op_type;
        
        // Cross test mode with boundary conditions
        mode_boundary_cross: cross test_mode_cp, boundary_crossing;
    endgroup

    // Simplified corner case selector constraint
    constraint corner_case_selector_c {
        if (!directed_test_mode) {
            corner_case_selector inside {[0:7]};
        }
    }

    // Basic operation distribution
    constraint operation_dist_c {
        op_type dist {READ_OP := 40, WRITE_OP := 60};
    }
    
    // Simplified test mode distribution
    constraint test_mode_dist_c {
        test_mode dist {
            RANDOM_MODE := 50,
            BOUNDARY_CROSSING_MODE := 20,
            BURST_LENGTH_MODE := 20,
            DATA_PATTERN_MODE := 10
        };
    }

    // Simplified burst length constraint
    constraint burst_length_c {
        if (burst_type == SINGLE_BEAT) {
            LEN == 0;
        } else if (burst_type == SHORT_BURST) {
            LEN inside {[1:7]};
        } else {
            LEN inside {[8:15]};
        }
    }

    // Simplified boundary targeting
    constraint boundary_targeting_c {
        if (!directed_test_mode && test_mode == BOUNDARY_CROSSING_MODE) {
            ((ADDR & 12'hFFF) + ((LEN + 1) << SIZE)) > 12'hFFF;  // Force boundary crossing
        }
    }

    // Simplified memory range constraint
    constraint memory_range_c {
        (ADDR >> 2) < MEMORY_DEPTH;
        ((ADDR >> 2) + LEN) < MEMORY_DEPTH;
    }
    
    // Address alignment constraint
    constraint addr_alignment_c {
        ADDR % (1 << SIZE) == 0;
    }

    // Simplified handshake delay constraint
    constraint handshake_delay_c {
        reset_cycles inside {[2:4]};
        valid_delay inside {[0:2]};
        ready_delay inside {[0:2]};
        
        // Basic control constraints
        awvalid_delay inside {[0:2]};
        awvalid_value dist {1 := 90, 0 := 10};
        bready_value dist {1 := 95, 0 := 5};
        
        // Array sizing
        wvalid_delay.size() == (LEN + 1);
        
        // Basic read constraints
        arvalid_delay inside {[0:2]};
        arvalid_duration inside {[1:2]};
    }

    // Simplified data pattern constraint
    constraint data_pattern_corner_c {
        data_pattern dist {
            RANDOM_DATA := 70,
            ALL_ZEROS := 10,
            ALL_ONES := 10,
            ALTERNATING_AA := 5,
            ALTERNATING_55 := 5
        };
    }

    function new();
        SIZE = 3'b010; // Fixed to 32-bit transfers
        
        // Instantiate comprehensive covergroups
        fsm_states_cg = new();
        boundary_conditions_cg = new();
        burst_coverage_cg = new();
        response_coverage_cg = new();
        memory_address_cg = new();
        handshaking_cg = new();
        error_conditions_cg = new();
        data_patterns_cg = new();
        test_mode_cg = new();
        
        // Initialize DUT state variables
        write_fsm_state = 0;
        read_fsm_state = 0;
        actual_bresp = 2'b00;
        actual_rresp = 2'b00;
        
        // Initialize helper variables
        boundary_crossing = 0;
        addr_valid = 1;
        memory_bounds_ok = 1;
        burst_len_int = 0;
    endfunction

    function void post_randomize();
        int burst_len;
        int i;
        
        burst_len = LEN + 1;
        
        // Update helper variables for coverage
        boundary_crossing = crosses_4KB_boundary();
        addr_valid = !exceeds_memory_range();
        memory_bounds_ok = !exceeds_memory_range();
        burst_len_int = int'(LEN);
        
        // Resize control signal arrays based on burst length
        wvalid_delay = new[burst_len];
        wvalid_pattern = new[burst_len];
        rready_delay = new[burst_len];
        rready_random_deassert = new[burst_len];
        
        // Randomize delay elements
        for (i = 0; i < wvalid_delay.size(); i++) begin
            wvalid_delay[i] = $urandom_range(0, 2);
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
            rready_delay[i] = $urandom_range(0, 2);
        end
        for (i = 0; i < rready_random_deassert.size(); i++) begin
            rready_random_deassert[i] = ($urandom_range(1, 100) <= 85) ? 1 : 0;
        end
        
        // Simplified data generation
        if (op_type == WRITE_OP) begin
            WDATA = new[burst_len];
            
            // Use data pattern directly without complex corner case logic
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

        // Update tracking
        corner_cases_hit[corner_case_selector] = 1;
        
        // Track address range coverage within valid memory limits
        if (ADDR inside {[0:16'h05FF]}) begin
            addr_ranges_hit[0][op_type] = 1; // Low range
        end else if (ADDR inside {[16'h600:16'hBFF]}) begin
            addr_ranges_hit[1][op_type] = 1; // Mid range  
        end else if (ADDR inside {[16'hC00:16'hFFF]}) begin
            addr_ranges_hit[2][op_type] = 1; // High range
        end
        
        // Increment counter for next transaction
        corner_case_counter++;
        
        // Display progress less frequently
        if (corner_case_counter % (total_corner_cases * 2) == 0) begin
            display_corner_coverage();
        end

        // Sample comprehensive coverage with updated helper variables
        sample_all_coverage();
    endfunction

    // Simplified coverage reporting
    function void display_corner_coverage();
        int data_hit_count;
        int range_hits;
        int total_corner_hits;
        int i, j;
        
        data_hit_count = 0;
        range_hits = 0;
        total_corner_hits = 0;
        
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
        
        // Count total corner cases hit
        for (i = 0; i < total_corner_cases; i++) begin
            if (corner_cases_hit[i]) total_corner_hits++;
        end
        
        $display("=== COVERAGE REPORT ===");
        $display("Data Patterns: %0d/4 (%0.1f%%)", data_hit_count, (data_hit_count * 100.0) / 4);
        $display("Address Ranges: %0d/6 (%0.1f%%)", range_hits, (range_hits * 100.0) / 6);
        $display("Corner Cases: %0d/%0d (%0.1f%%)", total_corner_hits, total_corner_cases, (total_corner_hits * 100.0) / total_corner_cases);
        $display("=======================");
    endfunction

    // Simplified corner case check
    function bit all_corners_covered();
        int data_hit_count;
        int range_hits;
        int i, j;
        
        data_hit_count = 0;
        range_hits = 0;
        
        for (i = 0; i < 4; i++) if (data_patterns_hit[i]) data_hit_count++;
        for (i = 0; i < 3; i++) for (j = 0; j < 2; j++) if (addr_ranges_hit[i][j]) range_hits++;
        
        return (data_hit_count >= 3) && (range_hits >= 4);
    endfunction

    // Utility functions (unchanged)
    function int total_bytes();
        return (LEN + 1) << SIZE;
    endfunction

    function bit crosses_4KB_boundary();
        return ((ADDR & 12'hFFF) + total_bytes()) > 12'hFFF;
    endfunction

    function bit exceeds_memory_range();
        return ((ADDR >> 2) + (LEN + 1)) > MEMORY_DEPTH;
    endfunction

    // Simplified display function
    function void display();
        $display("=== %s TRANSACTION ===", op_type.name());
        $display("ADDR = 0x%0h | LEN = %0d | SIZE = %0d | Beats = %0d",
                 ADDR, LEN, SIZE, LEN+1);
        $display("  Total Bytes: %0d", total_bytes());
        $display("  4KB boundary cross: %s", crosses_4KB_boundary() ? "YES" : "NO");
        
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
        real fsm_cov, boundary_cov, burst_cov, response_cov, memory_cov, handshake_cov, error_cov, data_cov, mode_cov;
        real total_cov;
        
        fsm_cov = fsm_states_cg.get_coverage();
        boundary_cov = boundary_conditions_cg.get_coverage();
        burst_cov = burst_coverage_cg.get_coverage();
        response_cov = response_coverage_cg.get_coverage();
        memory_cov = memory_address_cg.get_coverage();
        handshake_cov = handshaking_cg.get_coverage();
        error_cov = error_conditions_cg.get_coverage();
        data_cov = data_patterns_cg.get_coverage();
        mode_cov = test_mode_cg.get_coverage();
        
        total_cov = (fsm_cov + boundary_cov + burst_cov + response_cov + memory_cov + 
                    handshake_cov + error_cov + data_cov + mode_cov) / 9.0;
        
        return total_cov;
    endfunction

    // Function to sample all covergroups (for testbench use)
    function void sample_all_coverage();
        fsm_states_cg.sample();
        boundary_conditions_cg.sample(); 
        burst_coverage_cg.sample();
        response_coverage_cg.sample();
        memory_address_cg.sample();
        handshaking_cg.sample();
        error_conditions_cg.sample();
        data_patterns_cg.sample();
        test_mode_cg.sample();
    endfunction

    // Function to update DUT state for FSM coverage
    function void update_dut_state(logic [1:0] wr_state, logic [1:0] rd_state, 
                                 logic [1:0] bresp, logic [1:0] rresp);
        write_fsm_state = wr_state;
        read_fsm_state = rd_state;
        actual_bresp = bresp;
        actual_rresp = rresp;
    endfunction

    // Function to get detailed coverage report
    function void display_coverage_report();
        $display("=== COMPREHENSIVE COVERAGE REPORT ===");
        $display("FSM States Coverage:      %0.1f%%", fsm_states_cg.get_coverage());
        $display("Boundary Conditions:      %0.1f%%", boundary_conditions_cg.get_coverage());
        $display("Burst Coverage:           %0.1f%%", burst_coverage_cg.get_coverage());
        $display("Response Coverage:        %0.1f%%", response_coverage_cg.get_coverage());
        $display("Memory Address Coverage:  %0.1f%%", memory_address_cg.get_coverage());
        $display("Handshaking Coverage:     %0.1f%%", handshaking_cg.get_coverage());
        $display("Error Conditions:         %0.1f%%", error_conditions_cg.get_coverage());
        $display("Data Patterns:            %0.1f%%", data_patterns_cg.get_coverage());
        $display("Test Mode Coverage:       %0.1f%%", test_mode_cg.get_coverage());
        $display("-------------------------------------");
        $display("Overall Coverage:         %0.1f%%", get_overall_coverage());
        $display("=====================================");
    endfunction

endclass
