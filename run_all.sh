#!/bin/bash

# ==============================================================================
# 🛠️ MICRON PIM SYSTEM - FINAL REPORT
# ==============================================================================

SIM_DIR="sim"
LOG_DIR="logs"
OUTPUT_VVP="tb.vvp"

mkdir -p $SIM_DIR
mkdir -p $LOG_DIR

# 1. CLEANUP (Hapus file backup yang bikin error)
rm -f rtl/simple_memory_backup.v 2>/dev/null

# 2. COMPILE (Explicit File List)
echo "🔨 [1/3] Compiling Verilog..."
iverilog -g2012 -o $SIM_DIR/$OUTPUT_VVP \
    -I rtl \
    rtl/simple_riscv_cpu.v \
    rtl/simple_memory.v \
    rtl/cpu_to_axi.v \
    rtl/pim_sparsity_aware.v \
    rtl/pim_system_top.v \
    rtl/pim_perf_monitor.v \
    testbench/tb_pim_system.v

if [ $? -ne 0 ]; then
    echo "❌ Compile Failed!"; exit 1;
fi

# 3. GENERATE DATA
echo "🎲 [2/3] Generating Data..."
python3 gen_testcase.py

# 4. RUN SIMULATION
echo "🚀 [3/3] Running Sparsity Sweep..."
echo ""
# Header Tabel Sesuai Request
printf " %-10s | %-15s | %-15s | %-10s | %-12s | %-12s\n" "SPARSITY" "BASE E (uJ)" "PIM E (uJ)" "SAVING" "SPARSE PKTS" "TOTAL PKTS"
echo "==================================================================================================="

for s in 0 25 50 75 85 90 95
do
    cp sim_cases/firmware_sparse_$s.hex $SIM_DIR/firmware.hex
    cd $SIM_DIR; vvp $OUTPUT_VVP > ../$LOG_DIR/log_sparse_$s.txt; cd ..
    
    # Parse CSV Output dari Testbench
    # Format: RESULT,Total,Sparse,BaseEnergy,PIMEnergy,Saving
    LINE=$(grep "RESULT," $LOG_DIR/log_sparse_$s.txt)
    
    if [ ! -z "$LINE" ]; then
        TOTAL=$(echo $LINE | cut -d',' -f2)
        SPARSE=$(echo $LINE | cut -d',' -f3)
        BASE_E=$(echo $LINE | cut -d',' -f4)
        PIM_E=$(echo $LINE | cut -d',' -f5)
        SAVE=$(echo $LINE | cut -d',' -f6)
        
        printf " %-10s | %-15s | %-15s | %-10s | %-12s | %-12s\n" "$s%" "$BASE_E" "$PIM_E" "$SAVE" "$SPARSE" "$TOTAL"
    else
        printf " %-10s | %-15s | %-15s | %-10s | %-12s | %-12s\n" "$s%" "ERR" "ERR" "ERR" "ERR" "ERR"
    fi
done
echo "==================================================================================================="
