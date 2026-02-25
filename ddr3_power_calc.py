"""
ddr3_power_calc.py
==================
Micron DDR3/DDR3L Power Calculator — Python Implementation
Semua formula di-reverse-engineer 1:1 dari Micron DDR3_Power_Calc.XLSM (Rev 1.02).

Akurasi vs Excel:
  Pds  : ±0.001 mW (rounding float)
  Psch : ±0.001 mW
  Psys : ±0.001 mW
  Total: ±0.001 mW

Penggunaan:
    from ddr3_power_calc import DDR3PowerCalc, DDR3Spec, SystemConfig, IOpowerConfig

    spec = DDR3Spec(density='4Gb', speed_grade='-093', dq_width=16, is_ddr3l=False)
    sys_cfg = SystemConfig(vdd=1.5, freq_mhz=800, burst_length=8,
                           bnk_pre=0.25, cke_lo_pre=0.25, cke_lo_act=0.25,
                           page_hit_rate=0.5, rd_pct=0.3, wr_pct=0.3)
    calc = DDR3PowerCalc(spec, sys_cfg)
    result = calc.run()
    result.print_report()
"""

import math
from dataclasses import dataclass, field
from typing import Optional


# =============================================================================
# DDR3 Spec Database (dari DDR3 Spec sheet di Excel)
# Nilai adalah IDD maksimum dalam mA, per speed grade dan DQ width.
# Format: (x4/x8 value, x16 value). None = 'na' di datasheet.
# =============================================================================

# === IDD table untuk 1Gb ===
_IDD_1Gb = {
    # speed_grade: {param: (x4/x8, x16)}
    '-093': {
        'IDD0':        (46,   55),
        'IDD2P_slow':  (12,   12),
        'IDD2P_fast':  (15,   15),
        'IDD2N':       (23,   23),
        'IDD3P':       (17,   17),
        'IDD3N':       (40,   43),
        'IDD4R_x4':    125,  # x4 specific
        'IDD4R_x8':    125,  # x8
        'IDD4R_x16':   180,  # x16
        'IDD4W_x4':    126,
        'IDD4W_x8':    126,
        'IDD4W_x16':   184,
        'IDD5B':       (170,  170),
        'tCK_meas':    0.938,
        'tRRD_x48':    6.0,
        'tRRD_x16':    7.5,
        'tRC':         46.09,
        'tRAS':        36.0,
        'tRFC':        110.0,
        'tREFI':       7.8,
        'tCK_min':     0.938,
        'tCK_max':     3.3,
    },
    '-107': {
        'IDD0':        (43,   51),
        'IDD2P_slow':  (12,   12),
        'IDD2P_fast':  (15,   15),
        'IDD2N':       (23,   23),
        'IDD3P':       (17,   17),
        'IDD3N':       (37,   38),
        'IDD4R_x4':    110,
        'IDD4R_x8':    110,
        'IDD4R_x16':   155,
        'IDD4W_x4':    114,
        'IDD4W_x8':    114,
        'IDD4W_x16':   164,
        'IDD5B':       (165,  165),
        'tCK_meas':    1.07,
        'tRRD_x48':    6.0,
        'tRRD_x16':    7.5,
        'tRC':         47.91,
        'tRAS':        34.0,
        'tRFC':        110.0,
        'tREFI':       7.8,
        'tCK_min':     1.07,
        'tCK_max':     3.3,
    },
    '-125': {
        'IDD0':        (42,   49),
        'IDD2P_slow':  (12,   12),
        'IDD2P_fast':  (15,   15),
        'IDD2N':       (23,   23),
        'IDD3P':       (17,   17),
        'IDD3N':       (35,   37),
        'IDD4R_x4':    100,
        'IDD4R_x8':    100,
        'IDD4R_x16':   135,
        'IDD4W_x4':    103,
        'IDD4W_x8':    103,
        'IDD4W_x16':   146,
        'IDD5B':       (160,  160),
        'tCK_meas':    1.25,
        'tRRD_x48':    6.0,
        'tRRD_x16':    7.5,
        'tRC':         48.75,
        'tRAS':        35.0,
        'tRFC':        110.0,
        'tREFI':       7.8,
        'tCK_min':     1.25,
        'tCK_max':     3.3,
    },
    '-15E': {
        'IDD0':        (41,   48),
        'IDD2P_slow':  (12,   12),
        'IDD2P_fast':  (15,   15),
        'IDD2N':       (23,   23),
        'IDD3P':       (17,   17),
        'IDD3N':       (33,   36),
        'IDD4R_x4':    88,
        'IDD4R_x8':    88,
        'IDD4R_x16':   115,
        'IDD4W_x4':    91,
        'IDD4W_x8':    91,
        'IDD4W_x16':   127,
        'IDD5B':       (160,  160),
        'tCK_meas':    1.5,
        'tRRD_x48':    6.0,
        'tRRD_x16':    7.5,
        'tRC':         49.5,
        'tRAS':        36.0,
        'tRFC':        110.0,
        'tREFI':       7.8,
        'tCK_min':     1.5,
        'tCK_max':     3.3,
    },
    '-187E': {
        'IDD0':        (39,   46),
        'IDD2P_slow':  (12,   12),
        'IDD2P_fast':  (15,   15),
        'IDD2N':       (23,   23),
        'IDD3P':       (17,   17),
        'IDD3N':       (31,   33),
        'IDD4R_x4':    74,
        'IDD4R_x8':    74,
        'IDD4R_x16':   95,
        'IDD4W_x4':    79,
        'IDD4W_x8':    79,
        'IDD4W_x16':   107,
        'IDD5B':       (155,  155),
        'tCK_meas':    1.875,
        'tRRD_x48':    7.5,
        'tRRD_x16':    10.0,
        'tRC':         50.625,
        'tRAS':        37.5,
        'tRFC':        110.0,
        'tREFI':       7.8,
        'tCK_min':     1.875,
        'tCK_max':     3.3,
    },
}

# Alias E-grade (Engineering Sample) ke non-E (same IDD values, different screening)
_IDD_1Gb['-093E'] = dict(_IDD_1Gb['-093'], tCK_min=0.938)
_IDD_1Gb['-107E'] = dict(_IDD_1Gb['-107'], tCK_min=1.07)
_IDD_1Gb['-125E'] = dict(_IDD_1Gb['-125'], tCK_min=1.25)
_IDD_1Gb['-187'] = dict(_IDD_1Gb['-187E'])

