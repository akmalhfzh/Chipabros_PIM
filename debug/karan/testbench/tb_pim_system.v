`timescale 1ps/1ps

module tb_pim_system;

    localparam integer NUM_OPERATIONS = 3000;
    localparam [31:0]  ADDR_INPUTS    = 32'h0004_0000; // 0x40000
    localparam integer STRIDE_BYTES   = 64;

    // DDR clock (tCK=2500ps)
    reg clk = 0;
    always #1250 clk = ~clk;

    reg rst_n = 0;

    // TB <-> DUT
    reg         req_valid;
    wire        req_ready;
    reg [31:0]  req_addr;

    wire        resp_valid;
    reg         resp_ready;
    wire [511:0] resp_data;

    // DUT counters
    wire [31:0] act, rd, pre, skip;
    wire [31:0] pim_ops, pim_cycles;

    pim_system_top dut (
        .clk(clk),
        .rst_n(rst_n),

        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),

        .resp_valid(resp_valid),
        .resp_ready(resp_ready),
        .resp_data(resp_data),

        .act_count(act),
        .rd_count(rd),
        .pre_count(pre),
        .skip_count(skip),
        .pim_ops_count(pim_ops),
        .pim_cycle_count(pim_cycles)
    );

    // ------------------------------------------------------------
    // Energy model (uJ)
    // ------------------------------------------------------------
    real E_ACT, E_RD, E_PRE;
    real E_MAC_PER_CYCLE;

    real base_energy;
    real dram_energy;
    real pim_compute_energy;
    real pim_total_energy;
    real saving;

    // reductions (must be declared at module scope or top of initial)
    real r_act, r_pre;

    // ------------------------------------------------------------
    // Baseline shadow model (no skip, row-hit aware, SAME mapping)
    // ------------------------------------------------------------
    integer k;
    reg        base_bank_open [0:7];
    reg [12:0] base_open_row  [0:7];
    integer    base_act, base_rd, base_pre;
    integer    base_pim_cycles;

    // MUST match controller mapping:
    // bank = addr[12:10], row = addr[25:13]
    function [2:0] f_bank(input [31:0] a);
        begin f_bank = a[12:10]; end
    endfunction

    function [12:0] f_row(input [31:0] a);
        begin f_row = a[25:13]; end
    endfunction

    task baseline_model_step(input [31:0] a);
        reg [2:0]  b;
        reg [12:0] r;
        begin
            b = f_bank(a);
            r = f_row(a);

            if (base_bank_open[b] && base_open_row[b] == r) begin
                base_rd = base_rd + 1;
            end else if (base_bank_open[b]) begin
                base_pre = base_pre + 1;
                base_act = base_act + 1;
                base_rd  = base_rd  + 1;
                base_open_row[b]  = r;
                base_bank_open[b] = 1'b1;
            end else begin
                base_act = base_act + 1;
                base_rd  = base_rd  + 1;
                base_open_row[b]  = r;
                base_bank_open[b] = 1'b1;
            end

            base_pim_cycles = base_pim_cycles + 16;
        end
    endtask

    integer sent;
    integer received;

    // ------------------------------------------------------------
    // Latency measurement (cycles)
    // ------------------------------------------------------------
    integer cycle_count;
    integer start_cycle;
    integer end_cycle;
    integer total_cycles;

    always @(posedge clk) begin
        if (!rst_n) cycle_count <= 0;
        else        cycle_count <= cycle_count + 1;
    end

    // Keep the exact address that was issued
    reg [31:0] pending_addr;

    initial begin
        $dumpfile("tb_pim_system.vcd");
        $dumpvars(0, tb_pim_system);

        // constants
        E_ACT = 30.0;
        E_RD  = 20.0;
        E_PRE = 15.0;
        E_MAC_PER_CYCLE = 2.0;

        req_valid  = 0;
        req_addr   = 0;
        pending_addr = 0;
        resp_ready = 1;

        // init baseline shadow state
        for (k = 0; k < 8; k = k + 1) begin
            base_bank_open[k] = 1'b0;
            base_open_row[k]  = 13'd0;
        end
        base_act = 0;
        base_rd  = 0;
        base_pre = 0;
        base_pim_cycles = 0;

        // reset
        rst_n = 0;
        #10000;
        rst_n = 1;

        start_cycle = cycle_count;

        sent = 0;
        received = 0;

        // send requests
        while (sent < NUM_OPERATIONS) begin
            @(posedge clk);

            if (!req_valid && req_ready) begin
                pending_addr = ADDR_INPUTS + sent*STRIDE_BYTES;
                req_addr  <= pending_addr;
                req_valid <= 1'b1;
            end

            if (req_valid && req_ready) begin
                baseline_model_step(pending_addr);

                req_valid <= 1'b0;
                sent <= sent + 1;
            end

            if (resp_valid && resp_ready) begin
                received <= received + 1;
            end
        end

        // wait remaining responses
        while (received < NUM_OPERATIONS) begin
            @(posedge clk);
            if (resp_valid && resp_ready) begin
                received <= received + 1;
            end
        end

        end_cycle = cycle_count;
        total_cycles = end_cycle - start_cycle;

        // energies
        base_energy = (base_act * E_ACT) + (base_rd * E_RD) + (base_pre * E_PRE)
                      + (base_pim_cycles * E_MAC_PER_CYCLE);

        dram_energy = (act * E_ACT) + (rd * E_RD) + (pre * E_PRE);
        pim_compute_energy = (pim_cycles * E_MAC_PER_CYCLE);
        pim_total_energy = dram_energy + pim_compute_energy;

        if (base_energy > 0.0)
            saving = ((base_energy - pim_total_energy) / base_energy) * 100.0;
        else
            saving = 0.0;

        // reductions (avoid unsigned wrap by forcing real math)
        if (base_act > 0)
            r_act = 100.0 * (((base_act*1.0) - (act*1.0)) / (base_act*1.0));
        else
            r_act = 0.0;

        if (base_pre > 0)
            r_pre = 100.0 * (((base_pre*1.0) - (pre*1.0)) / (base_pre*1.0));
        else
            r_pre = 0.0;

        // prints
        $display("BASE_CMDS,ACT=%0d,RD=%0d,PRE=%0d,PIM_CYC=%0d",
                 base_act, base_rd, base_pre, base_pim_cycles);

        $display("DUT_CMDS,ACT=%0d,RD=%0d,PRE=%0d,SKIP=%0d,PIM_CYC=%0d",
                 act, rd, pre, skip, pim_cycles);

        $display("LATENCY_CYCLES,%0d", total_cycles);
        $display("REDUCTION_ACT,%0.2f%%", r_act);
        $display("REDUCTION_PRE,%0.2f%%", r_pre);

        $display("ENERGY,BASE=%0.2f,DRAM=%0.2f,PIM_COMP=%0.2f,TOTAL=%0.2f,SAVING=%0.2f%%",
                 base_energy, dram_energy, pim_compute_energy, pim_total_energy, saving);

        // run_all.bat parser compatible
        $display("RESULT,%0d,%0d,%0.2f,%0.2f,%0.2f%%",
                 NUM_OPERATIONS, skip, base_energy, pim_total_energy, saving);

        $finish;
    end

endmodule