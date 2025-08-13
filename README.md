# AXI4-Compliant Memory-Mapped Slave Verification

A comprehensive SystemVerilog-based verification environment for validating AXI4-compliant memory-mapped slave devices. This project implements a complete testbench with constrained random testing, assertion-based verification, functional coverage, and protocol compliance checking.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [File Structure](#file-structure)
- [Key Features](#key-features)
- [Verification Components](#verification-components)
- [Coverage Strategy](#coverage-strategy)
- [Getting Started](#getting-started)
- [Test Execution](#test-execution)
- [Results and Reports](#results-and-reports)
- [Advanced Features](#advanced-features)

## 🎯 Overview

This verification environment is designed to thoroughly validate AXI4 memory-mapped slave implementations through:

- **Protocol Compliance**: Comprehensive assertion-based verification ensuring strict AXI4 protocol adherence
- **Functional Coverage**: Multi-dimensional coverage tracking for complete feature verification
- **Constrained Random Testing**: Intelligent stimulus generation targeting corner cases and boundary conditions
- **Golden Model**: Reference implementation for result comparison and validation
- **Performance Analysis**: Handshaking patterns and timing verification

### Target Design Under Test (DUT)
- **Protocol**: AXI4 Memory-Mapped Slave Interface
- **Data Width**: Configurable (default: 32-bit)
- **Address Width**: Configurable (default: 16-bit)  
- **Memory Depth**: Configurable (default: 1024 entries)
- **Burst Support**: Up to 16 beats per transaction

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Testbench     │────│   AXI Interface  │────│      DUT        │
│   (Testbench.sv)│    │    (intf.sv)     │    │   (axi4.sv)     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                       │
         │                        │                       │
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Transaction    │    │   Assertions     │    │ Golden Memory   │
│(enhanced_       │    │(assertions.sv)   │    │    Model        │
│Transaction.sv)  │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 📁 File Structure

### Core Verification Files

| File | Description | Key Components |
|------|-------------|----------------|
| **`top.sv`** | Top-level test harness | Clock generation, DUT instantiation, interface binding |
| **`intf.sv`** | AXI4 interface definition | Signal declarations, clocking block, modports |
| **`pkg.sv`** | Package with enumerations | AXI4 response types, burst types, test modes |
| **`Testbench.sv`** | Main testbench module | Test orchestration, stimulus generation, checking |
| **`enhanced_Transaction.sv`** | Transaction class | Randomization constraints, coverage groups |
| **`assertions.sv`** | SystemVerilog assertions | Protocol compliance, timing checks |
| **`run.do`** | ModelSim simulation script | Compilation, optimization, coverage collection |

## ✨ Key Features

### 🔄 Transaction Generation
- **Constrained Random**: Intelligent constraint-based stimulus generation
- **Corner Case Targeting**: Automatic detection and generation of boundary conditions
- **Handshaking Variations**: Configurable VALID/READY timing patterns
- **Burst Length Control**: Single beat to 16-beat burst support

### 🎯 Coverage-Driven Verification
- **9 Comprehensive Coverage Groups**: FSM states, boundaries, bursts, responses, memory addressing
- **Cross Coverage**: Multi-dimensional coverage combinations
- **Adaptive Testing**: Dynamic test generation based on coverage holes
- **100% Coverage Target**: Systematic coverage closure methodology

### ⚡ Protocol Compliance
- **60+ Assertions**: Complete AXI4 protocol rule enforcement
- **Handshaking Verification**: VALID/READY protocol compliance
- **Burst Integrity**: AWLEN/ARLEN vs actual beat count validation
- **Response Checking**: BRESP/RRESP correctness verification

## 🧩 Verification Components

### Transaction Class (`enhanced_Transaction.sv`)

The heart of the verification environment, featuring:

```systemverilog
class Transaction #(parameter int DATA_WIDTH = 32, parameter int ADDR_WIDTH = 16);
    // Core transaction fields
    rand operation_type_e op_type;           // READ_OP or WRITE_OP
    rand logic [ADDR_WIDTH-1:0] ADDR;        // Transaction address
    rand logic [7:0] LEN;                    // Burst length (0-255)
    rand logic [DATA_WIDTH-1:0] WDATA[];     // Write data array
    
    // Advanced control fields
    rand int awvalid_delay;                  // Address valid timing
    rand int wvalid_delay[];                 // Per-beat data timing
    rand bit bready_value;                   // Response ready control
    rand test_mode_e test_mode;              // Test scenario selection
```

#### Coverage Groups (9 Comprehensive Groups)
1. **FSM States Coverage**: Write/Read state machine transitions
2. **Boundary Conditions**: 4KB boundary crossing scenarios
3. **Burst Coverage**: Length and size combinations
4. **Response Coverage**: OKAY/SLVERR response patterns
5. **Memory Address Coverage**: Full address space coverage
6. **Handshaking Coverage**: VALID/READY timing patterns
7. **Error Conditions**: Protocol violation scenarios
8. **Data Patterns**: Various data pattern coverage
9. **Test Mode Coverage**: Different test scenario coverage

### Testbench Architecture (`Testbench.sv`)

Multi-phase verification approach:

```systemverilog
// Phase 1: Random Testing (10 tests)
repeat(10) execute_test();

// Phase 2: Directed Sequences
run_directed_write_read_sequence();

// Phase 3: Single Beat Testing
run_single_beat_tests();

// Phase 4: Coverage-Driven Testing
run_coverage_driven_tests(); // Up to 200 tests for 100% coverage
```

#### Key Testbench Features
- **Golden Memory Model**: Reference model for data integrity verification
- **Comprehensive Checking**: Response validation, data integrity, protocol compliance
- **Statistics Tracking**: Pass/fail rates, response type distribution
- **Debug Support**: Configurable debug messaging system

### AXI4 Interface (`intf.sv`)

Complete AXI4 signal interface with:
- **Write Address Channel**: AWADDR, AWLEN, AWSIZE, AWVALID/AWREADY
- **Write Data Channel**: WDATA, WLAST, WVALID/WREADY  
- **Write Response Channel**: BRESP, BVALID/BREADY
- **Read Address Channel**: ARADDR, ARLEN, ARSIZE, ARVALID/ARREADY
- **Read Data Channel**: RDATA, RRESP, RLAST, RVALID/RREADY

### Assertion Suite (`assertions.sv`)

Comprehensive protocol verification:

#### Categories of Assertions
- **Reset Behavior**: Signal states during reset conditions
- **Channel Stability**: Signal stability during valid periods
- **Handshaking Rules**: VALID/READY protocol compliance
- **Burst Integrity**: AWLEN/ARLEN consistency with actual beats
- **Response Validation**: Correct BRESP/RRESP generation
- **Boundary Checks**: 4KB boundary crossing detection
- **Timeout Prevention**: Livelock avoidance assertions

## 📊 Coverage Strategy

### Coverage Metrics Tracking

The verification environment tracks multiple coverage dimensions:

| Coverage Type | Target | Key Metrics |
|---------------|--------|-------------|
| **FSM Coverage** | 100% | All state transitions covered |
| **Boundary Coverage** | 100% | 4KB boundary cross/no-cross scenarios |
| **Burst Coverage** | 100% | All burst lengths (1-16 beats) |
| **Address Coverage** | 100% | Low/mid/high address ranges |
| **Response Coverage** | 100% | OKAY/SLVERR for valid/invalid scenarios |
| **Handshaking Coverage** | 100% | All VALID/READY timing combinations |

### Adaptive Coverage Closure

The testbench employs intelligent coverage-driven testing:

```systemverilog
// Focused constraint methods for coverage holes
task constraint_memory_address_coverage();
task constraint_error_conditions_coverage();
task constraint_data_patterns_coverage();
```

## 🚀 Getting Started

### Prerequisites
- **ModelSim**: Mentor Graphics simulation tool
- **SystemVerilog Support**: IEEE 1800-2012 or later
- **Coverage Support**: Functional coverage collection capability

### Quick Setup

1. **Clone Repository**
   ```bash
   git clone https://github.com/Hussein-18021/AXI4-Compliant-Memory-Mapped-Slave-Verification.git
   cd AXI4-Compliant-Memory-Mapped-Slave-Verification
   ```

2. **Verify File Structure**
   ```
   Verification_Files/
   ├── top.sv
   ├── intf.sv
   ├── pkg.sv
   ├── Testbench.sv
   ├── enhanced_Transaction.sv
   ├── assertions.sv
   └── run.do
   
   Design_Files/
   ├── axi4.v
   └── axi_memory.v
   ```

3. **Run Simulation**
   ```bash
   cd Verification_Files
   vsim -do run.do
   ```

## 🎮 Test Execution

### Simulation Script (`run.do`)

The automated simulation flow:

```tcl
# Compilation with coverage
vlog intf.sv pkg.sv enhanced_Transaction.sv Testbench.sv ../Design_Files/axi_memory.v ../Design_Files/axi4.v top.sv +cover -covercells

# Optimization
vopt top -o opt +acc

# Simulation with coverage collection
vsim -c opt -do "add wave -radix hex /top/dut/*; coverage save -onexit cov.ucdb; run -all; coverage report -details -output cov_report.txt" -cover
```

### Test Parameters

Key simulation parameters (configurable in `Testbench.sv`):

```systemverilog
parameter int NUM_RANDOM_TESTS = 50;        // Initial random test count
parameter int NUM_DIRECTED_TESTS = 100;     // Directed test count  
parameter real TARGET_COVERAGE = 100.0;     // Coverage target
parameter bit DebugEn = 0;                  // Debug message control
```

### Test Phases

1. **Phase 1: Random Testing**
   - 10 completely random transactions
   - Basic functionality verification
   - Initial coverage seeding

2. **Phase 2: Directed Testing**  
   - Write-read sequences
   - Address-data correlation verification
   - Functional correctness validation

3. **Phase 3: Single Beat Testing**
   - Simple transactions across address space
   - Data pattern verification
   - Basic protocol compliance

4. **Phase 4: Coverage-Driven Testing**
   - Up to 200 adaptive tests
   - Targets specific coverage holes
   - Achieves 100% coverage target

## 📈 Results and Reports

### Test Results Format

```
======================================================
Test #X Result (WRITE_OP/READ_OP)
  Actual   : AWADDR=0xAAA AWLEN=N AWSIZE=S BRESP=RESP
  Expected : AWADDR=0xAAA AWLEN=N AWSIZE=S BRESP=RESP  
  TEST PASS/FAIL
======================================================
```

### Final Statistics

```
======================================================
                FINAL TEST REPORT                    
======================================================
Total Tests:    XXX
Read Tests:     XXX  
Write Tests:    XXX
Passed Tests:   XXX
Failed Tests:   XXX
Pass Rate:      XX.X%
------------------------------------------------------
OKAY Responses: XXX
SLVERR Count:   XXX
======================================================
```

### Coverage Report

```
=== COMPREHENSIVE COVERAGE REPORT ===
FSM States Coverage:      100.0%
Boundary Conditions:      100.0%
Burst Coverage:           100.0%
Response Coverage:        100.0%
Memory Address Coverage:  100.0%
Handshaking Coverage:     100.0%
Error Conditions:         100.0%
Data Patterns:            100.0%
Test Mode Coverage:       100.0%
-------------------------------------
Overall Coverage:         100.0%
=====================================
```

## ⚙️ Advanced Features

### Error Injection and Boundary Testing

The verification environment includes sophisticated error injection:

- **4KB Boundary Crossing**: Automatic detection and testing of AXI4 4KB boundary rule
- **Memory Range Violations**: Out-of-bounds address testing
- **Protocol Violations**: Invalid handshaking sequence testing
- **Timeout Scenarios**: Deadlock prevention validation

### Handshaking Pattern Testing

Advanced VALID/READY pattern generation:

```systemverilog
// Write channel handshaking control
rand int awvalid_delay;                    // Address valid delay
rand int wvalid_delay[];                   // Per-beat data delays  
rand bit awvalid_value;                    // Valid assertion control
rand bit bready_value;                     // Ready assertion control

// Read channel handshaking control  
rand int arvalid_delay;                    // Address valid delay
rand int rready_delay[];                   // Per-beat ready delays
rand bit rready_random_deassert[];         // Backpressure patterns
rand int rready_backpressure_prob;         // Backpressure probability
```

### Data Pattern Testing

Comprehensive data pattern coverage:

```systemverilog
typedef enum {
    RANDOM_DATA,      // Pseudo-random data patterns
    ALL_ZEROS,        // 0x00000000 patterns
    ALL_ONES,         // 0xFFFFFFFF patterns  
    ALTERNATING_AA,   // 0xAAAAAAAA patterns
    ALTERNATING_55    // 0x55555555 patterns
} data_pattern_e;
```

### Corner Case Detection

Automatic corner case identification and testing:

- **Burst Length Corners**: Single beat, maximum burst length
- **Address Alignment**: Aligned vs misaligned addresses
- **Boundary Conditions**: Address range boundaries
- **Response Scenarios**: OKAY vs error response conditions

## 🔍 Debug and Analysis

### Debug Features

Enable comprehensive debug output:

```systemverilog
parameter bit DebugEn = 1;  // Enable debug messages
```

Debug output includes:
- Transaction details and timing
- Handshaking sequence logging  
- Beat-by-beat data tracking
- Response analysis and validation

### Assertion Monitoring

Real-time assertion monitoring with detailed error reporting:

```systemverilog
// Example assertion with detailed error message
assert property (awvalid_stable_until_awready)
    else $error("ASSERTION FAILED: AWVALID deasserted before AWREADY handshake");
```

### Coverage Analysis

Detailed coverage reporting with hole identification:

- Coverage group percentages
- Uncovered bin identification  
- Cross-coverage analysis
- Coverage convergence tracking

## 🤝 Contributing

This verification environment is designed for extensibility:

### Adding New Test Scenarios
1. Extend `test_mode_e` enumeration in `pkg.sv`
2. Add corresponding constraints in `enhanced_Transaction.sv`
3. Implement test sequence in `Testbench.sv`

### Adding New Assertions
1. Add assertions to appropriate category in `assertions.sv`
2. Include meaningful error messages
3. Update assertion counter tracking

### Extending Coverage
1. Add new coverage groups to `enhanced_Transaction.sv`
2. Implement sampling triggers in testbench
3. Update coverage reporting methods

## 📜 License

This project is open source and available under standard open source licenses.

---

**Repository**: [AXI4-Compliant-Memory-Mapped-Slave-Verification](https://github.com/Hussein-18021/AXI4-Compliant-Memory-Mapped-Slave-Verification)

**Author**: Hussein Hassan

**Last Updated**: August 2025