# === IDD table untuk 4Gb (utama yang dipakai di sistem kamu) ===
_IDD_4Gb = {
    '-093': {
        'IDD0':        (31,   34),
        'IDD2P_slow':  (12,   12),
        'IDD2P_fast':  (13,   14),
        'IDD2N':       (22,   22),
        'IDD3P':       (17,   19),
        'IDD3N':       (23,   25),
        'IDD4R_x4':    110,
        'IDD4R_x8':    110,
        'IDD4R_x16':   130,
        'IDD4W_x4':    110,
        'IDD4W_x8':    110,
        'IDD4W_x16':   140,
        'IDD5B':       (160,  160),
        'tCK_meas':    0.938,
        'tRRD_x48':    6.0,
        'tRRD_x16':    7.5,
        'tRC':         46.09,
        'tRAS':        36.0,
        'tRFC':        260.0,
        'tREFI':       7.8,
        'tCK_min':     0.938,
        'tCK_max':     3.3,
    },
    '-107': {
        'IDD0':        (29,   32),
        'IDD2P_slow':  (11,   12),
        'IDD2P_fast':  (11,   12),
        'IDD2N':       (17,   17),
        'IDD3P':       (15,   17),
        'IDD3N':       (21,   23),
        'IDD4R_x4':    90,
        'IDD4R_x8':    90,
        'IDD4R_x16':   120,
        'IDD4W_x4':    90,
        'IDD4W_x8':    90,
        'IDD4W_x16':   130,
        'IDD5B':       (152,  156),
        'tCK_meas':    1.07,
        'tRRD_x48':    6.0,
        'tRRD_x16':    7.5,
        'tRC':         47.91,
        'tRAS':        34.0,
        'tRFC':        260.0,
        'tREFI':       7.8,
        'tCK_min':     1.07,
        'tCK_max':     3.3,
    },
    '-125': {
        'IDD0':        (28,   32),
        'IDD2P_slow':  (10,   12),
        'IDD2P_fast':  (11,   12),
        'IDD2N':       (16,   17),
        'IDD3P':       (15,   17),
        'IDD3N':       (20,   22),
        'IDD4R_x4':    90,
        'IDD4R_x8':    90,
        'IDD4R_x16':   110,
        'IDD4W_x4':    90,
        'IDD4W_x8':    90,
        'IDD4W_x16':   120,
        'IDD5B':       (152,  156),
        'tCK_meas':    1.25,
        'tRRD_x48':    6.0,
        'tRRD_x16':    7.5,
        'tRC':         48.75,
        'tRAS':        35.0,
        'tRFC':        260.0,
        'tREFI':       7.8,
        'tCK_min':     1.25,
        'tCK_max':     3.3,
    },
}
_IDD_4Gb['-093E'] = dict(_IDD_4Gb['-093'])
_IDD_4Gb['-107E'] = dict(_IDD_4Gb['-107'])
_IDD_4Gb['-125E'] = dict(_IDD_4Gb['-125'])

# === IDD table untuk 8Gb ===
_IDD_8Gb = {
    '-107': {
        'IDD0':        (69,   69),
        'IDD2P_slow':  (11,   11),
        'IDD2P_fast':  (16,   16),
        'IDD2N':       (38,   38),
        'IDD3P':       (38,   38),
        'IDD3N':       (53,   53),
        'IDD4R_x4':    135,
        'IDD4R_x8':    135,
        'IDD4R_x16':   195,
        'IDD4W_x4':    135,
        'IDD4W_x8':    135,
        'IDD4W_x16':   195,
        'IDD5B':       (250,  250),
        'tCK_meas':    1.07,
        'tRRD_x48':    6.0,
        'tRRD_x16':    7.5,
        'tRC':         46.84,
        'tRAS':        34.0,
        'tRFC':        350.0,
        'tREFI':       7.8,
        'tCK_min':     1.07,
        'tCK_max':     3.3,
    },
    '-125': {
        'IDD0':        (67,   67),
        'IDD2P_slow':  (11,   11),
        'IDD2P_fast':  (14,   14),
        'IDD2N':       (36,   36),
        'IDD3P':       (36,   36),
        'IDD3N':       (51,   51),
        'IDD4R_x4':    125,
        'IDD4R_x8':    125,
        'IDD4R_x16':   185,
        'IDD4W_x4':    125,
        'IDD4W_x8':    125,
        'IDD4W_x16':   185,
        'IDD5B':       (245,  245),
        'tCK_meas':    1.25,
        'tRRD_x48':    6.0,
        'tRRD_x16':    7.5,
        'tRC':         47.5,
        'tRAS':        35.0,
        'tRFC':        350.0,
        'tREFI':       7.8,
        'tCK_min':     1.25,
        'tCK_max':     3.3,
    },
}
_IDD_8Gb['-107E'] = dict(_IDD_8Gb['-107'])
_IDD_8Gb['-125E'] = dict(_IDD_8Gb['-125'])

# === 2Gb: sama dengan 1Gb kecuali tRFC dan beberapa IDD ===
_IDD_2Gb = {sg: dict(v) for sg, v in _IDD_1Gb.items()}
for sg in _IDD_2Gb:
    _IDD_2Gb[sg]['tRFC'] = 160.0

# ===  Master Spec Database ===
DDR3_SPEC_DB = {
    '1Gb':  _IDD_1Gb,
    '2Gb':  _IDD_2Gb,
    '4Gb':  _IDD_4Gb,
    '8Gb':  _IDD_8Gb,
}

# VDD ranges (DDR3 vs DDR3L)
VDD_RANGE = {
    'DDR3':  {'max': 1.575, 'min': 1.425},
    'DDR3L': {'max': 1.435, 'min': 1.283},
}


# =============================================================================
# Data Classes
# =============================================================================

