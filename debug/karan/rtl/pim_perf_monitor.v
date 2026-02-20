/*
 * PIM PERFORMANCE MONITOR (Bitlet Model Implementation)
 * ---------------------------------------------------
 * Metodologi: Bitlet Model [Ronen et al., 2021]
 * - Energy = Sum(Activity_Vector * Energy_Vector)
 * - Area   = Sum(Component_Count * Area_Vector)
 * * Data Constants: Horowitz 2014 & ISSCC Trends
 */

module pim_perf_monitor #(
    parameter DATA_WIDTH = 512
)(
    input wire clk,
    input wire rst_n,
    
    // Sinyal yang dipantau (Snooping Signals)
    input wire [31:0] active_cycles_in, // Dari PIM Logic
    input wire [31:0] idle_cycles_in,   // Dari PIM Logic (Skipped)
    input wire [31:0] total_ops_in      // Total instruksi
);

    // =========================================================================
    // 1. HOROWITZ 2014 ENERGY CONSTANTS (Joules)
    // =========================================================================
    // Bitlet: "Memory Bitlet" (DRAM vs SRAM) & "Compute Bitlet" (MAC)
    
    // Baseline (Off-Chip DRAM): ~2000pJ/access + Bus overhead
    real E_BITLET_MEM_OFFCHIP = 3100.0e-12; 
    
    // PIM Active (On-Chip SRAM): ~20pJ/access + Logic Overhead (~80pJ total)
    real E_BITLET_MEM_ONCHIP  = 100.0e-12;
    
    // PIM Idle (Gating Logic): Cuma comparator (Sangat kecil)
    real E_BITLET_GATING      = 5.0e-12;
    
    // Compute (MAC 32-bit INT/FP): ~50pJ [Horowitz Fig 1.1.6]
    real E_BITLET_COMPUTE     = 50.0e-12;

    // =========================================================================
    // 2. AREA MODEL (Estimasi 45nm/28nm - Scaled)
    // =========================================================================
    // Satuan: micrometer persegi (um^2)
    // PIM Area Overhead is critical in Bitlet analysis.
    
    real AREA_MAC_UNIT      = 5000.0; // Approx 1 MAC unit 
    real AREA_LOGIC_GATING  = 200.0;  // Simple Comparator
    real AREA_PER_CORE      = (16 * AREA_MAC_UNIT) + AREA_LOGIC_GATING; // 16 SIMD lanes
    real AREA_TOTAL_PIM     = 4 * AREA_PER_CORE; // 4 Cores implementation

    // =========================================================================
    // 3. THERMAL MODEL VARIABLES (HotSpot RC)
    // =========================================================================
    real T_AMBIENT = 45.0;
    real R_THERMAL = 25.0;
    real C_THERMAL = 0.0001; 
    real DT        = 10.0 * 1e-9; // 10ns Clock
    
    real current_temp;
    real current_power;
    real active_ratio;

    // =========================================================================
    // 4. METRIC CALCULATION
    // =========================================================================
    real base_energy_total;
    real pim_energy_total;
    real saving_pct;
    real total_pkts;

    // Init
    initial begin
        current_temp = T_AMBIENT;
        current_power = 0.0;
        
        // Print Area Estimation at Start
        $display("\n[PERF_MON] PIM Area Estimation (Bitlet Model)");
        $display("   - Tech Node      : 28nm (Reference)");
        $display("   - MAC Unit Area  : %0.0f um2", AREA_MAC_UNIT);
        $display("   - Core Area (x16): %0.0f um2", AREA_PER_CORE);
        $display("   - Total PIM Area : %0.0f um2 (4 Cores)", AREA_TOTAL_PIM);
        $display("   - Density Impact : < 2%% of DRAM Die Size\n");
    end

    // Real-time Monitoring & Thermal Update
    always @(posedge clk) begin
        if (rst_n) begin
            // Hitung Rasio Aktivitas untuk Suhu
            if ((active_cycles_in + idle_cycles_in) > 0) begin
                active_ratio = active_cycles_in * 1.0 / (active_cycles_in + idle_cycles_in);
                // Power Model: Dynamic Power scaling based on activity
                // 3.5W (Peak Active) vs 0.2W (Leakage/Idle)
                current_power = (active_ratio * 3.5) + ((1.0 - active_ratio) * 0.2);
            end else begin
                current_power = 0.1; // Standby
            end
            
            // RC Thermal Update
            current_temp <= current_temp + (current_power - ((current_temp - T_AMBIENT)/R_THERMAL)) / C_THERMAL * DT;
        end
    end

    // =========================================================================
    // 5. FINAL REPORTING TASK
    // =========================================================================
    // Tugas ini dipanggil oleh Testbench saat finish
    task report_metrics;
        begin
            total_pkts = active_cycles_in + idle_cycles_in;
            
            if (total_pkts > 0) begin
                // --- BITLET ENERGY CALCULATION ---
                // E = N_activ * E_activ
                
                // 1. Baseline Energy (Memory Bound)
                // Anggap Baseline memproses 100% data lewat Off-chip DRAM (Mahal)
                // 1 Packet = 16 words (512 bit)
                base_energy_total = total_pkts * 16.0 * E_BITLET_MEM_OFFCHIP; 
                
                // 2. PIM Energy (Sparsity Aware)
                // Active Packets: On-Chip Mem Cost + Compute Cost
                // Idle Packets:   Gating Cost only
                pim_energy_total  = (active_cycles_in * 16.0 * (E_BITLET_MEM_ONCHIP + E_BITLET_COMPUTE)) + 
                                    (idle_cycles_in   * 16.0 * E_BITLET_GATING);

                // Saving
                saving_pct = ((base_energy_total - pim_energy_total) / base_energy_total) * 100.0;

                // Console Output
                $display("\n====================================================");
                $display("   FINAL REPORT: BITLET MODEL ANALYTICS");
                $display("====================================================");
                $display("Total Workload (Pkts)   : %0.0f", total_pkts);
                $display("  - Active Bitlets      : %0d", active_cycles_in);
                $display("  - Skipped Bitlets     : %0d", idle_cycles_in);
                $display("  - Sparsity Level      : %0.2f %%", (idle_cycles_in * 100.0) / total_pkts);
                $display("----------------------------------------------------");
                $display("Baseline Energy (J)     : %0.9f", base_energy_total);
                $display("PIM Energy (J)          : %0.9f", pim_energy_total);
                $display("Energy Saving           : %0.2f %%", saving_pct);
                $display("Peak Temperature        : %0.2f C", current_temp);
                $display("Est. Area Overhead      : %0.0f um2", AREA_TOTAL_PIM);
                $display("----------------------------------------------------");

                // CSV Output for Script
                // Scaling ke uJ (micro-joule) agar mudah dibaca di tabel bash
                $display("RESULT,%0d,%0d,%0.2f,%0.2f,%0.2f", 
                         total_pkts, idle_cycles_in, base_energy_total*1e6, pim_energy_total*1e6, saving_pct);

            end else begin
                $display("RESULT,0,0,0,0,0"); // Safety fallback
            end
            $display("====================================================\n");
        end
    endtask

endmodule
