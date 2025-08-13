vlib work

vlog intf.sv pkg.sv enhanced_Transaction.sv Testbench.sv axi_memory.v axi4.v top.sv +cover -covercells

for {set i 0} {$i < 5} {incr i} {
    set seed [expr {int(rand() * 1000000)}]
    set ucdb_file "cov_run${i}.ucdb"
    
    puts "Running simulation $i with random seed: $seed"
    
    if {$i < 4} {
        # For all runs except the last one, quit after saving coverage
        vsim -voptargs=+acc work.top -coverage +ntb_random_seed=$seed -do "
            coverage save -onexit -du work.axi4 $ucdb_file
            coverage save -onexit -du work.Testbench $ucdb_file
            add wave -radix hex /top/dut/*
            run -all
            quit -sim
        "
    } else {
        # For the last run, don't quit the simulation
        vsim -voptargs=+acc work.top -coverage +ntb_random_seed=$seed -do "
            coverage save -onexit -du work.axi4 $ucdb_file
            coverage save -onexit -du work.Testbench $ucdb_file
            add wave -radix hex /top/dut/*
            run -all
        "
    }
}

puts "Merging coverage databases..."
vcover merge merged_cov.ucdb cov_run*.ucdb

puts "Generating coverage reports..."
vcover report merged_cov.ucdb -details -output cov_report.txt
vcover report merged_cov.ucdb -details -html -output cov_report

puts "Coverage analysis complete!"
puts "Text report: cov_report.txt"
puts "HTML report: cov_report/index.html"
puts "Last simulation is still running for interactive debugging..."