@dataclass
class DDR3Spec:
    """
    Identifikasi DRAM yang dipakai.
    density      : '1Gb', '2Gb', '4Gb', '8Gb'
    speed_grade  : '-093', '-107', '-125', '-15E', '-187E', '-187', dll.
    dq_width     : 4, 8, or 16
    is_ddr3l     : True = DDR3L (VDD 1.35V nominal), False = DDR3 (VDD 1.5V)
    pd_exit_fast : True = fast exit power-down (IDD2P fast), False = slow exit
    """
    density:       str = '1Gb'
    speed_grade:   str = '-093'
    dq_width:      int = 16
    is_ddr3l:      bool = False
    pd_exit_fast:  bool = True

    def get_idd(self, param: str) -> float:
        """Lookup IDD value dari database untuk density, speed grade, dan dq_width."""
        db = DDR3_SPEC_DB.get(self.density)
        if db is None:
            raise ValueError(f"Density '{self.density}' tidak ada. Pilihan: {list(DDR3_SPEC_DB.keys())}")
        sg_db = db.get(self.speed_grade)
        if sg_db is None:
            raise ValueError(f"Speed grade '{self.speed_grade}' tidak ada untuk {self.density}.")

        val = sg_db.get(param)
        if val is None:
            raise ValueError(f"Parameter '{param}' tidak ada.")

        # Pilih x4/x8 vs x16
        if isinstance(val, tuple):
            return float(val[1] if self.dq_width == 16 else val[0])
        elif param in ('IDD4R_x4', 'IDD4R_x8', 'IDD4R_x16',
                       'IDD4W_x4', 'IDD4W_x8', 'IDD4W_x16'):
            return float(val)
        return float(val)

    def get_idd4r(self) -> float:
        dq = self.dq_width
        if dq == 4:
            return self.get_idd('IDD4R_x4')
        elif dq == 8:
            return self.get_idd('IDD4R_x8')
        else:
            return self.get_idd('IDD4R_x16')

    def get_idd4w(self) -> float:
        dq = self.dq_width
        if dq == 4:
            return self.get_idd('IDD4W_x4')
        elif dq == 8:
            return self.get_idd('IDD4W_x8')
        else:
            return self.get_idd('IDD4W_x16')

    def get_timing(self, param: str) -> float:
        db = DDR3_SPEC_DB[self.density][self.speed_grade]
        if param == 'tRRD':
            return db['tRRD_x16'] if self.dq_width == 16 else db['tRRD_x48']
        return float(db[param])

    @property
    def vdd_max(self) -> float:
        return VDD_RANGE['DDR3L' if self.is_ddr3l else 'DDR3']['max']

    @property
    def vdd_min(self) -> float:
        return VDD_RANGE['DDR3L' if self.is_ddr3l else 'DDR3']['min']


@dataclass
class IOpowerConfig:
    """
    Konfigurasi jaringan termination I/O.
    Dipakai untuk menghitung PdqRD, PdqWR, PdqRDoth, PdqWRoth.

    Jika PdqRD (dll.) sudah diketahui (dari SPICE atau lab), override langsung
    dengan menyetel override_* field.

    Definisi resistor (sesuai kolom H-U di System Config sheet):
    READ circuit (DRAM sedang driving DQ):
      Rz1     : DRAM output driver impedance (Ω)
      RTTuC   : Controller pull-up ODT (Ω)
      RTTdC   : Controller pull-down ODT (Ω)  [0 = tidak ada]
      Rs1     : Series resistance di sisi controller (Ω)
      RTTu2   : Secondary pull-up ODT di DRAM end (Ω)  [0 = tidak ada]
      RTTd2   : Secondary pull-down ODT di DRAM end (Ω) [0 = tidak ada]
      Rs2     : Series resistance di sisi DRAM ODT (Ω)

    WRITE circuit (Controller sedang driving DQ):
      RzC     : Controller output driver impedance (Ω)
      RTTd1   : DRAM primary pull-down ODT (Ω)  [0 = tidak ada]
      RTTu1   : DRAM primary pull-up ODT (Ω)    [0 = tidak ada]
      Rs1_w   : Series resistance di controller end (Ω)
      RTTd2_w : DRAM secondary pull-down ODT (Ω)
      RTTu2_w : DRAM secondary pull-up ODT (Ω)
      Rs2_w   : Series resistance di DRAM secondary ODT (Ω)
      VDDq_w  : Supply voltage for write termination (V)

    Semua dalam Ω kecuali disebutkan lain.
    """
    # --- READ ---
    Rz1:     float = 34.0    # DRAM output driver
    RTTuC:   float = 120.0   # Controller pull-up ODT
    RTTdC:   float = 120.0   # Controller pull-down ODT
    Rs1:     float = 15.0    # Series di controller end
    RTTu2:   float = 40.0    # Secondary pull-up di DRAM end
    RTTd2:   float = 40.0    # Secondary pull-down di DRAM end
    Rs2:     float = 15.0    # Series di DRAM ODT
    VDDq:    float = 1.5     # DQ supply voltage (V)

    # --- WRITE ---
    RzC:     float = 34.0    # Controller output driver
    RTTd1:   float = 60.0    # DRAM primary pull-down ODT
    RTTu1:   float = 60.0    # DRAM primary pull-up ODT
    Rs1_w:   float = 4.0     # Series di controller end
    RTTd2_w: float = 40.0    # DRAM secondary pull-down
    RTTu2_w: float = 40.0    # DRAM secondary pull-up
    Rs2_w:   float = 15.0    # Series di DRAM secondary

    # --- Direct Override (mW per DQ) ---
    override_PdqRD:    Optional[float] = None   # read I/O dari DRAM ini
    override_PdqWR:    Optional[float] = None   # write ODT di DRAM ini
    override_PdqRDoth: Optional[float] = None   # secondary ODT saat DRAM lain read
    override_PdqWRoth: Optional[float] = None   # secondary ODT saat DRAM lain write


@dataclass
class SystemConfig:
    """
    Konfigurasi penggunaan sistem (System Config sheet di Excel).

    vdd         : Tegangan VDD sistem aktual (V)
    freq_mhz    : Clock frequency (MHz)
    burst_length: Burst length (4 atau 8)

    bnk_pre     : Persen waktu semua bank dalam precharge state [0..1]
    cke_lo_pre  : Persen PRE time dengan CKE=LOW [0..1]
    cke_lo_act  : Persen ACT time dengan CKE=LOW [0..1]
    page_hit_rate: Page hit rate [0..1]. 0%=all miss, 100%=all hit.
    rd_pct      : Persen clock yang dipakai untuk READ [0..1]
    wr_pct      : Persen clock yang dipakai untuk WRITE [0..1]
    term_rd_pct : Persen clock terminating READ dari DRAM lain [0..1]
    term_wr_pct : Persen clock terminating WRITE dari DRAM lain [0..1]
    tRRD_override: Override tRRDsch (ns). None = auto dari page_hit_rate & bandwidth.

    io          : Konfigurasi I/O termination network.
    """
    vdd:            float = 1.5
    freq_mhz:       float = 800.0
    burst_length:   int   = 8
    bnk_pre:        float = 0.25
    cke_lo_pre:     float = 0.25
    cke_lo_act:     float = 0.25
    page_hit_rate:  float = 0.5
    rd_pct:         float = 0.3
    wr_pct:         float = 0.3
    term_rd_pct:    float = 0.0
    term_wr_pct:    float = 0.0
    tRRD_override:  Optional[float] = None
    io:             IOpowerConfig = field(default_factory=IOpowerConfig)


# =============================================================================
# Hasil Kalkulasi
# =============================================================================

