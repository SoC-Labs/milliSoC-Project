


create_bd_design "ddr_design"

create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_0

set_property -dict [list \
  CONFIG.C0.DDR4_MemoryPart {MTA4ATF51264HZ-2G6} \
  CONFIG.C0.DDR4_MemoryType {SODIMMs} \
  CONFIG.C0.DDR4_TimePeriod {1071} \
  CONFIG.C0.DDR4_isCustom {false} \
] [get_bd_cells ddr4_0]

make_bd_pins_external  [get_bd_cells ddr4_0]
make_bd_intf_pins_external  [get_bd_cells ddr4_0]

assign_bd_address -target_address_space /C0_DDR4_S_AXI_0 [get_bd_addr_segs ddr4_0/C0_DDR4_MEMORY_MAP/C0_DDR4_ADDRESS_BLOCK] -force

make_wrapper -files [get_files ./vivado_project/millisoc.srcs/sources_1/bd/ddr_design/ddr_design.bd] -top
add_files -norecurse ./vivado_project/millisoc.gen/sources_1/bd/ddr_design/hdl/ddr_design_wrapper.v
