# Makefile for Standalone PIM System

RTL_DIR = rtl
TB_DIR = testbench
SIM_DIR = sim
SIM_CASES = sim_cases

RTL_FILES = $(wildcard $(RTL_DIR)/*.v)
TB_FILES = $(wildcard $(TB_DIR)/*.v)

.PHONY: all clean sim view help

all: sim

help:
	@echo "PIM Memory System - Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make sim    - Run simulation"
	@echo "  make view   - View waveform with GTKWave"
	@echo "  make clean  - Clean generated files"
	@echo ""

$(SIM_DIR):
	mkdir -p $(SIM_DIR)

sim: $(SIM_DIR)
	@echo "Compiling..."
	iverilog -g2012 -o $(SIM_DIR)/tb.vvp \
		-I$(RTL_DIR) \
		$(RTL_FILES) $(TB_FILES)
	@echo "Running simulation..."
	cd $(SIM_DIR) && vvp tb.vvp
	@if [ -f pim_system.vcd ]; then mv pim_system.vcd $(SIM_DIR)/; fi
	@echo ""
	@echo "Simulation complete! Waveform: $(SIM_DIR)/pim_system.vcd"
	@echo "Run 'make view' to see waveform"

view:
	@if [ -f $(SIM_DIR)/pim_system.vcd ]; then \
		gtkwave $(SIM_DIR)/pim_system.vcd &; \
	else \
		echo "No waveform found. Run 'make sim' first"; \
	fi

clean:
	rm -rf $(SIM_DIR)
	rm -rf $(SIM_CASES)
	rm -f *.vcd *.vvp
	@echo "Cleaned!"

