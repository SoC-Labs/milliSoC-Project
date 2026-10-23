#-----------------------------------------------------------------------------
# MilliSoC Simulation Makefile 
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
# Daniel Newbrook (d.newbrook@soton.ac.uk)
#
# Copyright (C) 2021-4, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

# MTI options
MTI_VC_OPTIONS    = +acc +define+ARM_TARMAC +define+RTL_SIM +define+ARM_ASSERT_ON
MTI_VC_OPTIONS    += -suppress 2892
MTI_VC_OPTIONS    += -f $(TBENCH_VC) 
MTI_RUN_OPTIONS   = -voptargs=+acc +define+ARM_TARMAC +define+RTL_SIM +TarmacI +TarmacM +TarmacR +TarmacE
MODELSIM_INI := $(SIM_BUILD_DIR)/modelsim.ini
WORK_LIB   := $(SIM_BUILD_DIR)/work
# VCS options
VCS_OPTIONS    = +define+ARM_TARMAC +define+RTL_SIM +define+ARM_ASSERT_ON +vcs+lic+wait +v2k -sverilog -override_timescale=1ns/1ps +lint=TFIPC-L +warn=noUSVS-ACWCFC -debug -debug_access+all 
VCS_SIM_OPTION = +vcs+lic+wait +vcs+flush+log -assert nopostproc +define+ARM_TARMAC +define+RTL_SIM +TarmacI +TarmacM +TarmacR +TarmacE
VCS_VC_OPTIONS = -f $(TBENCH_VC) 

#---------------------------------
# Optional VCS 
#---------------------------------
ifeq ($(CPU_TYPE),CM7)
	VCS_OPTIONS +=  -sverilog $(CORTEX_M7_LOGICAL_DIR)/testbench/shared/tarmac/lib64/cm7_tarmac_dpi.so +define+CM7_TARMAC +define+CM7_TARMAC_DPI
else ifeq ($(CPU_TYPE), CM85)
	VCS_OPTIONS += +define+OLYMPUS_TARMAC +define+OLYMPUS_TARMAC_DPI +define+OLYMPUS_TARMAC_CAPTURE_TIME_VERILOG_TASK
	VCS_SIM_OPTION +=  -sv_lib $(CORTEX_M85_LOGICAL_DIR)/logical/testbench/shared/tarmac/linux64/lib/olympus_tarmac_dpi 
endif

# ------- Cocotb Variables -----------
# Convert Simulator Name for Cocotb
COCOTB_SIMULATOR ?= questa

ifeq ($(SIMULATOR),mti)
	COCOTB_SIMULATOR := questa
else ifeq ($(SIMULATOR),xm)
	COCOTB_SIMULATOR := xcelium
else ifeq ($(SIMULATOR),vcs)
	COCOTB_SIMULATOR := vcs
endif

# Cocotb GUI Variable
GUI ?= 0

# Cocotb Test Location
COCOTB_TEST_DIR := $(SOCLABS_PROJECT_DIR)/verif/cocotb

# Cocotb Scratch Directory
COCOTB_DIR := $(SIM_TOP_DIR)/cocotb
COCOTB_SCRATCH_DIR := $(COCOTB_DIR)/scratch

# Filelist for Cocotb 
MAKEFILE_FILELIST     := $(COCOTB_DIR)/makefile.flist

MODULE ?= test_adp

# Create a List of PHONY Targets
.PHONY: compile_$(SIMULATOR) run_$(SIMULATOR) sim_$(SIMULATOR) build_soc400

# ------- Simulator redirect -----------

compile: compile_$(SIMULATOR)

run: run_$(SIMULATOR)

sim: sim_$(SIMULATOR)

# Preload IMEM in Simulation
compile_mti: MILLISOC_DEFINES += IMEM_0_RAM_PRELOAD
compile_vcs: MILLISOC_DEFINES += IMEM_0_RAM_PRELOAD
compile_xm:  MILLISOC_DEFINES += IMEM_0_RAM_PRELOAD


# Generate verilog .vc filelist from flists
flist_vfiles_millisoc: build_soc400 gen_defs
	echo $(FLIST_INCLUDES)
	@if [ ! -d $(SIM_BUILD_DIR) ] ; then \
	  mkdir -p $(SIM_BUILD_DIR); \
	fi
	@if [ ! -d $(SIM_BUILD_DIR)/logs ] ; then \
	  mkdir -p $(SIM_BUILD_DIR)/logs; \
	fi
	@cd $(SIM_BUILD_DIR); python $(SOCLABS_SOCTOOLS_FLOW_DIR)/bin/filelist_compile.py -f $(TBENCH_VC) -a -i $(FLIST_INCLUDES) -v -o tbench.vc

