#!/usr/bin/env python3
"""
gen_testcase.py - FIXED VERSION
================================
Bug fixes:
1. LUI x4: lui_val=1 bukan 0 → loop limit = 3000 (bukan 4 miliar)
2. WEIGHT_BASE=0x50000 bukan 0x20000 → di luar range PIM [0x10000,0x40000)
   sehingga LW weight tidak salah terhitung sebagai sparse

Memory layout:
  0x00000 - 0x0002C : Firmware (11 instruksi)
  0x10000 - 0x3EE80 : Input data (3000 x 64 bytes, dibaca CPU loop)
  0x40000 - 0x4007F : ESPIM Metadata bitmask (32 x 32bit = 1024 bit)
  0x50000 - 0x5BBFF : Weight data (3000 x 64 bytes, LUAR range PIM)
"""

import os, math

# === CONFIG ===
LOOP_COUNT    = 3000
DATA_BASE     = 0x10000   # Dalam range PIM → diintersep
WEIGHT_BASE   = 0x50000   # DI LUAR range PIM [0x10000,0x40000) → bypass langsung ke memori
META_ADDR     = 0x40000
SPARSITY_LIST = [0, 25, 50, 75, 85, 90, 95]
OUT_DIR       = "sim_cases"
MEM_WORDS     = 262144    # 1MB / 4

# === INSTRUCTION ENCODERS ===

def lui(rd, imm20):
    return (imm20 << 12) | (rd << 7) | 0x37

def addi(rd, rs1, imm12):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (rd << 7) | 0x13

def lw(rd, rs1, imm12):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (0b010 << 12) | (rd << 7) | 0x03

def bne(rs1, rs2, offset):
    o = offset & 0x1FFF
    return (((o>>12)&1)<<31) | (((o>>5)&0x3F)<<25) | (rs2<<20) | (rs1<<15) | \
           (0b001<<12) | (((o>>1)&0xF)<<8) | (((o>>11)&1)<<7) | 0x63

def jal(rd, offset):
    o = offset & 0x1FFFFF
    return (((o>>20)&1)<<31) | (((o>>12)&0xFF)<<12) | (((o>>11)&1)<<20) | \
           (((o>>1)&0x3FF)<<21) | (rd<<7) | 0x6F

# === FIRMWARE ===

def build_firmware():
    """
    Assembly:
      LUI  x1, DATA_BASE>>12       ; x1 = 0x10000
      LUI  x2, WEIGHT_BASE>>12     ; x2 = 0x50000 (LUAR range PIM!)
      ADDI x3, x0, 0               ; counter = 0
      LUI  x4, 1                   ; x4 = 0x1000 (BUG FIX: bukan 0!)
      ADDI x4, x4, -1096           ; x4 = 4096-1096 = 3000
    LOOP:
      LW   x5, 0(x1)               ; baca data → PIM gate berdasarkan bitmask
      LW   x6, 0(x2)               ; baca weight → bypass PIM (alamat di luar range)
      ADDI x1, x1, 64              ; data ptr += 64 byte (1 block 512-bit)
      ADDI x3, x3, 1               ; counter++
      BNE  x3, x4, LOOP            ; ulangi jika counter != 3000
      JAL  x0, 0                   ; infinite loop (selesai)
    """
    # LUI+ADDI encoding untuk 3000
    upper = (LOOP_COUNT + 0x800) >> 12  # = 1
    lower = LOOP_COUNT - (upper << 12)  # = 3000 - 4096 = -1096

    fw = [
        lui(1, DATA_BASE >> 12),    # 0x00: LUI x1, 0x10
        lui(2, WEIGHT_BASE >> 12),  # 0x04: LUI x2, 0x50  ← FIX
        addi(3, 0, 0),              # 0x08: ADDI x3, x0, 0
        lui(4, upper),              # 0x0C: LUI x4, 1     ← FIX
        addi(4, 4, lower),          # 0x10: ADDI x4, x4, -1096
    ]
    loop_pc = len(fw) * 4           # = 0x14

    fw += [
        lw(5, 1, 0),                # 0x14: LW x5, 0(x1)
        lw(6, 2, 0),                # 0x18: LW x6, 0(x2)
        addi(1, 1, 64),             # 0x1C: ADDI x1, x1, 64
        addi(3, 3, 1),              # 0x20: ADDI x3, x3, 1
    ]
    branch_pc = len(fw) * 4        # = 0x24
    fw += [
        bne(3, 4, loop_pc - branch_pc),  # 0x24: BNE x3, x4, -16
        jal(0, 0),                       # 0x28: JAL x0, 0
    ]
    return fw

