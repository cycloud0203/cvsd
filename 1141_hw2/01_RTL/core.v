module core #( // DO NOT MODIFY INTERFACE!!!
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) ( 
    input i_clk,
    input i_rst_n,

    // Testbench IOs
    output [2:0] o_status, 
    output       o_status_valid,

    // Memory IOs
    output [ADDR_WIDTH-1:0] o_addr,
    output [DATA_WIDTH-1:0] o_wdata,
    output                  o_we,
    input  [DATA_WIDTH-1:0] i_rdata
);

// state machine states
typedef enum logic [2:0] {
    IDLE,
    INSTRUCTION_FETCH,
    INSTRUCTION_DECODE,
    ALU_COMPUTE,
    DATA_WRITE_BACK,
    NEXT_PC_GENERATION,
    PROCESS_END
} state;


state current_state, next_state;

// Instruction format constants
localparam [6:0] OP_SUB    = 7'b0110011;
localparam [6:0] OP_ADDI   = 7'b0010011;
localparam [6:0] OP_LW     = 7'b0000011;
localparam [6:0] OP_SW     = 7'b0100011;
localparam [6:0] OP_BEQ    = 7'b1100011;
localparam [6:0] OP_BLT    = 7'b1100011;
localparam [6:0] OP_JALR   = 7'b1100111;
localparam [6:0] OP_AUIPC  = 7'b0010111;
localparam [6:0] OP_SLT    = 7'b0110011;
localparam [6:0] OP_SRL    = 7'b0110011;
localparam [6:0] OP_FSUB   = 7'b1010011;
localparam [6:0] OP_FMUL   = 7'b1010011;
localparam [6:0] OP_FCVTWS = 7'b1010011;
localparam [6:0] OP_FLW    = 7'b0000111;
localparam [6:0] OP_FSW    = 7'b0100111;
localparam [6:0] OP_FCLASS = 7'b1010011;
localparam [6:0] OP_EOF    = 7'b1110011;

localparam [2:0] FUNCT3_SUB    = 3'b000;
localparam [2:0] FUNCT3_ADDI   = 3'b000;
localparam [2:0] FUNCT3_LW     = 3'b010;
localparam [2:0] FUNCT3_SW     = 3'b010;
localparam [2:0] FUNCT3_BEQ    = 3'b000;
localparam [2:0] FUNCT3_BLT    = 3'b100;
localparam [2:0] FUNCT3_JALR   = 3'b000;
localparam [2:0] FUNCT3_SLT    = 3'b010;
localparam [2:0] FUNCT3_SRL    = 3'b101;
localparam [2:0] FUNCT3_FSUB   = 3'b000;
localparam [2:0] FUNCT3_FMUL   = 3'b000;
localparam [2:0] FUNCT3_FCVTWS = 3'b000;
localparam [2:0] FUNCT3_FLW    = 3'b010;
localparam [2:0] FUNCT3_FSW    = 3'b010;
localparam [2:0] FUNCT3_FCLASS = 3'b000;

localparam [6:0] FUNCT7_SUB    = 7'b0100000;
localparam [6:0] FUNCT7_SLT    = 7'b0000000;
localparam [6:0] FUNCT7_SRL    = 7'b0000000;
localparam [6:0] FUNCT7_FSUB   = 7'b0000100;
localparam [6:0] FUNCT7_FMUL   = 7'b0001000;
localparam [6:0] FUNCT7_FCVTWS = 7'b1100000;
localparam [6:0] FUNCT7_FCLASS = 7'b1110000;

localparam [2:0] STATUS_R_TYPE = 3'd0;
localparam [2:0] STATUS_I_TYPE = 3'd1;
localparam [2:0] STATUS_S_TYPE = 3'd2;
localparam [2:0] STATUS_B_TYPE = 3'd3;
localparam [2:0] STATUS_U_TYPE = 3'd4;
localparam [2:0] STATUS_INVALID = 3'd5;
localparam [2:0] STATUS_EOF = 3'd6;

