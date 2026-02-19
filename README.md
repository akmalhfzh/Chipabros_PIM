# PIM Memory System - Standalone Version

## 🎯 Overview

Sistem **Processing-in-Memory (PIM)** yang sparsity-aware untuk mengurangi energi fetch pada workload AI/Neural Network. 

**STANDALONE** - Tidak perlu download PicoRV32, LiteDRAM, atau Verilog-AXI!

## ✨ Komponen

- **CPU**: Simplified RISC-V core (built-in)
- **Memory**: Simple DDR-like model (built-in)
- **PIM**: Sparsity-aware processing module
- **Interconnect**: AXI4 adapter

## 🚀 Quick Start

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt-get install iverilog gtkwave

# macOS
brew install icarus-verilog gtkwave
```

### Running Simulation

```bash
# Clone/extract project
cd pim_memory_system

# Run simulation
make sim

# View waveform
make view
```

**Output yang diharapkan:**
```
========================================
PIM Memory System Test
========================================

[INFO] Running CPU program...

========================================
RESULTS
========================================
Configuration      | Cycles | Sparse | Total | Energy
--------------------------------------------------------
Baseline (no PIM)  |   5000 |      0 |     0 |     0%
PIM-enabled        |   5000 |    112 |   160 |    70%
--------------------------------------------------------

✓ PIM successfully detected sparsity!
  Energy savings: 70%

========================================
TEST PASSED
========================================
```

## 📁 Structure

```
pim_memory_system/
├── rtl/
│   ├── simple_riscv_cpu.v      # Simplified RISC-V CPU
│   ├── cpu_to_axi.v            # CPU to AXI adapter
│   ├── pim_sparsity_aware.v    # PIM module (CORE)
│   ├── simple_memory.v         # Memory model
│   └── pim_system_top.v        # Top integration
├── testbench/
│   └── tb_pim_system.v         # Testbench
├── Makefile
└── README.md
```

## 🔬 How It Works

### Architecture

```
Baseline Mode (ENABLE_PIM=0):
CPU → AXI Adapter → Memory

PIM Mode (ENABLE_PIM=1):
CPU → AXI Adapter → PIM → Memory
                     ↓
                Sparsity Detection
                (70% energy saved!)
```

### PIM Operation

1. CPU requests data
2. Request goes through PIM
3. PIM forwards to memory
4. Memory returns 512-bit data
5. PIM detects zero chunks
6. Statistics updated
7. Data forwarded to CPU

## 🎓 What's Included

### CPU (simple_riscv_cpu.v)
- Basic RISC-V instruction set
- LUI, ADDI, ADD, SUB, LW, SW, JAL
- Built-in test program
- Memory loop execution

### PIM (pim_sparsity_aware.v)
- 32-bit granularity detection
- Real-time bitmap generation
- Energy savings calculation
- AXI4 pass-through

### Memory (simple_memory.v)
- Pre-initialized with sparse data
- DDR-like latency (CAS = 10 cycles)
- 1MB size

## 📊 Expected Results

CPU akan menjalankan program loop yang:
1. Load data dari memory (sparse ~70%)
2. Store data kembali
3. Increment address
4. Repeat

PIM akan detect:
- ~70% data adalah zero
- ~70% energy savings
- Sama cycle count (minimal overhead)

## 🔧 Configuration

### Enable/Disable PIM

Edit `rtl/pim_system_top.v`:
```verilog
pim_system_top #(
    .ENABLE_PIM(1)  // 1=enable, 0=disable
) dut (
    // ...
);
```

### Change Sparsity Level

Edit `rtl/simple_memory.v` line ~50:
```verilog
if ($random % 10 < 3) begin  // 30% non-zero (70% sparse)
    // Change to:
    // < 1  → 10% non-zero (90% sparse)
    // < 5  → 50% non-zero (50% sparse)
    // < 9  → 90% non-zero (10% sparse)
```

## 🐛 Troubleshooting

**Error: "command not found: iverilog"**
```bash
sudo apt-get install iverilog
```

**Simulation hangs**
- Check timeout (default 1ms)
- Verify clock generation
- Check reset timing

**No sparsity detected**
- Memory initialized correctly?
- PIM enabled?
- CPU actually accessing memory?

## 📖 Learn More

1. **rtl/pim_sparsity_aware.v** - Understand sparsity detection
2. **rtl/simple_riscv_cpu.v** - See CPU implementation
3. **testbench/tb_pim_system.v** - Learn testing methodology

## 🎯 Next Steps

1. ✅ Run simulation successfully
2. ✅ Understand results
3. 📝 Modify sparsity level
4. 📝 Change CPU program
5. 📝 Add more statistics
6. 🚀 Integrate real PicoRV32 (optional)
7. 🚀 Add compression (optional)

## 💡 Educational Value

Sistem ini demonstrate:
- ✅ Basic CPU operation
- ✅ Memory controller design
- ✅ AXI4 protocol
- ✅ Processing-in-Memory concept
- ✅ Energy-efficient computing
- ✅ Sparse data handling

Perfect untuk:
- Computer architecture students
- Hardware design learners
- PIM researchers
- AI acceleration enthusiasts

## 📄 License

Standalone implementation - free to use and modify.

No external dependencies means no license conflicts!

---

**Made with ❤️ for learning and research**
