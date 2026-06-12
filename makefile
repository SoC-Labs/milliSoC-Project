include $(SOCLABS_PROJECT_DIR)/millisoc.config
export CORTEX_M7_LOGICAL_DIR
export CPU_TYPE
# Directory to put simulation files
SIM_TOP_DIR ?= $(SOCLABS_PROJECT_DIR)/simulate/sim
SIM_DIR      = $(SIM_TOP_DIR)/$(TESTNAME)
SIM_BUILD_DIR = $(SIM_TOP_DIR)/build
TBENCH_VC ?= $(SOCLABS_PROJECT_DIR)/flist/top_BEHAV.flist
SIM?=vcs
export SIM

#-------------------------------------
# - Directory Setups
#-------------------------------------
# Directory of Testcodes
TESTCODES_DIR    := $(SOCLABS_MILLISOC_TECH_DIR)/software/src
TESTCODES_BUILD_DIR := $(SOCLABS_MILLISOC_TECH_DIR)/software/build
export TESTCODES_BUILD_DIR

# Location of Defines File
DEFINES_DIR := $(SOCLABS_PROJECT_DIR)/top/logical/
DEFINES_FILE := $(DEFINES_DIR)/gen_defines.v

MILLISOC_DEFINES = MILLISOC  PMU_PWR_DOWN  OVL_INIT_MSG
DEFINES_VC = +define+CPU_TYPE=$(CPU_TYPE)
TOOL_CHAIN = ds5

export TOOL_CHAIN
export DEFINES_VC

# Default test
TESTNAME ?= hello

#---------------------------------
# Optional file includes
#---------------------------------
ifeq ($(CPU_TYPE),CM7)
	FLIST_INCLUDES += $(SOCLABS_MILLISOC_TECH_DIR)/flist/IP/CortexM7.flist
	FLIST_INCLUDES += $(SOCLABS_MILLISOC_TECH_DIR)/flist/IP/CortexM7_BEHAV.flist
endif

export FLIST_INCLUDES
#------------------------------------------
# - Include Makefiles for Specific Flows
#------------------------------------------
# Include Software Compilation Makefile
include $(SOCLABS_PROJECT_DIR)/flows/makefile.software

# Include Linting Makefile
include $(SOCLABS_PROJECT_DIR)/flows/makefile.lint

# Include Simulation Makefile
include $(SOCLABS_PROJECT_DIR)/flows/makefile.simulate

# Include Regression Simulation Makefile
include $(SOCLABS_PROJECT_DIR)/flows/makefile.regression

# Include FPGA Makefile
include $(SOCLABS_PROJECT_DIR)/flows/makefile.fpga

# Include Synthesis Makefile
include $(SOCLABS_PROJECT_DIR)/flows/makefile.asic

#------------------------------------------
# - Common Targets Across Flows
#------------------------------------------
# Generate Defines File for MegaSoC
gen_defs:
	@mkdir -p $(DEFINES_DIR)
	@$(SOCLABS_SOCTOOLS_FLOW_DIR)/bin/defines_compile.py -d $(MILLISOC_DEFINES) -o $(DEFINES_FILE)

get_flash_model:
	make -C $(SOCLABS_AHB_QSPI_DIR) get_flash_model