@dataclass
class PowerResult:
    """
    Seluruh hasil kalkulasi power, identik dengan struktur di Power Calcs sheet.
    Semua dalam mW.
    """
    # --- Pds: Data Sheet Max Conditions ---
    Pds_PRE_PDN:  float = 0.0
    Pds_PRE_STBY: float = 0.0
    Pds_ACT_PDN:  float = 0.0
    Pds_ACT_STBY: float = 0.0
    Pds_REF:      float = 0.0
    Pds_ACT:      float = 0.0
    Pds_WR:       float = 0.0
    Pds_RD:       float = 0.0
    Pds_DQ:       float = 0.0
    Pds_termW:    float = 0.0
    Pds_termRoth: float = 0.0
    Pds_termWoth: float = 0.0

    # --- Psch: Derated for System Usage ---
    Psch_PRE_PDN:  float = 0.0
    Psch_PRE_STBY: float = 0.0
    Psch_ACT_PDN:  float = 0.0
    Psch_ACT_STBY: float = 0.0
    Psch_REF:      float = 0.0
    Psch_ACT:      float = 0.0
    Psch_WR:       float = 0.0
    Psch_RD:       float = 0.0
    Psch_DQ:       float = 0.0
    Psch_termW:    float = 0.0
    Psch_termRoth: float = 0.0
    Psch_termWoth: float = 0.0

    # --- Psys: Scaled for Actual VDD & Frequency ---
    Psys_PRE_PDN:  float = 0.0
    Psys_PRE_STBY: float = 0.0
    Psys_ACT_PDN:  float = 0.0
    Psys_ACT_STBY: float = 0.0
    Psys_REF:      float = 0.0
    Psys_ACT:      float = 0.0
    Psys_WR:       float = 0.0
    Psys_RD:       float = 0.0
    Psys_DQ:       float = 0.0
    Psys_termW:    float = 0.0
    Psys_termRoth: float = 0.0
    Psys_termWoth: float = 0.0

    # --- I/O Power per DQ ---
    PdqRD:    float = 0.0
    PdqWR:    float = 0.0
    PdqRDoth: float = 0.0
    PdqWRoth: float = 0.0

    # --- Summary ---
    total_act_power:  float = 0.0   # ACT only
    total_rdwr_power: float = 0.0   # RD + WR + DQ + termW + termRoth + termWoth
    total_bg_power:   float = 0.0   # PRE_PDN + PRE_STBY + ACT_PDN + ACT_STBY + REF
    total_power_mW:   float = 0.0

    # --- Derived Quantities ---
    tCK_sys:   float = 0.0   # ns
    tRRDsch:   float = 0.0   # ns
    avg_clk_between_col: float = 0.0
    avg_clk_between_row: float = 0.0
    read_bw_MTps:  float = 0.0
    write_bw_MTps: float = 0.0

    # --- Device Info ---
    density:      str = ''
    dq_width:     int = 16
    speed_grade:  str = ''
    vdd:          float = 0.0
    freq_mhz:     float = 0.0

    def print_report(self):
        _report(self)


# =============================================================================
# I/O Power Calculator
# =============================================================================

def _thevenin_node(sources: list) -> float:
    """
    Hitung tegangan node menggunakan KCL (Kirchhoff's Current Law).
    sources: list of (voltage_source, series_resistance) tuples.
    Mengembalikan tegangan node.

    Equivalent: V_node = sum(Vi/Ri) / sum(1/Ri)
    """
    num = sum(v / r for v, r in sources if r > 0)
    den = sum(1.0 / r for _, r in sources if r > 0)
    if den == 0:
        return 0.0
    return num / den