# === METADATA ===

def build_metadata(sparsity_pct):
    n_sparse = int(math.ceil(LOOP_COUNT * sparsity_pct / 100.0))
    n_dense  = LOOP_COUNT - n_sparse
    # Blok 0..n_sparse-1 = sparse (0), blok n_sparse..2999 = dense (1)
    bits = [0] * n_sparse + [1] * n_dense

    words = []
    for w in range(128):  # 128 words x 32 bit = 4096 bit
        val = 0
        for b in range(32):
            idx = w * 32 + b
            if idx < len(bits):
                val |= (bits[idx] << b)
        words.append(val)
    return words

# === HEX WRITER ===

def write_hex(fname, firmware, metadata):
    mem = [0] * MEM_WORDS

    for i, w in enumerate(firmware):
        mem[i] = w

    # Data region: isi dengan nilai non-zero agar read tidak trivial
    dw = DATA_BASE // 4
    for i in range(LOOP_COUNT * 16):
        mem[dw + i] = (0xA5000000 | i) & 0xFFFFFFFF

    # Weight region: isi dengan nilai berbeda
    ww = WEIGHT_BASE // 4
    for i in range(LOOP_COUNT * 16):
        mem[ww + i] = (0xB6000000 | i) & 0xFFFFFFFF

    # Metadata di 0x40000
    mw = META_ADDR // 4
    for i, w in enumerate(metadata):
        mem[mw + i] = w

    with open(fname, 'w') as f:
        for w in mem:
            f.write(f"{w:08x}\n")

# === MAIN ===

if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)

    fw = build_firmware()

    print("=" * 55)
    print("Firmware:")
    for i, w in enumerate(fw):
        print(f"  0x{i*4:04x}: {w:08x}")

    # Validasi loop count
    upper = (fw[3] >> 12) & 0xFFFFF
    lower = (fw[4] >> 20) & 0xFFF
    if lower & 0x800: lower -= 0x1000
    actual = (upper << 12) + lower
    assert actual == LOOP_COUNT, f"Loop count mismatch: {actual} != {LOOP_COUNT}"
    print(f"Loop count: LUI({upper}) + ADDI({lower}) = {actual} ✓")

    # Validasi weight base di luar PIM range
    wb = (fw[1] >> 12) & 0xFFFFF  # LUI x2 upper 20 bits
    wb_addr = wb << 12
    assert not (0x10000 <= wb_addr < 0x40000), f"Weight 0x{wb_addr:X} masih dalam PIM range!"
    print(f"Weight base: 0x{wb_addr:05X} → di luar PIM range [0x10000,0x40000) ✓")
    print("=" * 55)

    print(f"\nGenerating Fixed Loop Testcases...")
    for s in SPARSITY_LIST:
        meta = build_metadata(s)
        n_sp = int(math.ceil(LOOP_COUNT * s / 100.0))
        out  = f"{OUT_DIR}/firmware_sparse_{s}.hex"
        write_hex(out, fw, meta)
        print(f"  [{s:3d}%] sparse={n_sp:4d} dense={LOOP_COUNT-n_sp:4d} → {out}")
    print(f"Done. Hex files in '{OUT_DIR}/'")
