# AXI4-Compliant Memory-Mapped Slave Verification Framework

## 📋 Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [File Structure](#file-structure)
- [Key Features](#key-features)
- [Verification Components](#verification-components)
- [Coverage Methodology](#coverage-methodology)
- [Running the Tests](#running-the-tests)
- [Results and Reports](#results-and-reports)
- [Technical Deep Dive](#technical-deep-dive)
- [Contributing](#contributing)

## 🎯 Overview

This repository contains a **comprehensive SystemVerilog verification framework** for AXI4-compliant memory-mapped slave designs. The framework implements industry-standard verification methodologies including constrained random testing, coverage-driven verification, assertion-based verification, and directed testing to ensure complete AXI4 protocol compliance.

### Key Achievements
- ✅ **100% Functional Coverage** targeting all AXI4 protocol scenarios
- ✅ **Comprehensive Assertion Coverage** with 200+ SystemVerilog assertions
- ✅ **Advanced Transaction Modeling** with corner case detection
- ✅ **Multi-phase Testing Strategy** combining random, directed, and coverage-driven tests
- ✅ **Real-world Protocol Compliance** validation

## 🏗️ Architecture

The verification environment follows a layered testbench architecture:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Testbench     │◄──►│   Interface      │◄──►│      DUT        │
│   (Driver)      │    │   (Protocol)     │    │   (AXI4 Slave)  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         ▲                       ▲                       ▲
         │                       │                       │
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Transaction    │    │   Assertions     │    │  Golden Model   │
│   Generator     │    │    Monitor       │    │   (Reference)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 📁 File Structure

### Core Verification Files

| File | Purpose | Key Features |
|------|---------|--------------|
| **`top.sv`** | Top-level testbench module | Clock generation, DUT instantiation, assertion binding |
| **`intf.sv`** | AXI4 interface definition | Modular ports, signal definitions, protocol abstraction |
| **`pkg.sv`** | Package definitions | Enumerations, typedefs, constants |
| **`Testbench.sv`** | Main test driver | Transaction orchestration, golden model, result checking |
| **`enhanced_Transaction.sv`** | Transaction class | Constrained random generation, coverage collection |
| **`assertions.sv`** | SVA assertion module | 200+ protocol compliance checks |
| **`run.do`** | ModelSim automation script | Multi-seed simulation, coverage merging |

### DUT Files (Referenced)
- `axi4.v` - AXI4 slave implementation
- `axi_memory.v` - Internal memory module

## 🚀 Key Features

### 1. **Advanced Transaction Generation**
```systemverilog
class Transaction #(parameter int DATA_WIDTH = 32, parameter int ADDR_WIDTH = 16);
    // Smart constraints for comprehensive testing
    constraint memory_range_c {
        ADDR inside {[16'h0000:16'h0FFC]};  // 4KB memory space
        ADDR[1:0] == 2'b00;                 // Word alignment
        (ADDR + ((LEN + 1) << SIZE)) <= MEMORY_SIZE_BYTES;
    }
    
    // Coverage-driven test modes
    rand test_mode_e test_mode;
    constraint test_mode_dist_c {
        test_mode dist {
            RANDOM_MODE := 40,
            BOUNDARY_CROSSING_MODE := 25,
            BURST_LENGTH_MODE := 20,
            DATA_PATTERN_MODE := 15
        };
    }
endclass
```

### 2. **Comprehensive Coverage Model**
- **Burst Coverage**: Single beats, short/medium/long bursts, maximum AXI4 bursts
- **Memory Address Coverage**: Complete 4KB address space partitioning
- **Data Pattern Coverage**: Corner case data patterns (all-zeros, all-ones, alternating patterns)
- **Protocol Coverage**: Error responses, boundary conditions, FSM states

### 3. **Assertion-Based Verification**
```systemverilog
// Example: AWVALID stability assertion
property awvalid_stable_until_awready;
    @(posedge clk) disable iff (!ARESTN)
    (AWVALID && !AWREADY) |=> AWVALID;
endproperty
assert_awvalid_stable: assert property (awvalid_stable_until_awready)
    else $error("ASSERTION FAILED: AWVALID deasserted before AWREADY handshake");
```

## 🔍 Verification Components

### Transaction Generator (`enhanced_Transaction.sv`)

**Key Capabilities:**
- **Constrained Random Generation**: Smart constraints ensuring valid AXI4 transactions
- **Corner Case Detection**: Automatic identification of boundary crossings, alignment issues
- **Data Pattern Support**: 5 different data patterns for comprehensive data testing
- **Coverage Tracking**: Real-time coverage collection and reporting

**Advanced Features:**
```systemverilog
// Boundary crossing detection
function bit crosses_4KB_boundary();
    logic [15:0] start_4kb_block = ADDR[15:12];
    logic [15:0] end_4kb_block = (ADDR + total_bytes() - 1) >> 12;
    return (start_4kb_block != end_4kb_block);
endfunction

// Smart address distribution
constraint addr_distribution_c {
    ADDR dist {
        [16'h0000:16'h0554] := 30,  // Low range
        [16'h0558:16'hAAC] := 30,   // Mid range  
        [16'hAB0:16'h0FFC] := 30,   // High range
        [16'h0FF0:16'h0FFC] := 10   // Boundary cases
    };
}
```

### Testbench Driver (`Testbench.sv`)

**Multi-Phase Testing Strategy:**

1. **Phase 1 - Random Testing**: Unconstrained random transactions for basic functionality
2. **Phase 2 - Directed Testing**: Targeted write-read sequences and corner cases  
3. **Phase 3 - Coverage-Driven Testing**: Intelligent test generation to fill coverage holes

**Golden Model Integration:**
```systemverilog
task automatic golden_model(input Transaction tr);
    // Predict expected responses based on:
    // - Memory boundary checks
    // - 4KB boundary crossing detection
    // - Address alignment validation
    // - Protocol compliance rules
endtask
```

### Protocol Interface (`intf.sv`)

**Modular Design:**
```systemverilog
interface axi_if #(parameter int DATA_WIDTH = 32, parameter int ADDR_WIDTH = 16);
    // Complete AXI4 signal set
    logic [ADDR_WIDTH-1:0] AWADDR, ARADDR;
    logic [7:0] AWLEN, ARLEN;
    logic [2:0] AWSIZE, ARSIZE;
    // ... all AXI4 signals
    
    // Testbench modport for clean signal access
    modport TB (
        input  ACLK, AWREADY, WREADY, BRESP, BVALID, ARREADY, RDATA, RRESP, RLAST, RVALID,
        output ARESTN, AWADDR, AWLEN, AWSIZE, AWVALID, WDATA, WLAST, WVALID, BREADY,
               ARADDR, ARLEN, ARSIZE, ARVALID, RREADY
    );
endinterface
```

### Assertion Monitor (`assertions.sv`)

**200+ SystemVerilog Assertions covering:**

**Protocol Compliance:**
- Valid/Ready handshaking rules
- Signal stability during transactions
- Burst length compliance
- Response code validation

**Design-Specific Checks:**
- Memory boundary compliance
- 4KB boundary crossing errors
- Address alignment validation
- Timeout prevention

**Coverage Monitoring:**
```systemverilog
// Transaction completion coverage
sequence write_transaction_complete;
    (AWVALID && AWREADY) ##[1:$] (WVALID && WREADY && WLAST) ##[1:$] (BVALID && BREADY);
endsequence
cover_write_transaction_complete: cover property (write_transaction_complete);
```

## 📊 Coverage Methodology

### Functional Coverage Groups

1. **Burst Coverage**
   - Single transfers (LEN=0)
   - Short bursts (LEN=1-3)
   - Medium bursts (LEN=4-7)
   - Long bursts (LEN=8-15)
   - Maximum bursts (LEN=16-255)

2. **Memory Address Coverage**
   - Low range: 0x000-0x555 (addresses 0-341)
   - Mid range: 0x556-0xAAA (addresses 342-681)
   - High range: 0xAAB-0xFFF (addresses 682-1023)
   - Boundary crossing scenarios

3. **Data Pattern Coverage**
   - Random data
   - All zeros (0x00000000)
   - All ones (0xFFFFFFFF)
   - Alternating patterns (0xAAAAAAAA, 0x55555555)

4. **Protocol Coverage**
   - OKAY/SLVERR response scenarios
   - Memory bounds compliance
   - FSM state transitions

### Coverage-Driven Testing
```systemverilog
task automatic run_coverage_driven_tests();
    while (overall_coverage < TARGET_COVERAGE && coverage_tests < max_coverage_tests) begin
        run_targeted_coverage_test();  // Smart test generation
        
        if (coverage_stagnant) begin
            run_specific_coverage_holes();  // Hole-filling tests
        end
    end
endtask
```

## 🏃 Running the Tests

### Prerequisites
- **ModelSim/QuestaSim** (version 10.6 or later)
- **SystemVerilog** support
- **Coverage analysis** capabilities

### Quick Start
```bash
# Clone the repository
git clone https://github.com/Hussein-18021/AXI4-Compliant-Memory-Mapped-Slave-Verification.git
cd AXI4-Compliant-Memory-Mapped-Slave-Verification

# Run the automated test suite
vsim -do run.do
```

### Manual Execution
```bash
# Compile all files
vlib work
vlog intf.sv pkg.sv enhanced_Transaction.sv Testbench.sv axi_memory.v axi4.v top.sv +cover -covercells

# Run simulation with coverage
vsim -voptargs=+acc work.top -coverage +ntb_random_seed=12345
add wave -radix hex /top/dut/*
run -all
```

### Test Configuration
The testbench supports several parameters for customization:

```systemverilog
module Testbench;
    parameter int NUM_RANDOM_TESTS = 50;      // Random test count
    parameter int NUM_DIRECTED_TESTS = 100;   // Directed test count  
    parameter real TARGET_COVERAGE = 100.0;   // Coverage target
    parameter bit DebugEn = 1;                // Debug messages
endmodule
```

## 📈 Results and Reports

### Automated Reporting
The `run.do` script automatically:
1. **Runs 5 simulations** with different random seeds
2. **Merges coverage databases** for comprehensive analysis
3. **Generates HTML and text reports**
4. **Provides interactive debugging** session

### Coverage Reports
```
Coverage analysis complete!
Text report: cov_report.txt
HTML report: cov_report/index.html
```

### Sample Test Results
```
======================================================
                FINAL TEST REPORT                    
======================================================
Total Tests:    485
Read Tests:     242  
Write Tests:    243
Passed Tests:   462
Failed Tests:   23 (intended boundary crossing failures)
Pass Rate:      95.3%
------------------------------------------------------
OKAY Responses: 438
SLVERR Count:   47
======================================================

=== COMPREHENSIVE COVERAGE REPORT ===
Burst Coverage:           100.0%
Memory Address Coverage:  100.0%
Data Patterns Coverage:   100.0%
Protocol Coverage:        100.0%
-------------------------------------
Overall Coverage:         100.0%
=====================================
```

### Assertion Results
```
AXI4 ASSERTION VERIFICATION REPORT
========================================
Total Assertions Passed: 2847
Total Assertions Failed: 0
Overall Pass Rate: 100.0%
========================================
```

## 🔧 Technical Deep Dive

### Advanced Features

#### 1. **Smart Constraint Solving**
The transaction generator uses sophisticated constraints to ensure comprehensive coverage while maintaining AXI4 protocol compliance:

```systemverilog
// Memory range constraint with burst consideration
constraint memory_range_c {
    ADDR inside {[16'h0000:16'h0FFC]};
    ADDR[1:0] == 2'b00;  // Word alignment
    (ADDR + ((LEN + 1) << SIZE)) <= MEMORY_SIZE_BYTES;  // Burst bounds
}
```

#### 2. **Intelligent Coverage Hole Detection**
The framework automatically identifies and targets uncovered scenarios:

```systemverilog
task automatic run_specific_coverage_holes();
    // FSM State Coverage - Force different FSM transitions
    // Address Coverage - Hit all memory ranges systematically  
    // Error Conditions - Boundary crossing and invalid scenarios
    // Data Patterns - All combinations with different burst lengths
endtask
```

#### 3. **Protocol Compliance Validation**
Comprehensive assertion checking ensures strict AXI4 compliance:

- **Handshaking Protocols**: Valid/Ready signal relationships
- **Signal Stability**: Data/address stability during valid periods
- **Burst Integrity**: LAST signal placement, beat counting
- **Response Accuracy**: Correct error responses for boundary violations

#### 4. **Golden Model Architecture**
The reference model predicts expected behavior for all scenarios:

```systemverilog
// Boundary crossing detection
if (tr.exceeds_memory_range() || tr.crosses_4KB_boundary()) begin
    expected.BRESP = enuming::SLVERR;
end else begin
    expected.BRESP = enuming::OKAY;
    // Update golden memory
    start_addr = tr.ADDR >> 2;
    for (int i = 0; i <= tr.LEN; i++) begin
        golden_mem[start_addr + i] = tr.WDATA[i];
    end
end
```

### Performance Optimizations

1. **Efficient Coverage Sampling**: Coverage data collection optimized to minimize simulation overhead
2. **Smart Test Generation**: Targeted test generation based on coverage holes reduces simulation time
3. **Parallel Execution**: Multi-seed simulation support for faster coverage closure

### Error Injection and Recovery

The framework includes sophisticated error injection capabilities:

- **Boundary Crossing Tests**: Transactions that cross 4KB boundaries
- **Invalid Address Tests**: Out-of-range memory accesses
- **Protocol Violation Tests**: Handshaking errors and timing violations
- **Backpressure Scenarios**: READY signal deassertion patterns

## 🤝 Contributing

We welcome contributions to improve the verification framework! Here's how you can help:

### Development Guidelines

1. **Follow SystemVerilog best practices**
2. **Add comprehensive comments** for new features
3. **Include coverage points** for new scenarios
4. **Update assertions** for new protocol checks
5. **Test thoroughly** with multiple random seeds

### Contribution Areas

- **Additional AXI4 features** (WRAP bursts, different sizes)
- **Performance optimizations** in coverage collection
- **New assertion checks** for edge cases
- **Enhanced reporting** capabilities
- **Integration with other verification methodologies** (UVM)

### Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-verification-feature`)
3. Commit changes (`git commit -am 'Add new verification feature'`)
4. Push to branch (`git push origin feature/new-verification-feature`)  
5. Create a Pull Request

## 📚 Additional Resources

### AXI4 Specification References
- ARM AMBA AXI4 Specification (IHI0022E)
- AXI4 Protocol Checker Implementation Guide
- SystemVerilog Assertions Methodology

### Related Documentation
- `docs/` directory contains detailed technical specifications
- Coverage analysis methodology documents
- Assertion development guidelines

### Support and Contact

For questions, issues, or contributions:
- **GitHub Issues**: [Report bugs or request features](https://github.com/Hussein-18021/AXI4-Compliant-Memory-Mapped-Slave-Verification/issues)
- **Discussions**: [Join technical discussions](https://github.com/Hussein-18021/AXI4-Compliant-Memory-Mapped-Slave-Verification/discussions)

---

**Built with ❤️ for the verification community**

*This comprehensive verification framework represents months of development effort to create a robust, reusable, and industry-standard AXI4 verification environment. We hope it serves as a valuable resource for verification engineers working on AXI4-compliant designs.*
