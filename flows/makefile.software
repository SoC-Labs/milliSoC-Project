#-----------------------------------------------------------------------------
# MILLI SoC Software Compilation Makefile 
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# Daniel Newbrook (d.newbrook@soton.ac.uk)
#
# Copyright (C) 2021-5, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

# Software Directory
MILLISOC_SW_DIR     ?= $(SOCLABS_MILLISOC_TECH_DIR)/software

bootrom:
	make -C $(SOCLABS_MILLISOC_SDK_DIR) bootrom


# Compile test code
# Note : The use of ls after compile allows the computing server to sync up
testcode:
ifeq ($(TESTNAME),)
	$(error Please specify TESTNAME on the make command line)
endif
	@(if [ -d "$(SOCLABS_MILLISOC_SDK_DIR)/apps/$(TESTNAME)" ] ; then \
	  cd $(SOCLABS_MILLISOC_SDK_DIR) ;\
	  $(MAKE) -C $(SOCLABS_MILLISOC_SDK_DIR) all $(SW_MAKE_OPTIONS) ; \
	  echo Compile done ;\
	  ls > /dev/null ;\
	  echo Copy $(TESTNAME).hex ;\
	  if [ -e  build/$(TESTNAME)/$(TESTNAME).hex ] ; then \
	    mkdir -p $(SIM_DIR) ; \
	    cp  build/$(TESTNAME)/$(TESTNAME).hex $(SIM_DIR)/image.hex ; \
	    if [ -e apps/$(TESTNAME)/adp.cmd ] ; then \
	    cp apps/$(TESTNAME)/adp.cmd $(SIM_DIR)/adp.cmd ; \
		fi ;\
	    if [ -e data_in.csv ] ; then \
	  	cp data_in.csv $(SIM_DIR)/data_in.csv ; \
	    fi ;\
	  else \
	    while [ ! -e $(TESTNAME).hex ] ; do \
	      echo Wait for $(TESTNAME).hex file ...; \
	      ls > /dev/null ; \
	      sleep 5 ; \
	    done; \
	    if [ -e  $(TESTNAME).hex ] ; then \
		  mkdir -p $(SIM_DIR) ; \
	      cp $(TESTNAME).hex $(SIM_DIR)/image.hex ; \
	      cp $(TESTNAME).hex ../../image.hex ; \
	    else \
	      echo Problem reading hex file ;\
	      exit 1; \
	    fi ;\
	  fi ;\
	  if [ -e expram_l.hex ] ; then \
	  	cp expram_l.hex $(SIM_DIR)/expram_l.hex ; \
	  fi ;\
	  if [ -e expram_h.hex ] ; then \
	  	cp expram_h.hex $(SIM_DIR)/expram_h.hex ; \
	  fi ;\
	  if [ -e data_in.csv ] ; then \
	  	cp data_in.csv $(SIM_DIR)/data_in.csv ; \
	  fi ;\
	  cd $(SIM_DIR) ;\
	elif [ -d "$(PROJ_SW_DIR)/$(TESTNAME)" ] ; then \
	  cd $(PROJ_SW_DIR)/$(TESTNAME) ;\
	  $(MAKE) all $(SW_MAKE_OPTIONS) ; \
	  echo Compile done ;\
	  ls > /dev/null ;\
	  echo Copy $(TESTNAME).hex ;\
	  if [ -e  $(TESTNAME).hex ] ; then \
	    mkdir -p $(SIM_DIR) ; \
	    cp $(TESTNAME).hex $(SIM_DIR)/image.hex ; \
	    cp adp.cmd $(SIM_DIR)/adp.cmd ; \
	    if [ -e data_in.csv ] ; then \
	  	cp data_in.csv $(SIM_DIR)/data_in.csv ; \
	    fi ;\
	  else \
	    while [ ! -e $(TESTNAME).hex ] ; do \
	      echo Wait for $(TESTNAME).hex file ...; \
	      ls > /dev/null ; \
	      sleep 5 ; \
	    done; \
	    if [ -e  $(TESTNAME).hex ] ; then \
		  mkdir -p $(SIM_DIR) ; \
	      cp $(TESTNAME).hex $(SIM_DIR)/image.hex ; \
	    else \
	      echo Problem reading hex file ;\
	      exit 1; \
	    fi ;\
	  fi ;\
	  cd $(SIM_DIR) ;\
	else \
	  echo "ERROR: invalid TESTNAME value ( $(TESTNAME) )" ;\
	  exit 1 ;\
	fi ;\
	)


