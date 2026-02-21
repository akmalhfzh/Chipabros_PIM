#!/bin/bash
SIM_DIR="sim_v7"
LOG_DIR="logs_v7"
OUTPUT_VVP="tb.vvp"
MICRON_DIR="micron_ddr3"

mkdir -p "$SIM_DIR" "$LOG_DIR"

echo "🔨 [1/3] Compiling Verilog (TLM Model)..."
iverilog -g2012 -o "$SIM_DIR/$OUTPUT_VVP" \
  -I rtl_v7 -I "$MICRON_DIR" -Dden1024Mb -Dx8 -Dsg25 \
  rtl_v7/ddr3_blackbox.v rtl_v7/dram_controller_ddr3.v \
  rtl_v7/pim_system_top.v rtl_v7/pim_mac_engine.v \
  "$MICRON_DIR/ddr3.v" tb_v7/tb_pim_system.v

if [ $? -ne 0 ]; then exit 1; fi

echo "🎲 [2/3] Extracting Benchmark Workloads (NumPy)..."
python3 gen_real_trace.py

echo "🚀 [3/3] Running PIM Benchmark (Micron Excel OOP Power Logic)..."
echo " AI MODEL   | BASE E (uJ) | PIM E (uJ) | SAVING | SPARSE PKTS | TOTAL PKTS"
echo "========================================================================================"

for MODEL in Baseline ResNet_50 BERT_NLP LLaMA3_8B GPT4_Sim; do
  cp "sim_cases/meta_${MODEL}.hex" "$SIM_DIR/meta.hex"
  cd "$SIM_DIR"
  vvp "$OUTPUT_VVP" > "../$LOG_DIR/log_${MODEL}.txt"
  cd ..
  
  LINE=$(grep "^RESULT," "$LOG_DIR/log_${MODEL}.txt")
  if [ -n "$LINE" ]; then
    TOTAL=$(echo "$LINE" | cut -d"," -f2)
    SPARSE=$(echo "$LINE" | cut -d"," -f3)
    
    # Manggil logic python lu!
    POWER_DATA=$(python3 evaluate_power.py "$TOTAL" "$SPARSE")
    BASE_E=$(echo "$POWER_DATA" | cut -d"," -f1)
    PIM_E=$(echo "$POWER_DATA" | cut -d"," -f2)
    SAVE=$(echo "$POWER_DATA" | cut -d"," -f3)
    
    printf " %-10s | %-11s | %-10s | %-6s | %-11s | %-10s\n" "${MODEL}" "$BASE_E" "$PIM_E" "${SAVE}%" "$SPARSE" "$TOTAL"
  else
    printf " %-10s | ERR         | ERR        | ERR    | ERR         | ERR\n" "${MODEL}"
  fi
done
