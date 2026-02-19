module pim_system_top #(
    parameter ENABLE_PIM = 1,
    parameter DATA_WIDTH = 512,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] mac_ops_count,
    output wire [31:0] active_cycles,
    output wire [31:0] idle_cycles
);
    // Wires Declaration
    wire [ID_WIDTH-1:0] m_axi_awid; wire [ADDR_WIDTH-1:0] m_axi_awaddr; wire [7:0] m_axi_awlen; wire [2:0] m_axi_awsize; wire [1:0] m_axi_awburst; wire m_axi_awvalid, m_axi_awready;
    wire [DATA_WIDTH-1:0] m_axi_wdata; wire [DATA_WIDTH/8-1:0] m_axi_wstrb; wire m_axi_wlast, m_axi_wvalid, m_axi_wready;
    wire [ID_WIDTH-1:0] m_axi_bid; wire [1:0] m_axi_bresp; wire m_axi_bvalid, m_axi_bready;
    wire [ID_WIDTH-1:0] m_axi_arid; wire [ADDR_WIDTH-1:0] m_axi_araddr; wire [7:0] m_axi_arlen; wire [2:0] m_axi_arsize; wire [1:0] m_axi_arburst; wire m_axi_arvalid, m_axi_arready;
    wire [ID_WIDTH-1:0] m_axi_rid; wire [DATA_WIDTH-1:0] m_axi_rdata; wire [1:0] m_axi_rresp; wire m_axi_rlast, m_axi_rvalid, m_axi_rready;
    wire m_axi_ruser; // Dummy

    // PIM to Mem Wires
    wire [ID_WIDTH-1:0] p_awid; wire [ADDR_WIDTH-1:0] p_awaddr; wire [7:0] p_awlen; wire [2:0] p_awsize; wire [1:0] p_awburst; wire p_awvalid, p_awready;
    wire [DATA_WIDTH-1:0] p_wdata; wire [DATA_WIDTH/8-1:0] p_wstrb; wire p_wlast, p_wvalid, p_wready;
    wire [ID_WIDTH-1:0] p_bid; wire [1:0] p_bresp; wire p_bvalid, p_bready;
    wire [ID_WIDTH-1:0] p_arid; wire [ADDR_WIDTH-1:0] p_araddr; wire [7:0] p_arlen; wire [2:0] p_arsize; wire [1:0] p_arburst; wire p_arvalid, p_arready;
    wire [ID_WIDTH-1:0] p_rid; wire [DATA_WIDTH-1:0] p_rdata; wire [1:0] p_rresp; wire p_rlast, p_rvalid, p_rready;

    // Internal wires
    wire cpu_valid, cpu_instr, cpu_ready; wire [31:0] cpu_addr, cpu_wdata, cpu_rdata; wire [3:0] cpu_wstrb;

    // 1. CPU
    simple_riscv_cpu #(.RESET_ADDR(32'h0000_0000)) cpu_inst (
        .clk(clk), .resetn(rst_n), .mem_valid(cpu_valid), .mem_instr(cpu_instr), .mem_ready(cpu_ready),
        .mem_addr(cpu_addr), .mem_wdata(cpu_wdata), .mem_wstrb(cpu_wstrb), .mem_rdata(cpu_rdata), .trace_valid(), .trace_data()
    );

    // 2. ADAPTER
    cpu_to_axi #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .ID_WIDTH(ID_WIDTH)) adapter_inst (
        .clk(clk), .rst_n(rst_n), .mem_valid(cpu_valid), .mem_instr(cpu_instr), .mem_ready(cpu_ready), .mem_addr(cpu_addr), .mem_wdata(cpu_wdata), .mem_wstrb(cpu_wstrb), .mem_rdata(cpu_rdata),
        .m_axi_awid(m_axi_awid), .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid), .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid), .m_axi_rdata(m_axi_rdata), .m_axi_ruser(m_axi_ruser), .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready)
    );

    // 3. PIM
    generate
        if (ENABLE_PIM) begin : gen_pim
            pim_sparsity_aware #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .ID_WIDTH(ID_WIDTH)) pim_inst (
                .clk(clk), .rst_n(rst_n), .pim_enable(1'b1),
                // Slave Side (From Adapter)
                .s_axi_awid(m_axi_awid), .s_axi_awaddr(m_axi_awaddr), .s_axi_awlen(m_axi_awlen), .s_axi_awsize(m_axi_awsize), .s_axi_awburst(m_axi_awburst), .s_axi_awvalid(m_axi_awvalid), .s_axi_awready(m_axi_awready),
                .s_axi_wdata(m_axi_wdata), .s_axi_wstrb(m_axi_wstrb), .s_axi_wlast(m_axi_wlast), .s_axi_wvalid(m_axi_wvalid), .s_axi_wready(m_axi_wready),
                .s_axi_bid(m_axi_bid), .s_axi_bresp(m_axi_bresp), .s_axi_bvalid(m_axi_bvalid), .s_axi_bready(m_axi_bready),
                .s_axi_arid(m_axi_arid), .s_axi_araddr(m_axi_araddr), .s_axi_arlen(m_axi_arlen), .s_axi_arsize(m_axi_arsize), .s_axi_arburst(m_axi_arburst), .s_axi_arvalid(m_axi_arvalid), .s_axi_arready(m_axi_arready),
                .s_axi_rid(m_axi_rid), .s_axi_rdata(m_axi_rdata), .s_axi_rresp(m_axi_rresp), .s_axi_rlast(m_axi_rlast), .s_axi_rvalid(m_axi_rvalid), .s_axi_rready(m_axi_rready),
                // Master Side (To Memory)
                .m_axi_awid(p_awid), .m_axi_awaddr(p_awaddr), .m_axi_awlen(p_awlen), .m_axi_awsize(p_awsize), .m_axi_awburst(p_awburst), .m_axi_awvalid(p_awvalid), .m_axi_awready(p_awready),
                .m_axi_wdata(p_wdata), .m_axi_wstrb(p_wstrb), .m_axi_wlast(p_wlast), .m_axi_wvalid(p_wvalid), .m_axi_wready(p_wready),
                .m_axi_bid(p_bid), .m_axi_bresp(p_bresp), .m_axi_bvalid(p_bvalid), .m_axi_bready(p_bready),
                .m_axi_arid(p_arid), .m_axi_araddr(p_araddr), .m_axi_arlen(p_arlen), .m_axi_arsize(p_arsize), .m_axi_arburst(p_arburst), .m_axi_arvalid(p_arvalid), .m_axi_arready(p_arready),
                .m_axi_rid(p_rid), .m_axi_rdata(p_rdata), .m_axi_rresp(p_rresp), .m_axi_rlast(p_rlast), .m_axi_rvalid(p_rvalid), .m_axi_rready(p_rready),
                // Stats
                .mac_ops_count(mac_ops_count), .active_cycles(active_cycles), .idle_cycles(idle_cycles)
            );
        end else begin : gen_bypass
            // Bypass Wiring
            assign p_awid=m_axi_awid; assign p_awaddr=m_axi_awaddr; assign p_awlen=m_axi_awlen; assign p_awsize=m_axi_awsize; assign p_awburst=m_axi_awburst; assign p_awvalid=m_axi_awvalid; assign m_axi_awready=p_awready;
            assign p_wdata=m_axi_wdata; assign p_wstrb=m_axi_wstrb; assign p_wlast=m_axi_wlast; assign p_wvalid=m_axi_wvalid; assign m_axi_wready=p_wready;
            assign m_axi_bid=p_bid; assign m_axi_bresp=p_bresp; assign m_axi_bvalid=p_bvalid; assign p_bready=m_axi_bready;
            assign p_arid=m_axi_arid; assign p_araddr=m_axi_araddr; assign p_arlen=m_axi_arlen; assign p_arsize=m_axi_arsize; assign p_arburst=m_axi_arburst; assign p_arvalid=m_axi_arvalid; assign m_axi_arready=p_arready;
            assign m_axi_rid=p_rid; assign m_axi_rdata=p_rdata; assign m_axi_rresp=p_rresp; assign m_axi_rlast=p_rlast; assign m_axi_rvalid=p_rvalid; assign p_rready=m_axi_rready;
            assign mac_ops_count=0; assign active_cycles=0; assign idle_cycles=0;
        end
    endgenerate

    // 4. MEMORY (Updated to 1MB)
    simple_memory #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .ID_WIDTH(ID_WIDTH), .MEM_SIZE(1048576)) memory_inst (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(p_awid), .s_axi_awaddr(p_awaddr), .s_axi_awlen(p_awlen), .s_axi_awsize(p_awsize), .s_axi_awburst(p_awburst), .s_axi_awvalid(p_awvalid), .s_axi_awready(p_awready),
        .s_axi_wdata(p_wdata), .s_axi_wstrb(p_wstrb), .s_axi_wlast(p_wlast), .s_axi_wvalid(p_wvalid), .s_axi_wready(p_wready),
        .s_axi_bid(p_bid), .s_axi_bresp(p_bresp), .s_axi_bvalid(p_bvalid), .s_axi_bready(p_bready),
        .s_axi_arid(p_arid), .s_axi_araddr(p_araddr), .s_axi_arlen(p_arlen), .s_axi_arsize(p_arsize), .s_axi_arburst(p_arburst), .s_axi_arvalid(p_arvalid), .s_axi_arready(p_arready),
        .s_axi_rid(p_rid), .s_axi_rdata(p_rdata), .s_axi_rresp(p_rresp), .s_axi_rlast(p_rlast), .s_axi_rvalid(p_rvalid), .s_axi_rready(p_rready)
    );
endmodule
