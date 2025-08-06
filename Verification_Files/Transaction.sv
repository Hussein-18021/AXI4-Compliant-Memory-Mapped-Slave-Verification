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

    // Coverage groups
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

    // Constraints
    constraint operation_dist_c {
        op_type dist {READ_OP := 30, WRITE_OP := 70};
    }
    
    constraint test_mode_dist_c {
        test_mode dist {
            RANDOM_MODE := 40,
            BOUNDARY_CROSSING_MODE := 20,
            BURST_LENGTH_MODE := 20,
            DATA_PATTERN_MODE := 20
        };
    }

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

    constraint boundary_targeting_c {
        solve LEN before ADDR;
        if (test_mode == BOUNDARY_CROSSING_MODE) {
            ((ADDR & 12'hFFF) + ((LEN + 1) << SIZE)) > 12'hFFF;  // Force boundary crossing
        } else {
            ((ADDR & 12'hFFF) + ((LEN + 1) << SIZE)) <= 12'hFFF; // Stay within boundary
        }
    }

    constraint memory_range_c {
        (ADDR >> 2) < MEMORY_DEPTH;
        ((ADDR >> 2) + LEN) < MEMORY_DEPTH;
    }
    
    constraint addr_alignment_c {
        ADDR % (1 << SIZE) == 0;
    }

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
        
        wvalid_pattern.size() == (LEN + 1);
        
        // AXI4 Protocol Compliance - matching Wstim.sv logic:
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
        
        // Read operation control constraints
        arvalid_delay inside {[0:4]};
        arvalid_duration inside {[1:3]};
        rready_backpressure_prob inside {[10:40]}; // 10-40% chance of backpressure
    }

    function new();
        SIZE = 3'b010; // Fixed to 32-bit transfers
        operation_coverage = new();
        boundary_coverage = new();
    endfunction

    function void post_randomize();
        int burst_len = LEN + 1;
        
        // Resize and randomize control signal arrays based on burst length
        wvalid_delay = new[burst_len];
        wvalid_pattern = new[burst_len];
        rready_delay = new[burst_len];
        rready_random_deassert = new[burst_len];
        
        // Randomize array elements since constraints couldn't be applied before sizing
        foreach (wvalid_delay[i]) begin
            wvalid_delay[i] = $urandom_range(0, 2);
        end
        foreach (wvalid_pattern[i]) begin
            wvalid_pattern[i] = ($urandom_range(1, 100) <= 90) ? 1 : 0; // 90% chance of 1
        end
        foreach (rready_delay[i]) begin
            rready_delay[i] = $urandom_range(0, 2);
        end
        foreach (rready_random_deassert[i]) begin
            rready_random_deassert[i] = ($urandom_range(1, 100) <= 85) ? 1 : 0; // 85% chance of 1
        end
        
        // For write operations, create data array
        if (op_type == WRITE_OP) begin
            WDATA = new[burst_len];
            case (data_pattern)
                RANDOM_DATA:      foreach (WDATA[i]) WDATA[i] = $random;
                ALL_ZEROS:        foreach (WDATA[i]) WDATA[i] = 32'h0;
                ALL_ONES:         foreach (WDATA[i]) WDATA[i] = 32'hFFFFFFFF;
                ALTERNATING_AA:   foreach (WDATA[i]) WDATA[i] = 32'hAAAAAAAA;
                ALTERNATING_55:   foreach (WDATA[i]) WDATA[i] = 32'h55555555;
                default:          foreach (WDATA[i]) WDATA[i] = $random;
            endcase
        end
        
        // For read operations, allocate result arrays
        if (op_type == READ_OP) begin
            RDATA = new[burst_len];
            RRESP = new[burst_len];
        end

        // Sample coverage
        operation_coverage.sample();
        boundary_coverage.sample();
    endfunction

    // Utility functions
    function int total_bytes();
        return (LEN + 1) << SIZE;
    endfunction

    function bit crosses_4KB_boundary();
        return ((ADDR & 12'hFFF) + total_bytes()) > 12'hFFF;
    endfunction

    function bit exceeds_memory_range();
        return ((ADDR >> 2) + (LEN + 1)) > MEMORY_DEPTH;
    endfunction

    function void display();
        $display("=== %s TRANSACTION ===", op_type.name());
        $display("ADDR = 0x%0h | LEN = %0d | SIZE = %0d | Beats = %0d",
                 ADDR, LEN, SIZE, LEN+1);
        $display("  Memory range: word_addr %0d to %0d (max: %0d)", 
                 ADDR >> 2, (ADDR >> 2) + LEN, MEMORY_DEPTH-1);
        $display("  4KB boundary cross: %s", crosses_4KB_boundary() ? "YES" : "NO");
        
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
            foreach (wvalid_delay[i]) $write("%0d ", wvalid_delay[i]);
            $display("");
            $write("  WVALID patterns: ");
            foreach (wvalid_pattern[i]) $write("%b ", wvalid_pattern[i]);
            $display(" (All should be %s)", awvalid_value ? "1" : "0");
        end else begin
            $display("  Control: ARVALID_delay=%0d, RREADY_backpressure_prob=%0d%%", 
                     arvalid_delay, rready_backpressure_prob);
        end
        $display("========================");
    endfunction

    function real get_overall_coverage();
        real op_cov = operation_coverage.get_coverage();
        real bound_cov = boundary_coverage.get_coverage();
        return (op_cov + bound_cov) / 2.0;
    endfunction

endclass
