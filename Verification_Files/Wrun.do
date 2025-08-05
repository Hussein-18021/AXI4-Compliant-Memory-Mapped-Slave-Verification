vlog intf.sv pkg.sv Wstim.sv WTestbench.sv axi_memory.v axi4.v top.sv +cover -covercells
vopt top -o opt +acc
vsim -c opt -do "add wave *; coverage save -onexit cov.ucdb; run -all; coverage report -details -output cov_report.txt" -cover