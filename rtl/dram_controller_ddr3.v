`timescale 1ps/1ps
module dram_controller_ddr3 #(parameter META_DEPTH = 16384)(
    input clk, input rst_n, input req_valid, output reg req_ready, input [31:0] req_addr,
    output reg resp_valid, input resp_ready, output reg [511:0] resp_data,
    output reg cke, cs_n, ras_n, cas_n, we_n, output reg [2:0] ba, output reg [13:0] addr, output reg odt,
    output reg pim_start, input pim_done, input [63:0] pim_result,
    output reg [31:0] act_count, rd_count, pre_count, skip_count, pim_ops_count, pim_cycle_count
);
    wire [2:0] bank = req_addr[12:10]; wire [12:0] row = req_addr[25:13];
    reg [12:0] open_row [0:7]; reg row_open [0:7]; integer i;
    reg meta_mem [0:META_DEPTH-1]; reg [13:0] meta_index;
    initial begin $readmemh("meta.hex", meta_mem); end

    localparam ST_IDLE=3'd0, ST_PRE=3'd1, ST_ACT=3'd2, ST_RD=3'd3, ST_PIM=3'd4, ST_RESP=3'd5;
    reg [2:0] state, lat_bank; reg [12:0] lat_row;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE; req_ready <= 1; resp_valid <= 0; resp_data <= 0; pim_start <= 0;
            act_count <= 0; rd_count <= 0; pre_count <= 0; skip_count<= 0; pim_ops_count <= 0; pim_cycle_count <= 0;
            meta_index <= 0; for(i=0; i<8; i=i+1) begin row_open[i] <= 0; open_row[i] <= 0; end
            cke <= 1; odt <= 0; cs_n <= 1; ras_n<= 1; cas_n<= 1; we_n <= 1; ba <= 0; addr <= 0;
        end else begin
            resp_valid <= 0; pim_start <= 0; cs_n <= 0; ras_n <= 1; cas_n <= 1; we_n <= 1;
            case (state)
                ST_IDLE: begin
                    req_ready <= 1;
                    if (req_valid && req_ready) begin
                        req_ready <= 0; lat_bank <= bank; lat_row <= row;
                        if (meta_mem[meta_index] == 1) begin
                            skip_count <= skip_count + 1; meta_index <= meta_index + 1;
                            resp_data <= 0; resp_valid <= 1; state <= ST_RESP;
                        end else begin
                            if (row_open[bank] && open_row[bank] == row) state <= ST_RD;
                            else if (row_open[bank]) state <= ST_PRE; else state <= ST_ACT;
                        end
                    end
                end
                ST_PRE: begin
                    pre_count <= pre_count + 1; ba <= lat_bank; addr <= 0;
                    cs_n <= 0; ras_n <= 0; cas_n <= 1; we_n <= 0;
                    row_open[lat_bank] <= 0; state <= ST_ACT;
                end
                ST_ACT: begin
                    act_count <= act_count + 1; ba <= lat_bank; addr <= {1'b0, lat_row};
                    cs_n <= 0; ras_n <= 0; cas_n <= 1; we_n <= 1;
                    open_row[lat_bank] <= lat_row; row_open[lat_bank] <= 1; state <= ST_RD;
                end
                ST_RD: begin
                    rd_count <= rd_count + 1; ba <= lat_bank; addr <= 0;
                    cs_n <= 0; ras_n <= 1; cas_n <= 0; we_n <= 1; state <= ST_PIM;
                end
                ST_PIM: begin
                    pim_start <= 1;
                    if (pim_done) begin
                        resp_data <= {448'd0, pim_result}; resp_valid <= 1;
                        meta_index <= meta_index + 1; state <= ST_RESP;
                    end
                end
                ST_RESP: begin if (resp_ready) state <= ST_IDLE; else resp_valid <= 1; end
            endcase
            if (state == ST_RD) begin pim_ops_count <= pim_ops_count + 1; pim_cycle_count <= pim_cycle_count + 16; end
        end
    end
endmodule
