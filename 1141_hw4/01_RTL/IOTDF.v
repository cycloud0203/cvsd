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


// ========================================
// Registers & Wires
// ========================================
(* fsm_encoding = "auto" *) reg [1:0]   current_state, next_state;
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

// Registered enable signals for clock gating
reg         des_en_reg, des_en_reg_next;
reg         crc_sort_en_reg, crc_sort_en_reg_next;

(* synopsys_clock_gating = "true" *) wire enable;

function automatic [127:0] write_byte;
    input [127:0] word_in;
    input [3:0]  byte_idx;
    input [7:0]  byte_value;
    begin
        write_byte = word_in;
        case (byte_idx)
            4'd0:  write_byte[7:0]       = byte_value;
            4'd1:  write_byte[15:8]      = byte_value;
            4'd2:  write_byte[23:16]     = byte_value;
            4'd3:  write_byte[31:24]     = byte_value;
            4'd4:  write_byte[39:32]     = byte_value;
            4'd5:  write_byte[47:40]     = byte_value;
            4'd6:  write_byte[55:48]     = byte_value;
            4'd7:  write_byte[63:56]     = byte_value;
            4'd8:  write_byte[71:64]     = byte_value;
            4'd9:  write_byte[79:72]     = byte_value;
            4'd10: write_byte[87:80]     = byte_value;
            4'd11: write_byte[95:88]     = byte_value;
            4'd12: write_byte[103:96]    = byte_value;
            4'd13: write_byte[111:104]   = byte_value;
            4'd14: write_byte[119:112]   = byte_value;
            4'd15: write_byte[127:120]   = byte_value;
            default: write_byte = word_in;
        endcase
    end
endfunction

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
assign mode_is_des    = (fn_sel == DES_ENCRYPT) || (fn_sel == DES_DECRYPT);
assign mode_is_crc_sort = (fn_sel == CRC_GEN) || (fn_sel == SORT);
assign des_decrypt    = (fn_sel == DES_DECRYPT);

// Operand isolation: gate inputs to prevent switching in unused cores
assign des_data_in    = mode_is_des ? compute_data[63:0] : 64'd0;
assign des_key_in     = mode_is_des ? compute_data[127:64] : 64'd0;

des_core des_inst (
    .clk(clk),
    .rst(rst),
    .en(des_en_reg),
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
wire [127:0] crc_sort_data_in;
wire [127:0] crc_sort_data_out;
wire         crc_sort_done;

// Operand isolation for CRC/Sort core
assign crc_sort_data_in = mode_is_crc_sort ? compute_data : 128'd0;

crc_sort_core crc_sort_inst (
    .clk(clk),
    .rst(rst),
    .en(crc_sort_en_reg),
    .start(crc_sort_start_reg),
    .data_in(crc_sort_data_in),
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
    des_en_reg_next = des_en_reg;
    crc_sort_en_reg_next = crc_sort_en_reg;

    case (current_state)
        IDLE: begin
            if (in_en) begin
                if (!buffer_full[0]) begin
                    load_sel_next = 1'b0;
                    load_cnt_next = 4'd1;
                    data_buf0_next = write_byte(128'd0, 4'd0, iot_in);
                    next_state = LOAD;
                    busy_reg_next = 1'b0;
                end else if (!buffer_full[1]) begin
                    load_sel_next = 1'b1;
                    load_cnt_next = 4'd1;
                    data_buf1_next = write_byte(128'd0, 4'd0, iot_in);
                    next_state = LOAD;
                    busy_reg_next = 1'b0;
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
                    data_buf0_next = write_byte(data_buf0, load_cnt, iot_in);
                    if (load_cnt == 4'd15) begin
                        load_cnt_next = 4'd0;
                        buffer_full_next[0] = 1'b1;
                        next_state = IDLE;
                        if (buffer_full[1])
                            busy_reg_next = 1'b1;
                    end else begin
                        load_cnt_next = load_cnt + 4'd1;
                        if ((load_cnt == 4'd14) && buffer_full[1])
                            busy_reg_next = 1'b1;
                    end
                end else begin
                    data_buf1_next = write_byte(data_buf1, load_cnt, iot_in);
                    if (load_cnt == 4'd15) begin
                        load_cnt_next = 4'd0;
                        buffer_full_next[1] = 1'b1;
                        next_state = IDLE;
                        if (buffer_full[0])
                            busy_reg_next = 1'b1;
                    end else begin
                        load_cnt_next = load_cnt + 4'd1;
                        if ((load_cnt == 4'd14) && buffer_full[0])
                            busy_reg_next = 1'b1;
                    end
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

    // Start computation when buffer is ready and not computing
    if (!compute_active_next) begin
        if (buffer_full_next[0] || buffer_full_next[1]) begin
            compute_sel_next = buffer_full_next[0] ? 1'b0 : 1'b1;
            compute_active_next = 1'b1;
            if (mode_is_des) begin
                des_start_reg_next = 1'b1;
            end else if (mode_is_crc_sort) begin
                crc_sort_start_reg_next = 1'b1;
            end
        end
    end
    
    // Enable signals: active when compute will be active and mode matches
    // Computed at the end so compute_active_next is finalized
    des_en_reg_next = compute_active_next && mode_is_des;
    crc_sort_en_reg_next = compute_active_next && mode_is_crc_sort;
end

assign enable = in_en |
                      compute_active |
                      compute_active_next |
                      valid_reg |
                      valid_reg_next |
                      busy_reg |
                      busy_reg_next;

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
        des_en_reg          <= 1'b0;
        crc_sort_en_reg     <= 1'b0;
        current_state       <= IDLE;
    end else if (enable) begin
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
        des_en_reg          <= des_en_reg_next;
        crc_sort_en_reg     <= crc_sort_en_reg_next;
        current_state       <= next_state;
    end
end

endmodule
