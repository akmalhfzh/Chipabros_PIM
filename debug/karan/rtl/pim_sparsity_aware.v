module pim_sparsity_aware #(
    parameter DATA_WIDTH = 512,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH = 8
)(
    input wire clk, input wire rst_n, input wire pim_enable,

    // --- SLAVE INTERFACE (Input dari Adapter/CPU) ---
    input  wire [ID_WIDTH-1:0]      s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire [2:0]               s_axi_awsize,
    input  wire [1:0]               s_axi_awburst,
    input  wire                     s_axi_awvalid,
    output wire                     s_axi_awready,

    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output wire                     s_axi_wready,

    output wire [ID_WIDTH-1:0]      s_axi_bid,
    output wire [1:0]               s_axi_bresp,
    output wire                     s_axi_bvalid,
    input  wire                     s_axi_bready,

    input  wire [ID_WIDTH-1:0]      s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire [2:0]               s_axi_arsize,
    input  wire [1:0]               s_axi_arburst,
    input  wire                     s_axi_arvalid,
    output wire                     s_axi_arready,

    output wire [ID_WIDTH-1:0]      s_axi_rid,
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [1:0]               s_axi_rresp,
    output wire                     s_axi_rlast,
    output wire                     s_axi_rvalid,
    input  wire                     s_axi_rready,
    
    // Additional Flag for Adapter (ZVC - Zero Value Compression)
    output wire                     s_axi_ruser,   

    // --- MASTER INTERFACE (Output ke Memory) ---
    output wire [ID_WIDTH-1:0]      m_axi_awid,
    output wire [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output wire [7:0]               m_axi_awlen,
    output wire [2:0]               m_axi_awsize,
    output wire [1:0]               m_axi_awburst,
    output wire                     m_axi_awvalid,
    input  wire                     m_axi_awready,

    output wire [DATA_WIDTH-1:0]    m_axi_wdata,
    output wire [DATA_WIDTH/8-1:0]  m_axi_wstrb,
    output wire                     m_axi_wlast,
    output wire                     m_axi_wvalid,
    input  wire                     m_axi_wready,

    input  wire [ID_WIDTH-1:0]      m_axi_bid,
    input  wire [1:0]               m_axi_bresp,
    input  wire                     m_axi_bvalid,
    output wire                     m_axi_bready,

    output wire [ID_WIDTH-1:0]      m_axi_arid,
    output wire [ADDR_WIDTH-1:0]    m_axi_araddr,
    output wire [7:0]               m_axi_arlen,
    output wire [2:0]               m_axi_arsize,
    output wire [1:0]               m_axi_arburst,
    output wire                     m_axi_arvalid,
    input  wire                     m_axi_arready,

    input  wire [ID_WIDTH-1:0]      m_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire                     m_axi_rvalid,
    output wire                     m_axi_rready,

    // Stats Ports
    output reg [31:0] mac_ops_count, 
    output reg [31:0] active_cycles, 
    output reg [31:0] idle_cycles
);

    // --- ESPIM CORE LOGIC ---
    reg [4095:0] metadata_table;  // 4096 bit = cover 4096 blocks
    reg [3:0] cores_busy; 
    
    // Internal Check Logic
    wire is_data_access = (s_axi_araddr >= 32'h10000) && (s_axi_araddr < 32'h40000);
    // Block index calculation: Offset from base (0x10000) divided by 64 bytes (512-bit)
    wire [11:0] block_index = (s_axi_araddr - 32'h10000) >> 6;
    // Check Bitmask: 0 = Sparse (Skip), 1 = Dense (Fetch)
    wire is_block_sparse = (metadata_table[block_index] == 1'b0);

    // =========================================================================
    // 1. ADDRESS PATH (GATING LOGIC)
    // =========================================================================
    
    // Gating: Jika data sparse, JANGAN teruskan request ke memori (Hemat Energi)
    assign m_axi_arvalid = s_axi_arvalid && (!is_data_access || !is_block_sparse);
    
    // Passthrough Address Signals
    assign m_axi_arid    = s_axi_arid;
    assign m_axi_araddr  = s_axi_araddr;
    assign m_axi_arlen   = s_axi_arlen;
    assign m_axi_arsize  = s_axi_arsize;
    assign m_axi_arburst = s_axi_arburst;

    // Fake Ready: Jika sparse, PIM yang menjawab "Ready" ke CPU, bukan memori
    assign s_axi_arready = (is_data_access && is_block_sparse) ? 1'b1 : m_axi_arready;

    // =========================================================================
    // 2. DATA RESPONSE PATH (FIXED HANDSHAKE)
    // =========================================================================
    
    // State machine sederhana untuk menahan respon "Fake Zero" sampai CPU siap
    reg sparse_resp_active;
    reg [ID_WIDTH-1:0] sparse_rid_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sparse_resp_active <= 0;
            sparse_rid_reg <= 0;
        end else begin
            // Trigger: Saat Address Handshake terjadi DAN terdeteksi Sparse
            if (s_axi_arvalid && s_axi_arready && is_data_access && is_block_sparse) begin
                sparse_resp_active <= 1;
                sparse_rid_reg <= s_axi_arid; // Simpan ID request agar cocok saat response
            end
            // Clear: Saat Data Handshake selesai (Valid & Ready bertemu)
            else if (s_axi_rvalid && s_axi_rready && sparse_resp_active) begin
                sparse_resp_active <= 0;
            end
        end
    end

    // RVALID Logic: High jika Memory menjawab ATAU Sparse Logic sedang aktif
    assign s_axi_rvalid = sparse_resp_active ? 1'b1 : m_axi_rvalid;
    
    // RDATA Muxing: Inject Zero jika sparse, pass-through jika dense
    always @(*) begin
        if (sparse_resp_active) begin
            s_axi_rdata = {DATA_WIDTH{1'b0}}; // INJECT ZERO (ESPIM FEATURE)
        end else begin
            s_axi_rdata = m_axi_rdata;        // Ambil data asli dari memori
        end
    end

    // RRESP Signals
    assign s_axi_rid    = sparse_resp_active ? sparse_rid_reg : m_axi_rid;
    assign s_axi_rresp  = sparse_resp_active ? 2'b00 : m_axi_rresp; // Response OKAY
    assign s_axi_rlast  = sparse_resp_active ? 1'b1 : m_axi_rlast;  // Always Last (len=0 assumption)
    assign s_axi_ruser  = sparse_resp_active; // Flag ZVC untuk adapter

    assign m_axi_rready = s_axi_rready; // Backpressure pass through

    // =========================================================================
    // 3. WRITE PATH (PASSTHROUGH - NO CHANGE)
    // =========================================================================
    assign m_axi_awid=s_axi_awid; assign m_axi_awaddr=s_axi_awaddr; assign m_axi_awlen=s_axi_awlen; assign m_axi_awsize=s_axi_awsize; assign m_axi_awburst=s_axi_awburst; assign m_axi_awvalid=s_axi_awvalid; assign s_axi_awready=m_axi_awready;
    assign m_axi_wdata=s_axi_wdata; assign m_axi_wstrb=s_axi_wstrb; assign m_axi_wlast=s_axi_wlast; assign m_axi_wvalid=s_axi_wvalid; assign s_axi_wready=m_axi_wready;
    assign s_axi_bid=m_axi_bid; assign s_axi_bresp=m_axi_bresp; assign s_axi_bvalid=m_axi_bvalid; assign m_axi_bready=s_axi_bready;

    // =========================================================================
    // 4. STATS & SCHEDULING LOGIC
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            mac_ops_count <= 0; active_cycles <= 0; idle_cycles <= 0;
            cores_busy <= 0;
            metadata_table <= {4096{1'b1}}; 
        end else begin
            // Hitung Stats SAAT REQUEST DITERIMA (Address Handshake)
            // Ini memastikan data sparse (yang tidak ke memori) tetap terhitung
            if (s_axi_arvalid && s_axi_arready && is_data_access) begin
                mac_ops_count <= mac_ops_count + 16; // 1 Burst = 16 words ops
                
                if (is_block_sparse) begin
                    // Sparse Case: 
                    // Tidak ada akses memori -> Hemat Energi & Waktu
                    idle_cycles <= idle_cycles + 1; 
                    
                    // Fine-Grained Simulation: Core langsung selesai (Free)
                    cores_busy[0] <= 0; 
                end else begin
                    // Dense Case:
                    // Akses memori -> Boros Energi
                    active_cycles <= active_cycles + 1; 
                    
                    // Fine-Grained Simulation: Core jadi sibuk
                    // Simple Round Robin allocation
                    if (!cores_busy[0]) cores_busy[0] <= 1;
                    else if (!cores_busy[1]) cores_busy[1] <= 1;
                    else if (!cores_busy[2]) cores_busy[2] <= 1;
                    else cores_busy[3] <= 1;
                end
            end
            
            // Release Core saat Memory Response datang (Hanya untuk Dense)
            if (m_axi_rvalid && m_axi_rready) begin
                if (cores_busy[3]) cores_busy[3] <= 0;
                else if (cores_busy[2]) cores_busy[2] <= 0;
                else if (cores_busy[1]) cores_busy[1] <= 0;
                else if (cores_busy[0]) cores_busy[0] <= 0;
            end
        end
    end
    
    // Metadata Init Message
    initial begin
        #100;
        $display("[PIM] PIM Sparsity Aware Module Initialized.");
    end

endmodule
