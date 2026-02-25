`timescale 1ps/1ps
module ddr3_blackbox #(parameter ADDR_BITS = 14, parameter BA_BITS = 3)(
    input rst_n, input ck, input ck_n, input cke, input cs_n, input ras_n, input cas_n, input we_n,
    input [BA_BITS-1:0] ba, input [ADDR_BITS-1:0] addr, input odt,
    inout [0:0] dm_tdqs, inout [7:0] dq, inout [0:0] dqs, inout [0:0] dqs_n, output [0:0] tdqs_n
);
    ddr3 u_ddr3 (
        .rst_n(rst_n), .ck(ck), .ck_n(ck_n), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .dm_tdqs(dm_tdqs), .ba(ba), .addr(addr), .dq(dq), .dqs(dqs), .dqs_n(dqs_n), .tdqs_n(tdqs_n), .odt(odt)
    );
endmodule