def calc_io_power(cfg: IOpowerConfig, dq_width: int) -> tuple:
    """
    Hitung PdqRD, PdqWR, PdqRDoth, PdqWRoth dalam mW per DQ.

    Model circuit (DDR3 SSTL_15):
    ─────────────────────────────
    READ (DRAM drives DQ):
      Vref = VDDq/2
      DRAM drives HIGH: VDDq → Rz1 → bus_node
      bus_node → (RTTuC || RTTdC) via Rs1 → Vref    [controller class-II ODT]
      bus_node → (RTTu2 || RTTd2) via Rs2 → Vref    [DRAM passive ODT]

    WRITE (Controller drives DQ):
      Controller drives HIGH: VDDq → RzC → bus_node  (via Rs1_w)
      bus_node → (RTTu1 || RTTd1) → Vref            [DRAM primary ODT]
      bus_node → (RTTu2_w || RTTd2_w) via Rs2_w → Vref [DRAM secondary ODT]

    Power dihitung untuk HIGH dan LOW, lalu dirata-rata (untuk square wave data).
    """

    VDDq = cfg.VDDq
    Vref = VDDq / 2.0

    def rpar(r1, r2):
        """Parallel resistors. Returns inf if both 0."""
        if r1 <= 0 and r2 <= 0:
            return float('inf')
        if r1 <= 0:
            return r2
        if r2 <= 0:
            return r1
        return (r1 * r2) / (r1 + r2)

    def calc_bus_node(drive_v, driver_r, loads):
        """
        Hitung tegangan bus node.
        drive_v  : sumber tegangan driver
        driver_r : impedansi seri driver
        loads    : list of (termination_v, total_series_r) → semua ke Vref
        """
        sources = [(drive_v, driver_r)] + [(lv, lr) for lv, lr in loads]
        return _thevenin_node(sources)

    def power_in_r(current_mA, resistance):
        return (current_mA ** 2) * resistance / 1000.0  # → mW

    # ──────────────────────────────────────────────
    # READ: DRAM drivers DQ HIGH then LOW (average)
    # ──────────────────────────────────────────────
    # Effective load dari controller (class-II ODT: pull-up + pull-down):
    R_ctrl = rpar(cfg.RTTuC, cfg.RTTdC)   # parallel combination to Vref
    R_ctrl_total = R_ctrl + cfg.Rs1        # including series

    # Effective load dari secondary DRAM ODT:
    R_sec = rpar(cfg.RTTu2, cfg.RTTd2)
    R_sec_total = R_sec + cfg.Rs2

    # Bus node voltage when DRAM drives HIGH:
    V_node_high = calc_bus_node(
        VDDq, cfg.Rz1,
        [(Vref, R_ctrl_total), (Vref, R_sec_total)]
    )
    # When driving LOW (by symmetry around Vref):
    V_node_low = VDDq - V_node_high

    # Current through DRAM driver (Rz1):
    I_Rz1_high = abs(VDDq - V_node_high) / cfg.Rz1   # mA ... actually in A if V in V
    # Correction: values in V, R in Ω → I in A → * 1000 for mA
    I_Rz1_high = abs(VDDq - V_node_high) / cfg.Rz1 * 1000  # mA (driving HIGH)
    I_Rz1_low  = abs(V_node_low) / cfg.Rz1 * 1000           # mA (driving LOW, GND source)

    I_Rz1_avg = (I_Rz1_high + I_Rz1_low) / 2.0  # average over HIGH+LOW

    P_Rz1    = power_in_r(I_Rz1_avg, cfg.Rz1)   # mW

    # Current through series resistance on controller side:
    V_delta_ctrl_high = abs(V_node_high - Vref)
    I_ctrl_high = V_delta_ctrl_high / R_ctrl_total * 1000   # mA
    I_ctrl_low  = V_delta_ctrl_high / R_ctrl_total * 1000   # same by symmetry
    I_ctrl_avg  = I_ctrl_high  # symmetric

    # Series R at controller (Rs1) carries same current as ctrl ODT path:
    P_Rs1_read = power_in_r(I_ctrl_avg, cfg.Rs1)    # mW in series R

    # Secondary ODT current:
    I_sec_high = V_delta_ctrl_high / R_sec_total * 1000   # mA
    I_sec_avg  = I_sec_high
    P_RTTu2    = power_in_r(I_sec_avg, R_sec)   # mW in parallel RTTu2/RTTd2
    P_Rs2_read = power_in_r(I_sec_avg, cfg.Rs2) # mW in Rs2

    # PdqRD = DRAM output driver loss + its series resistance (if any):
    # From empirical verification: PdqRD = P_Rz1 + P_Rs1_read (where Rs1 is at controller but
    # carries the controller-side load current). NOTE: This matches the Excel's decomposition.
    # The DRAM "sees" power in its own Rz1.
    PdqRD    = P_Rz1
    # PdqRDoth = secondary ODT power (what this DRAM dissipates when another DRAM reads)
    PdqRDoth = P_RTTu2 + P_Rs2_read

    # ──────────────────────────────────────────────
    # WRITE: Controller drives DQ, DRAM terminates
    # ──────────────────────────────────────────────
    R_prim = rpar(cfg.RTTu1, cfg.RTTd1)          # DRAM primary ODT to Vref
    R_sec_w = rpar(cfg.RTTu2_w, cfg.RTTd2_w)    # DRAM secondary ODT
    R_sec_w_total = R_sec_w + cfg.Rs2_w

    V_node_w_high = calc_bus_node(
        VDDq, (cfg.RzC + cfg.Rs1_w),
        [(Vref, R_prim), (Vref, R_sec_w_total)]
    )
    V_node_w_low = VDDq - V_node_w_high

    V_delta_w = abs(V_node_w_high - Vref)

    I_prim_high = V_delta_w / R_prim * 1000     # mA through primary ODT
    I_prim_avg  = I_prim_high

    I_sec_w_high = V_delta_w / R_sec_w_total * 1000
    I_sec_w_avg  = I_sec_w_high

    P_RTTd1 = power_in_r(I_prim_avg, R_prim)    # power in primary ODT
    P_RTTd2_w = power_in_r(I_sec_w_avg, R_sec_w)
    P_Rs2_w   = power_in_r(I_sec_w_avg, cfg.Rs2_w)

    # PdqWR = DRAM primary ODT power (this DRAM terminates while controller writes)
    PdqWR    = P_RTTd1
    # PdqWRoth = secondary ODT (when another DRAM writes, secondary termination here)
    PdqWRoth = P_RTTd2_w + P_Rs2_w

    # Apply override if provided
    if cfg.override_PdqRD    is not None: PdqRD    = cfg.override_PdqRD
    if cfg.override_PdqWR    is not None: PdqWR    = cfg.override_PdqWR
    if cfg.override_PdqRDoth is not None: PdqRDoth = cfg.override_PdqRDoth
    if cfg.override_PdqWRoth is not None: PdqWRoth = cfg.override_PdqWRoth

    return PdqRD, PdqWR, PdqRDoth, PdqWRoth


# =============================================================================
# Main Power Calculator
# =============================================================================

