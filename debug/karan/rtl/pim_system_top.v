`timescale 1ps/1ps

module pim_system_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,

    output wire        resp_valid,
    input  wire        resp_ready,
    output wire [511:0] resp_data,

    output wire [31:0] act_count,
    output wire [31:0] rd_count,
    output wire [31:0] pre_count,
    output wire [31:0] skip_count
);

    // -----------------------------
    // DDR wires
    // -----------------------------
    wire cke, cs_n, ras_n, cas_n, we_n, odt;
    wire [2:0]  ba;
    wire [13:0] addr;

    // DDR differential clock
    wire ck   = clk;
    wire ck_n = ~clk;

    // DDR data bus (tri-stated for now; we are not capturing DQ yet)
    wire [7:0] dq;
    wire [0:0] dqs;
    wire [0:0] dqs_n;
    wire [0:0] dm_tdqs;
    wire [0:0] tdqs_n;

    assign dq      = 8'hzz;
    assign dqs     = 1'bz;
    assign dqs_n   = 1'bz;
    assign dm_tdqs = 1'bz;

    // -----------------------------
    // PIM wires
    // -----------------------------
    wire pim_start;
    wire pim_done;
    wire [63:0] pim_result;

    // -----------------------------
    // Controller
    // -----------------------------
    dram_controller_ddr3 u_ctrl (
        .clk(clk),
        .rst_n(rst_n),

        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),

        .resp_valid(resp_valid),
        .resp_ready(resp_ready),
        .resp_data(resp_data),

        .cke(cke),
        .cs_n(cs_n),
        .ras_n(ras_n),
        .cas_n(cas_n),
        .we_n(we_n),
        .ba(ba),
        .addr(addr),
        .odt(odt),

        .pim_start(pim_start),
        .pim_done(pim_done),
        .pim_result(pim_result),

        .act_count(act_count),
        .rd_count(rd_count),
        .pre_count(pre_count),
        .skip_count(skip_count)
    );

    // -----------------------------
    // PIM MAC engine (near-memory compute)
    // -----------------------------
    pim_mac_engine u_pim (
        .clk(clk),
        .rst_n(rst_n),
        .start(pim_start),
        .busy(),
        .done(pim_done),
        .result(pim_result)
    );

    // -----------------------------
    // Micron DDR3 blackbox
    // -----------------------------
    ddr3_blackbox u_mem (
        .rst_n(rst_n),
        .ck(ck),
        .ck_n(ck_n),
        .cke(cke),
        .cs_n(cs_n),
        .ras_n(ras_n),
        .cas_n(cas_n),
        .we_n(we_n),
        .ba(ba),
        .addr(addr),
        .odt(odt),

        .dm_tdqs(dm_tdqs),
        .dq(dq),
        .dqs(dqs),
        .dqs_n(dqs_n),
        .tdqs_n(tdqs_n)
    );

endmodule