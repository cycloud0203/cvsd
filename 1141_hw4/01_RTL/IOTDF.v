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
// FSM State Definition
// ========================================
localparam IDLE     = 2'd0;
localparam LOAD     = 2'd1;
localparam PIPELINE = 2'd2;  // Load and Compute simultaneously

// ========================================
// Registers & Wires
// ========================================
reg [1:0]   current_state, next_state;
reg [3:0]   load_cnt, load_cnt_next;
reg [3:0]   comp_cnt, comp_cnt_next;  // Compute counter (16 cycles for DES)

// Ping-pong dual buffer
reg [127:0] data_buf0, data_buf0_next;  // Buffer 0
reg [127:0] data_buf1, data_buf1_next;  // Buffer 1
reg         buf0_full, buf0_full_next;  // Buffer 0 full flag
reg         buf1_full, buf1_full_next;  // Buffer 1 full flag
reg         compute_buf_sel, compute_buf_sel_next;  // 0: compute buf0, 1: compute buf1
reg         load_buf_sel, load_buf_sel_next;        // 0: load to buf0, 1: load to buf1

// output registers
reg         busy_reg, busy_reg_next;
reg [127:0] result_reg, result_reg_next;
reg         valid_reg, valid_reg_next;

// ========================================
// DES Core Wires
// ========================================
wire [63:0] des_data_in;
wire [63:0] des_key_in;
wire        des_decrypt;
wire [63:0] des_data_out;

