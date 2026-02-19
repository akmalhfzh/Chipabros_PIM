# 🧠 Micron PIM System - Sparsity Aware Accelerator (v4)

Repositori ini berisi implementasi simulasi RTL (Register Transfer Level) untuk sistem **Processing-In-Memory (PIM)** yang dirancang untuk mengeksploitasi *Coarse-Grained Block Sparsity* pada beban kerja AI/Machine Learning.

Sistem ini berevolusi dari sekadar pemantauan data pasif menjadi **PIM Controller Aktif** yang mampu melakukan **Controller-Level Zero-Skipping**, mencegah akses ke DRAM secara fisik untuk menghemat energi secara masif.

---

## ✨ Fitur Utama (Update v4)

1. **Controller-Level Address Gating (Check-then-Read)**
   Sistem PIM mencegat permintaan baca (Read Request) dari CPU di level bus AXI. PIM mengecek tabel metadata internal (*lookahead*); jika blok berukuran 512-bit terdeteksi sebagai sekumpulan nilai nol (*sparse*), permintaan ke DRAM (`ARVALID`) akan **diblokir total**. Ini menghemat energi dari perintah ACT (Activate) dan RD (Read) pada fisik DRAM.

2. **Local Zero Injection (Fake Ready)**
   Untuk blok data yang *sparse*, PIM tidak membiarkan CPU menunggu. PIM akan secara instan merespons CPU dengan sinyal Ready dan memberikan data balasan berisi nol murni. Ini secara dramatis memotong *latency* akses memori.

3. **Coarse-Grained Block Sparsity (512-bit)**
   Metode *sparsity* dioptimalkan untuk fisika DRAM (*burst length* 64 Byte). 1 bit metadata mengontrol nasib 16 *words* (512-bit) sekaligus, menghasilkan *overhead* metadata yang sangat kecil (<0.2%).

4. **Analytical Bitlet Energy Model**
   Terintegrasi dengan monitor performa berbasis *Bitlet Model* (Horowitz 2014 & Newton 2020) yang berjalan berdampingan dengan simulasi RTL untuk menghitung estimasi suhu dan konsumsi energi secara akurat (*Active vs Idle Energy*).

5. **Model-Aware Profiling**
   Generator *testcase* mensimulasikan karakteristik *Structured Block Pruning* dari model AI nyata seperti **ResNet-50**, **BERT-Base**, dan **LLaMA-2**, memberikan pengujian arsitektur yang valid secara akademis.

---

## 📂 Struktur Direktori

```text
.
├── rtl/                        # Kode sumber Verilog untuk perangkat keras
│   ├── simple_riscv_cpu.v      # Host CPU (Mandor) yang mengirimkan trigger LW
│   ├── simple_memory.v         # Model DRAM (Bekerja di belakang PIM)
│   ├── cpu_to_axi.v            # Adapter memori CPU ke antarmuka AXI4
│   ├── pim_sparsity_aware.v    # 🌟 INTI PIM: Controller dengan fitur Address Gating & Fake Ready
│   ├── pim_perf_monitor.v      # 🌟 Modul kalkulasi energi Bitlet Model & RC Thermal
│   └── pim_system_top.v        # Modul Top-Level yang menyatukan seluruh sistem
├── testbench/                  # Kode untuk pengujian
│   └── tb_pim_system.v         # Testbench utama penghasil clock & backdoor metadata loader
├── gen_testcase.py             # Script Python untuk generate Model-Aware firmware (.hex)
├── run_all.sh                  # Script Bash untuk eksekusi otomatis 1-klik
├── Makefile                    # Makefile untuk kompilasi dan simulasi manual
└── README.md                   # Dokumentasi ini

## 🚀 Cara Menjalankan Simulasi
Cara termudah untuk mengkompilasi, membuat data model, dan menjalankan benchmark adalah menggunakan skrip yang telah disediakan:

Bash
chmod +x run_all.sh
./run_all.sh
Alur yang terjadi saat script dijalankan:

iverilog mengkompilasi seluruh file rtl/ dan testbench/.

gen_testcase.py menghasilkan profil data (firmware) yang mensimulasikan distribusi Gaussian bobot dari model ResNet, BERT, dan LLaMA, lalu menerapkan magnitude-based block pruning.

Testbench mengeksekusi firmware tersebut di dalam arsitektur bersiklus-akurat (cycle-accurate).

pim_perf_monitor.v menangkap statistik siklus (Active vs Idle) dan mencetak metrik energi ke konsol.

## 📊 Contoh Output Benchmark
Setelah menjalankan skrip, Anda akan melihat laporan metrik Bitlet Model beserta tabel rangkuman energi berdasarkan profil model AI:

Plaintext
 MODEL           | BASE E (uJ)     | PIM E (uJ)      | SAVING     
======================================================================
 resnet-50       | 198.40          | 138.88          | 30.00 % 
 bert-base       | 198.40          | 79.36           | 60.00 % 
 llama-2         | 198.40          | 29.76           | 85.00 % 
 ideal-case      | 198.40          | 9.92            | 95.00 % 
BASE E: Energi yang dihabiskan jika CPU standar mengakses Off-Chip DRAM terus-menerus tanpa ada fitur PIM.

PIM E: Energi aktual yang dikonsumsi oleh PIM (kombinasi dari akses DRAM untuk data dense dan komputasi/pengecekan metadata untuk data sparse).

SAVING: Persentase energi yang berhasil diselamatkan berkat fitur Controller-Level Zero-Skipping. Semakin sparse modelnya (seperti LLaMA), semakin tinggi penghematannya.
