import sys
from ddr3_power_calc import DDR3PowerCalc, DDR3Spec, SystemConfig

TOTAL      = int(sys.argv[1])
B_ACT      = int(sys.argv[2])
B_RD       = int(sys.argv[3])
B_PIM_CYC  = int(sys.argv[4])
D_ACT      = int(sys.argv[5])
D_RD       = int(sys.argv[6])
D_SKIP     = int(sys.argv[7])
D_PIM_CYC  = int(sys.argv[8])

spec    = DDR3Spec(density="1Gb", speed_grade="-125", dq_width=8, is_ddr3l=False)
sys_cfg = SystemConfig(vdd=1.5, freq_mhz=800, burst_length=8)
calc    = DDR3PowerCalc(spec, sys_cfg)
res     = calc.run()

VDD = sys_cfg.vdd
IDD0 = spec.get_idd("IDD0")
IDD3N = spec.get_idd("IDD3N")
IDD4R = spec.get_idd4r()
tRC = spec.get_timing("tRC")
tCK = 1000.0 / sys_cfg.freq_mhz

E_ACT_pJ = VDD * (IDD0 - IDD3N) * tRC
E_RD_pJ  = VDD * (IDD4R - IDD3N) * (tCK * 4)
E_MAC_pJ = 2.0  # Asumsi 2 pJ per operasi MAC di dalam silikon PIM

# Menghitung Energi Baseline (Tanpa PIM)
base_dram_pJ  = (B_ACT * E_ACT_pJ) + (B_RD * E_RD_pJ)
base_comp_pJ  = B_PIM_CYC * E_MAC_pJ
base_total_uJ = (base_dram_pJ + base_comp_pJ) / 1e6

# Menghitung Energi DUT (Dengan PIM)
pim_dram_pJ   = (D_ACT * E_ACT_pJ) + (D_RD * E_RD_pJ)
pim_comp_pJ   = D_PIM_CYC * E_MAC_pJ
pim_total_uJ  = (pim_dram_pJ + pim_comp_pJ) / 1e6

saving = 0.0
if base_total_uJ > 0:
    saving = (base_total_uJ - pim_total_uJ) / base_total_uJ * 100.0

# Mengirim output pakai CSV string ke bash script
print(f"{base_total_uJ:.3f},{pim_total_uJ:.3f},{saving:.2f}")