localparam [4:0] ALU_ADD    = 5'd0;
localparam [4:0] ALU_SUB    = 5'd1;
localparam [4:0] ALU_SLT    = 5'd2;
localparam [4:0] ALU_SRL    = 5'd3;
localparam [4:0] ALU_FSUB   = 5'd4;
localparam [4:0] ALU_FMUL   = 5'd5;
localparam [4:0] ALU_FCVTWS = 5'd6;
localparam [4:0] ALU_FCLASS = 5'd7;
localparam [4:0] ALU_PASS_A = 5'd8;
localparam [4:0] ALU_PASS_B = 5'd9;

// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// ---- Add your own wires and registers here if needed ---- //

// Program Counter signals
wire [DATA_WIDTH-1:0] pc_current;
reg [DATA_WIDTH-1:0] pc_next;
reg pc_en;

// Instruction register and decode
reg [DATA_WIDTH-1:0] instruction;
wire [6:0] opcode;
wire [2:0] funct3;
wire [6:0] funct7;
wire [4:0] rs1;
wire [4:0] rs2;
wire [4:0] rd;
reg [DATA_WIDTH-1:0] imm;
reg [2:0] inst_type;

// Register File - Integer registers
reg [4:0] rs1_addr;
reg [4:0] rs2_addr;
reg [4:0] rd_addr;
reg [DATA_WIDTH-1:0] rd_data;
reg rd_we;
wire [DATA_WIDTH-1:0] rs1_data;
wire [DATA_WIDTH-1:0] rs2_data;

// Register File - Floating-point registers
reg [4:0] frs1_addr;
reg [4:0] frs2_addr;
reg [4:0] frd_addr;
reg [DATA_WIDTH-1:0] frd_data;
reg frd_we;
wire [DATA_WIDTH-1:0] frs1_data;
wire [DATA_WIDTH-1:0] frs2_data;

// ALU signals
reg [4:0] alu_op;
reg signed [DATA_WIDTH-1:0] alu_in_a;
reg signed [DATA_WIDTH-1:0] alu_in_b;
reg [DATA_WIDTH-1:0] alu_fin_a;
reg [DATA_WIDTH-1:0] alu_fin_b;
wire [DATA_WIDTH-1:0] alu_result;
wire alu_zero;
wire alu_less_than;

// Control signals
reg is_branch_taken;
reg is_memory_op;
reg is_fp_inst;
reg [DATA_WIDTH-1:0] alu_result_reg;
reg [DATA_WIDTH-1:0] mem_addr;
reg [DATA_WIDTH-1:0] branch_target;
reg branch_taken_reg;
reg [DATA_WIDTH-1:0] branch_target_reg;

// Status output
reg [2:0] status;
reg status_valid;


// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //

// Instruction decode
assign opcode = instruction[6:0];
assign funct3 = instruction[14:12];
assign funct7 = instruction[31:25];
assign rs1 = instruction[19:15];
assign rs2 = instruction[24:20];
assign rd = instruction[11:7];

// Output assignments
assign o_status = status;
assign o_status_valid = status_valid;
assign o_addr = mem_addr;
assign o_wdata = is_fp_inst ? frs2_data : rs2_data;
assign o_we = (current_state == DATA_WRITE_BACK) && is_memory_op && 
              (opcode == OP_SW || opcode == OP_FSW);

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your combinational block design here ---- //