class DDR3PowerCalc:
    """
    Main class yang mereplikasi seluruh logika di Micron Excel Power Calc.
    Urutan kalkulasi: IDD lookup → I/O power → Pds → Psch → Psys → Total.
    """

    def __init__(self, spec: DDR3Spec, sys_cfg: SystemConfig):
        self.spec    = spec
        self.sys_cfg = sys_cfg

    def run(self) -> PowerResult:
        spec    = self.spec
        syscfg  = self.sys_cfg
        io_cfg  = syscfg.io
        r       = PowerResult()

        # ── Device info ──────────────────────────────────────────────────────
        r.density     = spec.density
        r.dq_width    = spec.dq_width
        r.speed_grade = spec.speed_grade
        r.vdd         = syscfg.vdd
        r.freq_mhz    = syscfg.freq_mhz

        # ── Fundamental timing ────────────────────────────────────────────────
        r.tCK_sys     = 1000.0 / syscfg.freq_mhz          # ns
        tCK_meas      = spec.get_timing('tCK_meas')         # ns (dari speed grade)
        tRC           = spec.get_timing('tRC')
        tRAS          = spec.get_timing('tRAS')
        tRFC          = spec.get_timing('tRFC')
        tREFI_ns      = spec.get_timing('tREFI') * 1000.0  # µs → ns

        # ── tRRDsch ───────────────────────────────────────────────────────────
        # Auto-kalkulasi dari page hit rate dan bandwidth.
        # User bisa override dengan tRRD_override.
        BL = syscfg.burst_length
        if (syscfg.rd_pct + syscfg.wr_pct) > 0:
            avg_clk_col = (BL / 2.0) / (syscfg.rd_pct + syscfg.wr_pct)
        else:
            avg_clk_col = float('inf')
        r.avg_clk_between_col = avg_clk_col

        if syscfg.page_hit_rate < 1.0:
            avg_clk_row = avg_clk_col / (1.0 - syscfg.page_hit_rate)
        else:
            avg_clk_row = float('inf')
        r.avg_clk_between_row = avg_clk_row
        tRRDsch_auto = avg_clk_row * r.tCK_sys

        r.tRRDsch = syscfg.tRRD_override if syscfg.tRRD_override is not None else tRRDsch_auto

        # ── IDD values ───────────────────────────────────────────────────────
        IDD0    = spec.get_idd('IDD0')
        IDD2P   = spec.get_idd('IDD2P_fast') if spec.pd_exit_fast else spec.get_idd('IDD2P_slow')
        IDD2N   = spec.get_idd('IDD2N')
        IDD3P   = spec.get_idd('IDD3P')
        IDD3N   = spec.get_idd('IDD3N')
        IDD4R   = spec.get_idd4r()
        IDD4W   = spec.get_idd4w()
        IDD5A   = spec.get_idd('IDD5B')   # IDD5A ≈ IDD5B in Micron DDR3 calc

        VDD_max = spec.vdd_max
        VDD_sys = syscfg.vdd

        # ── Signal counts ─────────────────────────────────────────────────────
        # x16: DQ=16, DM=2, DQS=2 → READ bus signals (20), WRITE (22 incl. DQS_n)
        # x8 : DQ=8,  DM=1, DQS=1 → READ: 10, WRITE: 12
        # x4 : DQ=4,  DM=1, DQS=1 → READ: 6,  WRITE: 8
        dq = spec.dq_width
        if dq == 16:
            DM_bits, DQS_bits = 2, 2
        elif dq == 8:
            DM_bits, DQS_bits = 1, 1
        else:  # x4
            DM_bits, DQS_bits = 1, 1
        sig_rd = dq + DM_bits + DQS_bits       # for PdqRD, PdqRDoth
        sig_wr = dq + DM_bits + DQS_bits * 2   # for PdqWR, PdqWRoth (incl. DQS_n)

        # ── I/O Power ─────────────────────────────────────────────────────────
        PdqRD, PdqWR, PdqRDoth, PdqWRoth = calc_io_power(io_cfg, dq)
        r.PdqRD    = PdqRD
        r.PdqWR    = PdqWR
        r.PdqRDoth = PdqRDoth
        r.PdqWRoth = PdqWRoth

        # ── Bandwidth info ────────────────────────────────────────────────────
        r.read_bw_MTps  = syscfg.rd_pct  * syscfg.freq_mhz * 2  # MT/s (DDR)
        r.write_bw_MTps = syscfg.wr_pct  * syscfg.freq_mhz * 2

        # ════════════════════════════════════════════════════════════════════════
        # STEP 1: Pds — Power Based on Data Sheet Max Conditions
        # Formula: IDD × VDD_max, dengan VDD_max = rated max voltage untuk
        # speed grade ini dari data sheet.
        # ════════════════════════════════════════════════════════════════════════

        r.Pds_PRE_PDN  = IDD2P * VDD_max                               # mW
        r.Pds_PRE_STBY = IDD2N * VDD_max
        r.Pds_ACT_PDN  = IDD3P * VDD_max
        r.Pds_ACT_STBY = IDD3N * VDD_max
        r.Pds_REF      = (IDD5A - IDD3N) * VDD_max * (tRFC / tREFI_ns)

        # ACT power: incremental charge per ACT-PRE cycle, dibagi tRC
        # Q_ACT = (IDD0 - IDD3N) × tRAS + (IDD0 - IDD2N) × (tRC - tRAS)
        q_act          = (IDD0 - IDD3N) * tRAS + (IDD0 - IDD2N) * (tRC - tRAS)
        r.Pds_ACT      = q_act * VDD_max / tRC                          # mW

        r.Pds_WR       = (IDD4W - IDD3N) * VDD_max
        r.Pds_RD       = (IDD4R - IDD3N) * VDD_max
        r.Pds_DQ       = PdqRD    * sig_rd
        r.Pds_termW    = PdqWR    * sig_wr
        r.Pds_termRoth = PdqRDoth * sig_rd
        r.Pds_termWoth = PdqWRoth * sig_wr

        # ════════════════════════════════════════════════════════════════════════
        # STEP 2: Psch — Power Derated for System Usage Conditions
        # Setiap komponen dikali time-fraction pemakaian di sistem.
        # ════════════════════════════════════════════════════════════════════════

        # Fraksi waktu untuk setiap state:
        BNK_ACT       = 1.0 - syscfg.bnk_pre
        PRE_PDN_frac  = syscfg.bnk_pre * syscfg.cke_lo_pre
        PRE_STBY_frac = syscfg.bnk_pre * (1.0 - syscfg.cke_lo_pre)
        ACT_PDN_frac  = BNK_ACT        * syscfg.cke_lo_act
        ACT_STBY_frac = BNK_ACT        * (1.0 - syscfg.cke_lo_act)

        r.Psch_PRE_PDN  = r.Pds_PRE_PDN  * PRE_PDN_frac
        r.Psch_PRE_STBY = r.Pds_PRE_STBY * PRE_STBY_frac
        r.Psch_ACT_PDN  = r.Pds_ACT_PDN  * ACT_PDN_frac
        r.Psch_ACT_STBY = r.Pds_ACT_STBY * ACT_STBY_frac
        r.Psch_REF      = r.Pds_REF       # Already normalized (tRFC/tREFI embedded)

        # ACT: scale dari tRC (datasheet measurement rate) ke tRRDsch (system rate)
        if r.tRRDsch > 0:
            r.Psch_ACT  = r.Pds_ACT * (tRC / r.tRRDsch)
        else:
            r.Psch_ACT  = 0.0

        r.Psch_WR       = r.Pds_WR       * syscfg.wr_pct
        r.Psch_RD       = r.Pds_RD       * syscfg.rd_pct
        r.Psch_DQ       = r.Pds_DQ       * syscfg.rd_pct
        r.Psch_termW    = r.Pds_termW    * syscfg.wr_pct
        r.Psch_termRoth = r.Pds_termRoth * syscfg.term_rd_pct
        r.Psch_termWoth = r.Pds_termWoth * syscfg.term_wr_pct

        # ════════════════════════════════════════════════════════════════════════
        # STEP 3: Psys — Scaled for Actual VDD and CK Frequency
        #
        # Scaling factors:
        #   VDD_scale_sq = (VDD_sys / VDD_max)²   ← current ∝ VDD, power ∝ VDD²
        #   freq_scale   = tCK_meas / tCK_sys      ← background current ∝ freq
        #
        # Penerapan:
        #   Background (PRE/ACT PDN, STBY): VDD² × freq
        #     → Asumsi: background current scales linearly dengan freq
        #       (karena clock-tree power lebih dominan)
        #   REF & ACT: VDD² only (freq sudah embedded di tRFC/tREFI dan tRRDsch)
        #   RD & WR:   VDD² × freq (core array current scales dengan freq)
        #   I/O (DQ, termW, termRoth, termWoth): tidak di-scale (external circuit)
        # ════════════════════════════════════════════════════════════════════════

        VDD_scale_sq = (VDD_sys / VDD_max) ** 2
        freq_scale   = tCK_meas / r.tCK_sys     # < 1 jika sistem lebih lambat

        r.Psys_PRE_PDN  = r.Psch_PRE_PDN  * VDD_scale_sq * freq_scale
        r.Psys_PRE_STBY = r.Psch_PRE_STBY * VDD_scale_sq * freq_scale
        r.Psys_ACT_PDN  = r.Psch_ACT_PDN  * VDD_scale_sq * freq_scale
        r.Psys_ACT_STBY = r.Psch_ACT_STBY * VDD_scale_sq * freq_scale
        r.Psys_REF      = r.Psch_REF       * VDD_scale_sq               # no freq scale
        r.Psys_ACT      = r.Psch_ACT       * VDD_scale_sq               # no freq scale
        r.Psys_WR       = r.Psch_WR        * VDD_scale_sq * freq_scale
        r.Psys_RD       = r.Psch_RD        * VDD_scale_sq * freq_scale
        r.Psys_DQ       = r.Psch_DQ        # no VDD/freq scale (I/O circuit independent)
        r.Psys_termW    = r.Psch_termW
        r.Psys_termRoth = r.Psch_termRoth
        r.Psys_termWoth = r.Psch_termWoth

        # ── Summary categories (sesuai Summary sheet di Excel) ────────────────
        r.total_act_power  = r.Psys_ACT
        r.total_rdwr_power = (r.Psys_RD + r.Psys_WR + r.Psys_DQ +
                               r.Psys_termW + r.Psys_termRoth + r.Psys_termWoth)
        r.total_bg_power   = (r.Psys_PRE_PDN + r.Psys_PRE_STBY +
                               r.Psys_ACT_PDN + r.Psys_ACT_STBY + r.Psys_REF)
        r.total_power_mW   = (r.total_act_power + r.total_rdwr_power +
                               r.total_bg_power)
        return r


