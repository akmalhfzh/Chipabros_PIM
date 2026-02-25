#!/bin/bash
SIM_DIR="sim"
LOG_DIR="logs"
OUTPUT_VVP="tb.vvp"
MICRON_DIR="micron_ddr3"
CSV_FILE="results_sweep_precise.csv"

mkdir -p "$SIM_DIR" "$LOG_DIR"

echo "🔨 [1/2] Compiling Verilog (TLM Model)..."
iverilog -g2012 -o "$SIM_DIR/$OUTPUT_VVP" \
  -I rtl -I "$MICRON_DIR" -Dden1024Mb -Dx8 -Dsg125 \
  rtl/ddr3_blackbox.v rtl/dram_controller_ddr3.v \
  rtl/pim_system_top.v rtl/pim_mac_engine.v \
  "$MICRON_DIR/ddr3.v" testbench/tb_pim_system.v

if [ $? -ne 0 ]; then exit 1; fi

echo "🚀 [2/2] Running Precision Sweep for AI Models (Row-Hit Aware)..."
echo " MODEL      | SPARSITY | BASE E(uJ) | Proposed Concept E(uJ) | SAVING | REAL ACT | REAL RD | SKIP "
echo "====================================================================================================="

# Siapkan Header CSV yang baru
echo "Model,Sparsity_Pct,Base_Energy_uJ,PIM_Energy_uJ,Saving_Pct,Base_ACT,Base_RD,PIM_ACT,PIM_RD,PIM_SKIP" > "$CSV_FILE"

# Looping sesuai dengan file yang lu punya di folder sim_cases
for MODEL in ResNet_50 BERT_NLP LLaMA3_8B GPT4_Sim; do
  for S in 0 25 50 75 85 90 95; do
    TRACE_FILE="sim_cases/meta_${MODEL}_${S}.hex"
    
    if [ ! -f "$TRACE_FILE" ]; then
      printf " %-10s | %-8s | FILE MISSING! \n" "$MODEL" "${S}%"
      continue
    fi

    cp "$TRACE_FILE" "$SIM_DIR/meta.hex"
    cd "$SIM_DIR"
    vvp "$OUTPUT_VVP" > "../$LOG_DIR/log_${MODEL}_${S}.txt"
    cd ..
    
    # INI YANG DIBENERIN: Hapus "../" karena kita udah ada di root directory
    LOG="$LOG_DIR/log_${MODEL}_${S}.txt"
    
    # Ekstraksi Presisi dari Verilog
    BASE_LINE=$(grep "^BASE_CMDS," "$LOG")
    DUT_LINE=$(grep "^DUT_CMDS," "$LOG")
    RES_LINE=$(grep "^RESULT," "$LOG")
    
    if [ -n "$BASE_LINE" ] && [ -n "$DUT_LINE" ]; then
      B_ACT=$(echo "$BASE_LINE" | grep -o "ACT=[0-9]*" | cut -d= -f2)
      B_RD=$(echo "$BASE_LINE" | grep -o "RD=[0-9]*" | cut -d= -f2)
      B_PIM_CYC=$(echo "$BASE_LINE" | grep -o "PIM_CYC=[0-9]*" | cut -d= -f2)
      
      D_ACT=$(echo "$DUT_LINE" | grep -o "ACT=[0-9]*" | cut -d= -f2)
      D_RD=$(echo "$DUT_LINE" | grep -o "RD=[0-9]*" | cut -d= -f2)
      D_SKIP=$(echo "$DUT_LINE" | grep -o "SKIP=[0-9]*" | cut -d= -f2)
      D_PIM_CYC=$(echo "$DUT_LINE" | grep -o "PIM_CYC=[0-9]*" | cut -d= -f2)
      
      TOTAL=$(echo "$RES_LINE" | cut -d, -f2)
      
      # Lempar ke Evaluator Python yang butuh 8 argumen
      POWER_DATA=$(python3 evaluate_power.py "$TOTAL" "$B_ACT" "$B_RD" "$B_PIM_CYC" "$D_ACT" "$D_RD" "$D_SKIP" "$D_PIM_CYC")
      
      BASE_E=$(echo "$POWER_DATA" | cut -d"," -f1)
      PIM_E=$(echo "$POWER_DATA" | cut -d"," -f2)
      SAVE=$(echo "$POWER_DATA" | cut -d"," -f3)
      
      printf " %-10s | %-8s | %-10s | %-20s | %-6s | %-8s | %-7s | %-5s\n" "$MODEL" "${S}%" "$BASE_E" "$PIM_E" "${SAVE}%" "$D_ACT" "$D_RD" "$D_SKIP"
      
      echo "${MODEL},${S},${BASE_E},${PIM_E},${SAVE},${B_ACT},${B_RD},${D_ACT},${D_RD},${D_SKIP}" >> "$CSV_FILE"
    else
      printf " %-10s | %-8s | ERR        | ERR       | ERR    | ERR      | ERR     | ERR\n" "$MODEL" "${S}%"
    fi
  done
  echo "---------------------------------------------------------------------------------------"
done
echo "✅ Data presisi (Row-Hit Aware) disimpan di: $CSV_FILE"
