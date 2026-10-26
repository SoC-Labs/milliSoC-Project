
FPGA_DIR		:= $(SOCLABS_PROJECT_DIR)/fpga/ARM_MPS3
TCL_FLIST_DIR	:= $(FPGA_DIR)/flist
FPGA_OUTPUT_FILELIST := $(TCL_FLIST_DIR)/fpga_flist.f

flist_fpga_millisoc: gen_defs
	@mkdir -p $(TCL_FLIST_DIR)
	@(cd $(TCL_FLIST_DIR); \
	$(SOCLABS_SOCTOOLS_FLOW_DIR)/bin/filelist_compile.py -f $(DESIGN_VC_FPGA) -a -i $(FLIST_INCLUDES) -v -o $(FPGA_OUTPUT_FILELIST)  ;)

fpga_build: flist_fpga_millisoc
	cd $(SOCLABS_PROJECT_DIR)/fpga/ARM_MPS3; vivado -mode batch -source build.tcl