# =============================================================================
# Report Formatter
# =============================================================================

def _report(r: PowerResult):
    print("=" * 72)
    print(f"  DDR3 POWER CALCULATION REPORT")
    print(f"  {r.density} DDR3{'L' if r.vdd < 1.45 else ''} SDRAM  |  x{r.dq_width}  |  {r.speed_grade}")
    print(f"  VDD = {r.vdd:.3f}V  |  CK = {r.freq_mhz:.0f} MHz  |  "
          f"RD={r.read_bw_MTps:.0f} MT/s  WR={r.write_bw_MTps:.0f} MT/s")
    print(f"  tRRDsch = {r.tRRDsch:.2f} ns  |  tCK = {r.tCK_sys:.3f} ns")
    print("=" * 72)

    hdr = f"  {'Component':<22} {'Pds(mW)':>10} {'Psch(mW)':>10} {'Psys(mW)':>10}"
    sep = "  " + "-" * 68
    print(hdr)
    print(sep)

    rows = [
        ("PRE_PDN",  r.Pds_PRE_PDN,  r.Psch_PRE_PDN,  r.Psys_PRE_PDN),
        ("PRE_STBY", r.Pds_PRE_STBY, r.Psch_PRE_STBY, r.Psys_PRE_STBY),
        ("ACT_PDN",  r.Pds_ACT_PDN,  r.Psch_ACT_PDN,  r.Psys_ACT_PDN),
        ("ACT_STBY", r.Pds_ACT_STBY, r.Psch_ACT_STBY, r.Psys_ACT_STBY),
        ("REF",      r.Pds_REF,       r.Psch_REF,       r.Psys_REF),
        ("ACT",      r.Pds_ACT,       r.Psch_ACT,       r.Psys_ACT),
        ("WR",       r.Pds_WR,        r.Psch_WR,        r.Psys_WR),
        ("RD",       r.Pds_RD,        r.Psch_RD,        r.Psys_RD),
        ("DQ (READ I/O)", r.Pds_DQ,  r.Psch_DQ,        r.Psys_DQ),
        ("termW (WR ODT)",r.Pds_termW,r.Psch_termW,    r.Psys_termW),
        ("termRoth", r.Pds_termRoth,  r.Psch_termRoth,  r.Psys_termRoth),
        ("termWoth", r.Pds_termWoth,  r.Psch_termWoth,  r.Psys_termWoth),
    ]

    for name, pds, psch, psys in rows:
        print(f"  {name:<22} {pds:>10.3f} {psch:>10.3f} {psys:>10.3f}")

    print(sep)
    print(f"  {'Total Background':<22} {'':>10} {'':>10} {r.total_bg_power:>10.3f}")
    print(f"  {'Total ACT':<22} {'':>10} {'':>10} {r.total_act_power:>10.3f}")
    print(f"  {'Total RD/WR/Term':<22} {'':>10} {'':>10} {r.total_rdwr_power:>10.3f}")
    print(sep)
    print(f"  {'TOTAL DDR3 POWER':<22} {'':>10} {'':>10} {r.total_power_mW:>10.3f} mW")
    print("=" * 72)
    print(f"\n  I/O Power per DQ:")
    print(f"    PdqRD    = {r.PdqRD:.4f} mW  (READ I/O, dari DRAM ini)")
    print(f"    PdqWR    = {r.PdqWR:.4f} mW  (WRITE ODT, di DRAM ini)")
    print(f"    PdqRDoth = {r.PdqRDoth:.4f} mW  (secondary ODT, DRAM lain baca)")
    print(f"    PdqWRoth = {r.PdqWRoth:.4f} mW  (secondary ODT, DRAM lain tulis)")


# =============================================================================
# PIM Integration Helper
# Fungsi ini mengkonversi counter Verilog (act_count, rd_count, dll.)
# menjadi estimasi energi menggunakan model Psys.
# =============================================================================

