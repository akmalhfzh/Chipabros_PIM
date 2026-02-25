# 🧠 Hybrid Trace-Driven PIM Co-Simulation Framework

![Simulation Status](https://img.shields.io/badge/Simulation-Cycle_Accurate-success)
![Power Model](https://img.shields.io/badge/Power_Model-Micron_DDR3-blue)
![Architecture](https://img.shields.io/badge/Architecture-Processing_In_Memory-orange)

An industry-grade, hybrid trace-driven co-simulation framework for evaluating **Processing-In-Memory (PIM)** architectures against conventional Von Neumann architectures (CPU/GPU + DRAM). This framework accurately measures energy consumption by combining real-world AI workload extraction, cycle-accurate RTL simulation, and discrete event-based analytical power modeling.



## ✨ Key Features

1. **Real-World AI Workloads**: Extracts memory traces from state-of-the-art Neural Networks (`ResNet-50`, `BERT_NLP`, `LLaMA3_8B`, `GPT4_Sim`) using magnitude pruning while preserving spatial locality.
2. **Row-Hit Aware RTL Simulation**: The Verilog testbench doesn't just guess memory accesses. It maintains a "Shadow Model" to track exact physical Row Activations (ACT) and Column Reads (RD) dynamically based on row-hit/miss probability.
3. **Zero-Value Skipping**: The PIM Engine actively skips memory fetching for zero-value data, drastically reducing memory bandwidth and energy.
4. **Micron Analytical Power Model**: Energy is calculated using an object-oriented Python power model reverse-engineered from the official **Micron DDR3 Power Calculator (Rev 1.02)**.
5. **Fair Compute Penalties**: Includes a conservative 2.0 pJ/MAC penalty for in-memory logic computation, grounded in standard CMOS literature (Horowitz, ISSCC 2014).

## 📂 Repository Structure

* `run_all.sh` / `run_all.bat` : Master orchestrator script.
* `gen_real_trace.py` : Generates AI memory traces (0% - 95% sparsity).
* `tb_pim_system.v` : Cycle-accurate Verilog Testbench (generates `BASE_CMDS` & `DUT_CMDS`).
* `pim_system_top.v` : Top-level RTL for the Processing-In-Memory engine.
* `dram_controller_ddr3.v` : TLM DRAM Controller.
* `evaluate_power.py` : Calculates absolute energy ($\mu J$) based on precise physical counters.
* `ddr3_power_calc.py` : Physics database containing Micron's exact IDD current values and timing parameters.

## 🛠️ Prerequisites

To run this simulation framework, ensure you have the following installed:
* **Icarus Verilog (`iverilog` & `vvp`)**: For TLM RTL Simulation.
* **Python 3.8+**: For trace generation and analytical power calculation.
* **Python Libraries**: `numpy`

## 🚀 How to Run

1. Clone this repository and navigate to the project directory:
   ```bash
   cd cpu_memory_v9
   ```
2. Make the orchestrator script executable (Linux/macOS):
   ```bash
   chmod +x run_all.sh
   ```
4. Execute the full simulation pipeline:
   ```bash
   ./run_all.sh
   ```

## 📊 Outputs
The script will sweep through various AI models and sparsity levels, extracting exact hardware counters and calculating energy. 
The results are automatically appended to: results_sweep_precise.csv

## 🔬 Simulation Pipeline Methodology
Our hybrid co-simulation runs in 4 distinct phases:

Software Domain: gen_real_trace.py creates HEX files acting as instruction memory traces based on the specific distribution curves of modern AI architectures.

Hardware Domain: Icarus Verilog simulates the transaction layer, evaluating both a standard CPU memory access pattern (Baseline) and the PIM architecture (DUT) cycle-by-cycle.

Physics Domain: Python scripts query the Verilog log for exact ACT, PRE, RD, and SKIP counters.

Energy Domain: evaluate_power.py applies Micron's VDD and IDD parameters to the counters, producing an undeniable, hardware-backed energy consumption report.
EOF
