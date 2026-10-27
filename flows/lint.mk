
LINT_DIR := $(SOCLABS_PROJECT_DIR)/lint/build

TOP := millisoc_chip_pads
MODULE := $(TOP)

# ── Paths ─────────────────────────────────────────────────────────
LOGFILE = $(LINT_DIR)/$(MODULE)_hal.log
XMLFILE = $(LINT_DIR)/$(MODULE)_hal.xml
RPTFILE = $(LINT_DIR)/$(MODULE)_hal_report.txt


HAL_FLAGS = -64bit \
            -sv \
            -top $(TOP) \
            -check ALL_RTL \
            -logfile $(LOGFILE) \
            -xmlfile $(XMLFILE) \
            -messages \
            -stats \
            -lintpragma


$(LINT_DIR):
	mkdir -p $@

lint_hal: $(LINT_DIR)
	cd $(LINT_DIR); hal $(HAL_FLAGS) -f $(SOCLABS_PROJECT_DIR)/lint/milliSoC_lint.f