// ===========================
// Immediate Generation Logic
// ===========================
always @(*) begin
    // Decode instruction type from opcode directly
    case (opcode)
        OP_ADDI, OP_LW, OP_JALR, OP_FLW: begin
            // I-type: sign-extend imm[11:0]
            imm = {{20{instruction[31]}}, instruction[31:20]};
        end
        OP_SW, OP_FSW: begin
            // S-type: sign-extend {imm[11:5], imm[4:0]}
            imm = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
        end
        OP_BEQ, OP_BLT: begin
            // B-type: sign-extend {imm[12], imm[10:5], imm[4:1], 0}
            imm = {{19{instruction[31]}}, instruction[31], instruction[7], 
                   instruction[30:25], instruction[11:8], 1'b0};
        end
        OP_AUIPC: begin
            // U-type: {imm[31:12], 12'b0}
            imm = {instruction[31:12], 12'b0};
        end
        default: begin
            imm = 32'd0;
        end
    endcase
end

// ===========================
// Next State Logic
// ===========================
always @(*) begin
    // Default next state
    next_state = current_state;
    
    case (current_state)
        IDLE: begin
            next_state = INSTRUCTION_FETCH;
        end
        
        INSTRUCTION_FETCH: begin
            next_state = INSTRUCTION_DECODE;
        end
        
        INSTRUCTION_DECODE: begin
            if (opcode == OP_EOF) begin
                next_state = PROCESS_END;
            end else begin
                next_state = ALU_COMPUTE;
            end
        end
        
        ALU_COMPUTE: begin
            // Check if instruction needs memory access
            if (opcode == OP_LW || opcode == OP_SW || opcode == OP_FLW || opcode == OP_FSW) begin
                next_state = DATA_WRITE_BACK;
            end else begin
                next_state = NEXT_PC_GENERATION;
            end
        end
        
        DATA_WRITE_BACK: begin
            next_state = NEXT_PC_GENERATION;
        end
        
        NEXT_PC_GENERATION: begin
            next_state = INSTRUCTION_FETCH;
        end
        
        PROCESS_END: begin
            next_state = PROCESS_END;
        end
        
        default: begin
            next_state = IDLE;
        end
    endcase
end

// ===========================
// Output Logic (Combinational)
// ===========================
always @(*) begin
    // Default values
    pc_next = pc_current + 4;
    pc_en = 1'b0;
    rs1_addr = 5'd0;
    rs2_addr = 5'd0;
    rd_addr = 5'd0;
    rd_data = 32'd0;
    rd_we = 1'b0;
    frs1_addr = 5'd0;
    frs2_addr = 5'd0;
    frd_addr = 5'd0;
    frd_data = 32'd0;
    frd_we = 1'b0;
    alu_op = ALU_ADD;
    alu_in_a = 32'd0;
    alu_in_b = 32'd0;
    alu_fin_a = 32'd0;
    alu_fin_b = 32'd0;
    is_branch_taken = 1'b0;
    is_memory_op = 1'b0;
    is_fp_inst = 1'b0;
    mem_addr = 32'd0;
    branch_target = pc_current + 4;
    inst_type = STATUS_INVALID;
    status = STATUS_INVALID;
    status_valid = 1'b0;
    
    case (current_state)
        IDLE: begin
            // Do nothing, wait for reset
        end
        
        INSTRUCTION_FETCH: begin
            // Set memory address to PC for instruction fetch
            mem_addr = pc_current;
        end
        
        INSTRUCTION_DECODE: begin
            // Decode instruction and determine type
            mem_addr = pc_current;
            
            // Determine instruction type and set status
            case (opcode)
                OP_SUB, OP_SLT, OP_SRL: begin
                    inst_type = STATUS_R_TYPE;
                    status = STATUS_R_TYPE;
                    status_valid = 1'b1;
                    rs1_addr = rs1;
                    rs2_addr = rs2;
                    rd_addr = rd;
                end
                
                OP_ADDI, OP_LW, OP_JALR: begin
                    inst_type = STATUS_I_TYPE;
                    status = STATUS_I_TYPE;
                    status_valid = 1'b1;
                    rs1_addr = rs1;
                    rd_addr = rd;
                end
                
                OP_SW: begin
                    inst_type = STATUS_S_TYPE;
                    status = STATUS_S_TYPE;
                    status_valid = 1'b1;
                    rs1_addr = rs1;
                    rs2_addr = rs2;
                    is_memory_op = 1'b1;
                end
                
                OP_BEQ, OP_BLT: begin
                    inst_type = STATUS_B_TYPE;
                    status = STATUS_B_TYPE;
                    status_valid = 1'b1;
                    rs1_addr = rs1;
                    rs2_addr = rs2;
                end
                
                OP_AUIPC: begin
                    inst_type = STATUS_U_TYPE;
                    status = STATUS_U_TYPE;
                    status_valid = 1'b1;
                    rd_addr = rd;
                end
                
                OP_FSUB, OP_FMUL, OP_FCLASS: begin
                    inst_type = STATUS_R_TYPE;
                    status = STATUS_R_TYPE;
                    status_valid = 1'b1;
                    frs1_addr = rs1;
                    frs2_addr = rs2;
                    frd_addr = rd;
                    is_fp_inst = 1'b1;
                end
                
                OP_FCVTWS: begin
                    inst_type = STATUS_R_TYPE;
                    status = STATUS_R_TYPE;
                    status_valid = 1'b1;
                    frs1_addr = rs1;
                    rd_addr = rd;
                    is_fp_inst = 1'b1;
                end
                
                OP_FLW: begin
                    inst_type = STATUS_I_TYPE;
                    status = STATUS_I_TYPE;
                    status_valid = 1'b1;
                    rs1_addr = rs1;
                    frd_addr = rd;
                    is_memory_op = 1'b1;
                    is_fp_inst = 1'b1;
                end
                
                OP_FSW: begin
                    inst_type = STATUS_S_TYPE;
                    status = STATUS_S_TYPE;
                    status_valid = 1'b1;
                    rs1_addr = rs1;
                    frs2_addr = rs2;
                    is_memory_op = 1'b1;
                    is_fp_inst = 1'b1;
                end
                
                OP_EOF: begin
                    inst_type = STATUS_EOF;
                    status = STATUS_EOF;
                    status_valid = 1'b1;
                end
                
                default: begin
                    inst_type = STATUS_INVALID;
                    status = STATUS_INVALID;
                    status_valid = 1'b1;
                end
            endcase
        end
        
        ALU_COMPUTE: begin
            // Set register file addresses
            rs1_addr = rs1;
            rs2_addr = rs2;
            rd_addr = rd;
            frs1_addr = rs1;
            frs2_addr = rs2;
            frd_addr = rd;
            
            // Perform ALU operations or address calculation
            case (opcode)
                OP_SUB: begin
                    if (funct7 == FUNCT7_SUB && funct3 == FUNCT3_SUB) begin
                        alu_op = ALU_SUB;
                        alu_in_a = rs1_data;
                        alu_in_b = rs2_data;
                        rd_data = alu_result;
                        rd_we = 1'b1;
                    end
                end
                
                OP_ADDI: begin
                    alu_op = ALU_ADD;
                    alu_in_a = rs1_data;
                    alu_in_b = imm;
                    rd_data = alu_result;
                    rd_we = 1'b1;
                end
                
                OP_LW: begin
                    mem_addr = rs1_data + imm;
                    is_memory_op = 1'b1;
                end
                
                OP_SW: begin
                    mem_addr = rs1_data + imm;
                    is_memory_op = 1'b1;
                end
                
                OP_BEQ: begin
                    alu_op = ALU_SUB;
                    alu_in_a = rs1_data;
                    alu_in_b = rs2_data;
                    branch_target = pc_current + imm;
                    is_branch_taken = alu_zero;
                end
                
                OP_BLT: begin
                    if (funct3 == FUNCT3_BLT) begin
                        alu_op = ALU_SUB;
                        alu_in_a = rs1_data;
                        alu_in_b = rs2_data;
                        branch_target = pc_current + imm;
                        is_branch_taken = alu_less_than;
                    end
                end
                
                OP_JALR: begin
                    alu_op = ALU_ADD;
                    alu_in_a = rs1_data;
                    alu_in_b = imm;
                    branch_target = {alu_result[31:1], 1'b0};
                    rd_data = pc_current + 4;
                    rd_we = 1'b1;
                    is_branch_taken = 1'b1;
                end
                
                OP_AUIPC: begin
                    alu_op = ALU_ADD;
                    alu_in_a = pc_current;
                    alu_in_b = imm;
                    rd_data = alu_result;
                    rd_we = 1'b1;
                end
                
                OP_SLT: begin
                    if (funct7 == FUNCT7_SLT && funct3 == FUNCT3_SLT) begin
                        alu_op = ALU_SLT;
                        alu_in_a = rs1_data;
                        alu_in_b = rs2_data;
                        rd_data = alu_result;
                        rd_we = 1'b1;
                    end
                end
                
                OP_SRL: begin
                    if (funct7 == FUNCT7_SRL && funct3 == FUNCT3_SRL) begin
                        alu_op = ALU_SRL;
                        alu_in_a = rs1_data;
                        alu_in_b = rs2_data;
                        rd_data = alu_result;
                        rd_we = 1'b1;
                    end
                end
                
                OP_FSUB: begin
                    if (funct7 == FUNCT7_FSUB) begin
                        alu_op = ALU_FSUB;
                        alu_fin_a = frs1_data;
                        alu_fin_b = frs2_data;
                        frd_data = alu_result;
                        frd_we = 1'b1;
                    end
                end
                
                OP_FMUL: begin
                    if (funct7 == FUNCT7_FMUL) begin
                        alu_op = ALU_FMUL;
                        alu_fin_a = frs1_data;
                        alu_fin_b = frs2_data;
                        frd_data = alu_result;
                        frd_we = 1'b1;
                    end
                end
                
                OP_FCVTWS: begin
                    if (funct7 == FUNCT7_FCVTWS) begin
                        alu_op = ALU_FCVTWS;
                        alu_fin_a = frs1_data;
                        rd_data = alu_result;
                        rd_we = 1'b1;
                    end
                end
                
                OP_FLW: begin
                    mem_addr = rs1_data + imm;
                    is_memory_op = 1'b1;
                end
                
                OP_FSW: begin
                    mem_addr = rs1_data + imm;
                    is_memory_op = 1'b1;
                end
                
                OP_FCLASS: begin
                    if (funct7 == FUNCT7_FCLASS) begin
                        alu_op = ALU_FCLASS;
                        alu_fin_a = frs1_data;
                        rd_data = alu_result;
                        rd_we = 1'b1;
                    end
                end
                
                default: begin
                    // Do nothing
                end
            endcase
        end
        
        DATA_WRITE_BACK: begin
            rs1_addr = rs1;
            frd_addr = rd;
            rd_addr = rd;
            mem_addr = alu_result_reg;
            
            // Write back from memory
            if (opcode == OP_LW) begin
                rd_data = i_rdata;
                rd_we = 1'b1;
            end else if (opcode == OP_FLW) begin
                frd_data = i_rdata;
                frd_we = 1'b1;
            end
        end
        
        NEXT_PC_GENERATION: begin
            // Update PC using registered branch information
            if (branch_taken_reg) begin
                pc_next = branch_target_reg;
            end else begin
                pc_next = pc_current + 4;
            end
            pc_en = 1'b1;
        end
        
        PROCESS_END: begin
            // Hold state
            pc_en = 1'b0;
        end
        
        default: begin
            // Do nothing
        end
    endcase
end
// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //

// ===========================
// State Register
// ===========================
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        current_state <= IDLE;
    end else begin
        current_state <= next_state;
    end
end

// ===========================
// Instruction Register
// ===========================
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        instruction <= 32'd0;
    end else begin
        if (current_state == INSTRUCTION_FETCH) begin
            instruction <= i_rdata;
        end
    end
end

// ===========================
// ALU Result Register (for memory address)
// ===========================
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        alu_result_reg <= 32'd0;
    end else begin
        if (current_state == ALU_COMPUTE && is_memory_op) begin
            alu_result_reg <= mem_addr;
        end
    end
end

// ===========================
// Branch Information Registers
// ===========================
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        branch_taken_reg <= 1'b0;
        branch_target_reg <= 32'd0;
    end else begin
        if (current_state == ALU_COMPUTE) begin
            branch_taken_reg <= is_branch_taken;
            branch_target_reg <= branch_target;
        end
    end
end

// ---------------------------------------------------------------------------
// Module Instantiations
// ---------------------------------------------------------------------------

// Program Counter instantiation
program_counter #(
    .DATA_WIDTH(DATA_WIDTH)
) u_program_counter (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_en(pc_en),
    .i_pc(pc_next),
    .o_pc(pc_current)
);

// Register File instantiation
register_file #(
    .DATA_WIDTH(DATA_WIDTH)
) u_register_file (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    // Integer register file ports
    .i_rs1_addr(rs1_addr),
    .i_rs2_addr(rs2_addr),
    .i_rd_addr(rd_addr),
    .i_rd_data(rd_data),
    .i_rd_we(rd_we),
    .o_rs1_data(rs1_data),
    .o_rs2_data(rs2_data),
    // Floating-point register file ports
    .i_frs1_addr(frs1_addr),
    .i_frs2_addr(frs2_addr),
    .i_frd_addr(frd_addr),
    .i_frd_data(frd_data),
    .i_frd_we(frd_we),
    .o_frs1_data(frs1_data),
    .o_frs2_data(frs2_data)
);

// ALU instantiation
alu #(
    .DATA_WIDTH(DATA_WIDTH)
) u_alu (
    .i_alu_op(alu_op),
    .i_data_a(alu_in_a),
    .i_data_b(alu_in_b),
    .i_fdata_a(alu_fin_a),
    .i_fdata_b(alu_fin_b),
    .o_result(alu_result),
    .o_zero(alu_zero),
    .o_less_than(alu_less_than)
);

