# AXI4-Compliant Memory-Mapped Slave Verification

## Project Overview

This repository contains a comprehensive functional verification environment for an AXI4-compliant memory-mapped slave design. The verification environment is built using SystemVerilog and OOP principles, providing robust testing capabilities to ensure protocol compliance and functional correctness.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [File Structure](#file-structure)
- [Verification Environment](#verification-environment)
- [Key Features](#key-features)
- [Getting Started](#getting-started)
- [Running Simulations](#running-simulations)
- [Verification Strategy](#verification-strategy)
- [Coverage Analysis](#coverage-analysis)
- [Assertions](#assertions)
- [Results and Reports](#results-and-reports)
- [Contributing](#contributing)

## Architecture Overview

The verification environment implements a layered testbench architecture that follows industry-standard verification methodologies:

```
┌────────────────────┐    ┌─────────────────┐
│ Transaction Layer  │    │   Assertions    │
├────────────────────┤    ├─────────────────┤
│  Transaction.sv    │    │  assertions.sv  │
└────────────────────┘    └─────────────────┘
         │                       │
┌─────────────────┐    ┌─────────────────┐
│ Test Layer      │    │   Interface     │
│                 │    │     Layer       │
├─────────────────┤    ├─────────────────┤
│ Testbench.sv    │    │    intf.sv      │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────┬───────────────┘
                 │
    ┌─────────────────┐
    │      DUT        │
    ├─────────────────┤
    │    top.sv       │
    └─────────────────┘
```

## File Structure

### Core Verification Files

| File | Description |
|------|-------------|
| `top.sv` | **Top-level testbench module** - Instantiates DUT, interface, and verification components |
| `intf.sv` | **AXI4 Interface Definition** - Contains all AXI4 signal declarations and modports |
| `pkg.sv` | **Verification Package** - Houses all verification classes, parameters, and utilities |
| `Testbench.sv` | **Main Testbench Class** - Orchestrates the verification environment and test execution |
| `enhanced_Transaction.sv` | **Transaction Class** - Defines AXI4 transaction objects with constraints and methods |
| `assertions.sv` | **SystemVerilog Assertions** - Protocol compliance and functional property checks |
| `run.do` | **Simulation Script** - ModelSim/QuestaSim automation script for compilation and simulation |

## Verification Environment

### Interface Layer (`intf.sv`)
The interface layer provides a clean abstraction between the testbench and DUT, featuring:

- **Complete AXI4 Signal Set**: All required AXI4-MM signals including address, data, control, and response channels
- **Clocking Blocks**: Synchronous signal handling with proper setup/hold timing
- **Modports**: Separate views for master, slave, and monitor perspectives
- **Signal Bundling**: Logical grouping of related AXI4 signals for easier manipulation

Key Interface Features:
```systemverilog
// Write Address Channel
logic [31:0] AWADDR
logic [7:0]  AWLEN
logic [2:0]  AWSIZE
logic [1:0]  AWBURST
logic        AWVALID
logic        AWREADY

// Write Data Channel
logic [31:0] WDATA
logic [3:0]  WSTRB
logic        WLAST
logic        WVALID
logic        WREADY

// Write Response Channel
logic [1:0]  BRESP
logic        BVALID
logic        BREADY

// Read Address Channel
logic [31:0] ARADDR
logic [7:0]  ARLEN
logic [2:0]  ARSIZE
logic [1:0]  ARBURST
logic        ARVALID
logic        ARREADY

// Read Data Channel
logic [31:0] RDATA
logic [1:0]  RRESP
logic        RLAST
logic        RVALID
logic        RREADY
```

### Transaction Layer (`enhanced_Transaction.sv`)
Implements sophisticated transaction modeling with:

- **Randomization Constraints**: Ensures realistic and protocol-compliant stimulus generation
- **Transaction Types**: Support for various AXI4 operations (single/burst read/write)
- **Error Injection**: Controllable error scenarios for robust verification
- **Timing Control**: Configurable delays and timing relationships

Transaction Class Features:
- **Smart Randomization**: Weighted distributions for realistic traffic patterns
- **Address Alignment**: Automatic address alignment based on transfer size
- **Burst Handling**: Support for INCR, WRAP, and FIXED burst types
- **Response Modeling**: Comprehensive error response generation

### Testbench Layer (`Testbench.sv`)
The main verification engine providing:

- **Driver Components**: Generate stimulus and drive AXI4 transactions
- **Monitor Components**: Observe and collect transaction data
- **Scoreboard**: Compare expected vs. actual behavior
- **Coverage Collection**: Functional and code coverage tracking
- **Test Orchestration**: Coordinate test execution phases

### Package Layer (`pkg.sv`)
Central repository containing:

- **Parameter Definitions**: Configurable testbench parameters
- **Type Definitions**: Custom data types and enumerations  
- **Utility Functions**: Common verification utilities and helper functions
- **Coverage Definitions**: Covergroups and coverage points
- **Test Configuration**: Test-specific parameters and settings

## Key Features

### 🎯 Comprehensive AXI4 Protocol Support
- **Full AXI4-MM Implementation**: Complete support for all AXI4 memory-mapped features
- **Burst Transfer Support**: INCR, WRAP, and FIXED burst types with configurable lengths
- **Multiple Outstanding Transactions**: Support for concurrent read/write operations
- **Size and Alignment Handling**: Proper byte enable and address alignment validation

### 🔧 Advanced Verification Capabilities
- **Constrained Random Stimulus**: Intelligent test generation with configurable constraints
- **Protocol Compliance Checking**: Comprehensive assertion-based verification
- **Functional Coverage**: Detailed coverage model tracking feature utilization
- **Error Injection and Recovery**: Systematic testing of error conditions and responses

### 📊 Monitoring and Analysis
- **Transaction-Level Monitoring**: Complete visibility into AXI4 transaction flow
- **Performance Analysis**: Bandwidth and latency measurement capabilities
- **Comprehensive Logging**: Detailed transaction and event logging
- **Waveform Integration**: Full signal visibility for debug and analysis

## Getting Started

### Prerequisites
- **ModelSim/QuestaSim**: Version 10.7 or later recommended
- **SystemVerilog Support**: IEEE 1800-2017 compliance required
- **Memory Requirements**: Minimum 8GB RAM for complex simulations

### Quick Setup
1. **Clone the Repository**:
   ```bash
   git clone https://github.com/Hussein-18021/AXI4-Compliant-Memory-Mapped-Slave-Verification.git
   cd AXI4-Compliant-Memory-Mapped-Slave-Verification
   ```

2. **Environment Setup**:
   ```bash
   # Ensure ModelSim/QuestaSim is in PATH
   export PATH=$PATH:/path/to/modelsim/bin
   
   # Set up library paths if needed
   export MODEL_TECH=/path/to/modelsim/modeltech
   ```

## Running Simulations

### Using the Automation Script (`run.do`)
The primary method for running simulations:

```bash
# Basic simulation run
vsim -do run.do

# Run with GUI for debugging
vsim -gui -do run.do

# Batch mode execution
vsim -c -do "do run.do; quit -f"
```

### Manual Compilation and Simulation
For custom simulation flows:

```bash
# Compilation phase
vlog -sv pkg.sv
vlog -sv intf.sv  
vlog -sv enhanced_Transaction.sv
vlog -sv Testbench.sv
vlog -sv assertions.sv
vlog -sv top.sv

# Simulation execution
vsim -voptargs=+acc top
run -all
```

### Simulation Configuration
Key parameters can be configured via:

- **Test Selection**: Choose specific test scenarios
- **Random Seed Control**: Reproducible random stimulus
- **Coverage Control**: Enable/disable coverage collection  
- **Debug Level**: Control verbosity of simulation output
- **Timeout Settings**: Configure maximum simulation time

## Verification Strategy

### 1. **Directed Testing**
- **Basic Functionality**: Single read/write operations with various sizes
- **Burst Operations**: Different burst types and lengths
- **Address Boundary Testing**: Alignment and 4KB boundary crossing
- **Error Scenarios**: SLVERR, DECERR response testing

### 2. **Constrained Random Testing**  
- **Transaction Randomization**: Address, data, size, and burst randomization
- **Timing Randomization**: Variable delays and ready signal timing
- **Mixed Traffic Patterns**: Concurrent read/write operations
- **Stress Testing**: High-frequency transaction generation

### 3. **Protocol Compliance Verification**
- **Handshake Verification**: Valid/ready signal relationships
- **Timing Requirements**: Setup/hold and response timing checks  
- **Data Integrity**: Write-read data comparison and verification
- **State Machine Validation**: Proper state transitions and responses

### 4. **Corner Case Testing**
- **Minimum/Maximum Values**: Extreme parameter value testing
- **Reset Scenarios**: Reset during active transactions
- **Back-to-Back Operations**: Consecutive transaction handling
- **Resource Limitations**: Buffer overflow and underflow scenarios

## Coverage Analysis

### Functional Coverage
Comprehensive coverage model including:

- **Address Coverage**: Full address space utilization tracking
- **Size Coverage**: All supported transfer sizes (1, 2, 4, 8, 16+ bytes)
- **Burst Coverage**: All burst types and length combinations
- **Transaction Coverage**: Read/write operation distributions
- **Cross Coverage**: Address-size-burst interactions

### Code Coverage
- **Line Coverage**: Statement execution tracking
- **Branch Coverage**: Conditional path verification  
- **Toggle Coverage**: Signal activity monitoring
- **Expression Coverage**: Boolean expression evaluation

### Coverage Goals
- **Functional Coverage Target**: ≥95% for all defined coverpoints
- **Code Coverage Target**: ≥98% line coverage, ≥95% branch coverage
- **Assertion Coverage**: 100% assertion pass rate

## Assertions (`assertions.sv`)

### Protocol Assertions
Comprehensive SystemVerilog Assertions (SVA) covering:

#### Write Channel Assertions
- **Address Channel**: `AWVALID` stability until `AWREADY`
- **Data Channel**: `WVALID`/`WDATA` relationship and `WLAST` timing
- **Response Channel**: `BRESP` validity and `BVALID`/`BREADY` handshake

#### Read Channel Assertions
- **Address Channel**: `ARVALID`/`ARADDR` stability requirements
- **Data Channel**: `RVALID`/`RDATA` timing and `RLAST` correctness
- **Response Timing**: Appropriate response delays and ordering

#### Cross-Channel Assertions
- **Outstanding Transaction Limits**: Maximum concurrent transaction tracking
- **Address Alignment**: Size-based address alignment verification
- **4KB Boundary**: Burst boundary crossing prevention
- **Reset Behavior**: Proper reset response and state clearing

### Custom Assertions
Project-specific assertions for:
- **Memory Coherency**: Read-after-write data consistency
- **Performance Constraints**: Maximum response time verification
- **Power Management**: Clock gating and power state transitions
- **Configuration Compliance**: Register access and configuration validation

## Results and Reports

### Simulation Reports
Automated generation of:

- **Test Summary Reports**: Pass/fail status and statistics
- **Coverage Reports**: Detailed coverage analysis with gap identification  
- **Performance Reports**: Transaction throughput and latency analysis
- **Assertion Reports**: Protocol compliance verification results

### Debug Information
Comprehensive logging including:

- **Transaction Logs**: Detailed transaction-level information
- **Timing Analysis**: Setup/hold and response time measurements
- **Error Reports**: Detailed error condition analysis
- **Waveform Dumps**: Complete signal visibility for debug

### Report Locations
```
reports/
├── coverage/
│   ├── functional_coverage.html
│   ├── code_coverage.html
│   └── coverage_summary.txt
├── simulation/
│   ├── test_results.log
│   ├── assertion_report.txt
│   └── performance_analysis.txt
└── debug/
    ├── transaction.log
    ├── waveform.wlf
    └── debug_info.txt
```

## Advanced Features

### Configuration Management
- **Parameterizable DUT**: Configurable address width, data width, and ID width
- **Test Configuration**: YAML/JSON-based test parameter management
- **Environment Scaling**: Support for multiple AXI4 interfaces

### Integration Capabilities  
- **UVM Compatibility**: Structured for easy UVM integration
- **Continuous Integration**: Jenkins/GitHub Actions integration support  
- **Regression Testing**: Automated nightly regression capabilities
- **Metric Tracking**: Historical performance and coverage tracking

## Troubleshooting

### Common Issues and Solutions

#### Simulation Startup Issues
```bash
# Issue: Compilation errors
# Solution: Check SystemVerilog version compatibility
vlog -sv +define+SV_VERSION_CHECK pkg.sv

# Issue: Interface connection problems  
# Solution: Verify modport usage and signal connections
```

#### Coverage Issues
```bash
# Issue: Low functional coverage
# Solution: Increase random test iterations or add directed tests

# Issue: Missing code coverage
# Solution: Review unreachable code and add appropriate stimuli
```

#### Performance Issues
```bash
# Issue: Slow simulation
# Solution: Optimize random constraints and reduce debug verbosity

# Issue: Memory usage
# Solution: Limit waveform recording or use checkpoint/restore
```

## Contributing

We welcome contributions to improve the verification environment:

### Contribution Guidelines
1. **Fork the Repository**: Create your feature branch
2. **Code Standards**: Follow SystemVerilog coding standards
3. **Testing**: Ensure all tests pass before submission  
4. **Documentation**: Update documentation for new features
5. **Review Process**: Submit pull requests for review

### Development Setup
```bash
# Development environment setup
git clone https://github.com/Hussein-18021/AXI4-Compliant-Memory-Mapped-Slave-Verification.git
cd AXI4-Compliant-Memory-Mapped-Slave-Verification

# Create development branch
git checkout -b feature/new-verification-feature

# Make changes and test
vsim -do run.do

# Submit changes
git push origin feature/new-verification-feature
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- **ARM AMBA Specification**: AXI4 protocol implementation based on ARM AMBA 4 AXI4 specification
- **SystemVerilog Community**: Verification methodologies and best practices
- **Open Source Tools**: Integration with open-source simulation and analysis tools

## Contact

For questions, issues, or contributions:

- **Repository**: [AXI4-Compliant-Memory-Mapped-Slave-Verification](https://github.com/Hussein-18021/AXI4-Compliant-Memory-Mapped-Slave-Verification)
- **Issues**: Use GitHub Issues for bug reports and feature requests
- **Discussions**: GitHub Discussions for questions and community interaction

---

## Revision History

| Version | Date | Author | Description |
|---------|------|--------|-------------|
| v1.0 | 2024 | Hussein-18021 | Initial verification environment |
| v1.1 | 2024 | Hussein-18021 | Enhanced transaction model and assertions |
| v1.2 | 2024 | Hussein-18021 | Added comprehensive coverage model |

---

*This README provides comprehensive documentation for the AXI4-Compliant Memory-Mapped Slave Verification project. For technical support or detailed implementation questions, please refer to the individual file documentation or create an issue in the repository.*
