`timescale 1ns/1ps

module tb_pim_system;
    // --- SIMULATION CONFIG ---
    parameter CLK_PERIOD  = 10;        // 10ns = 100MHz
    parameter SIM_DURATION = 20000000; // 20ms >> 3000 iter x 40cyc x 10ns = 1.2ms

    reg clk, rst_n;

    wire [31:0] total_ops;
    wire [31:0] active_cyc;
    wire [31:0] idle_cyc;

    // --- 1. DUT ---
    pim_system_top #(
        .ENABLE_PIM(1),
        .DATA_WIDTH(512),
        .ADDR_WIDTH(32)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .mac_ops_count(total_ops),
        .active_cycles(active_cyc),
        .idle_cycles(idle_cyc)
    );

    // --- 2. PERFORMANCE MONITOR ---
    pim_perf_monitor perf_mon (
        .clk(clk), .rst_n(rst_n),
        .active_cycles_in(active_cyc),
        .idle_cycles_in(idle_cyc),
        .total_ops_in(total_ops)
    );

    // --- 3. CLOCK ---
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- 4. METADATA LOADER ---
    // KRITIS: Load SETELAH rst_n=1!
    // Kalau di-load saat rst_n=0, synchronous reset di pim_sparsity_aware
    // akan overwrite metadata_table ke all-1s di setiap clock edge.
    reg [31:0] temp_mem [0:262143]; // 1MB = 262144 words (matching firmware.hex)
    integer m_idx;

    // --- 5. MAIN SIMULATION FLOW ---
    // TIDAK ADA $finish lain selain di sini. Semua debug monitor
    // dari versi sebelumnya harus dihapus untuk mencegah early termination.
    initial begin
        $dumpfile("pim_system.vcd");
        $dumpvars(0, tb_pim_system);

        // Reset sequence
        rst_n = 0;
        #(CLK_PERIOD * 10);
        rst_n = 1;

        // Load metadata tepat setelah reset
        #(CLK_PERIOD * 2);
        $readmemh("firmware.hex", temp_mem);
        for (m_idx = 0; m_idx < 128; m_idx = m_idx + 1) begin
            dut.gen_pim.pim_inst.metadata_table[(m_idx*32) +: 32] = temp_mem[65536 + m_idx];
        end
        $display("[TB] Metadata loaded post-reset. Word[0]=%h", temp_mem[65536]);

        // Tunggu seluruh simulasi
        #(SIM_DURATION);

        // Report — HARUS dipanggil sebelum $finish
        perf_mon.report_metrics();
        $finish;
    end

endmodule
