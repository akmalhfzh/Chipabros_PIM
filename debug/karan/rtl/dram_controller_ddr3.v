`timescale 1ps/1ps

module dram_controller_ddr3 #(
    parameter META_DEPTH = 16384
)(
    input  wire        clk,
    input  wire        rst_n,

    // Request channel
    input  wire        req_valid,
    output reg         req_ready,
    input  wire [31:0] req_addr,

    // Response channel
    output reg         resp_valid,
    input  wire        resp_ready,
    output reg [511:0] resp_data,

    // DDR signals (blackbox driven only for activity visibility)
    output reg        cke,
    output reg        cs_n,
    output reg        ras_n,
    output reg        cas_n,
    output reg        we_n,
    output reg [2:0]  ba,
    output reg [13:0] addr,
    output reg        odt,

    // PIM engine
    output reg        pim_start,
    input  wire       pim_done,
    input  wire [63:0] pim_result,

    // Counters
    output reg [31:0] act_count,
    output reg [31:0] rd_count,
    output reg [31:0] pre_count,
    output reg [31:0] skip_count,
    output reg [31:0] pim_ops_count,
    output reg [31:0] pim_cycle_count
);

    // -------------------------------------------------
    // DDR3-like address mapping (8KB row)
    // -------------------------------------------------
    wire [2:0]  bank = req_addr[12:10];   // 8 banks
    wire [12:0] row  = req_addr[25:13];   // 8KB row index

    // -------------------------------------------------
    // Row buffer tracking per bank
    // -------------------------------------------------
    reg [12:0] open_row [0:7];
    reg        row_open [0:7];
    integer i;

    // -------------------------------------------------
    // Metadata memory: 1 = SKIP, 0 = EXECUTE
    // -------------------------------------------------
    reg meta_mem [0:META_DEPTH-1];
    reg [13:0] meta_index;

    initial begin
        $readmemh("meta.hex", meta_mem);
    end

    // -------------------------------------------------
    // FSM states
    // -------------------------------------------------
    localparam [2:0]
        ST_IDLE = 3'd0,
        ST_PRE  = 3'd1,
        ST_ACT  = 3'd2,
        ST_RD   = 3'd3,
        ST_PIM  = 3'd4,
        ST_RESP = 3'd5;

    reg [2:0] state;

    // latch decode
    reg [2:0]  lat_bank;
    reg [12:0] lat_row;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;

            req_ready  <= 1'b1;
            resp_valid <= 1'b0;
            resp_data  <= 512'b0;

            pim_start <= 1'b0;

            act_count <= 32'd0;
            rd_count  <= 32'd0;
            pre_count <= 32'd0;
            skip_count<= 32'd0;
            pim_ops_count   <= 32'd0;
            pim_cycle_count <= 32'd0;

            meta_index <= 14'd0;

            for (i=0; i<8; i=i+1) begin
                row_open[i] <= 1'b0;
                open_row[i] <= 13'd0;
            end

            // DDR outputs
            cke  <= 1'b1;
            odt  <= 1'b0;
            cs_n <= 1'b1;
            ras_n<= 1'b1;
            cas_n<= 1'b1;
            we_n <= 1'b1;
            ba   <= 3'd0;
            addr <= 14'd0;

            lat_bank <= 3'd0;
            lat_row  <= 13'd0;

        end else begin
            // defaults
            resp_valid <= 1'b0;
            pim_start  <= 1'b0;

            // NOP default
            cs_n  <= 1'b0;
            ras_n <= 1'b1;
            cas_n <= 1'b1;
            we_n  <= 1'b1;

            case (state)

                ST_IDLE: begin
                    req_ready <= 1'b1;

                    if (req_valid && req_ready) begin
                        req_ready <= 1'b0;

                        lat_bank <= bank;
                        lat_row  <= row;

                        // meta: 1 => skip
                        if (meta_mem[meta_index] == 1'b1) begin
                            skip_count <= skip_count + 1;
                            meta_index <= meta_index + 1;

                            resp_data  <= 512'b0;
                            resp_valid <= 1'b1;
                            state      <= ST_RESP;
                        end else begin
                            // execute: row-hit aware
                            if (row_open[bank] && open_row[bank] == row) begin
                                state <= ST_RD;
                            end else if (row_open[bank]) begin
                                state <= ST_PRE; // conflict
                            end else begin
                                state <= ST_ACT; // closed
                            end
                        end
                    end
                end

                ST_PRE: begin
                    // PRECHARGE (per-bank)
                    pre_count <= pre_count + 1;

                    ba    <= lat_bank;
                    addr  <= 14'd0;
                    cs_n  <= 1'b0;
                    ras_n <= 1'b0;
                    cas_n <= 1'b1;
                    we_n  <= 1'b0;

                    row_open[lat_bank] <= 1'b0;

                    state <= ST_ACT;
                end

                ST_ACT: begin
                    // ACTIVATE
                    act_count <= act_count + 1;

                    ba    <= lat_bank;
                    addr  <= {1'b0, lat_row}; // 13->14
                    cs_n  <= 1'b0;
                    ras_n <= 1'b0;
                    cas_n <= 1'b1;
                    we_n  <= 1'b1;

                    open_row[lat_bank] <= lat_row;
                    row_open[lat_bank] <= 1'b1;

                    state <= ST_RD;
                end

                ST_RD: begin
                    // READ
                    rd_count <= rd_count + 1;

                    ba    <= lat_bank;
                    addr  <= 14'd0;
                    cs_n  <= 1'b0;
                    ras_n <= 1'b1;
                    cas_n <= 1'b0;
                    we_n  <= 1'b1;

                    state <= ST_PIM;
                end

                ST_PIM: begin
                    // Start PIM compute (serialized 16 cycles)
                    pim_start <= 1'b1;

                    // count only once per operation (guard by counting at entry)
                    // easiest: count when we first assert pim_start
                    // but pim_start asserts every cycle in this state,
                    // so only increment when state just entered.
                    // We'll use pim_ops_count==meta_index trick? (no)
                    // Simpler: increment when we transition into ST_PIM (done below)

                    if (pim_done) begin
                        resp_data <= {448'd0, pim_result};
                        resp_valid <= 1'b1;

                        meta_index <= meta_index + 1;
                        state <= ST_RESP;
                    end
                end

                ST_RESP: begin
                    // hold response until accepted
                    if (resp_ready) begin
                        state <= ST_IDLE;
                    end else begin
                        resp_valid <= 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase

            // -------------------------------------------------
            // PIM counters update on state transition into ST_PIM
            // -------------------------------------------------
            // Detect rising edge of entering ST_PIM:
            // If current state is ST_RD and next state becomes ST_PIM, count.
            if (state == ST_RD) begin
                // we always go ST_RD -> ST_PIM
                pim_ops_count   <= pim_ops_count + 1;
                pim_cycle_count <= pim_cycle_count + 16;
            end

        end
    end

endmodule