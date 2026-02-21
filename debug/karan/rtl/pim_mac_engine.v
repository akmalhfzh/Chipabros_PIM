`timescale 1ps/1ps

module pim_mac_engine #(
    parameter BLOCK_SIZE = 16
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,
    output reg         busy,
    output reg         done,

    // Dummy input vectors (for now generated internally)
    output reg [63:0]  result
);

    reg [4:0]  idx;
    reg [63:0] acc;

    // For realism: simple deterministic pattern
    wire [31:0] x = idx + 1;
    wire [31:0] w = (idx + 1) << 1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx   <= 0;
            acc   <= 0;
            busy  <= 0;
            done  <= 0;
            result<= 0;
        end else begin
            done <= 0;

            if (start && !busy) begin
                busy <= 1;
                idx  <= 0;
                acc  <= 0;
            end
            else if (busy) begin
                acc <= acc + (x * w);
                idx <= idx + 1;

                if (idx == BLOCK_SIZE-1) begin
                    busy   <= 0;
                    done   <= 1;
                    result <= acc + (x * w);
                end
            end
        end
    end

endmodule