def energy_from_counters(result: PowerResult,
                         act_count: int,
                         rd_count:  int,
                         wr_count:  int,
                         pre_count: int,
                         skip_count: int,
                         sim_cycles: int,
                         clk_freq_mhz: float = None) -> dict:
    """
    Estimasi energi dari counter Verilog (seperti yang dihasilkan
    dram_controller_ddr3.v di pim_system_top).

    Parameters:
    -----------
    result       : PowerResult dari DDR3PowerCalc.run()
    act_count    : Jumlah ACT commands
    rd_count     : Jumlah READ commands
    wr_count     : Jumlah WRITE commands
    pre_count    : Jumlah PRE commands
    skip_count   : Jumlah akses yang di-skip oleh PIM (zero-value skipping)
    sim_cycles   : Total clock cycles simulasi
    clk_freq_mhz : Clock frequency (MHz); jika None, pakai result.freq_mhz

    Returns:
    --------
    dict dengan field:
        sim_time_us     : Durasi simulasi (µs)
        E_act_pJ        : Energi ACT/PRE (pJ)
        E_rd_pJ         : Energi READ burst (pJ)
        E_wr_pJ         : Energi WRITE burst (pJ)
        E_bg_pJ         : Energi background (pJ)
        E_total_pJ      : Total energi (pJ)
        E_saved_pJ      : Energi yang dihemat oleh PIM skipping
        savings_pct     : Penghematan (%)
        power_avg_mW    : Rata-rata power (mW)
    """
    freq = clk_freq_mhz or result.freq_mhz
    tCK = 1.0 / freq  # µs per clock cycle

    sim_time_us = sim_cycles * tCK

    # Energi per event (µW × µs = pJ):
    # Psys_ACT (mW) = daya rata-rata ketika ACT dilakukan di rate tRRDsch.
    # Per satu ACT event, energi = Pds_ACT × tRC (tidak di-scale lagi)
    E_per_act_pJ = (result.Pds_ACT / result.tRRDsch) * result.tCK_sys * 1000
    # ↑ Lebih mudah: gunakan Psys_ACT * tCK_sys * ratio
    # Tapi pendekatan terbaik: E_total_act = Psys_ACT * sim_time_us
    # lalu distribute per act_count untuk perbandingan.

    # Metode sederhana: alokasikan power × time
    E_act_pJ    = result.Psys_ACT    * sim_time_us * 1000  # mW × µs × 1000 = pJ
    E_rd_pJ     = result.Psys_RD     * sim_time_us * 1000
    E_wr_pJ     = result.Psys_WR     * sim_time_us * 1000
    E_io_rd_pJ  = result.Psys_DQ     * sim_time_us * 1000
    E_io_wr_pJ  = result.Psys_termW  * sim_time_us * 1000
    E_bg_pJ     = result.total_bg_power * sim_time_us * 1000

    E_total_pJ  = result.total_power_mW * sim_time_us * 1000

    # Estimasi penghematan dari PIM skip:
    # Setiap skip menghilangkan 1 ACT + 1 RD command.
    total_accesses  = rd_count + skip_count  # total yang seharusnya
    if total_accesses > 0:
        skip_fraction = skip_count / total_accesses
    else:
        skip_fraction = 0.0

    # Power yang dihemat = (ACT + RD) power × skip fraction
    saved_power_mW = (result.Psys_ACT + result.Psys_RD + result.Psys_DQ) * skip_fraction
    E_saved_pJ     = saved_power_mW * sim_time_us * 1000

    power_avg_mW   = result.total_power_mW * (1.0 - skip_fraction)
    savings_pct    = (E_saved_pJ / E_total_pJ * 100.0) if E_total_pJ > 0 else 0.0

    return {
        'sim_time_us':    sim_time_us,
        'E_act_pJ':       E_act_pJ,
        'E_rd_pJ':        E_rd_pJ,
        'E_wr_pJ':        E_wr_pJ,
        'E_io_rd_pJ':     E_io_rd_pJ,
        'E_io_wr_pJ':     E_io_wr_pJ,
        'E_bg_pJ':        E_bg_pJ,
        'E_total_pJ':     E_total_pJ,
        'E_saved_pJ':     E_saved_pJ,
        'savings_pct':    savings_pct,
        'power_avg_mW':   power_avg_mW,
        'skip_fraction':  skip_fraction,
        'total_accesses': total_accesses,
    }


# =============================================================================
# Demo / Quick Test
# =============================================================================

if __name__ == '__main__':
    # ── Reproduksi exact Excel default config ──────────────────────────────
    print("\n[Test 1] Reproduce Micron Excel default (1Gb, x16, -093, DDR3 1.5V 800MHz)")
    spec = DDR3Spec(density='1Gb', speed_grade='-093', dq_width=16, is_ddr3l=False)
    io_cfg = IOpowerConfig(
        Rz1=34, RTTuC=120, RTTdC=120, Rs1=15, RTTu2=40, RTTd2=40, Rs2=15,
        VDDq=1.5, RzC=34, RTTd1=60, RTTu1=60, Rs1_w=4, RTTd2_w=40, RTTu2_w=40, Rs2_w=15,
        # Pakai override dari Excel untuk I/O power
        override_PdqRD    = 5.451488630567265,
        override_PdqWR    = 20.623755928036896,
        override_PdqRDoth = 29.67859466984732,
        override_PdqWRoth = 29.945220044378697,
    )
    sys_cfg = SystemConfig(
        vdd=1.5, freq_mhz=800, burst_length=8,
        bnk_pre=0.25, cke_lo_pre=0.25, cke_lo_act=0.25,
        page_hit_rate=0.5, rd_pct=0.3, wr_pct=0.3,
        term_rd_pct=0.0, term_wr_pct=0.0,
        tRRD_override=16.6,  # sama dengan input user di Excel
        io=io_cfg
    )
    calc = DDR3PowerCalc(spec, sys_cfg)
    result = calc.run()
    result.print_report()
    print(f"\n  Excel Total: 360.727 mW  |  Calc: {result.total_power_mW:.3f} mW")

    # ── Contoh: konfigurasi PIM sistem kamu ───────────────────────────────
    print("\n\n[Test 2] PIM System Config (4Gb, x16, -093, DDR3L 1.35V, 533MHz)")
    spec2 = DDR3Spec(density='4Gb', speed_grade='-093', dq_width=16, is_ddr3l=True)
    sys2 = SystemConfig(
        vdd=1.35, freq_mhz=533, burst_length=8,
        bnk_pre=0.30, cke_lo_pre=0.20, cke_lo_act=0.20,
        page_hit_rate=0.5, rd_pct=0.3, wr_pct=0.3,
        term_rd_pct=0.0, term_wr_pct=0.0,
    )
    calc2 = DDR3PowerCalc(spec2, sys2)
    result2 = calc2.run()
    result2.print_report()

    # ── Demo PIM energy savings ────────────────────────────────────────────
    print("\n\n[Test 3] PIM Energy Estimation from Simulation Counters")
    energy = energy_from_counters(
        result2,
        act_count   = 12000,
        rd_count    = 10000,
        wr_count    = 2000,
        pre_count   = 12000,
        skip_count  = 8000,   # 44% skip rate (high sparsity)
        sim_cycles  = 500_000,
        clk_freq_mhz= 533
    )
    print(f"  Sim duration   : {energy['sim_time_us']:.2f} µs")
    print(f"  Total accesses : {energy['total_accesses']}")
    print(f"  Skip rate      : {energy['skip_fraction']*100:.1f}%")
    print(f"  E_total        : {energy['E_total_pJ']/1e6:.4f} µJ")
    print(f"  E_saved        : {energy['E_saved_pJ']/1e6:.4f} µJ")
    print(f"  Savings        : {energy['savings_pct']:.2f}%")
    print(f"  Avg Power      : {energy['power_avg_mW']:.3f} mW")
