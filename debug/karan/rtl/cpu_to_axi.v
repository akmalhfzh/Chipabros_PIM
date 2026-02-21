/*
 * CPU to AXI4 Adapter - ZVC & STICKY HANDSHAKE
 * Menerima ruser untuk dekompresi data nol.
 */
module cpu_to_axi #(
    parameter DATA_WIDTH = 512,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    // CPU side
    input  wire        mem_valid, input wire mem_instr,
    output wire        mem_ready, // Wire (Instan)
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata, input wire [3:0]  mem_wstrb,
    output reg  [31:0] mem_rdata,
    
    // AXI side
    output reg [ID_WIDTH-1:0] m_axi_awid, output reg [ADDR_WIDTH-1:0] m_axi_awaddr, output reg [7:0] m_axi_awlen, output reg [2:0] m_axi_awsize, output reg [1:0] m_axi_awburst, output reg m_axi_awvalid, input wire m_axi_awready,
    output reg [DATA_WIDTH-1:0] m_axi_wdata, output reg [DATA_WIDTH/8-1:0] m_axi_wstrb, output reg m_axi_wlast, output reg m_axi_wvalid, input wire m_axi_wready,
    input wire [ID_WIDTH-1:0] m_axi_bid, input wire [1:0] m_axi_bresp, input wire m_axi_bvalid, output reg m_axi_bready,
    output reg [ID_WIDTH-1:0] m_axi_arid, output reg [ADDR_WIDTH-1:0] m_axi_araddr, output reg [7:0] m_axi_arlen, output reg [2:0] m_axi_arsize, output reg [1:0] m_axi_arburst, output reg m_axi_arvalid, input wire m_axi_arready,
    input wire [ID_WIDTH-1:0] m_axi_rid, 
    input wire [DATA_WIDTH-1:0] m_axi_rdata, 
    input wire m_axi_ruser, // FLAG KOMPRESI
    input wire [1:0] m_axi_rresp, input wire m_axi_rlast, input wire m_axi_rvalid, output reg m_axi_rready
);

    localparam IDLE = 0, READ_ADDR = 1, READ_DATA = 2, WRITE_ADDR = 3, WRITE_DATA = 4, WRITE_RESP = 5, HOLD_DONE = 6;
    reg [2:0] state;

    assign mem_ready = (state == HOLD_DONE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            m_axi_awvalid <= 0; m_axi_wvalid <= 0; m_axi_arvalid <= 0;
            m_axi_rready <= 0; m_axi_bready <= 0;
            m_axi_awlen <= 0; m_axi_awsize <= 2; m_axi_awburst <= 1;
            m_axi_arlen <= 0; m_axi_arsize <= 2; m_axi_arburst <= 1;
        end else begin
            case (state)
                IDLE: begin
                    if (mem_valid) begin
                        if (|mem_wstrb) begin
                            // BUG FIX: Align ke 64-byte cache-line boundary.
                            // cpu_to_axi mengekstrak word ke-(mem_addr[5:2]) dari burst 512-bit.
                            // Formula ini hanya benar jika memory mulai mengembalikan data dari
                            // cache-line boundary (bukan dari araddr apa adanya).
                            // Tanpa alignment: PC=0x0C → araddr=0x0C → memory mulai dari word[3]
                            // → extract[3] = word[6] = instruksi di 0x18! (SALAH!)
                            // Dengan alignment: PC=0x0C → araddr=0x00 → memory mulai dari word[0]
                            // → extract[3] = word[3] = instruksi di 0x0C! (BENAR!)
                            m_axi_awaddr <= {mem_addr[31:6], 6'b0}; m_axi_awvalid <= 1; state <= WRITE_ADDR;
                        end else begin
                            m_axi_araddr <= {mem_addr[31:6], 6'b0}; m_axi_arvalid <= 1; state <= READ_ADDR;
                        end
                    end
                end
                READ_ADDR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 0; m_axi_rready <= 1; state <= READ_DATA;
                    end
                end
                READ_DATA: begin
                    if (m_axi_rvalid) begin
                        // --- ZVC LOGIC ---
                        if (m_axi_ruser) begin
                            // Flag is ON: Generate Local Zero (Hemat Energi Bus)
                            mem_rdata <= 32'h00000000;
                            // $display("[ADAPTER] Compressed Zero received. Generating locally.");
                        end else begin
                            // Flag is OFF: Baca Bus
                            mem_rdata <= m_axi_rdata[(mem_addr[5:2]*32) +: 32];
                        end
                        m_axi_rready <= 0;
                        state <= HOLD_DONE;
                    end
                end
                WRITE_ADDR: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 0;
                        m_axi_wdata <= {{(DATA_WIDTH-32){1'b0}}, mem_wdata} << (mem_addr[5:2]*32);
                        m_axi_wstrb <= {{(DATA_WIDTH/8-4){1'b0}}, mem_wstrb} << (mem_addr[5:2]*4);
                        m_axi_wvalid <= 1; m_axi_wlast <= 1; state <= WRITE_DATA;
                    end
                end
                WRITE_DATA: begin
                    if (m_axi_wready) begin
                        m_axi_wvalid <= 0; m_axi_bready <= 1; state <= WRITE_RESP;
                    end
                end
                WRITE_RESP: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 0; state <= HOLD_DONE;
                    end
                end
                HOLD_DONE: begin
                    if (!mem_valid) state <= IDLE;
                end
            endcase
        end
    end
endmodule
