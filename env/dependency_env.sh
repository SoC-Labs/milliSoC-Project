#-----------------------------------------------------------------------------
# SoC Labs Dependency Repository Environment Setup Script
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
# Daniel Newbrook (d.newbrook@soton.ac.uk)
#
# Copyright  2025, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
#!/bin/bash

#-----------------------------------------------------------------------------
# Technologies
#-----------------------------------------------------------------------------

# Accelerator Engine -- Add Your Accelerator Environment Variable HERE!
export ACCELERATOR_DIR="$SOCLABS_PROJECT_DIR/secworks-aes"

# Accelerator Wrapper
export SOCLABS_WRAPPER_TECH_DIR="$SOCLABS_PROJECT_DIR/accelerator_wrapper_tech"

# millisoc
export SOCLABS_MILLISOC_TECH_DIR="$SOCLABS_PROJECT_DIR/millisoc_tech"
export SOCLABS_MILLISOC_SDK_DIR="$SOCLABS_PROJECT_DIR/millisoc_sdk"
export SOCLABS_ETHOS_U85_DIR="$SOCLABS_MILLISOC_TECH_DIR/logical/ethos_u85"
# SoCDebug
export SOCLABS_SOCDEBUG_TECH_DIR="$SOCLABS_PROJECT_DIR/millisoc_tech/logical/socdebug_tech"

# Arm CoreSight SoC-400 (debug subsystem)
# The Arm IP itself lives under $ARM_IP_LIBRARY_PATH; this variable points
# at the location where the rendered SoC-400 components are placed.
export SOCLABS_SOC400_DIR="$SOCLABS_PROJECT_DIR/millisoc_tech/logical/soc400"

# SL AHB QPSPI
export SOCLABS_AHB_QSPI_DIR="$SOCLABS_PROJECT_DIR/millisoc_tech/logical/ahb_qspi"

# SLDMA-350
export SOCLABS_SLDMA350_TECH_DIR="$SOCLABS_PROJECT_DIR/millisoc_tech/logical/sldma350_tech"

# Primtives
export SOCLABS_PRIMITIVES_TECH_DIR="$SOCLABS_PROJECT_DIR/rtl_primitives_tech"

# FPGA Libraries
export SOCLABS_FPGA_LIB_TECH_DIR="$SOCLABS_PROJECT_DIR/fpga_lib_tech"

# ASIC Libraries
export SOCLABS_ASIC_LIB_TECH_DIR="$SOCLABS_PROJECT_DIR/asic_lib_tech"

export SOCLABS_ASIC_FLOW_DIR="$SOCLABS_PROJECT_DIR/asic_flow"

# Generic Libraries
export SOCLABS_GENERIC_LIB_TECH_DIR="$SOCLABS_PROJECT_DIR/generic_lib_tech"

#-----------------------------------------------------------------------------
# Flows
#-----------------------------------------------------------------------------

# SoCTools - Toolkit of scripts related to SoCLabs projects
export SOCLABS_SOCTOOLS_FLOW_DIR="$SOCLABS_PROJECT_DIR/soctools_flow"

# CHIPKIT - Register Generation
export SOCLABS_CHIPKIT_FLOW_DIR="$SOCLABS_SOCTOOLS_FLOW_DIR/tools/chipkit_flow"
