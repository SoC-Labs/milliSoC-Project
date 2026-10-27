
# ============================================================
# milliSoC FPGA implementation flow
# Target: Arm MPS3 FPGA prototyping board
# Tool:   Xilinx Vivado
#
# No Xilinx IP is instantiated by this script.
# All processor, memory, interconnect and peripheral IP is
# expected to be supplied by the milliSoC RTL.
# ============================================================

# ----------------------------
# User configuration
# ----------------------------

set PROJECT_NAME "millisoc"
set PROJECT_DIR  "./vivado_project"
set RTL_DIR      "../../rtl"
set OUTPUT_DIR  "./output"
set REPORT_DIR  "$OUTPUT_DIR/reports"
set BIT_DIR     "$OUTPUT_DIR/bitstream"

file mkdir $OUTPUT_DIR
file mkdir $REPORT_DIR
file mkdir $BIT_DIR

source ../read_flist.tcl

# IMPORTANT:
# Replace with the exact FPGA part fitted to your MPS3 variant.
set FPGA_PART "xcku115-flvb1760-1-c"

# Replace with your actual top-level module name.
set TOP_MODULE "millisoc_fpga_wrapper"

# Optional XDC constraints file.
set XDC_FILE "./millisoc.xdc"

# ----------------------------
# Create project
# ----------------------------

create_project -force $PROJECT_NAME $PROJECT_DIR \
    -part $FPGA_PART

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# ----------------------------
# Discover RTL sources
# ----------------------------
set search_path ./

read_flist "./flist/fpga_flist.f"
read_verilog ./millisoc_fpga_wrapper.sv

# Define any project-wide RTL macros here if required.
# set_property verilog_define {SYNTHESIS FPGA} \
#     [get_filesets sources_1]

# ----------------------------
# Top-level configuration
# ----------------------------

set_property top $TOP_MODULE [get_filesets sources_1]

update_compile_order -fileset sources_1

# ----------------------------
# Add board constraints
# ----------------------------

if {[file exists $XDC_FILE]} {
    add_files -fileset constrs_1 $XDC_FILE
    set_property file_type XDC \
        [get_files $XDC_FILE]
} else {
    puts "WARNING: No XDC file found at $XDC_FILE"
    puts "WARNING: Physical implementation may be incomplete."
}

# ----------------------------
# Synthesis
# ----------------------------

launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synth_status"

report_utilization \
    -file "$REPORT_DIR/millisoc_synth_utilization.rpt"

report_utilization -hierarchical \
    -file "$REPORT_DIR/millisoc_synth_hierarchical_utilization.rpt"

report_timing_summary \
    -file "$REPORT_DIR/millisoc_synth_timing.rpt"

report_io \
    -file "$REPORT_DIR/millisoc_io.rpt"

# ----------------------------
# Implementation + bitstream
# ----------------------------

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $impl_status"

if {![string match "*Complete*" $impl_status]} {
    error "Implementation failed. Check the Vivado implementation log."
}


# Resource utilization
report_utilization \
    -file "$REPORT_DIR/millisoc_impl_utilization.rpt"

report_utilization -hierarchical \
    -file "$REPORT_DIR/millisoc_impl_hierarchical_utilization.rpt"

# Timing analysis
report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -file "$REPORT_DIR/millisoc_impl_timing.rpt"

# Detailed worst timing paths
report_timing \
    -delay_type max \
    -max_paths 20 \
    -file "$REPORT_DIR/millisoc_critical_paths.rpt"

# Design rule checks
report_drc \
    -file "$REPORT_DIR/millisoc_drc.rpt"

# ----------------------------
# Reports
# ----------------------------

open_run impl_1

report_utilization \
    -file "$PROJECT_DIR/millisoc_utilization.rpt"

report_timing_summary \
    -file "$PROJECT_DIR/millisoc_timing.rpt"

puts "=========================================="
puts "milliSoC FPGA build completed successfully"
puts "Project: $PROJECT_DIR"
puts "=========================================="

save_project