import random
import os

# =============================================================================
# CONFIG
# =============================================================================
NUM_OPERATIONS   = 3000
SPARSITY_LEVELS  = [0.0, 0.25, 0.50, 0.75, 0.85, 0.90, 0.95]

# MEMORY MAP  (CHOICE B: move inputs further so program fits)
ADDR_INPUTS  = 0x40000
ADDR_WEIGHTS = 0x80000

WORDS_PER_BLOCK = 16  # 64B = 16 x 32-bit words

OUTPUT_DIR = "sim_cases"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# =============================================================================
# RISC-V encoding helpers (minimal)
# =============================================================================
def to_hex(val): return f"{val & 0xFFFFFFFF:08x}"

def instr_lui(rd, imm20):
    return to_hex(0x00000037 | (rd << 7) | ((imm20 & 0xFFFFF) << 12))

def instr_addi(rd, rs1, imm):
    return to_hex(0x00000013 | (rd << 7) | (rs1 << 15) | ((imm & 0xFFF) << 20))

def instr_lw(rd, rs1, imm):
    return to_hex(0x00002003 | (rd << 7) | (rs1 << 15) | ((imm & 0xFFF) << 20))

def instr_add(rd, rs1, rs2):
    return to_hex(0x00000033 | (rd << 7) | (rs1 << 15) | (rs2 << 20))

print("Generating Line-Sparse Testcases + Metadata (meta.hex)...")

for s in SPARSITY_LEVELS:
    fw_filename   = f"{OUTPUT_DIR}/firmware_sparse_{int(s*100)}.hex"
    meta_filename = f"{OUTPUT_DIR}/meta_sparse_{int(s*100)}.hex"

    mem_words = []

    # -------------------------------------------------------------------------
    # 1) Program (not used by our TB traffic generator, but OK to keep)
    # -------------------------------------------------------------------------
    prog = [
        instr_lui(1, ADDR_INPUTS  >> 12),   # x1 = base inputs
        instr_lui(2, ADDR_WEIGHTS >> 12),   # x2 = base weights
        instr_addi(3, 0, 0)                 # x3 = accumulator
    ]

    for _ in range(NUM_OPERATIONS):
        prog += [
            instr_lw(4, 1, 0),
            instr_lw(5, 2, 0),
            instr_add(3, 3, 4),
            instr_add(3, 3, 5),
            instr_addi(1, 1, 64),
            instr_addi(2, 2, 64)
        ]

    prog.append("0000006f")  # HALT / loop forever

    # Align to 16-word boundary
    while len(prog) % WORDS_PER_BLOCK != 0:
        prog.append("00000013")  # NOP

    mem_words.extend(prog)

    # -------------------------------------------------------------------------
    # 2) Pad until ADDR_INPUTS
    # -------------------------------------------------------------------------
    current_addr = len(mem_words) * 4
    if current_addr > ADDR_INPUTS:
        raise RuntimeError(
            f"Program too large: current_addr=0x{current_addr:x} > ADDR_INPUTS=0x{ADDR_INPUTS:x}. "
            "Increase ADDR_INPUTS or reduce NUM_OPERATIONS."
        )

    pad_needed = (ADDR_INPUTS - current_addr) // 4
    mem_words.extend(["00000000"] * pad_needed)

    # -------------------------------------------------------------------------
    # 3) Inputs + Meta
    # meta: 0 -> ZERO block (skip), 1 -> NONZERO (execute)
    # -------------------------------------------------------------------------
    meta_lines = []
    for _ in range(NUM_OPERATIONS):
        is_zero = (random.random() < s)
        meta_lines.append("0" if is_zero else "1")

        if is_zero:
            mem_words.extend(["00000000"] * WORDS_PER_BLOCK)
        else:
            mem_words.extend([to_hex(random.randint(1, 100)) for _ in range(WORDS_PER_BLOCK)])

    # -------------------------------------------------------------------------
    # 4) Pad until ADDR_WEIGHTS
    # -------------------------------------------------------------------------
    current_addr = len(mem_words) * 4
    if current_addr > ADDR_WEIGHTS:
        raise RuntimeError(
            f"Inputs too large: current_addr=0x{current_addr:x} > ADDR_WEIGHTS=0x{ADDR_WEIGHTS:x}. "
            "Increase ADDR_WEIGHTS or reduce NUM_OPERATIONS."
        )

    pad_needed = (ADDR_WEIGHTS - current_addr) // 4
    mem_words.extend(["00000000"] * pad_needed)

    # -------------------------------------------------------------------------
    # 5) Weights (dense)
    # -------------------------------------------------------------------------
    for _ in range(NUM_OPERATIONS * WORDS_PER_BLOCK):
        mem_words.append(to_hex(random.randint(1, 255)))

    # -------------------------------------------------------------------------
    # Write outputs
    # -------------------------------------------------------------------------
    with open(fw_filename, "w") as f:
        for w in mem_words:
            f.write(w + "\n")

    with open(meta_filename, "w") as f:
        for m in meta_lines:
            f.write(m + "\n")

    print(f"  [{int(s*100):>3}%] → {fw_filename} + {meta_filename}")

print("✅ Done. Hex files in 'sim_cases/'")