endmodule

// ---------------------------------------------------------------------------
// Program Counter
// ---------------------------------------------------------------------------
module program_counter #(
    parameter DATA_WIDTH = 32
) (
    input i_clk,
    input i_rst_n,
    input i_en,
    input [DATA_WIDTH-1:0] i_pc,
    output reg [DATA_WIDTH-1:0] o_pc
);

    // Program counter register
    // Updates when enabled with new PC value (PC+4 or branch target)
    // Default PC starts at 0 on reset
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_pc <= 32'd0;  // Reset PC to 0
        end else begin
            if (i_en) begin
                o_pc <= i_pc;  // Load next PC value
            end
        end
    end

endmodule

// ---------------------------------------------------------------------------
// Register File
// ---------------------------------------------------------------------------
module register_file #(
    parameter DATA_WIDTH = 32
) (
    input i_clk,
    input i_rst_n,
    
    // Integer register file ports
    input [4:0] i_rs1_addr,                // Read address 1
    input [4:0] i_rs2_addr,                // Read address 2
    input [4:0] i_rd_addr,                 // Write address
    input [DATA_WIDTH-1:0] i_rd_data,      // Write data
    input i_rd_we,                         // Write enable
    output reg [DATA_WIDTH-1:0] o_rs1_data, // Read data 1
    output reg [DATA_WIDTH-1:0] o_rs2_data, // Read data 2
    
    // Floating-point register file ports
    input [4:0] i_frs1_addr,                // FP Read address 1
    input [4:0] i_frs2_addr,                // FP Read address 2
    input [4:0] i_frd_addr,                 // FP Write address
    input [DATA_WIDTH-1:0] i_frd_data,      // FP Write data
    input i_frd_we,                         // FP Write enable
    output reg [DATA_WIDTH-1:0] o_frs1_data, // FP Read data 1
    output reg [DATA_WIDTH-1:0] o_frs2_data  // FP Read data 2
);

    // 32 signed 32-bit integer registers
    reg signed [DATA_WIDTH-1:0] int_regs [0:31];
    
    // 32 single-precision floating-point registers
    reg [DATA_WIDTH-1:0] float_regs [0:31];
    
    integer i;
    
    // Integer register file read (combinational)
    always @(*) begin
        o_rs1_data = int_regs[i_rs1_addr];
        o_rs2_data = int_regs[i_rs2_addr];
    end
    
    // Floating-point register file read (combinational)
    always @(*) begin
        o_frs1_data = float_regs[i_frs1_addr];
        o_frs2_data = float_regs[i_frs2_addr];
    end
    
    // Integer register file write (sequential)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                int_regs[i] <= 0;
            end
        end else begin
            if (i_rd_we && i_rd_addr != 5'b0) begin // x0 is hardwired to 0
                int_regs[i_rd_addr] <= i_rd_data;
            end
        end
    end
    
    // Floating-point register file write (sequential)
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                float_regs[i] <= 0;
            end
        end else begin
            if (i_frd_we) begin
                float_regs[i_frd_addr] <= i_frd_data;
            end
        end
    end

endmodule

// ---------------------------------------------------------------------------
// ALU (Arithmetic Logic Unit)
// ---------------------------------------------------------------------------
module alu #(
    parameter DATA_WIDTH = 32
) (
    // Control signals
    input [4:0] i_alu_op,
    
    // Integer operands
    input signed [DATA_WIDTH-1:0] i_data_a,
    input signed [DATA_WIDTH-1:0] i_data_b,
    
    // Floating-point operands
    input [DATA_WIDTH-1:0] i_fdata_a,
    input [DATA_WIDTH-1:0] i_fdata_b,
    
    // Outputs
    output reg [DATA_WIDTH-1:0] o_result,
    output reg o_zero,
    output reg o_less_than
);

    // ALU operation codes
    localparam ALU_ADD    = 5'd0;
    localparam ALU_SUB    = 5'd1;
    localparam ALU_SLT    = 5'd2;
    localparam ALU_SRL    = 5'd3;
    localparam ALU_FSUB   = 5'd4;
    localparam ALU_FMUL   = 5'd5;
    localparam ALU_FCVTWS = 5'd6;
    localparam ALU_FCLASS = 5'd7;
    localparam ALU_PASS_A = 5'd8;
    localparam ALU_PASS_B = 5'd9;
    
    // Floating-point components extraction
    wire sign_a, sign_b;
    wire [7:0] exp_a, exp_b;
    wire [22:0] frac_a, frac_b;
    
    assign sign_a = i_fdata_a[31];
    assign exp_a = i_fdata_a[30:23];
    assign frac_a = i_fdata_a[22:0];
    
    assign sign_b = i_fdata_b[31];
    assign exp_b = i_fdata_b[30:23];
    assign frac_b = i_fdata_b[22:0];
    
    // Temporary variables for floating-point operations
    reg [DATA_WIDTH-1:0] fp_result;
    reg [DATA_WIDTH-1:0] fclass_result;
    
    always @(*) begin
        // Default outputs
        o_result = 32'd0;
        o_zero = 1'b0;
        o_less_than = 1'b0;
        fp_result = 32'd0;
        fclass_result = 32'd0;
        
        case (i_alu_op)
            ALU_ADD: begin
                o_result = i_data_a + i_data_b;
            end
            
            ALU_SUB: begin
                o_result = i_data_a - i_data_b;
                o_zero = (i_data_a == i_data_b);
                o_less_than = (i_data_a < i_data_b);
            end
            
            ALU_SLT: begin
                o_result = (i_data_a < i_data_b) ? 32'd1 : 32'd0;
            end
            
            ALU_SRL: begin
                o_result = i_data_a >> i_data_b[4:0];
            end
            
            ALU_FSUB: begin
                // Simplified floating-point subtraction
                // For now, placeholder - full IEEE 754 implementation needed
                fp_result = {~i_fdata_b[31], i_fdata_b[30:0]}; // Flip sign of B
                o_result = fp_result; // TODO: Implement full FP addition
            end
            
            ALU_FMUL: begin
                // Simplified floating-point multiplication
                // Placeholder - full IEEE 754 implementation needed
                o_result = 32'd0; // TODO: Implement full FP multiplication
            end
            
            ALU_FCVTWS: begin
                // Convert float to signed integer
                // Placeholder - full IEEE 754 to integer conversion needed
                o_result = 32'd0; // TODO: Implement conversion
            end
            
            ALU_FCLASS: begin
                // Classify floating-point number
                // bit 0: negative infinity
                // bit 1: negative normal
                // bit 2: negative subnormal
                // bit 3: negative zero
                // bit 4: positive zero
                // bit 5: positive subnormal
                // bit 6: positive normal
                // bit 7: positive infinity
                // bit 8: signaling NaN
                // bit 9: quiet NaN
                
                if (exp_a == 8'hFF) begin
                    if (frac_a == 23'd0) begin
                        // Infinity
                        fclass_result = sign_a ? 32'd1 : 32'd128; // bit 0 or bit 7
                    end else begin
                        // NaN
                        fclass_result = frac_a[22] ? 32'd512 : 32'd256; // bit 9 (qNaN) or bit 8 (sNaN)
                    end
                end else if (exp_a == 8'd0) begin
                    if (frac_a == 23'd0) begin
                        // Zero
                        fclass_result = sign_a ? 32'd8 : 32'd16; // bit 3 or bit 4
                    end else begin
                        // Subnormal
                        fclass_result = sign_a ? 32'd4 : 32'd32; // bit 2 or bit 5
                    end
                end else begin
                    // Normal
                    fclass_result = sign_a ? 32'd2 : 32'd64; // bit 1 or bit 6
                end
                
                o_result = fclass_result;
            end
            
            ALU_PASS_A: begin
                o_result = i_data_a;
            end
            
            ALU_PASS_B: begin
                o_result = i_data_b;
            end
            
            default: begin
                o_result = 32'd0;
            end
        endcase
    end

endmodule