vlog axi_memory.v axi4.v intf.sv Rstim.sv R_TB.sv top.sv
vsim -voptargs=+acc work.top
add wave *
run -all