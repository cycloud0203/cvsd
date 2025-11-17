`timescale 1ns/10ps

module crc_sort_core(
    input wire clk,
    input wire rst,
    input wire en,
    input wire start,
    input wire [127:0] data_in,
    input wire [2:0] fn_sel,
    output reg [127:0] data_out,
    output reg done
);

// Function codes
localparam CRC_GEN = 3'b011;
localparam SORT    = 3'b100;

// Internal signals for sort core
wire sort_start;
wire sort_en;
wire [127:0] sort_data_out;
wire sort_done;

// Internal signals for CRC core
wire crc_start;
wire crc_en;
wire [127:0] crc_data_out;
wire crc_done;

// Module selection and enable
assign sort_start = (fn_sel == SORT) ? start : 1'b0;
assign crc_start  = (fn_sel == CRC_GEN) ? start : 1'b0;
assign sort_en = (fn_sel == SORT) && en;
assign crc_en  = (fn_sel == CRC_GEN) && en;

// ========================================
// Sort Core Instantiation
// ========================================
sort_core sort_inst (
    .clk(clk),
    .rst(rst),
    .en(sort_en),
    .start(sort_start),
    .data_in(data_in),
    .data_out(sort_data_out),
    .done(sort_done)
);

// ========================================
// CRC Core Instantiation
// ========================================
crc_core crc_inst (
    .clk(clk),
    .rst(rst),
    .en(crc_en),
    .start(crc_start),
    .data_in(data_in),
    .data_out(crc_data_out),
    .done(crc_done)
);

// ========================================
// Output Multiplexing
// ========================================
always @(*) begin
    case (fn_sel)
        SORT: begin
            data_out = sort_data_out;
            done = sort_done;
        end
        CRC_GEN: begin
            data_out = crc_data_out;
            done = crc_done;
        end
        default: begin
            data_out = 128'd0;
            done = 1'b0;
        end
    endcase
end

endmodule


module crc_core(
    input wire clk,
    input wire rst,
    input wire en,
    input wire start,
    input wire [127:0] data_in,
    output reg [127:0] data_out,
    output reg done
);

// CRC-3 polynomial: x^3 + x^2 + 1 = 1101 in binary
// Polynomial representation: bit 3 is implicit (x^3), so we use bits [2:0] = 101
localparam [2:0] CRC_POLY = 3'b101;  // x^2 + 1

function automatic [2:0] crc_update_byte;
    input [2:0] crc_in;
    input [7:0] data_byte;
    integer idx;
    reg [2:0] crc_tmp;
    begin
        crc_tmp = crc_in;
        for (idx = 0; idx < 8; idx = idx + 1) begin
            if (crc_tmp[2] ^ data_byte[7 - idx]) begin
                crc_tmp = {crc_tmp[1:0], 1'b0} ^ CRC_POLY;
            end else begin
                crc_tmp = {crc_tmp[1:0], 1'b0};
            end
        end
        crc_update_byte = crc_tmp;
    end
endfunction

// State machine
localparam IDLE = 2'd0;
localparam COMPUTE = 2'd1;
localparam DONE = 2'd2;

(* fsm_encoding = "auto" *) reg [1:0] state, state_next;
reg [2:0] crc_reg, crc_reg_next;
reg [4:0] byte_cnt, byte_cnt_next;
reg [127:0] data_reg, data_reg_next;
wire [7:0] current_byte;

assign current_byte = data_reg[127:120];

// ========================================
// Combinational Logic
// ========================================
always @(*) begin
    state_next = state;
    crc_reg_next = crc_reg;
    byte_cnt_next = byte_cnt;
    data_reg_next = data_reg;
    done = 1'b0;
    
    case (state)
        IDLE: begin
            if (start) begin
                state_next = COMPUTE;
                crc_reg_next = 3'b000; // Initial CRC value (all zeros)
                byte_cnt_next = 5'd0;
                data_reg_next = data_in;
            end
        end
        
        COMPUTE: begin
            if (byte_cnt < 5'd16) begin
                // Process one byte per cycle
                crc_reg_next = crc_update_byte(crc_reg, current_byte);
                data_reg_next = {data_reg[119:0], 8'd0};
                byte_cnt_next = byte_cnt + 5'd1;
            end else begin
                state_next = DONE;
            end
        end
        
        DONE: begin
            done = 1'b1;
            state_next = IDLE;
        end
        
        default: begin
            state_next = IDLE;
        end
    endcase
end

// ========================================
// Output Assignment
// ========================================
always @(*) begin
    // CRC result in lower 3 bits, rest zeros
    data_out = {125'd0, crc_reg};
end

// ========================================
// Sequential Logic
// ========================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= IDLE;
        crc_reg <= 3'b000;
        byte_cnt <= 5'd0;
        data_reg <= 128'd0;
    end else if (en) begin
        state <= state_next;
        crc_reg <= crc_reg_next;
        byte_cnt <= byte_cnt_next;
        data_reg <= data_reg_next;
    end
end

endmodule

module sort_core(
    input wire clk,
    input wire rst,
    input wire en,
    input wire start,
    input wire [127:0] data_in,
    output reg [127:0] data_out,
    output reg done
);

// ========================================
// Sort 16 bytes in descending order
// Using pipelined bitonic sort network
// Completes in 16 cycles
// ========================================

// State machine
localparam IDLE = 2'd0;
localparam SORT = 2'd1;
localparam DONE = 2'd2;

(* fsm_encoding = "auto" *) reg [1:0] state, state_next;
reg [4:0] cycle_cnt, cycle_cnt_next;

// Array to hold 16 bytes during sorting
reg [7:0] sort_array [0:15];
reg [7:0] sort_array_next [0:15];

integer i;

// ========================================
// Combinational Logic - FSM and Sorting
// ========================================
always @(*) begin
    // Default assignments
    state_next = state;
    cycle_cnt_next = cycle_cnt;
    done = 1'b0;
    
    // Copy array by default
    for (i = 0; i < 16; i = i + 1) begin
        sort_array_next[i] = sort_array[i];
    end
    
    case (state)
        IDLE: begin
            if (start) begin
                state_next = SORT;
                cycle_cnt_next = 5'd0;
                
                // Load input data into array
                sort_array_next[0]  = data_in[7:0];
                sort_array_next[1]  = data_in[15:8];
                sort_array_next[2]  = data_in[23:16];
                sort_array_next[3]  = data_in[31:24];
                sort_array_next[4]  = data_in[39:32];
                sort_array_next[5]  = data_in[47:40];
                sort_array_next[6]  = data_in[55:48];
                sort_array_next[7]  = data_in[63:56];
                sort_array_next[8]  = data_in[71:64];
                sort_array_next[9]  = data_in[79:72];
                sort_array_next[10] = data_in[87:80];
                sort_array_next[11] = data_in[95:88];
                sort_array_next[12] = data_in[103:96];
                sort_array_next[13] = data_in[111:104];
                sort_array_next[14] = data_in[119:112];
                sort_array_next[15] = data_in[127:120];
            end
        end
        
        SORT: begin
            // Simple bubble-sort style network for descending order
            // Optimized cycle count while maintaining correctness
            // For 16 elements, using 17 cycles (9 even + 8 odd passes)
            
            case (cycle_cnt)
                // Even-indexed comparisons (even cycles)
                5'd0, 5'd2, 5'd4, 5'd6, 5'd8, 5'd10, 5'd12, 5'd14, 5'd16: begin
                    // Compare and swap (0, 1) - descending order
                    if (sort_array[0] < sort_array[1]) begin
                        sort_array_next[0] = sort_array[1];
                        sort_array_next[1] = sort_array[0];
                    end else begin
                        sort_array_next[0] = sort_array[0];
                        sort_array_next[1] = sort_array[1];
                    end
                    // Compare and swap (2, 3) - descending order
                    if (sort_array[2] < sort_array[3]) begin
                        sort_array_next[2] = sort_array[3];
                        sort_array_next[3] = sort_array[2];
                    end else begin
                        sort_array_next[2] = sort_array[2];
                        sort_array_next[3] = sort_array[3];
                    end
                    // Compare and swap (4, 5) - descending order
                    if (sort_array[4] < sort_array[5]) begin
                        sort_array_next[4] = sort_array[5];
                        sort_array_next[5] = sort_array[4];
                    end else begin
                        sort_array_next[4] = sort_array[4];
                        sort_array_next[5] = sort_array[5];
                    end
                    // Compare and swap (6, 7) - descending order
                    if (sort_array[6] < sort_array[7]) begin
                        sort_array_next[6] = sort_array[7];
                        sort_array_next[7] = sort_array[6];
                    end else begin
                        sort_array_next[6] = sort_array[6];
                        sort_array_next[7] = sort_array[7];
                    end
                    // Compare and swap (8, 9) - descending order
                    if (sort_array[8] < sort_array[9]) begin
                        sort_array_next[8] = sort_array[9];
                        sort_array_next[9] = sort_array[8];
                    end else begin
                        sort_array_next[8] = sort_array[8];
                        sort_array_next[9] = sort_array[9];
                    end
                    // Compare and swap (10, 11) - descending order
                    if (sort_array[10] < sort_array[11]) begin
                        sort_array_next[10] = sort_array[11];
                        sort_array_next[11] = sort_array[10];
                    end else begin
                        sort_array_next[10] = sort_array[10];
                        sort_array_next[11] = sort_array[11];
                    end
                    // Compare and swap (12, 13) - descending order
                    if (sort_array[12] < sort_array[13]) begin
                        sort_array_next[12] = sort_array[13];
                        sort_array_next[13] = sort_array[12];
                    end else begin
                        sort_array_next[12] = sort_array[12];
                        sort_array_next[13] = sort_array[13];
                    end
                    // Compare and swap (14, 15) - descending order
                    if (sort_array[14] < sort_array[15]) begin
                        sort_array_next[14] = sort_array[15];
                        sort_array_next[15] = sort_array[14];
                    end else begin
                        sort_array_next[14] = sort_array[14];
                        sort_array_next[15] = sort_array[15];
                    end
                    cycle_cnt_next = cycle_cnt + 1;
                    if (cycle_cnt == 5'd16) begin
                        state_next = DONE;
                    end
                end
                
                // Odd-indexed comparisons (odd cycles)
                5'd1, 5'd3, 5'd5, 5'd7, 5'd9, 5'd11, 5'd13, 5'd15: begin
                    // Compare and swap (1, 2) - descending order
                    if (sort_array[1] < sort_array[2]) begin
                        sort_array_next[1] = sort_array[2];
                        sort_array_next[2] = sort_array[1];
                    end else begin
                        sort_array_next[1] = sort_array[1];
                        sort_array_next[2] = sort_array[2];
                    end
                    // Compare and swap (3, 4) - descending order
                    if (sort_array[3] < sort_array[4]) begin
                        sort_array_next[3] = sort_array[4];
                        sort_array_next[4] = sort_array[3];
                    end else begin
                        sort_array_next[3] = sort_array[3];
                        sort_array_next[4] = sort_array[4];
                    end
                    // Compare and swap (5, 6) - descending order
                    if (sort_array[5] < sort_array[6]) begin
                        sort_array_next[5] = sort_array[6];
                        sort_array_next[6] = sort_array[5];
                    end else begin
                        sort_array_next[5] = sort_array[5];
                        sort_array_next[6] = sort_array[6];
                    end
                    // Compare and swap (7, 8) - descending order
                    if (sort_array[7] < sort_array[8]) begin
                        sort_array_next[7] = sort_array[8];
                        sort_array_next[8] = sort_array[7];
                    end else begin
                        sort_array_next[7] = sort_array[7];
                        sort_array_next[8] = sort_array[8];
                    end
                    // Compare and swap (9, 10) - descending order
                    if (sort_array[9] < sort_array[10]) begin
                        sort_array_next[9] = sort_array[10];
                        sort_array_next[10] = sort_array[9];
                    end else begin
                        sort_array_next[9] = sort_array[9];
                        sort_array_next[10] = sort_array[10];
                    end
                    // Compare and swap (11, 12) - descending order
                    if (sort_array[11] < sort_array[12]) begin
                        sort_array_next[11] = sort_array[12];
                        sort_array_next[12] = sort_array[11];
                    end else begin
                        sort_array_next[11] = sort_array[11];
                        sort_array_next[12] = sort_array[12];
                    end
                    // Compare and swap (13, 14) - descending order
                    if (sort_array[13] < sort_array[14]) begin
                        sort_array_next[13] = sort_array[14];
                        sort_array_next[14] = sort_array[13];
                    end else begin
                        sort_array_next[13] = sort_array[13];
                        sort_array_next[14] = sort_array[14];
                    end
                    cycle_cnt_next = cycle_cnt + 1;
                end
                
                default: begin
                    state_next = DONE;
                end
            endcase
        end
        
        DONE: begin
            done = 1'b1;
            state_next = IDLE;
        end
        
        default: begin
            state_next = IDLE;
        end
    endcase
end

// ========================================
// Output Assignment  
// ========================================
always @(*) begin
    data_out = {sort_array[0],  sort_array[1],  sort_array[2],  sort_array[3],
                sort_array[4],  sort_array[5],  sort_array[6],  sort_array[7],
                sort_array[8],  sort_array[9],  sort_array[10], sort_array[11],
                sort_array[12], sort_array[13], sort_array[14], sort_array[15]};
end

// ========================================
// Sequential Logic
// ========================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= IDLE;
        cycle_cnt <= 5'd0;
        for (i = 0; i < 16; i = i + 1) begin
            sort_array[i] <= 8'd0;
        end
    end else if (en) begin
        state <= state_next;
        cycle_cnt <= cycle_cnt_next;
        for (i = 0; i < 16; i = i + 1) begin
            sort_array[i] <= sort_array_next[i];
        end
    end
end

endmodule
