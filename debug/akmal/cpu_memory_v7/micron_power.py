import sys

# Parameter dari ddr3-ddr3l-power-calc.xlsm (DDR3-1600 1Gb x8)
VDD   = 1.5      # Volts
tCK   = 1.25     # ns (Clock period)
tRC   = 48.75    # ns (Row Cycle Time)
IDD0  = 40.0     # mA (Operating One Bank Active-Precharge)
IDD3N = 35.0     # mA (Active Standby)
IDD4R = 100.0    # mA (Operating Burst Read)

# Rumus Energi Excel Micron (uJ = V * I * t / 1e6) -> kita ubah ke pJ (PicoJoules)
# E_ACT = VDD * (IDD0 - IDD3N) * tRC
E_ACT_PJ = VDD * (IDD0 - IDD3N) * tRC  # 1.5 * 5 * 48.75 = 365.6 pJ

# E_RD = VDD * (IDD4R - IDD3N) * (Durasi 4 clock cycles untuk Burst Length 8)
E_RD_PJ  = VDD * (IDD4R - IDD3N) * (tCK * 4.0) # 1.5 * 65 * 5.0 = 487.5 pJ

E_MAC_PJ = 2.0  # Asumsi 2 pJ per MAC operation (28nm)

total_ops = int(sys.argv[1])
sparse_ops = int(sys.argv[2])
dense_ops = total_ops - sparse_ops

# Kalkulasi Base (Tanpa PIM)
base_dram_energy = (total_ops * E_ACT_PJ) + (total_ops * E_RD_PJ)
base_compute_energy = (total_ops * 16.0 * E_MAC_PJ)
base_total_uj = (base_dram_energy + base_compute_energy) / 1e6

# Kalkulasi dengan PIM
pim_dram_energy = (dense_ops * E_ACT_PJ) + (dense_ops * E_RD_PJ)
pim_compute_energy = (total_ops * 16.0 * E_MAC_PJ)
pim_total_uj = (pim_dram_energy + pim_compute_energy) / 1e6

saving = ((base_total_uj - pim_total_uj) / base_total_uj) * 100.0

print(f"{base_total_uj:.3f},{pim_total_uj:.3f},{saving:.2f}")
