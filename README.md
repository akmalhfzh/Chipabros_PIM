# 🧠 Micron PIM System - Sparsity Aware Accelerator (v4)

This repository contains the RTL (Register Transfer Level) simulation implementation for a **Processing-In-Memory (PIM)** system designed to exploit *Coarse-Grained Block Sparsity* in AI/Machine Learning workloads.

The system has evolved from passive data monitoring into an **Active PIM Controller** capable of **Controller-Level Zero-Skipping**, physically preventing DRAM access to achieve massive energy savings.

---

## ✨ Key Features (v4 Update)

1. **Controller-Level Address Gating (Check-then-Read)**
   The PIM system intercepts read requests from the host CPU at the AXI bus level. It checks an internal metadata table (*lookahead*); if a 512-bit block is detected as a sequence of zeros (*sparse*), the DRAM request (`ARVALID`) is **completely blocked**. This effectively saves the energy typically consumed by physical DRAM ACT (Activate) and RD (Read) commands.
2. **Local Zero Injection (Fake Ready)**
   For sparse data blocks, the PIM controller does not keep the CPU waiting. It instantly responds to the CPU with a Ready signal and returns a zero-filled payload. This drastically reduces memory access latency.
3. **Coarse-Grained Block Sparsity (512-bit)**
   The sparsity method is optimized for DRAM physics (specifically, a 64-Byte burst length). A single metadata bit dictates the fate of 16 consecutive words (512 bits), resulting in extremely low metadata overhead (<0.2%).
4. **Analytical Bitlet Energy Model**
   The architecture is integrated with a *Bitlet Model*-based performance monitor (referencing Horowitz 2014 & Newton 2020 data). It runs alongside the cycle-accurate RTL simulation to compute precise energy consumption metrics (*Active vs. Idle Energy*) and estimate thermal behavior.
5. **Model-Aware Profiling**
   The synthetic testcase generator emulates the *Structured Block Pruning* characteristics of real-world AI models such as **ResNet-50**, **BERT-Base**, and **LLaMA-2**, ensuring the architectural evaluation is academically rigorous and valid.

---

## 📂 Directory Structure

```text
.
├── rtl/                        # Hardware Verilog source code
│   ├── simple_riscv_cpu.v      # Host CPU that issues memory-mapped LW triggers
│   ├── simple_memory.v         # Behavioral DRAM model
│   ├── cpu_to_axi.v            # CPU memory interface to AXI4 adapter
│   ├── pim_sparsity_aware.v    # 🌟 CORE PIM: Controller with Address Gating & Fake Ready
│   ├── pim_perf_monitor.v      # 🌟 Bitlet Model & RC Thermal energy calculator
│   └── pim_system_top.v        # Top-Level module integrating the entire system
├── testbench/                  # Verification and simulation files
│   └── tb_pim_system.v         # Main testbench (clock generator & metadata backdoor loader)
├── gen_testcase.py             # Python script to generate Model-Aware firmware (.hex)
├── run_all.sh                  # Bash script for 1-click automated execution
├── Makefile                    # Makefile for manual compilation and simulation
└── README.md                   # This documentation
```

## 🚀 How to Run the Simulation
The easiest way to compile the RTL, generate the AI model data profiles, and run the benchmarks is by using the provided bash script:

```text
Bash
chmod +x run_all.sh
./run_all.sh
```

Execution Flow:
1. iverilog compiles all source files in the rtl/ and testbench/ directories.
2. gen_testcase.py generates data profiles (firmware) simulating the Gaussian weight distributions of ResNet, BERT, and LLaMA, subsequently applying magnitude-based block pruning.
3. The testbench executes the generated firmware within the cycle-accurate RTL architecture.
4. pim_perf_monitor.v captures cycle statistics (Active vs. Idle) and prints the calculated energy metrics to the console.


## 📊 Benchmark Output Example
Upon successful execution, the console will output the Bitlet Model metrics alongside a summary table based on the AI model profiles:

Plaintext
 MODEL           | BASE E (uJ)     | PIM E (uJ)      | SAVING     
======================================================================
 resnet-50       | 198.40          | 138.88          | 30.00 % 
 bert-base       | 198.40          | 79.36           | 60.00 % 
 llama-2         | 198.40          | 29.76           | 85.00 % 
 ideal-case      | 198.40          | 9.92            | 95.00 % 
BASE E: The total energy consumed if a standard CPU continually accesses Off-Chip DRAM without any PIM intervention.

PIM E: The actual energy consumed by the PIM system (a combination of physical DRAM access for dense data and lightweight metadata checking/gating for sparse data).

SAVING: The percentage of energy saved thanks to the Controller-Level Zero-Skipping mechanism. Higher sparsity models (like LLaMA) yield greater savings.
