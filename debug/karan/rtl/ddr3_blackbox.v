// rtl/ddr3_blackbox.v
`timescale 1ps/1ps

module ddr3_blackbox #(
    parameter ADDR_BITS = 14, // typical for 1Gb x8
    parameter BA_BITS   = 3
)(
    input  wire rst_n,
    input  wire ck,
    input  wire ck_n,
    input  wire cke,
    input  wire cs_n,
    input  wire ras_n,
    input  wire cas_n,
    input  wire we_n,
    input  wire [BA_BITS-1:0]   ba,
    input  wire [ADDR_BITS-1:0] addr,
    input  wire odt,

    inout  wire [0:0] dm_tdqs,   // for x8: DM_BITS usually 1 (safe stub)
    inout  wire [7:0] dq,        // x8
    inout  wire [0:0] dqs,
    inout  wire [0:0] dqs_n,
    output wire [0:0] tdqs_n
);

    // Instantiate Micron DDR3 model directly
    ddr3 u_ddr3 (
        .rst_n   (rst_n),
        .ck      (ck),
        .ck_n    (ck_n),
        .cke     (cke),
        .cs_n    (cs_n),
        .ras_n   (ras_n),
        .cas_n   (cas_n),
        .we_n    (we_n),
        .dm_tdqs (dm_tdqs),
        .ba      (ba),
        .addr    (addr),
        .dq      (dq),
        .dqs     (dqs),
        .dqs_n   (dqs_n),
        .tdqs_n  (tdqs_n),
        .odt     (odt)
    );

endmodule