# The SoC-400 sources are copied/rendered into a gitignored directory, so ensure
# they are available before compiling any simulation filelist that references
# them.
build_soc400:
	$(MAKE) -C $(SOCLABS_MILLISOC_TECH_DIR) build_soc400

# ------- VCS -----------

# Compile RTL
compile_vcs : build_soc400 bootrom gen_defs flist_vfiles_millisoc
	cd $(SIM_BUILD_DIR); vcs $(VCS_OPTIONS) -f tbench.vc  -kdb $(DEFINES_VC)  | tee compile_vcs.log


# Run simulation in batch mode
run_vcs : testcode 
	@echo quit > $(SIM_DIR)/quit.do
	@if [ ! -d $(SIM_DIR)/logs ] ; then \
	  mkdir -p $(SIM_DIR)/logs; \
	fi
	@if [ $(ASIC_MEMS) -e yes] ; then \
		cp $(SOCLABS_PROJECT_DIR)/memories/millisoc/bootrom/bootrom_emulation.rcf $(SIM_DIR)/; \
	fi
	@if [ -f $(TESTCODES_DIR)/$(TESTNAME)/adp.cmd ] ; then \
		cp $(TESTCODES_DIR)/$(TESTNAME)/adp.cmd $(SIM_DIR)/; \
	fi
	cd $(SIM_DIR); $(SIM_BUILD_DIR)/simv $(VCS_SIM_OPTION) < quit.do | tee logs/run_$(TESTNAME).log ;

# Run simulation in interactive mode
sim_vcs : testcode 
	@if [ ! -d $(SIM_DIR)/logs ] ; then \
	  mkdir -p $(SIM_DIR)/logs; \
	fi
	cd $(SIM_DIR); $(SIM_BUILD_DIR)/simv $(VCS_SIM_OPTION) -gui +vcs+lic+wait +vcs+flush+log &

# ------- MTI -----------


$(MODELSIM_INI):
	cd "$(SIM_BUILD_DIR)" && vlib work
	cd "$(SIM_BUILD_DIR)" && vmap work "$(WORK_LIB)"

# Compile RTL
compile_mti : build_soc400 bootrom gen_defs flist_vfiles_millisoc $(MODELSIM_INI)
	cd $(SIM_BUILD_DIR); vlog -modelsimini "$(MODELSIM_INI)" -work work -incr -lint +v2k  -f tbench.vc $(DEFINES_VC) | tee compile_mti.log

# Run simulation in batch mode
run_mti : testcode
	@echo "run -all" > $(SIM_DIR)/run.tcl.tmp
	@echo "quit -f" >> $(SIM_DIR)/run.tcl.tmp
	@mv  $(SIM_DIR)/run.tcl.tmp $(SIM_DIR)/run.tcl
	cd $(SIM_DIR); vsim $(MTI_RUN_OPTIONS) -modelsimini "$(MODELSIM_INI)" -c work.millisoc_tb -do run.tcl | tee $(SIM_DIR)/logs/run_$(TESTNAME).log ;

run_mti_to:
	timeout 2s $(MAKE) run_mti >> /dev/null 2>&1 
	
run_mti_wrap:
	$(MAKE) run_mti_to
	
# Run simulation in interactive mode
sim_mti :  
	cd $(SIM_DIR); vsim $(MTI_RUN_OPTIONS) -modelsimini "$(MODELSIM_INI)"  -gui  work.millisoc_tb &

# Create work directory
lib_mti :
	@if [ -d $(SIM_BUILD_DIR)/work ] ; then \
          true ; \
	else \
	  vlib  $(SIM_BUILD_DIR)/work; \
	fi

# Generate Make filelist from flists
flist_makefile_millisoc: gen_defs
	@mkdir -p $(COCOTB_DIR)
	@(cd $(COCOTB_DIR); \
	$(SOCLABS_SOCTOOLS_FLOW_DIR)/bin/filelist_compile.py -m -f $(DESIGN_VC) -o $(MAKEFILE_FILELIST);)

run_cocotb: DEFINES_VC += COCOTB_SIM
run_cocotb: flist_makefile_millisoc
	@mkdir -p $(SIM_DIR)
	@cd $(SIM_DIR); $(MAKE) -C $(SOCLABS_PROJECT_DIR)/verif/cocotb clean SIM_BUILD=$(COCOTB_SCRATCH_DIR)
	@cd $(SIM_DIR); $(MAKE) -C $(SOCLABS_PROJECT_DIR)/verif/cocotb sim MODULE=$(MODULE) SIM=$(COCOTB_SIMULATOR) TESTCASE=$(TESTNAME) GUI=$(GUI) SIM_BUILD=$(COCOTB_SCRATCH_DIR) ACCELERATOR=$(ACCELERATOR)

sim_cocotb: GUI=1
sim_cocotb: run_cocotb
