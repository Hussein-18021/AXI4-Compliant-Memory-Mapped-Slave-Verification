vlog intf.sv pkg.sv Wstim.sv WTestbench.sv ../Design_Files/axi_memory.v ../Design_Files/axi4.v top.sv
vopt top -o opt +acc
vsim -c opt -do "add wave *; run -all"