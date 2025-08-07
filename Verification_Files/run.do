vlog intf.sv pkg.sv Transaction.sv Testbench.sv axi_memory.v axi4.v top.sv +cover -covercells
vopt top -o opt +acc
vsim -c opt -do "add wave -radix hex /top/dut/*; coverage save -onexit cov.ucdb; run -all; coverage report -details -output cov_report.txt" -cover