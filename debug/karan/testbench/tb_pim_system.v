`timescale 1ps/1ps

module tb_pim_system;

    // Must match gen_testcase.py
    localparam integer NUM_OPERATIONS = 3000;
    localparam [31:0] ADDR_INPUTS = 32'h0004_0000; // 0x40000
    localparam integer STRIDE_BYTES   = 64;

    // DDR3-800 example: tCK = 2500ps
    reg clk = 0;
    always #1250 clk = ~clk;

    reg rst_n = 0;

    // TB <-> DUT request/response
    reg         req_valid;
    wire        req_ready;
    reg [31:0]  req_addr;

    wire        resp_valid;
    reg         resp_ready;
    wire [511:0] resp_data;

    // Stats
    wire [31:0] act, rd, pre, skip;

    // DUT (NO PARAMETERS)
    pim_system_top dut (
        .clk(clk),
        .rst_n(rst_n),

        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),

        .resp_valid(resp_valid),
        .resp_ready(resp_ready),
        .resp_data(resp_data),

        .act_count(act),
        .rd_count(rd),
        .pre_count(pre),
        .skip_count(skip)
    );

    // Energy model (uJ) - you can tune later
    real E_ACT, E_RD, E_PRE;
    real base_energy, pim_energy, saving;

    integer sent;
    integer received;

    initial begin
        $dumpfile("ddr3_cmdlevel.vcd");
        $dumpvars(0, tb_pim_system);

        // Energy constants
        E_ACT = 30.0;
        E_RD  = 20.0;
        E_PRE = 15.0;

        req_valid  = 0;
        req_addr   = 0;
        resp_ready = 1;

        // Reset
        rst_n = 0;
        #10000;   // 10ns in ps
        rst_n = 1;

        sent = 0;
        received = 0;

        // Send NUM_OPERATIONS requests (handshake)
        while (sent < NUM_OPERATIONS) begin
            @(posedge clk);

            if (!req_valid && req_ready) begin
                req_addr  <= ADDR_INPUTS + sent*STRIDE_BYTES;
                req_valid <= 1'b1;
            end

            if (req_valid && req_ready) begin
                req_valid <= 1'b0;
                sent <= sent + 1;
            end

            if (resp_valid && resp_ready) begin
                received <= received + 1;
            end
        end

        // Wait for remaining responses
        while (received < NUM_OPERATIONS) begin
            @(posedge clk);
            if (resp_valid && resp_ready) begin
                received <= received + 1;
            end
        end

        // Baseline: no skipping, assume ACT+RD+PRE each access
        base_energy = NUM_OPERATIONS * (E_ACT + E_RD + E_PRE);

        // Our design: count commands issued by controller
        pim_energy  = (act * E_ACT) + (rd * E_RD) + (pre * E_PRE);

        if (base_energy > 0.0)
            saving = ((base_energy - pim_energy) / base_energy) * 100.0;
        else
            saving = 0.0;

        $display("RESULT,%0d,%0d,%0.2f,%0.2f,%0.2f%%",
                 NUM_OPERATIONS, skip, base_energy, pim_energy, saving);

        $finish;
    end

endmodule