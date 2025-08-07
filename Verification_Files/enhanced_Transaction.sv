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

    // Corner case tracking - static variables for global coverage
    static int corner_case_counter = 0;
    static int total_corner_cases = 24; // Expanded to cover all scenarios
    static bit corner_cases_hit[24] = '{default: 0};
    static bit addr_ranges_hit[3][2] = '{default: 0}; // [range][op_type]  
    static bit addr_boundary_crosses[operation_type_e] = '{default: 0};
    static bit data_patterns_hit[8] = '{default: 0}; // Track specific data patterns
    
    // Corner case control variable
    rand int corner_case_selector;

    // Coverage groups (unchanged)
    covergroup operation_coverage;
        op_type_cp: coverpoint op_type {
            bins read_ops = {READ_OP};
            bins write_ops = {WRITE_OP};
        }
        
        addr_cp: coverpoint ADDR {
            bins low_range  = {[0:16'h0FFF]};
            bins mid_range  = {[16'h1000:16'h2FFF]};
            bins high_range = {[16'h3000:16'hFFFF]};
        }
        
        len_cp: coverpoint LEN {
            bins single   = {0};
            bins short    = {[1:7]};
            bins mid      = {[8:31]};
            bins long     = {[32:255]};
        }
        
        test_mode_cp: coverpoint test_mode;
        
        // Coverage for handshake behaviors - matching Wstim.sv pattern
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
        
        // Cross coverage for transaction scenarios - matching Wstim.sv pattern
        transaction_scenario: cross awvalid_cp, bready_cp {
            bins normal_transaction    = binsof(awvalid_cp.asserted) && binsof(bready_cp.ready);
            bins no_response_capture   = binsof(awvalid_cp.asserted) && binsof(bready_cp.not_ready);
            bins aborted_transaction   = binsof(awvalid_cp.not_asserted);
        }
        
        cross op_type_cp, addr_cp;
        cross op_type_cp, len_cp;
    endgroup

    covergroup boundary_coverage;
        crosses_4kb_cp: coverpoint crosses_4KB_boundary() {
            bins no_cross = {0};
            bins crosses = {1};
        }
        
        exceeds_memory_cp: coverpoint exceeds_memory_range() {
            bins within_range = {0};
            bins exceeds = {1};
        }
        
        cross crosses_4kb_cp, op_type;
    endgroup

    // Enhanced corner case selector constraint
    constraint corner_case_selector_c {
        corner_case_selector == corner_case_counter % total_corner_cases;
    }

    // Operation distribution with corner case consideration
    constraint operation_dist_c {
        if (corner_case_selector inside {[8:15], [16:21]}) {
            // For address and boundary coverage, maintain specific op_type requirements
            op_type dist {READ_OP := 50, WRITE_OP := 50};
        } else {
            // Normal distribution for other cases
            op_type dist {READ_OP := 30, WRITE_OP := 70};
        }
    }
    
    // Enhanced test mode distribution with corner cases
    constraint test_mode_dist_c {
        if (corner_case_selector inside {[14:15], [20:21]}) {
            // Force boundary crossing mode for boundary coverage
            test_mode == BOUNDARY_CROSSING_MODE;
        } else if (corner_case_selector inside {[0:7]}) {
            // Force data pattern mode for data corner cases
            test_mode == DATA_PATTERN_MODE;
        } else {
            test_mode dist {
                RANDOM_MODE := 40,
                BOUNDARY_CROSSING_MODE := 20,
                BURST_LENGTH_MODE := 20,
                DATA_PATTERN_MODE := 20
            };
        }
    }

    // Enhanced burst length constraint
    constraint burst_length_c {
        if (burst_type == SINGLE_BEAT) {
            LEN == 0;
        } else if (burst_type == SHORT_BURST) {
            LEN inside {[1:7]};
        } else if (burst_type == MEDIUM_BURST) {
            LEN inside {[8:15]};  // Limited for debug
        } else if (burst_type == LONG_BURST) {
            LEN inside {[16:31]}; // Limited for debug
        } else {
            LEN inside {[32:63]}; // Limited for debug
        }
    }

    // Enhanced boundary targeting with corner case support
    constraint boundary_targeting_c {
        solve LEN before ADDR;
        solve corner_case_selector before ADDR;
        
        if (corner_case_selector inside {[14:15], [20:21]}) {
            // Force boundary crossing for specific corner cases
            ((ADDR & 12'hFFF) + ((LEN + 1) << SIZE)) > 12'hFFF;
        } else if (test_mode == BOUNDARY_CROSSING_MODE) {
            ((ADDR & 12'hFFF) + ((LEN + 1) << SIZE)) > 12'hFFF;  // Force boundary crossing
        } else {
            ((ADDR & 12'hFFF) + ((LEN + 1) << SIZE)) <= 12'hFFF; // Stay within boundary
        }
    }

    // Enhanced memory range constraint with address coverage
    constraint memory_range_c {
        solve corner_case_selector before ADDR;
        
        if (corner_case_selector == 8 || corner_case_selector == 9) {
            // Low range coverage
            ADDR inside {[0:16'h0FFF]};
        } else if (corner_case_selector == 10 || corner_case_selector == 11) {
            // Mid range coverage  
            ADDR inside {[16'h1000:16'h2FFF]};
        } else if (corner_case_selector == 12 || corner_case_selector == 13) {
            // High range coverage (with memory bounds)
            ADDR inside {[16'h3000:16'hFFFF]};
            ((ADDR >> 2) + LEN) < MEMORY_DEPTH;
        } else {
            // Normal memory constraints
            (ADDR >> 2) < MEMORY_DEPTH;
            ((ADDR >> 2) + LEN) < MEMORY_DEPTH;
        }
    }
    
    // Address alignment constraint (unchanged)
    constraint addr_alignment_c {
        ADDR % (1 << SIZE) == 0;
    }

    // Enhanced handshake delay constraint
    constraint handshake_delay_c {
        reset_cycles inside {[2:5]};
        valid_delay inside {[0:3]};
        ready_delay inside {[0:3]};
        
        // Write operation control constraints - matching Wstim.sv pattern
        awvalid_delay inside {[0:3]};    // 0-3 cycle delay for AWVALID
        awvalid_value dist {1 := 90, 0 := 10}; // Usually proceed with transaction
        bready_value dist {1 := 95, 0 := 5};   // Usually ready for response
        
        // Per-beat WVALID control arrays - sized to burst length
        wvalid_delay.size() == (LEN + 1);
        foreach (wvalid_delay[i]) {
            wvalid_delay[i] inside {[0:2]}; // 0-2 cycle delay per WVALID
        }
             
        // Read operation control constraints
        arvalid_delay inside {[0:4]};
        arvalid_duration inside {[1:3]};
        rready_backpressure_prob inside {[10:40]}; // 10-40% chance of backpressure
    }

    // Enhanced data pattern constraint for corner cases
    constraint data_pattern_corner_c {
        solve corner_case_selector before data_pattern;
        
        if (corner_case_selector == 0) {
            data_pattern == ALL_ZEROS;
        } else if (corner_case_selector == 1) {
            data_pattern == ALL_ONES;
        } else if (corner_case_selector == 2) {
            data_pattern == ALTERNATING_AA;
        } else if (corner_case_selector == 3) {
            data_pattern == ALTERNATING_55;  
        } else if (corner_case_selector inside {[4:7]}) {
            data_pattern == RANDOM_DATA; // Will be overridden in post_randomize for specific patterns
        } else {
            data_pattern dist {
                RANDOM_DATA := 60,
                ALL_ZEROS := 10,
                ALL_ONES := 10,
                ALTERNATING_AA := 10,
                ALTERNATING_55 := 10
            };
        }
    }

    // Enhanced operation type constraint for address coverage
    constraint op_type_coverage_c {
        solve corner_case_selector before op_type;
        
        if (corner_case_selector == 8 || corner_case_selector == 10 || corner_case_selector == 12 || corner_case_selector == 14) {
            op_type == READ_OP;
        } else if (corner_case_selector == 9 || corner_case_selector == 11 || corner_case_selector == 13 || corner_case_selector == 15) {
            op_type == WRITE_OP;
        }
        // Other cases use normal distribution
    }

    function new();
        SIZE = 3'b010; // Fixed to 32-bit transfers
        operation_coverage = new();
        boundary_coverage = new();
    endfunction

    function void post_randomize();
        int burst_len;
        int i;
        
        burst_len = LEN + 1;
        
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
        
        // Enhanced data generation with corner cases
        if (op_type == WRITE_OP) begin
            WDATA = new[burst_len];
            
            // Handle specific corner cases
            if (corner_case_selector == 0) begin
                // All zeros
                for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'h00000000;
                data_patterns_hit[0] = 1;
            end else if (corner_case_selector == 1) begin
                // All ones
                for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'hFFFFFFFF;
                data_patterns_hit[1] = 1;
            end else if (corner_case_selector == 2) begin
                // Alternating 1-0 (0xAAAAAAAA)
                for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'hAAAAAAAA;
                data_patterns_hit[2] = 1;
            end else if (corner_case_selector == 3) begin
                // Alternating 0-1 (0x55555555)
                for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'h55555555;
                data_patterns_hit[3] = 1;
            end else if (corner_case_selector == 4) begin
                // Single bit high (MSB)
                for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'h80000000;
                data_patterns_hit[4] = 1;
            end else if (corner_case_selector == 5) begin
                // Single bit high (LSB)
                for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'h00000001;
                data_patterns_hit[5] = 1;
            end else if (corner_case_selector == 6) begin
                // Checkerboard pattern 1
                for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'hCCCCCCCC;
                data_patterns_hit[6] = 1;
            end else if (corner_case_selector == 7) begin
                // Checkerboard pattern 2
                for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'h33333333;
                data_patterns_hit[7] = 1;
            end else begin
                // Use existing data pattern logic
                case (data_pattern)
                    RANDOM_DATA: begin
                        for (i = 0; i < WDATA.size(); i++) WDATA[i] = $random;
                    end
                    ALL_ZEROS: begin
                        for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'h0;
                    end
                    ALL_ONES: begin
                        for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'hFFFFFFFF;
                    end
                    ALTERNATING_AA: begin
                        for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'hAAAAAAAA;
                    end
                    ALTERNATING_55: begin
                        for (i = 0; i < WDATA.size(); i++) WDATA[i] = 32'h55555555;
                    end
                    default: begin
                        for (i = 0; i < WDATA.size(); i++) WDATA[i] = $random;
                    end
                endcase
            end
        end
        
        // For read operations, allocate result arrays
        if (op_type == READ_OP) begin
            RDATA = new[burst_len];
            RRESP = new[burst_len];
        end

        // Update corner case tracking
        corner_cases_hit[corner_case_selector] = 1;
        
        // Track address range coverage  
        if (ADDR inside {[0:16'h0FFF]}) begin
            addr_ranges_hit[0][op_type] = 1; // Low range
        end else if (ADDR inside {[16'h1000:16'h2FFF]}) begin
            addr_ranges_hit[1][op_type] = 1; // Mid range  
        end else if (ADDR inside {[16'h3000:16'hFFFF]}) begin
            addr_ranges_hit[2][op_type] = 1; // High range
        end
        
        // Track boundary crossing coverage
        if (crosses_4KB_boundary()) begin
            addr_boundary_crosses[op_type] = 1;
        end
        
        // Increment counter for next transaction
        corner_case_counter++;
        
        // Display progress every 24 transactions  
        if (corner_case_counter % total_corner_cases == 0) begin
            display_corner_coverage();
        end

        // Sample original coverage
        operation_coverage.sample();
        boundary_coverage.sample();
    endfunction

    // Enhanced coverage reporting
    function void display_corner_coverage();
        int data_hit_count;
        int range_hits;
        int boundary_hits;
        int total_corner_hits;
        real overall_corner_coverage;
        int i, j;
        
        data_hit_count = 0;
        range_hits = 0;
        boundary_hits = 0;
        total_corner_hits = 0;
        
        // Count data pattern corner cases
        for (i = 0; i < 8; i++) begin
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
            if (addr_boundary_crosses[operation_type_e'(i)]) boundary_hits++;
        end
        
        // Count total corner cases hit
        for (i = 0; i < total_corner_cases; i++) begin
            if (corner_cases_hit[i]) total_corner_hits++;
        end
        
        $display("=== ENHANCED CORNER CASE COVERAGE REPORT ===");
        $display("Data Pattern Corner Cases: %0d/8 (%0.1f%%)", data_hit_count, 
                 (data_hit_count * 100.0) / 8);
        $display("Address Range Coverage: %0d/6 (%0.1f%%)", range_hits, (range_hits * 100.0) / 6);
        $display("Boundary Crossing Coverage: %0d/2 (%0.1f%%)", boundary_hits, (boundary_hits * 100.0) / 2);
        $display("Total Corner Cases Hit: %0d/%0d (%0.1f%%)", total_corner_hits, total_corner_cases,
                 (total_corner_hits * 100.0) / total_corner_cases);
        
        overall_corner_coverage = ((data_hit_count + range_hits + boundary_hits) * 100.0) / 16;
        $display("Overall Corner Coverage: %0.1f%%", overall_corner_coverage);
        $display("===========================================");
        
        // Display what's been hit
        $write("Data patterns hit: ");
        for (i = 0; i < 8; i++) begin
            if (data_patterns_hit[i]) $write("%0d ", i);
        end
        $display("");
        
        $write("Address ranges hit (R/W): ");
        for (i = 0; i < 3; i++) begin
            $write("[%0d: %s%s] ", i, 
                   addr_ranges_hit[i][READ_OP] ? "R" : "-",
                   addr_ranges_hit[i][WRITE_OP] ? "W" : "-");
        end
        $display("");
        
        $display("Boundary crossing: READ=%s WRITE=%s", 
                 addr_boundary_crosses[READ_OP] ? "YES" : "NO",
                 addr_boundary_crosses[WRITE_OP] ? "YES" : "NO");
    endfunction

    // Function to check if all corner cases are covered
    function bit all_corners_covered();
        int data_hit_count;
        int range_hits; 
        int boundary_hits;
        int i, j;
        
        data_hit_count = 0;
        range_hits = 0;
        boundary_hits = 0;
        
        for (i = 0; i < 8; i++) if (data_patterns_hit[i]) data_hit_count++;
        for (i = 0; i < 3; i++) for (j = 0; j < 2; j++) if (addr_ranges_hit[i][j]) range_hits++;
        for (i = 0; i < 2; i++) if (addr_boundary_crosses[operation_type_e'(i)]) boundary_hits++;
        
        return (data_hit_count == 8) && (range_hits == 6) && (boundary_hits == 2);
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

    // Enhanced display function with corner case info
    function void display();
        string pattern_names[8];
        string addr_names[6];
        
        pattern_names[0] = "ALL_ZEROS";
        pattern_names[1] = "ALL_ONES";
        pattern_names[2] = "ALTERNATING_10";
        pattern_names[3] = "ALTERNATING_01";
        pattern_names[4] = "SINGLE_MSB";
        pattern_names[5] = "SINGLE_LSB";
        pattern_names[6] = "CHECKERBOARD_1";
        pattern_names[7] = "CHECKERBOARD_2";
        
        addr_names[0] = "LOW_READ";
        addr_names[1] = "LOW_WRITE";
        addr_names[2] = "MID_READ";
        addr_names[3] = "MID_WRITE";
        addr_names[4] = "HIGH_READ";
        addr_names[5] = "HIGH_WRITE";
        
        $display("=== %s TRANSACTION (Corner Case: %0d) ===", op_type.name(), corner_case_selector);
        $display("ADDR = 0x%0h | LEN = %0d | SIZE = %0d | Beats = %0d",
                 ADDR, LEN, SIZE, LEN+1);
        $display("  Memory range: word_addr %0d to %0d (max: %0d)", 
                 ADDR >> 2, (ADDR >> 2) + LEN, MEMORY_DEPTH-1);
        $display("  4KB boundary cross: %s", crosses_4KB_boundary() ? "YES" : "NO");
        
        // Display corner case information
        if (corner_case_selector inside {[0:7]} && op_type == WRITE_OP) begin
            $display("  CORNER CASE: %s", pattern_names[corner_case_selector]);
        end else if (corner_case_selector inside {[8:13]}) begin
            $display("  CORNER CASE: %s", addr_names[corner_case_selector-8]);
        end else if (corner_case_selector inside {[14:15]}) begin
            $display("  CORNER CASE: BOUNDARY_CROSSING_%s", op_type.name());
        end
        
        if (op_type == WRITE_OP) begin
            $display("  Data pattern: %s", data_pattern.name());
            $display("  Handshake control: AWVALID=%b (delay=%0d), BREADY=%b, Reset=%0d cycles", 
                     awvalid_value, awvalid_delay, bready_value, reset_cycles);
            
            // Determine transaction scenario based on AXI4 protocol flow - matching Wstim.sv
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
            for (int k = 0; k < wvalid_delay.size(); k++) $write("%0d ", wvalid_delay[k]);
            $display("");
            $write("  WVALID patterns: ");
            for (int k = 0; k < wvalid_pattern.size(); k++) $write("%b ", wvalid_pattern[k]);
            $display(" (All should be %s)", awvalid_value ? "1" : "0");
        end else begin
            $display("  Control: ARVALID_delay=%0d, RREADY_backpressure_prob=%0d%%", 
                     arvalid_delay, rready_backpressure_prob);
        end
        $display("========================");
    endfunction

    // Enhanced coverage function
    function real get_overall_coverage();
        real op_cov;
        real bound_cov;
        real corner_cov;
        int data_hits, range_hits, boundary_hits;
        int i, j;
        
        op_cov = operation_coverage.get_coverage();
        bound_cov = boundary_coverage.get_coverage();
        
        // Calculate corner case coverage
        data_hits = 0;
        range_hits = 0;
        boundary_hits = 0;
        
        for (i = 0; i < 8; i++) if (data_patterns_hit[i]) data_hits++;
        for (i = 0; i < 3; i++) for (j = 0; j < 2; j++) if (addr_ranges_hit[i][j]) range_hits++;
        for (i = 0; i < 2; i++) if (addr_boundary_crosses[operation_type_e'(i)]) boundary_hits++;
        
        corner_cov = ((data_hits + range_hits + boundary_hits) * 100.0) / 16;
        
        return (op_cov + bound_cov + corner_cov) / 3.0;
    endfunction

endclass