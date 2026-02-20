`timescale 1ps/1ps

module pim_system_top (


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

    // DDR clock differential
    wire ck;
    wire ck_n;

    // -----------------------------
    // PIM wires
    // -----------------------------
    wire pim_start;
    wire pim_done;
    wire [63:0] pim_result;

    assign ck   = clk;
    assign ck_n = ~clk;

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
    // PIM MAC engine
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
    .ck   (ck),
    .ck_n (ck_n),
    .cke  (cke),
    .cs_n (cs_n),
    .ras_n(ras_n),
    .cas_n(cas_n),
    .we_n (we_n),
    .ba   (ba),
    .addr (addr),
    .odt  (odt)
    );

endmodule