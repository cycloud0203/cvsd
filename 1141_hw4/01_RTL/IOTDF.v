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
reg         load_sel, load_sel_next;

// Dual input buffers
reg [127:0] data_buf0, data_buf0_next;
reg [127:0] data_buf1, data_buf1_next;
reg [1:0]   buffer_full, buffer_full_next;

// Compute control
reg         compute_sel, compute_sel_next;
reg         compute_active, compute_active_next;

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
wire [127:0] compute_data;
wire [63:0]  des_data_in;
wire [63:0]  des_key_in;
wire         des_decrypt;
wire [63:0]  des_data_out;
wire         des_done;
wire         mode_is_des;
wire         mode_is_crc_sort;

assign compute_data   = (compute_sel == 1'b0) ? data_buf0 : data_buf1;
assign des_data_in    = compute_data[63:0];
assign des_key_in     = compute_data[127:64];
assign mode_is_des    = (fn_sel == DES_ENCRYPT) || (fn_sel == DES_DECRYPT);
assign mode_is_crc_sort = (fn_sel == CRC_GEN) || (fn_sel == SORT);
assign des_decrypt    = (fn_sel == DES_DECRYPT);

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
    .data_in(compute_data),
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
    load_sel_next = load_sel;
    data_buf0_next = data_buf0;
    data_buf1_next = data_buf1;
    buffer_full_next = buffer_full;
    compute_sel_next = compute_sel;
    compute_active_next = compute_active;
    result_reg_next = result_reg;
    valid_reg_next = 1'b0;
    busy_reg_next = busy_reg;
    des_start_reg_next = 1'b0;
    crc_sort_start_reg_next = 1'b0;
    next_state = current_state;

    case (current_state)
        IDLE: begin
            if (in_en) begin
                if (!buffer_full[0]) begin
                    load_sel_next = 1'b0;
                    load_cnt_next = 4'd1;
                    data_buf0_next[7:0] = iot_in;
                    next_state = LOAD;
                end else if (!buffer_full[1]) begin
                    load_sel_next = 1'b1;
                    load_cnt_next = 4'd1;
                    data_buf1_next[7:0] = iot_in;
                    next_state = LOAD;
                end else begin
                    next_state = IDLE;
                    busy_reg_next = 1'b1;
                end
            end else begin
                next_state = IDLE;
            end
        end

        LOAD: begin
            if (in_en) begin
                next_state = LOAD;
                if (load_sel == 1'b0) begin
                    case (load_cnt)
                        4'd1: begin
                            data_buf0_next[15:8] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd2: begin
                            data_buf0_next[23:16] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd3: begin
                            data_buf0_next[31:24] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd4: begin
                            data_buf0_next[39:32] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd5: begin
                            data_buf0_next[47:40] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd6: begin
                            data_buf0_next[55:48] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd7: begin
                            data_buf0_next[63:56] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd8: begin
                            data_buf0_next[71:64] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd9: begin
                            data_buf0_next[79:72] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd10: begin
                            data_buf0_next[87:80] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd11: begin
                            data_buf0_next[95:88] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd12: begin
                            data_buf0_next[103:96] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd13: begin
                            data_buf0_next[111:104] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd14: begin
                            data_buf0_next[119:112] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                            if (buffer_full[1])
                                busy_reg_next = 1'b1;
                        end
                        4'd15: begin
                            data_buf0_next[127:120] = iot_in;
                            load_cnt_next = 4'd0;
                            buffer_full_next[0] = 1'b1;
                            next_state = IDLE;
                        end
                        default: begin
                            load_cnt_next = load_cnt;
                        end
                    endcase
                end else begin
                    case (load_cnt)
                        4'd1: begin
                            data_buf1_next[15:8] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd2: begin
                            data_buf1_next[23:16] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd3: begin
                            data_buf1_next[31:24] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd4: begin
                            data_buf1_next[39:32] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd5: begin
                            data_buf1_next[47:40] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd6: begin
                            data_buf1_next[55:48] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd7: begin
                            data_buf1_next[63:56] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd8: begin
                            data_buf1_next[71:64] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd9: begin
                            data_buf1_next[79:72] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd10: begin
                            data_buf1_next[87:80] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd11: begin
                            data_buf1_next[95:88] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd12: begin
                            data_buf1_next[103:96] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd13: begin
                            data_buf1_next[111:104] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                        end
                        4'd14: begin
                            data_buf1_next[119:112] = iot_in;
                            load_cnt_next = load_cnt + 4'd1;
                            if (buffer_full[0])
                                busy_reg_next = 1'b1;
                        end
                        4'd15: begin
                            data_buf1_next[127:120] = iot_in;
                            load_cnt_next = 4'd0;
                            buffer_full_next[1] = 1'b1;
                            next_state = IDLE;
                        end
                        default: begin
                            load_cnt_next = load_cnt;
                        end
                    endcase
                end
            end else begin
                next_state = LOAD;
            end
        end

        default: begin
            next_state = IDLE;
        end
    endcase

    if (compute_active) begin
        if (mode_is_des) begin
            if (des_done) begin
                result_reg_next = {compute_data[127:64], des_data_out};
                valid_reg_next = 1'b1;
                buffer_full_next[compute_sel] = 1'b0;
                compute_active_next = 1'b0;
                busy_reg_next = 1'b0;
            end
        end else if (mode_is_crc_sort) begin
            if (crc_sort_done) begin
                result_reg_next = crc_sort_data_out;
                valid_reg_next = 1'b1;
                buffer_full_next[compute_sel] = 1'b0;
                compute_active_next = 1'b0;
                busy_reg_next = 1'b0;
            end
        end else begin
            if (des_done || crc_sort_done) begin
                buffer_full_next[compute_sel] = 1'b0;
                compute_active_next = 1'b0;
                busy_reg_next = 1'b0;
            end
        end
    end

    if (!compute_active_next) begin
        if (buffer_full_next[0]) begin
            compute_sel_next = 1'b0;
            compute_active_next = 1'b1;
            if ((fn_sel == DES_ENCRYPT) || (fn_sel == DES_DECRYPT)) begin
                des_start_reg_next = 1'b1;
            end else if ((fn_sel == CRC_GEN) || (fn_sel == SORT)) begin
                crc_sort_start_reg_next = 1'b1;
            end
        end else if (buffer_full_next[1]) begin
            compute_sel_next = 1'b1;
            compute_active_next = 1'b1;
            if ((fn_sel == DES_ENCRYPT) || (fn_sel == DES_DECRYPT)) begin
                des_start_reg_next = 1'b1;
            end else if ((fn_sel == CRC_GEN) || (fn_sel == SORT)) begin
                crc_sort_start_reg_next = 1'b1;
            end
        end
    end
end

// ========================================
// Sequential Logic
// ========================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        load_cnt            <= 4'd0;
        load_sel            <= 1'b0;
        data_buf0           <= 128'd0;
        data_buf1           <= 128'd0;
        buffer_full         <= 2'b00;
        compute_sel         <= 1'b0;
        compute_active      <= 1'b0;
        result_reg          <= 128'd0;
        valid_reg           <= 1'b0;
        busy_reg            <= 1'b0;
        des_start_reg       <= 1'b0;
        crc_sort_start_reg  <= 1'b0;
        current_state       <= IDLE;
    end else begin
        load_cnt            <= load_cnt_next;
        load_sel            <= load_sel_next;
        data_buf0           <= data_buf0_next;
        data_buf1           <= data_buf1_next;
        buffer_full         <= buffer_full_next;
        compute_sel         <= compute_sel_next;
        compute_active      <= compute_active_next;
        result_reg          <= result_reg_next;
        valid_reg           <= valid_reg_next;
        busy_reg            <= busy_reg_next;
        des_start_reg       <= des_start_reg_next;
        crc_sort_start_reg  <= crc_sort_start_reg_next;
        current_state       <= next_state;
    end
end

endmodule
