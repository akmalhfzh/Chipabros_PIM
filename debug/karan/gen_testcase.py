import os
import random

NUM_OPERATIONS = 3000
SPARSITY_LEVELS = [0,25,50,75,85,90,95]

ADDR_INPUTS = 0x40000   # base
ROW_STRIDE  = 0x2000    # 8KB per row
LINE_SIZE   = 64
LINES_PER_ROW = 128     # 8KB / 64B

os.makedirs("sim_cases", exist_ok=True)

print("Generating Line-Sparse Testcases + Metadata (meta.hex)...")

for sp in SPARSITY_LEVELS:

    sparse_count = int(NUM_OPERATIONS * sp / 100)

    meta = [1]*sparse_count + [0]*(NUM_OPERATIONS - sparse_count)
    random.shuffle(meta)

    firmware = []
    addr_base = ADDR_INPUTS
    line_index = 0

    for i in range(NUM_OPERATIONS):

        # ping pong row 0 and row 1
        if i % 2 == 0:
            current_addr = addr_base + (line_index * LINE_SIZE)
        else:
            current_addr = addr_base + ROW_STRIDE + (line_index * LINE_SIZE)

        firmware.append(f"{current_addr:08x}")

        line_index += 1
        if line_index >= LINES_PER_ROW:
            line_index = 0

    # write firmware
    with open(f"sim_cases/firmware_sparse_{sp}.hex","w") as f:
        for line in firmware:
            f.write(line+"\n")

    # write meta
    with open(f"sim_cases/meta_sparse_{sp}.hex","w") as f:
        for m in meta:
            f.write(f"{m}\n")

    print(f"  [{sp:3d}%] → firmware + meta generated")

print("Done.")