#-----------------------------------------------------------------------------
# SoC Labs Environment Setup Script
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# Daniel Newbrook (d.newbrook@soton.ac.uk)
#
# Copyright  2025, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
#!/bin/bash

# Source set_env script from soctools_flow
source soctools_flow/bin/project_setup.sh $@

export PATH=$ARM_IP_LIBRARY_PATH/Cortex-M7/Cortex-M7_r1p2-00rel0/cortexm7/logical/testbench/shared/tarmac/bin:$PATH