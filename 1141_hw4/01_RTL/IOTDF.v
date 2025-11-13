`timescale 1ns/10ps
module IOTDF( clk, rst, in_en, iot_in, fn_sel, busy, valid, iot_out);
input          clk;
input          rst;
input          in_en;
input  [7:0]   iot_in;
input  [2:0]   fn_sel;
output         busy;
output         valid;
output [127:0] iot_out;

// ========================================
// Function Codes
// ========================================
localparam DES_ENCRYPT = 3'b001;
localparam DES_DECRYPT = 3'b010;
localparam CRC_GEN     = 3'b011;
localparam SORT        = 3'b100;

// ========================================
// FSM State Definition
// ========================================
localparam IDLE    = 2'd0;
localparam LOAD    = 2'd1;
localparam COMPUTE = 2'd2;


// ========================================
// Registers & Wires
// ========================================
reg [1:0]   current_state, next_state;
reg [3:0]   load_cnt, load_cnt_next;

// Single buffer
reg [127:0] data_buf, data_buf_next;

// Output registers
reg         busy_reg, busy_reg_next;
reg [127:0] result_reg, result_reg_next;
reg         valid_reg, valid_reg_next;

// Control signals for computation cores
reg         des_start_reg, des_start_reg_next;
reg         crc_sort_start_reg, crc_sort_start_reg_next;

// ========================================
// DES Core Interface
// ========================================
wire [63:0] des_data_in;
wire [63:0] des_key_in;
wire        des_decrypt;
wire [63:0] des_data_out;
wire        des_done;

assign des_data_in = data_buf[63:0];
assign des_key_in  = data_buf[127:64];
assign des_decrypt = (fn_sel == DES_DECRYPT);

des_core des_inst (
    .clk(clk),
    .rst(rst),
    .start(des_start_reg),
    .data_in(des_data_in),
    .key_in(des_key_in),
    .decrypt(des_decrypt),
    .data_out(des_data_out),
    .done(des_done)
);

// ========================================
// CRC/Sort Core Interface
// ========================================
wire [127:0] crc_sort_data_out;
wire         crc_sort_done;

crc_sort_core crc_sort_inst (
    .clk(clk),
    .rst(rst),
    .start(crc_sort_start_reg),
    .data_in(data_buf),
    .fn_sel(fn_sel),
    .data_out(crc_sort_data_out),
    .done(crc_sort_done)
);

// ========================================
// Combinational Logic - Output Assignment
// ========================================
assign busy    = busy_reg;
assign valid   = valid_reg;
assign iot_out = result_reg;

// ========================================
// Combinational Logic - Datapath and FSM
// ========================================
always @(*) begin
    // Default assignments to avoid latches
    load_cnt_next = load_cnt;
    data_buf_next = data_buf;
    result_reg_next = result_reg;
    valid_reg_next = 1'b0;
    busy_reg_next = busy_reg;
    des_start_reg_next = 1'b0;
    crc_sort_start_reg_next = 1'b0;
    next_state = current_state;
    
    case (current_state)
        IDLE: begin
            if (in_en) begin
                // Start loading first byte
                load_cnt_next = 4'd1;
                data_buf_next[7:0] = iot_in;
                next_state = LOAD;
                busy_reg_next = 1'b0;  // Not busy yet
            end
            else begin
                next_state = IDLE;
            end
        end
        
        LOAD: begin
            if (in_en) begin
                if (load_cnt < 4'd14) begin
                    // Loading bytes 1-13
                    load_cnt_next = load_cnt + 4'd1;
                    case (load_cnt)
                        4'd1:  data_buf_next[15:8]   = iot_in;
                        4'd2:  data_buf_next[23:16]  = iot_in;
                        4'd3:  data_buf_next[31:24]  = iot_in;
                        4'd4:  data_buf_next[39:32]  = iot_in;
                        4'd5:  data_buf_next[47:40]  = iot_in;
                        4'd6:  data_buf_next[55:48]  = iot_in;
                        4'd7:  data_buf_next[63:56]  = iot_in;
                        4'd8:  data_buf_next[71:64]  = iot_in;
                        4'd9:  data_buf_next[79:72]  = iot_in;
                        4'd10: data_buf_next[87:80]  = iot_in;
                        4'd11: data_buf_next[95:88]  = iot_in;
                        4'd12: data_buf_next[103:96] = iot_in;
                        4'd13: data_buf_next[111:104]= iot_in;
                    endcase
                    next_state = LOAD;
                end else if (load_cnt == 4'd14) begin
                    // Loading byte 14
                    load_cnt_next = load_cnt + 4'd1;
                    data_buf_next[119:112] = iot_in;
                    busy_reg_next = 1'b1;  // Busy during loading
                    next_state = LOAD;
                end else begin
                    // Loading last byte (load_cnt == 15)
                    data_buf_next[127:120] = iot_in;
                    load_cnt_next = 4'd0;
                    
                    // Start appropriate computation
                    if (fn_sel == DES_ENCRYPT || fn_sel == DES_DECRYPT) begin
                        des_start_reg_next = 1'b1;
                    end else if (fn_sel == CRC_GEN || fn_sel == SORT) begin
                        crc_sort_start_reg_next = 1'b1;
                    end
                    
                    next_state = COMPUTE;
                end
            end else begin
                // No more input, go back to IDLE
                next_state = IDLE;
            end
        end

        COMPUTE: begin
            // Wait for computation to complete
            if (des_done || crc_sort_done) begin
                // Computation complete, output ready
                if (des_done) begin
                    result_reg_next = {data_buf[127:64], des_data_out};
                end else begin
                    result_reg_next = crc_sort_data_out;
                end
                valid_reg_next = 1'b1;
                
                // no need to check i_en since i_en will be 1 in the next cycle when done is high   
                next_state = IDLE;
                busy_reg_next = 1'b0;

            end else begin
                // Still computing
                next_state = COMPUTE;
            end
                
        end
        
        default: begin
            next_state = IDLE;
        end
    endcase
end

// ========================================
// Sequential Logic
// ========================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        load_cnt           <= 4'd0;
        data_buf           <= 128'd0;
        result_reg         <= 128'd0;
        valid_reg          <= 1'b0;
        busy_reg           <= 1'b0;
        des_start_reg      <= 1'b0;
        crc_sort_start_reg <= 1'b0;
        current_state      <= IDLE;
    end else begin
        load_cnt           <= load_cnt_next;
        data_buf           <= data_buf_next;
        result_reg         <= result_reg_next;
        valid_reg          <= valid_reg_next;
        busy_reg           <= busy_reg_next;
        des_start_reg      <= des_start_reg_next;
        crc_sort_start_reg <= crc_sort_start_reg_next;
        current_state      <= next_state;
    end
end

endmodule
