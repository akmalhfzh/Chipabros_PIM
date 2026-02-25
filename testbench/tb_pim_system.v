`timescale 1ps/1ps
module tb_pim_system;
    localparam integer NUM_OPERATIONS = 3000;
    localparam [31:0] ADDR_INPUTS = 32'h0004_0000;
    localparam integer STRIDE_BYTES = 64;

    reg clk = 0; always #1250 clk = ~clk; reg rst_n = 0;
    reg req_valid; wire req_ready; reg [31:0] req_addr; wire resp_valid; reg resp_ready; wire [511:0] resp_data;
    wire [31:0] act, rd, pre, skip, pim_ops, pim_cycles;

    pim_system_top dut (
        .clk(clk), .rst_n(rst_n), .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr),
        .resp_valid(resp_valid), .resp_ready(resp_ready), .resp_data(resp_data),
        .act_count(act), .rd_count(rd), .pre_count(pre), .skip_count(skip), .pim_ops_count(pim_ops), .pim_cycle_count(pim_cycles)
    );

    real E_ACT=30.0, E_RD=20.0, E_PRE=15.0, E_MAC_PER_CYCLE=2.0;
    real base_energy, dram_energy, pim_compute_energy, pim_total_energy, saving;
    integer k, base_act, base_rd, base_pre, base_pim_cycles, sent, received;
    reg base_bank_open [0:7]; reg [12:0] base_open_row [0:7];

    function [2:0] f_bank(input [31:0] a); begin f_bank = a[12:10]; end endfunction
    function [12:0] f_row(input [31:0] a); begin f_row = a[25:13]; end endfunction

    task baseline_model_step(input [31:0] a);
        reg [2:0] b; reg [12:0] r;
        begin
            b = f_bank(a); r = f_row(a);
            if (base_bank_open[b] && base_open_row[b] == r) base_rd = base_rd + 1;
            else if (base_bank_open[b]) begin base_pre = base_pre+1; base_act = base_act+1; base_rd = base_rd+1; end
            else begin base_act = base_act+1; base_rd = base_rd+1; end
            base_open_row[b] = r; base_bank_open[b] = 1; base_pim_cycles = base_pim_cycles + 16;
        end
    endtask

    initial begin
        req_valid = 0; req_addr = 0; resp_ready = 1;
        for (k=0; k<8; k=k+1) begin base_bank_open[k] = 0; base_open_row[k] = 0; end
        base_act = 0; base_rd = 0; base_pre = 0; base_pim_cycles = 0;
        rst_n = 0; #10000; rst_n = 1; sent = 0; received = 0;

        while (sent < NUM_OPERATIONS) begin
            @(posedge clk);
            if (!req_valid && req_ready) begin
                req_addr <= ADDR_INPUTS + sent*STRIDE_BYTES; req_valid <= 1;
            end
            if (req_valid && req_ready) begin baseline_model_step(req_addr); req_valid <= 0; sent <= sent + 1; end
            if (resp_valid && resp_ready) received <= received + 1;
        end
        while (received < NUM_OPERATIONS) begin
            @(posedge clk); if (resp_valid && resp_ready) received <= received + 1;
        end

        base_energy = (base_act*E_ACT) + (base_rd*E_RD) + (base_pre*E_PRE) + (base_pim_cycles*E_MAC_PER_CYCLE);
        dram_energy = (act*E_ACT) + (rd*E_RD) + (pre*E_PRE);
        pim_compute_energy = (pim_cycles*E_MAC_PER_CYCLE);
        pim_total_energy = dram_energy + pim_compute_energy;
        if (base_energy > 0.0) saving = ((base_energy - pim_total_energy) / base_energy) * 100.0; else saving = 0.0;
        
        $display("BASE_CMDS,ACT=%0d,RD=%0d,PRE=%0d,PIM_CYC=%0d", base_act, base_rd, base_pre, base_pim_cycles);
        $display("DUT_CMDS,ACT=%0d,RD=%0d,PRE=%0d,SKIP=%0d,PIM_CYC=%0d", act, rd, pre, skip, pim_cycles);
        
        $display("RESULT,%0d,%0d,%0.2f,%0.2f,%0.2f%%", NUM_OPERATIONS, skip, base_energy, pim_total_energy, saving);
        $finish;
    end
endmodule
