/*
 * Simple RISC-V CPU - ROBUST HANDSHAKE
 */

module simple_riscv_cpu #( parameter RESET_ADDR = 32'h0000_0000 ) (
    input wire clk, input wire resetn,
    output reg mem_valid, output reg mem_instr, input wire mem_ready,
    output reg [31:0] mem_addr, output reg [31:0] mem_wdata, output reg [3:0] mem_wstrb, input wire [31:0] mem_rdata,
    output reg trace_valid, output reg [35:0] trace_data
);
    localparam CPU_RESET=0, CPU_FETCH=1, CPU_DECODE=2, CPU_EXECUTE=3, CPU_MEMORY=4, CPU_RETIRE=5;
    reg [2:0] cpu_state;
    reg [31:0] pc, next_pc, instr, alu_out, alu_a, alu_b;
    reg [31:0] regs [0:31];
    integer i;

    wire [6:0] opcode = instr[6:0]; wire [4:0] rd = instr[11:7], rs1 = instr[19:15], rs2 = instr[24:20];
    wire [2:0] funct3 = instr[14:12];
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
    // B-type immediate (for BEQ, BNE, BLT, BGE, etc.)
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

    initial for(i=0; i<32; i=i+1) regs[i]=0;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin cpu_state<=CPU_RESET; pc<=RESET_ADDR; mem_valid<=0; end
        else begin
            case (cpu_state)
                CPU_RESET: begin mem_valid<=0; cpu_state<=CPU_FETCH; end
                CPU_FETCH: begin
                    if (!mem_valid) begin mem_valid<=1; mem_instr<=1; mem_addr<=pc; mem_wstrb<=0; end
                    if (mem_valid && mem_ready) begin
                        instr<=mem_rdata; mem_valid<=0; cpu_state<=CPU_DECODE;
                    end
                end
                CPU_DECODE: begin
                    alu_a <= regs[rs1];
                    // BUG FIX #2: Tentukan alu_b berdasarkan tipe instruksi
                    case (opcode)
                        7'b0000011: alu_b <= imm_i;  // LW: pakai imm_i (BUKAN rs2!)
                        7'b0010011: alu_b <= imm_i;  // ADDI, dst
                        7'b0100011: alu_b <= imm_s;  // SW
                        default:    alu_b <= regs[rs2]; // R-type
                    endcase
                    // BUG FIX #3: Hitung next_pc termasuk untuk branch
                    case (opcode)
                        7'b1101111: next_pc <= pc + imm_j;  // JAL
                        7'b1100011: next_pc <= pc + 4;       // Branch (default no-jump, akan di-override di EXECUTE)
                        default:    next_pc <= pc + 4;
                    endcase
                    cpu_state <= CPU_EXECUTE;
                end
                CPU_EXECUTE: begin
                    case (opcode)
                        7'b0110111: begin alu_out<=imm_u; cpu_state<=CPU_RETIRE; end
                        7'b0010011: begin alu_out<=alu_a+alu_b; cpu_state<=CPU_RETIRE; end
                        // BUG FIX #2: LW sekarang pakai alu_b=imm_i (sudah di-decode dengan benar)
                        7'b0000011: begin mem_valid<=1; mem_instr<=0; mem_addr<=alu_a+alu_b; mem_wstrb<=0; cpu_state<=CPU_MEMORY; end
                        7'b0100011: begin mem_valid<=1; mem_instr<=0; mem_addr<=alu_a+alu_b; mem_wdata<=regs[rs2]; mem_wstrb<=4'b1111; cpu_state<=CPU_MEMORY; end
                        7'b1101111: begin alu_out<=pc+4; cpu_state<=CPU_RETIRE; end
                        // BUG FIX #3: Branch instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU)
                        7'b1100011: begin
                            case (funct3)
                                3'b000: next_pc <= (alu_a == regs[rs2]) ? pc+imm_b : pc+4; // BEQ
                                3'b001: next_pc <= (alu_a != regs[rs2]) ? pc+imm_b : pc+4; // BNE
                                3'b100: next_pc <= ($signed(alu_a) < $signed(regs[rs2])) ? pc+imm_b : pc+4; // BLT
                                3'b101: next_pc <= ($signed(alu_a) >= $signed(regs[rs2])) ? pc+imm_b : pc+4; // BGE
                                3'b110: next_pc <= (alu_a < regs[rs2]) ? pc+imm_b : pc+4;  // BLTU
                                3'b111: next_pc <= (alu_a >= regs[rs2]) ? pc+imm_b : pc+4; // BGEU
                                default: next_pc <= pc+4;
                            endcase
                            cpu_state <= CPU_RETIRE;
                        end
                        default: begin alu_out<=alu_a+alu_b; cpu_state<=CPU_RETIRE; end
                    endcase
                end
                CPU_MEMORY: begin
                    if (mem_valid && mem_ready) begin
                        mem_valid<=0;
                        if (opcode==7'b0000011) begin alu_out<=mem_rdata; end
                        cpu_state<=CPU_RETIRE;
                    end
                end
                CPU_RETIRE: begin
                    if (rd!=0 && opcode!=7'b0100011 && opcode!=7'b1100011) regs[rd]<=alu_out;
                    pc<=next_pc; cpu_state<=CPU_FETCH;
                end
            endcase
            regs[0]<=0;
        end
    end
endmodule