# Compile debugtester
# Note : The use of ls after compile allows the computing server to sync up
debugtester:
	@(cd $(MILLISOC_SW_DIR)/debug_tester ;\
	$(MAKE) all $(SW_MAKE_OPTIONS) ;\
	echo Compile done ;\
	ls > /dev/null ;\
	echo Copy $(DEBUGTESTER)_le.hex ;\
	if [ -e  $(DEBUGTESTER)_le.hex ] ; then \
	  cp $(DEBUGTESTER)_le.hex  $(SIM_DIR)/$(DEBUGTESTER)_le.hex ;\
	else \
	  while [ ! -e $(DEBUGTESTER)_le.hex ] ; do \
	    echo Wait for hex file ...; \
	    ls > /dev/null ; \
	    sleep 5 ; \
	  done; \
	  if [ -e  $(DEBUGTESTER)_le.hex ] ; then \
	  	mkdir -p $(SIM_DIR) ;\
	    cp $(DEBUGTESTER)_le.hex  $(SIM_DIR)/$(DEBUGTESTER)_le.hex ;\
	  fi ;\
	fi ;\
	echo Copy $(DEBUGTESTER)_be.hex ;\
	if [ -e  $(DEBUGTESTER)_be.hex ] ; then \
	  	mkdir -p $(SIM_DIR) ;\
	  cp $(DEBUGTESTER)_be.hex  $(SIM_DIR)/$(DEBUGTESTER)_be.hex ;\
	else \
	  while [ ! -e $(DEBUGTESTER)_be.hex ] ; do \
	    echo Wait for hex file ...;\
	    ls > /dev/null ;\
	    sleep 5 ; \
	  done; \
	  if [ -e  $(DEBUGTESTER)_be.hex ] ; then \
	    cp $(DEBUGTESTER)_be.hex  $(SIM_DIR)/$(DEBUGTESTER)_be.hex ;\
	  fi ;\
	fi ;\
	if [ ! -e $(DEBUGTESTER)_le.hex ] && [ ! -e $(DEBUGTESTER)_be.hex ] ; then \
	    echo Problem reading hex file ;\
	    exit 1 ;\
	fi ;\
	cd $(SIM_DIR) )

# Compile all software including boot ROM
compile_all_code: bootrom debugtester
	for thistest in $(TEST_LIST) ; do \
	  echo Compiling $$thistest   ; \
	  echo Removing old image.hex ;\
	  rm -f image.hex  ;\
	  $(MAKE) testcode TESTNAME=$$thistest;\
	  if [ -e $(SIM_TOP_DIR)/$$thistest/image.hex ] ; then \
            echo OK    - image.hex     created for test $$thistest ;\
	  else \
	    echo ERROR - image.hex NOT created for test $$thistest ;\
	    exit 1; \
	  fi ; \
	done

# Remove all software compilation results
clean_all_code:
	@(cd $(MILLISOC_SW_DIR)/debug_tester ; $(MAKE) clean; )
	@(cd $(TESTCODES_DIR)/$(BOOTLOADER) ; $(MAKE) clean; )
	@for thistest in $(TEST_LIST) ; do \
	  echo Cleaning $$thistest ...  ; \
	  if [ -e $(TESTCODES_DIR)/$$thistest ]; then \
	  	cd $(TESTCODES_DIR)/$$thistest ; \
	  	$(MAKE) clean; \
	  elif [ -e $(PROJ_SW_DIR)/$$thistest ]; then \
	  	cd $(PROJ_SW_DIR)/$$thistest ; \
	  	$(MAKE) clean; \
	  fi \
	done
	@rm -rf $(BOOTROM_BUILD_DIR)

# Remove only bootloader and default selected test
clean_code:
	@(cd $(TESTCODES_DIR)/$(BOOTLOADER) ; $(MAKE) clean; cd $(SIM_DIR); )
	@(cd $(TESTCODES_DIR)/$(TESTNAME)   ; $(MAKE) -C $(MILLISOC_SW_DIR)/common clean; cd $(SIM_DIR); )
