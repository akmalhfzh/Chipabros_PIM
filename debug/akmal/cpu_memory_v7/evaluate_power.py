import sys
from ddr3_power_calc import DDR3PowerCalc, DDR3Spec, SystemConfig, energy_from_counters

TOTAL = int(sys.argv[1])
SPARSE = int(sys.argv[2])
DENSE = TOTAL - SPARSE

# Konfigurasi sistem PIM Lu
spec = DDR3Spec(density="4Gb", speed_grade="-093", dq_width=16, is_ddr3l=True)
sys_cfg = SystemConfig(vdd=1.35, freq_mhz=533, burst_length=8)
calc = DDR3PowerCalc(spec, sys_cfg)
res = calc.run()

# Masukkan ke estimator PIM punya lu
energy = energy_from_counters(
    res, act_count=DENSE, rd_count=DENSE, wr_count=0, 
    pre_count=DENSE, skip_count=SPARSE, sim_cycles=TOTAL * 10, clk_freq_mhz=533
)

base_dram_uJ = energy["E_total_pJ"] / 1e6
saved_dram_uJ = energy["E_saved_pJ"] / 1e6
pim_dram_uJ = base_dram_uJ - saved_dram_uJ

compute_uJ = (TOTAL * 16.0 * 2.0) / 1e6
base_total = base_dram_uJ + compute_uJ
pim_total = pim_dram_uJ + compute_uJ
saving = (base_total - pim_total) / base_total * 100.0 if base_total > 0 else 0

print(f"{base_total:.3f},{pim_total:.3f},{saving:.2f}")