// Select which buffer to compute (use stable compute_buf_sel)
assign des_data_in = (compute_buf_sel == 1'b0) ? data_buf0[63:0] : data_buf1[63:0];
assign des_key_in  = (compute_buf_sel == 1'b0) ? data_buf0[127:64] : data_buf1[127:64];

// encrypt: 3'b001 decrypt: 3'b010
assign des_decrypt = fn_sel[1];

// ========================================
// DES Core Instantiation
// ========================================
des_core des_inst (
    .clk(clk),
    .rst(rst),
    .data_in(des_data_in),
    .key_in(des_key_in),
    .decrypt(des_decrypt),
    .data_out(des_data_out)
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
    comp_cnt_next = comp_cnt;
    data_buf0_next = data_buf0;
    data_buf1_next = data_buf1;
    buf0_full_next = buf0_full;
    buf1_full_next = buf1_full;
    compute_buf_sel_next = compute_buf_sel;
    load_buf_sel_next = load_buf_sel;
    result_reg_next = result_reg;
    valid_reg_next = 1'b0;
    next_state = current_state;
    
    // busy = both buffers are full
    busy_reg_next = buf0_full && buf1_full;
    
    case (current_state)
        IDLE: begin
            if (in_en) begin
                load_cnt_next = 4'd1;
                load_buf_sel_next = 1'b0;  // Start loading to buf0
                data_buf0_next[7:0] = iot_in;
                next_state = LOAD;
            end
            else begin
                next_state = IDLE;
            end
        end
        
        LOAD: begin
            // Initial loading - always load to buf0 only
            if (in_en) begin
                if (load_cnt < 4'd14) begin
                    load_cnt_next = load_cnt + 4'd1;
                    case (load_cnt)
                        4'd1:  data_buf0_next[15:8]   = iot_in;
                        4'd2:  data_buf0_next[23:16]  = iot_in;
                        4'd3:  data_buf0_next[31:24]  = iot_in;
                        4'd4:  data_buf0_next[39:32]  = iot_in;
                        4'd5:  data_buf0_next[47:40]  = iot_in;
                        4'd6:  data_buf0_next[55:48]  = iot_in;
                        4'd7:  data_buf0_next[63:56]  = iot_in;
                        4'd8:  data_buf0_next[71:64]  = iot_in;
                        4'd9:  data_buf0_next[79:72]  = iot_in;
                        4'd10: data_buf0_next[87:80]  = iot_in;
                        4'd11: data_buf0_next[95:88]  = iot_in;
                        4'd12: data_buf0_next[103:96] = iot_in;
                        4'd13: data_buf0_next[111:104]= iot_in;
                    endcase
                    next_state = LOAD;
                end else if (load_cnt == 4'd14) begin
                    // Second to last byte - set buf_full_next early for busy signal
                    load_cnt_next = load_cnt + 4'd1;
                    data_buf0_next[119:112] = iot_in;
                    buf0_full_next = 1'b1;  // Set full flag early
                    next_state = LOAD;
                end else begin
                    // Last byte received (load_cnt == 15)
                    data_buf0_next[127:120] = iot_in;
                    load_cnt_next = 4'd0;
                    comp_cnt_next = 4'd0;  // Start compute counter
                    compute_buf_sel_next = 1'b0;  // Start computing buf0
                    next_state = PIPELINE;
                end
            end else begin
                // No more input, return to IDLE
                next_state = IDLE;
            end
        end

        PIPELINE: begin
            // Increment computation counter
            if (comp_cnt < 4'd15) begin
                comp_cnt_next = comp_cnt + 4'd1;
            end else begin
                // Computation done - output ready at cycle 15
                result_reg_next = {64'b0, des_data_out};
                valid_reg_next = 1'b1;
                
                // Clear the buffer that just finished computing
                if (compute_buf_sel == 1'b0) begin
                    buf0_full_next = 1'b0;
                end else begin
                    buf1_full_next = 1'b0;
                end
                
                // Check if there's another full buffer to compute
                // Use current full status, avoid buffer that's receiving its last byte
                if (compute_buf_sel == 1'b0 && buf1_full && 
                    !(load_buf_sel == 1'b1 && load_cnt == 4'd15)) begin
                    // Switch to compute buf1 if fully loaded
                    compute_buf_sel_next = 1'b1;
                    comp_cnt_next = 4'd0;
                end else if (compute_buf_sel == 1'b1 && buf0_full && 
                             !(load_buf_sel == 1'b0 && load_cnt == 4'd15)) begin
                    // Switch to compute buf0 if fully loaded
                    compute_buf_sel_next = 1'b0;
                    comp_cnt_next = 4'd0;
                end else begin
                    // No buffer ready to compute
                    comp_cnt_next = 4'd0;
                end
            end
            
            // Handle loading simultaneously (independent of computation)
            if (in_en) begin
                // Determine which buffer to load to
                if (load_cnt == 4'd0) begin
                    // Need to start loading a new buffer
                    // Load to whichever buffer is empty
                    if (!buf0_full) begin
                        load_buf_sel_next = 1'b0;
                        load_cnt_next = 4'd1;
                        data_buf0_next[7:0] = iot_in;
                    end else if (!buf1_full) begin
                        load_buf_sel_next = 1'b1;
                        load_cnt_next = 4'd1;
                        data_buf1_next[7:0] = iot_in;
                    end
                    // If both buffers are full, we can't load (busy condition)
                end else begin
                    // Continue loading to current buffer
                    if (load_buf_sel == 1'b0) begin
                        // Loading to buf0
                        if (load_cnt < 4'd14) begin
                            load_cnt_next = load_cnt + 4'd1;
                            case (load_cnt)
                                4'd1:  data_buf0_next[15:8]   = iot_in;
                                4'd2:  data_buf0_next[23:16]  = iot_in;
                                4'd3:  data_buf0_next[31:24]  = iot_in;
                                4'd4:  data_buf0_next[39:32]  = iot_in;
                                4'd5:  data_buf0_next[47:40]  = iot_in;
                                4'd6:  data_buf0_next[55:48]  = iot_in;
                                4'd7:  data_buf0_next[63:56]  = iot_in;
                                4'd8:  data_buf0_next[71:64]  = iot_in;
                                4'd9:  data_buf0_next[79:72]  = iot_in;
                                4'd10: data_buf0_next[87:80]  = iot_in;
                                4'd11: data_buf0_next[95:88]  = iot_in;
                                4'd12: data_buf0_next[103:96] = iot_in;
                                4'd13: data_buf0_next[111:104]= iot_in;
                            endcase
                        end else if (load_cnt == 4'd14) begin
                            load_cnt_next = load_cnt + 4'd1;
                            data_buf0_next[119:112] = iot_in;
                            buf0_full_next = 1'b1;
                        end else if (load_cnt == 4'd15) begin
                            data_buf0_next[127:120] = iot_in;
                            load_cnt_next = 4'd0;
                        end
                    end else begin
                        // Loading to buf1
                        if (load_cnt < 4'd14) begin
                            load_cnt_next = load_cnt + 4'd1;
                            case (load_cnt)
                                4'd1:  data_buf1_next[15:8]   = iot_in;
                                4'd2:  data_buf1_next[23:16]  = iot_in;
                                4'd3:  data_buf1_next[31:24]  = iot_in;
                                4'd4:  data_buf1_next[39:32]  = iot_in;
                                4'd5:  data_buf1_next[47:40]  = iot_in;
                                4'd6:  data_buf1_next[55:48]  = iot_in;
                                4'd7:  data_buf1_next[63:56]  = iot_in;
                                4'd8:  data_buf1_next[71:64]  = iot_in;
                                4'd9:  data_buf1_next[79:72]  = iot_in;
                                4'd10: data_buf1_next[87:80]  = iot_in;
                                4'd11: data_buf1_next[95:88]  = iot_in;
                                4'd12: data_buf1_next[103:96] = iot_in;
                                4'd13: data_buf1_next[111:104]= iot_in;
                            endcase
                        end else if (load_cnt == 4'd14) begin
                            load_cnt_next = load_cnt + 4'd1;
                            data_buf1_next[119:112] = iot_in;
                            buf1_full_next = 1'b1;
                        end else if (load_cnt == 4'd15) begin
                            data_buf1_next[127:120] = iot_in;
                            load_cnt_next = 4'd0;
                        end
                    end
                end
            end
            
            // Determine next state
            if (!in_en && comp_cnt == 4'd15 && !buf0_full_next && !buf1_full_next) begin
                // No more input and no pending computation
                next_state = IDLE;
            end else begin
                next_state = PIPELINE;
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
// Data path registers
always @(posedge clk or posedge rst) begin
    if (rst) begin
        load_cnt        <= 4'd0;
        comp_cnt        <= 4'd0;
        data_buf0       <= 128'd0;
        data_buf1       <= 128'd0;
        buf0_full       <= 1'b0;
        buf1_full       <= 1'b0;
        compute_buf_sel <= 1'b0;
        load_buf_sel    <= 1'b0;
        result_reg      <= 128'd0;
        valid_reg       <= 1'b0;
        current_state   <= IDLE;
        busy_reg        <= 1'b0;
    end else begin
        busy_reg        <= busy_reg_next;
        load_cnt        <= load_cnt_next;
        comp_cnt        <= comp_cnt_next;
        data_buf0       <= data_buf0_next;
        data_buf1       <= data_buf1_next;
        buf0_full       <= buf0_full_next;
        buf1_full       <= buf1_full_next;
        compute_buf_sel <= compute_buf_sel_next;
        load_buf_sel    <= load_buf_sel_next;
        result_reg      <= result_reg_next;
        valid_reg       <= valid_reg_next;
        current_state   <= next_state;
    end
end

endmodule
