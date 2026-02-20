`timescale 1ps/1ps

module dram_controller_ddr3 #(
    parameter META_BASE_ADDR = 32'h0004_0000, // 0x40000
    parameter NUM_META       = 3000,

    // Representative DDR timing (cycles)
    parameter tRCD_CYC = 6,
    parameter tRP_CYC  = 6,
    parameter CL_CYC   = 6
)(
    input  wire        clk,
    input  wire        rst_n,

    // Host interface
    input  wire        req_valid,
    output reg         req_ready,
    input  wire [31:0] req_addr,

    output reg         resp_valid,
    input  wire        resp_ready,
    output reg [511:0] resp_data,

    // DDR3 pins
    output reg         cke,
    output reg         cs_n,
    output reg         ras_n,
    output reg         cas_n,
    output reg         we_n,
    output reg [2:0]   ba,
    output reg [13:0]  addr,
    output reg         odt,

    // PIM engine
    output reg         pim_start,
    input  wire        pim_done,
    input  wire [63:0] pim_result,

    // Stats
    output reg [31:0]  act_count,
    output reg [31:0]  rd_count,
    output reg [31:0]  pre_count,
    output reg [31:0]  skip_count
);

    // -------------------------------
    // Metadata
    // -------------------------------
    reg meta_mem [0:NUM_META-1];

    initial begin
        $readmemh("meta.hex", meta_mem);
    end

    wire [31:0] meta_idx = (req_addr - META_BASE_ADDR) >> 6;

    // -------------------------------
    // Simple address mapping
    // -------------------------------
    wire [13:0] row  = req_addr[31:18];
    wire [9:0]  col  = req_addr[17:8];
    wire [2:0]  bank = req_addr[7:5];

    reg row_open;
    reg [2:0]  open_bank;
    reg [13:0] open_row;

    // -------------------------------
    // DDR command helpers
    // -------------------------------
    task cmd_nop;
    begin
        cs_n  <= 0;
        ras_n <= 1;
        cas_n <= 1;
        we_n  <= 1;
    end
    endtask

    task cmd_precharge;
        input [2:0] b;
    begin
        cs_n  <= 0;
        ras_n <= 0;
        cas_n <= 1;
        we_n  <= 0;
        ba    <= b;
        addr  <= 14'b0;
    end
    endtask

    task cmd_activate;
        input [2:0] b;
        input [13:0] r;
    begin
        cs_n  <= 0;
        ras_n <= 0;
        cas_n <= 1;
        we_n  <= 1;
        ba    <= b;
        addr  <= r;
    end
    endtask

    task cmd_read;
        input [2:0] b;
        input [9:0] c;
    begin
        cs_n  <= 0;
        ras_n <= 1;
        cas_n <= 0;
        we_n  <= 1;
        ba    <= b;
        addr  <= {4'b0000, c};
    end
    endtask

    // -------------------------------
    // FSM
    // -------------------------------
    localparam ST_INIT      = 0,
               ST_IDLE      = 1,
               ST_CHECK     = 2,
               ST_PRE       = 3,
               ST_WAIT_RP   = 4,
               ST_ACT       = 5,
               ST_WAIT_RCD  = 6,
               ST_RD        = 7,
               ST_WAIT_CL   = 8,
               ST_PIM_START = 9,
               ST_PIM_WAIT  = 10,
               ST_RESP      = 11;

    reg [3:0] state;
    integer timer;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cke <= 0;
            odt <= 0;
            cs_n <= 1;
            ras_n <= 1;
            cas_n <= 1;
            we_n  <= 1;

            req_ready  <= 0;
            resp_valid <= 0;
            resp_data  <= 0;

            act_count  <= 0;
            rd_count   <= 0;
            pre_count  <= 0;
            skip_count <= 0;

            row_open <= 0;
            open_bank<= 0;
            open_row <= 0;

            pim_start <= 0;

            state <= ST_INIT;
        end
        else begin
            cmd_nop();
            pim_start <= 0;

            case (state)

            ST_INIT: begin
                cke <= 1;
                req_ready <= 1;
                state <= ST_IDLE;
            end

            ST_IDLE: begin
                resp_valid <= 0;
                if (req_valid && req_ready) begin
                    req_ready <= 0;
                    state <= ST_CHECK;
                end
            end

            ST_CHECK: begin
                if (meta_idx < NUM_META && meta_mem[meta_idx] == 0) begin
                    // ZERO BLOCK → skip DRAM + skip compute
                    skip_count <= skip_count + 1;
                    resp_data  <= 0;
                    resp_valid <= 1;
                    state <= ST_RESP;
                end
                else begin
                    if (row_open && open_bank==bank && open_row==row)
                        state <= ST_RD;
                    else if (row_open)
                        state <= ST_PRE;
                    else
                        state <= ST_ACT;
                end
            end

            ST_PRE: begin
                cmd_precharge(open_bank);
                pre_count <= pre_count + 1;
                row_open <= 0;
                timer <= tRP_CYC;
                state <= ST_WAIT_RP;
            end

            ST_WAIT_RP: begin
                if (timer==0) state <= ST_ACT;
                else timer <= timer - 1;
            end

            ST_ACT: begin
                cmd_activate(bank,row);
                act_count <= act_count + 1;
                open_bank <= bank;
                open_row  <= row;
                row_open  <= 1;
                timer <= tRCD_CYC;
                state <= ST_WAIT_RCD;
            end

            ST_WAIT_RCD: begin
                if (timer==0) state <= ST_RD;
                else timer <= timer - 1;
            end

            ST_RD: begin
                cmd_read(bank,col);
                rd_count <= rd_count + 1;
                timer <= CL_CYC;
                state <= ST_WAIT_CL;
            end

            ST_WAIT_CL: begin
                if (timer==0)
                    state <= ST_PIM_START;
                else
                    timer <= timer - 1;
            end

            ST_PIM_START: begin
                pim_start <= 1;
                state <= ST_PIM_WAIT;
            end

            ST_PIM_WAIT: begin
                if (pim_done) begin
                    resp_data  <= {448'b0, pim_result};
                    resp_valid <= 1;
                    state <= ST_RESP;
                end
            end

            ST_RESP: begin
                if (resp_valid && resp_ready) begin
                    resp_valid <= 0;
                    req_ready  <= 1;
                    state <= ST_IDLE;
                end
            end

            default: state <= ST_IDLE;

            endcase
        end
    end

endmodule