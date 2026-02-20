/*
 * Simple Memory - 1MB
 * Safe 32-bit Loading
 */
module simple_memory #(
    parameter DATA_WIDTH = 512,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH = 8,
    parameter MEM_SIZE = 1048576 // 1MB
)(
    input  wire clk, input wire rst_n,
    input  wire [ID_WIDTH-1:0] s_axi_awid, input wire [ADDR_WIDTH-1:0] s_axi_awaddr, input wire [7:0] s_axi_awlen, input wire [2:0] s_axi_awsize, input wire [1:0] s_axi_awburst, input wire s_axi_awvalid, output reg s_axi_awready,
    input  wire [DATA_WIDTH-1:0] s_axi_wdata, input wire [DATA_WIDTH/8-1:0] s_axi_wstrb, input wire s_axi_wlast, input wire s_axi_wvalid, output reg s_axi_wready,
    output reg [ID_WIDTH-1:0] s_axi_bid, output reg [1:0] s_axi_bresp, output reg s_axi_bvalid, input wire s_axi_bready,
    input  wire [ID_WIDTH-1:0] s_axi_arid, input wire [ADDR_WIDTH-1:0] s_axi_araddr, input wire [7:0] s_axi_arlen, input wire [2:0] s_axi_arsize, input wire [1:0] s_axi_arburst, input wire s_axi_arvalid, output reg s_axi_arready,
    output reg [ID_WIDTH-1:0] s_axi_rid, output reg [DATA_WIDTH-1:0] s_axi_rdata, output reg [1:0] s_axi_rresp, output reg s_axi_rlast, output reg s_axi_rvalid, input wire s_axi_rready
);

    // 32-bit array. Size / 4 words.
    reg [31:0] memory [0:(MEM_SIZE/4)-1];

    initial begin
        // Clear memory first to avoid X
        // integer i; for(i=0; i<(MEM_SIZE/4); i=i+1) memory[i] = 32'h0;
        
        // Load Hex (Format: 32-bit hex string per line)
        $readmemh("firmware.hex", memory);
    end

    // AXI Read Logic
    reg [ADDR_WIDTH-1:0] read_addr;
    reg [7:0] read_len, read_count;
    reg read_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1; s_axi_rvalid <= 0; read_active <= 0;
            s_axi_awready <= 1; s_axi_wready <= 0; s_axi_bvalid <= 0;
        end else begin
            // READ
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 0;
                read_addr <= s_axi_araddr;
                read_len <= s_axi_arlen;
                read_count <= 0;
                read_active <= 1;
                s_axi_rid <= s_axi_arid;
            end

            if (read_active) begin
                if (!s_axi_rvalid || s_axi_rready) begin
                    s_axi_rvalid <= 1;
                    // Construct 512-bit word from 16 x 32-bit words
                    // Indexing: address / 4
                    s_axi_rdata[31:0]    <= memory[(read_addr/4) + 0];
                    s_axi_rdata[63:32]   <= memory[(read_addr/4) + 1];
                    s_axi_rdata[95:64]   <= memory[(read_addr/4) + 2];
                    s_axi_rdata[127:96]  <= memory[(read_addr/4) + 3];
                    s_axi_rdata[159:128] <= memory[(read_addr/4) + 4];
                    s_axi_rdata[191:160] <= memory[(read_addr/4) + 5];
                    s_axi_rdata[223:192] <= memory[(read_addr/4) + 6];
                    s_axi_rdata[255:224] <= memory[(read_addr/4) + 7];
                    s_axi_rdata[287:256] <= memory[(read_addr/4) + 8];
                    s_axi_rdata[319:288] <= memory[(read_addr/4) + 9];
                    s_axi_rdata[351:320] <= memory[(read_addr/4) + 10];
                    s_axi_rdata[383:352] <= memory[(read_addr/4) + 11];
                    s_axi_rdata[415:384] <= memory[(read_addr/4) + 12];
                    s_axi_rdata[447:416] <= memory[(read_addr/4) + 13];
                    s_axi_rdata[479:448] <= memory[(read_addr/4) + 14];
                    s_axi_rdata[511:480] <= memory[(read_addr/4) + 15];

                    s_axi_rresp <= 0;
                    if (read_count == read_len) begin
                        s_axi_rlast <= 1;
                        read_active <= 0;
                        s_axi_arready <= 1;
                    end else begin
                        s_axi_rlast <= 0;
                        read_count <= read_count + 1;
                        read_addr <= read_addr + 64;
                    end
                end
            end else begin
                s_axi_rvalid <= 0; s_axi_rlast <= 0;
            end

            // WRITE (Dummy)
            if (s_axi_awvalid && s_axi_awready) begin
                s_axi_awready <= 0; s_axi_wready <= 1;
            end
            if (s_axi_wvalid && s_axi_wready && s_axi_wlast) begin
                s_axi_wready <= 0; s_axi_bvalid <= 1; s_axi_awready <= 1;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
        end
    end
endmodule
