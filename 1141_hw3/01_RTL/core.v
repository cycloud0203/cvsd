module core (                       //Don't modify interface
	input      		i_clk,
	input      		i_rst_n,
	input    	  	i_in_valid,
	input 	[31: 0] i_in_data,

	output			o_in_ready,

	output	[ 7: 0]	o_out_data1,
	output	[ 7: 0]	o_out_data2,
	output	[ 7: 0]	o_out_data3,
	output	[ 7: 0]	o_out_data4,

	output	[11: 0] o_out_addr1,
	output	[11: 0] o_out_addr2,
	output	[11: 0] o_out_addr3,
	output	[11: 0] o_out_addr4,

	output 			o_out_valid1,
	output 			o_out_valid2,
	output 			o_out_valid3,
	output 			o_out_valid4,

	output 			o_exe_finish
);

// ========================================
// SRAM Signals - 8x 512x8 SRAMs
// ========================================
// Each SRAM stores every 8th pixel based on load_counter % 8
// Separate address lines allow reading from multiple SRAMs simultaneously (needed for stride S=2)
wire [7:0] sram_q[0:7];
reg [8:0] sram_addr[0:7];  // Separate 9-bit address for each SRAM
reg [7:0] sram_d;          // Common data (we only write to one SRAM at a time)
reg [7:0] sram_cen;        // Separate CEN for each SRAM
reg sram_wen;              // Common WEN (we only write to one SRAM at a time)

// Instantiate 8 SRAM banks
sram_512x8 u_sram0 (
    .Q(sram_q[0]),
    .CLK(i_clk),
    .CEN(sram_cen[0]),
    .WEN(sram_wen),
    .A(sram_addr[0]),
    .D(sram_d)
);

sram_512x8 u_sram1 (
    .Q(sram_q[1]),
    .CLK(i_clk),
    .CEN(sram_cen[1]),
    .WEN(sram_wen),
    .A(sram_addr[1]),
    .D(sram_d)
);

sram_512x8 u_sram2 (
    .Q(sram_q[2]),
    .CLK(i_clk),
    .CEN(sram_cen[2]),
    .WEN(sram_wen),
    .A(sram_addr[2]),
    .D(sram_d)
);

sram_512x8 u_sram3 (
    .Q(sram_q[3]),
    .CLK(i_clk),
    .CEN(sram_cen[3]),
    .WEN(sram_wen),
    .A(sram_addr[3]),
    .D(sram_d)
);

sram_512x8 u_sram4 (
    .Q(sram_q[4]),
    .CLK(i_clk),
    .CEN(sram_cen[4]),
    .WEN(sram_wen),
    .A(sram_addr[4]),
    .D(sram_d)
);

sram_512x8 u_sram5 (
    .Q(sram_q[5]),
    .CLK(i_clk),
    .CEN(sram_cen[5]),
    .WEN(sram_wen),
    .A(sram_addr[5]),
    .D(sram_d)
);

sram_512x8 u_sram6 (
    .Q(sram_q[6]),
    .CLK(i_clk),
    .CEN(sram_cen[6]),
    .WEN(sram_wen),
    .A(sram_addr[6]),
    .D(sram_d)
);

sram_512x8 u_sram7 (
    .Q(sram_q[7]),
    .CLK(i_clk),
    .CEN(sram_cen[7]),
    .WEN(sram_wen),
    .A(sram_addr[7]),
    .D(sram_d)
);

// ========================================
// State Machine
// ========================================
localparam IDLE = 4'd0;
localparam LOAD_IMG = 4'd1;
localparam OUTPUT_RESULT = 4'd2;
localparam LOAD_WEIGHT = 4'd3;
localparam COMPUTE = 4'd4;
localparam OUTPUT = 4'd5;
localparam FINISH = 4'd6;

reg [3:0] state, state_next;

// ========================================
// Counters and Control Signals
// ========================================
reg [11:0] load_counter, load_counter_next;
reg [1:0] pixel_idx, pixel_idx_next;
reg [31:0] input_buffer, input_buffer_next;
reg [11:0] barcode_buffer, barcode_buffer_next;
reg [3:0] barcode_bits_count, barcode_bits_count_next;
reg [1:0] decode_symbol_idx, decode_symbol_idx_next;
reg in_ready_reg, in_ready_reg_next;
reg [3:0] weight_counter, weight_counter_next;

// Helper signals for barcode decoding
wire current_lsb;
reg [7:0] decoded_value;
reg symbol_valid;

// Decoded values
reg [7:0] K_value, K_value_next;
reg [7:0] S_value, S_value_next;
reg [7:0] D_value, D_value_next;
reg barcode_found, barcode_found_next;

// Weight storage (3x3 kernel)
reg [7:0] weight [0:8];
reg [7:0] weight_next [0:8];

// Convolution control signals - 4-line circular buffer
parameter LINE_BUFFER_ROWS = 8;
parameter COLS = 64;
reg [7:0] line_buffer [0:LINE_BUFFER_ROWS-1][0:COLS-1];  // 4×64 = 256 pixels
reg [7:0] line_buffer_next [0:LINE_BUFFER_ROWS-1][0:COLS-1];

reg [5:0] load_row, load_row_next;           // Current row being loaded (0-63)
reg [5:0] load_col, load_col_next;           // Current column being loaded (0-63)
reg [5:0] out_row, out_row_next;             // Output row (0-63)
reg [5:0] out_col, out_col_next;             // Output column (0-63)
reg [3:0] kernel_idx, kernel_idx_next;       // Kernel element (0-8)
reg signed [19:0] conv_acc, conv_acc_next;   // MAC accumulator
reg [1:0] conv_phase, conv_phase_next;       // 0:bootstrap, 1:overlap, 2:finish
reg [1:0] out_channel, out_channel_next;     // Output channel selector (0-3)
reg store_last_elem, store_last_elem_next;   // Flag to store the last SRAM element
// Temporary variables for SRAM address calculations
reg [11:0] pixel_addr;
reg [11:0] prev_addr;
reg [11:0] last_addr;
// Output registers
reg [7:0] out_data1_reg, out_data2_reg, out_data3_reg, out_data4_reg;
reg [7:0] out_data1_reg_next, out_data2_reg_next, out_data3_reg_next, out_data4_reg_next;
reg [11:0] out_addr1_reg, out_addr2_reg, out_addr3_reg, out_addr4_reg;
reg [11:0] out_addr1_reg_next, out_addr2_reg_next, out_addr3_reg_next, out_addr4_reg_next;
reg out_valid1_reg, out_valid2_reg, out_valid3_reg, out_valid4_reg;
reg out_valid1_reg_next, out_valid2_reg_next, out_valid3_reg_next, out_valid4_reg_next;
reg o_exe_finish_reg, o_exe_finish_reg_next;

assign o_out_data1 = out_data1_reg;
assign o_out_data2 = out_data2_reg;
assign o_out_data3 = out_data3_reg;
assign o_out_data4 = out_data4_reg;
assign o_out_addr1 = out_addr1_reg;
assign o_out_addr2 = out_addr2_reg;
assign o_out_addr3 = out_addr3_reg;
assign o_out_addr4 = out_addr4_reg;
assign o_out_valid1 = out_valid1_reg;
assign o_out_valid2 = out_valid2_reg;
assign o_out_valid3 = out_valid3_reg;
assign o_out_valid4 = out_valid4_reg;
assign o_exe_finish = o_exe_finish_reg;
assign o_in_ready = in_ready_reg;

// Extract current LSB based on pixel_idx
assign current_lsb = (pixel_idx == 2'd0) ? input_buffer[24] :
                     (pixel_idx == 2'd1) ? input_buffer[16] :
                     (pixel_idx == 2'd2) ? input_buffer[8]  : input_buffer[0];

// Decode barcode symbol to value
always @(*) begin
    symbol_valid = 1'b0;
    decoded_value = 8'd0;
    case (barcode_buffer[10:0]) //synopsys full_case parallel_case
        11'b11001101100: begin decoded_value = 8'd1; symbol_valid = 1'b1; end
        11'b11001100110: begin decoded_value = 8'd2; symbol_valid = 1'b1; end
        11'b10010011000: begin decoded_value = 8'd3; symbol_valid = 1'b1; end
        default: begin decoded_value = 8'd0; symbol_valid = 1'b0; end
    endcase
end

// ========================================
// Convolution Module Instantiation
// ========================================
// Extract 9 pixels from circular buffer with zero padding
reg [7:0] p00, p00_next;
reg [7:0] p01, p01_next;
reg [7:0] p02, p02_next;
reg [7:0] p10, p10_next;
reg [7:0] p11, p11_next;
reg [7:0] p12, p12_next;
reg [7:0] p20, p20_next;
reg [7:0] p21, p21_next;
reg [7:0] p22, p22_next;

integer i, j;
reg [1:0] output_channel;  // Temporary register for case selector

// Removed get_pixel tasks - logic inlined in load_3x3_window to avoid
// multi-dimensional array parameter issues with line_buffer_next
// Convolution result (one module, reused each cycle)
wire [7:0] conv_result;

// Instantiate single convolution module
// All channels use the same weights
conv_3x3 conv_unit (
    .p00(p00), .p01(p01), .p02(p02),
    .p10(p10), .p11(p11), .p12(p12),
    .p20(p20), .p21(p21), .p22(p22),
    .w00(weight[0]), .w01(weight[1]), .w02(weight[2]),
    .w10(weight[3]), .w11(weight[4]), .w12(weight[5]),
    .w20(weight[6]), .w21(weight[7]), .w22(weight[8]),
    .result(conv_result)
);

// ========================================
// Helper Tasks for Code Reuse
// ========================================
// Task to set output channel based on column modulo
task set_output_channel;
    input [1:0] channel;
    input [7:0] data;
    input [11:0] addr;
    input [7:0] cur_data1;
    input [7:0] cur_data2;
    input [7:0] cur_data3;
    input [7:0] cur_data4;
    input [11:0] cur_addr1;
    input [11:0] cur_addr2;
    input [11:0] cur_addr3;
    input [11:0] cur_addr4;
    output [7:0] out_data1;
    output [7:0] out_data2;
    output [7:0] out_data3;
    output [7:0] out_data4;
    output [11:0] out_addr1;
    output [11:0] out_addr2;
    output [11:0] out_addr3;
    output [11:0] out_addr4;
    output out_valid1;
    output out_valid2;
    output out_valid3;
    output out_valid4;
    begin
        out_data1 = (channel == 2'd0) ? data : cur_data1;
        out_data2 = (channel == 2'd1) ? data : cur_data2;
        out_data3 = (channel == 2'd2) ? data : cur_data3;
        out_data4 = (channel == 2'd3) ? data : cur_data4;
        
        out_addr1 = (channel == 2'd0) ? addr : cur_addr1;
        out_addr2 = (channel == 2'd1) ? addr : cur_addr2;
        out_addr3 = (channel == 2'd2) ? addr : cur_addr3;
        out_addr4 = (channel == 2'd3) ? addr : cur_addr4;
        
        out_valid1 = (channel == 2'd0);
        out_valid2 = (channel == 2'd1);
        out_valid3 = (channel == 2'd2);
        out_valid4 = (channel == 2'd3);
    end
endtask

// Task to load 3x3 pixel window centered at (row, col)
// Sets p00_next through p22_next directly - avoids function sensitivity list issues (W122)
// Optimized: Direct bit slicing instead of redundant $unsigned() calls (fixes WRN_1024)
task load_3x3_window;
    input signed [6:0] center_row;
    input signed [6:0] center_col;
    input signed [7:0] dilation;
    input [7:0] s_value_in;
    reg signed [7:0] r_offset;
    reg signed [7:0] c_offset;
    reg signed [7:0] calc_row;
    reg signed [7:0] calc_col;
    reg [2:0] buffer_idx;
    reg [5:0] col_idx;
    begin
      // Initialize all output pixels to zero (default case)
      p00_next = 8'd0;
      p01_next = 8'd0;
      p02_next = 8'd0;
      p10_next = 8'd0;
      p11_next = 8'd0;
      p12_next = 8'd0;
      p20_next = 8'd0;
      p21_next = 8'd0;
      p22_next = 8'd0;
      
      r_offset = dilation;
      c_offset = dilation;
      
      if(dilation == 8'sd1) begin
        // p00: top-left
        calc_row = $signed({1'b0, center_row}) - r_offset;
        calc_col = $signed({1'b0, center_col}) - c_offset;
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p00_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];  // Bit slice is unsigned by default - no $unsigned needed
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 6) : (calc_row[6:0] % 4);
            p00_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p01: top-center
        calc_row = $signed({1'b0, center_row}) - r_offset;
        calc_col = $signed({1'b0, center_col});
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p01_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 6) : (calc_row[6:0] % 4);
            p01_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p02: top-right
        calc_row = $signed({1'b0, center_row}) - r_offset;
        calc_col = $signed({1'b0, center_col}) + c_offset;
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p02_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 6) : (calc_row[6:0] % 4);
            p02_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p10: middle-left
        calc_row = $signed({1'b0, center_row});
        calc_col = $signed({1'b0, center_col}) - c_offset;
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p10_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 6) : (calc_row[6:0] % 4);
            p10_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p11: center (no bounds check needed - always valid)
        col_idx = center_col[5:0];
        buffer_idx = (s_value_in == 8'd2) ? (center_row[6:0] % 6) : (center_row[6:0] % 4);
        p11_next = line_buffer_next[buffer_idx][col_idx];
        
        // p12: middle-right
        calc_row = $signed({1'b0, center_row});
        calc_col = $signed({1'b0, center_col}) + c_offset;
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p12_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 6) : (calc_row[6:0] % 4);
            p12_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p20: bottom-left
        calc_row = $signed({1'b0, center_row}) + r_offset;
        calc_col = $signed({1'b0, center_col}) - c_offset;
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p20_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 6) : (calc_row[6:0] % 4);
            p20_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p21: bottom-center
        calc_row = $signed({1'b0, center_row}) + r_offset;
        calc_col = $signed({1'b0, center_col});
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p21_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 6) : (calc_row[6:0] % 4);
            p21_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p22: bottom-right
        calc_row = $signed({1'b0, center_row}) + r_offset;
        calc_col = $signed({1'b0, center_col}) + c_offset;
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p22_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 6) : (calc_row[6:0] % 4);
            p22_next = line_buffer_next[buffer_idx][col_idx];
        end
      end else if(dilation == 8'sd2) begin
        // p00: top-left (dilation=2)
        calc_row = $signed({1'b0, center_row}) - r_offset;
        calc_col = $signed({1'b0, center_col}) - c_offset;
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p00_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 8) : (calc_row[6:0] % 6);
            p00_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p01: top-center (dilation=2)
        calc_row = $signed({1'b0, center_row}) - r_offset;
        calc_col = $signed({1'b0, center_col});
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p01_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 8) : (calc_row[6:0] % 6);
            p01_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p02: top-right (dilation=2)
        calc_row = $signed({1'b0, center_row}) - r_offset;
        calc_col = $signed({1'b0, center_col}) + c_offset;
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p02_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 8) : (calc_row[6:0] % 6);
            p02_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p10: middle-left (dilation=2)
        calc_row = $signed({1'b0, center_row});
        calc_col = $signed({1'b0, center_col}) - c_offset;
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p10_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 8) : (calc_row[6:0] % 6);
            p10_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p11: center (dilation=2, no bounds check needed)
        col_idx = center_col[5:0];
        buffer_idx = (s_value_in == 8'd2) ? (center_row[6:0] % 8) : (center_row[6:0] % 6);
        p11_next = line_buffer_next[buffer_idx][col_idx];
        
        // p12: middle-right (dilation=2)
        calc_row = $signed({1'b0, center_row});
        calc_col = $signed({1'b0, center_col}) + c_offset;
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p12_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 8) : (calc_row[6:0] % 6);
            p12_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p20: bottom-left (dilation=2)
        calc_row = $signed({1'b0, center_row}) + r_offset;
        calc_col = $signed({1'b0, center_col}) - c_offset;
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p20_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 8) : (calc_row[6:0] % 6);
            p20_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p21: bottom-center (dilation=2)
        calc_row = $signed({1'b0, center_row}) + r_offset;
        calc_col = $signed({1'b0, center_col});
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p21_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 8) : (calc_row[6:0] % 6);
            p21_next = line_buffer_next[buffer_idx][col_idx];
        end
        
        // p22: bottom-right (dilation=2)
        calc_row = $signed({1'b0, center_row}) + r_offset;
        calc_col = $signed({1'b0, center_col}) + c_offset;
        if (calc_row < 0 || calc_row > 63 || calc_col < 0 || calc_col > 63) begin
            p22_next = 8'd0;
        end else begin
            col_idx = calc_col[5:0];
            buffer_idx = (s_value_in == 8'd2) ? (calc_row[6:0] % 8) : (calc_row[6:0] % 6);
            p22_next = line_buffer_next[buffer_idx][col_idx];
        end
      end
    end
endtask

// ========================================
// State Machine Logic
// ========================================
always @(*) begin
    
    state_next = state;
    load_counter_next = load_counter;
    pixel_idx_next = pixel_idx;
    input_buffer_next = input_buffer;
    barcode_buffer_next = barcode_buffer;
    barcode_bits_count_next = barcode_bits_count;
    decode_symbol_idx_next = decode_symbol_idx;
    K_value_next = K_value;
    S_value_next = S_value;
    D_value_next = D_value;
    barcode_found_next = barcode_found;
    in_ready_reg_next = in_ready_reg;
    weight_counter_next = weight_counter;
    load_row_next = load_row;
    load_col_next = load_col;
    out_row_next = out_row;
    out_col_next = out_col;
    kernel_idx_next = kernel_idx;
    conv_acc_next = conv_acc;
    conv_phase_next = conv_phase;
    out_channel_next = out_channel;
    store_last_elem_next = store_last_elem;
    for (i = 0; i < LINE_BUFFER_ROWS; i = i + 1) begin
      for (j = 0; j < COLS; j = j + 1) begin
        line_buffer_next[i][j] = line_buffer[i][j];
      end
    end

    weight_next[0] = weight[0];
    weight_next[1] = weight[1];
    weight_next[2] = weight[2];
    weight_next[3] = weight[3];
    weight_next[4] = weight[4];
    weight_next[5] = weight[5];
    weight_next[6] = weight[6];
    weight_next[7] = weight[7];
    weight_next[8] = weight[8];
    
    // Initialize all SRAM control signals
    sram_addr[0] = 9'd0;
    sram_addr[1] = 9'd0;
    sram_addr[2] = 9'd0;
    sram_addr[3] = 9'd0;
    sram_addr[4] = 9'd0;
    sram_addr[5] = 9'd0;
    sram_addr[6] = 9'd0;
    sram_addr[7] = 9'd0;
    sram_d = 8'd0;
    sram_cen = 8'hFF;  // All SRAMs disabled by default
    sram_wen = 1'b1;   // Write disabled by default
    
    out_data1_reg_next = out_data1_reg;
    out_data2_reg_next = out_data2_reg;
    out_data3_reg_next = out_data3_reg;
    out_data4_reg_next = out_data4_reg;
    out_addr1_reg_next = out_addr1_reg;
    out_addr2_reg_next = out_addr2_reg;
    out_addr3_reg_next = out_addr3_reg;
    out_addr4_reg_next = out_addr4_reg;
    out_valid1_reg_next = out_valid1_reg;
    out_valid2_reg_next = out_valid2_reg;
    out_valid3_reg_next = out_valid3_reg;
    out_valid4_reg_next = out_valid4_reg;
    o_exe_finish_reg_next = o_exe_finish_reg;
    
    p00_next = p00;
    p01_next = p01;
    p02_next = p02;
    p10_next = p10;
    p11_next = p11;
    p12_next = p12;
    p20_next = p20;
    p21_next = p21;
    p22_next = p22;
    
    case (state)
        IDLE: begin
            if (i_in_valid) begin
                state_next = LOAD_IMG;
                input_buffer_next = i_in_data;
                pixel_idx_next = 2'd0;
            end else begin
            in_ready_reg_next = 1'b0;
            load_counter_next = 12'd0;
            pixel_idx_next = 2'd0;
            input_buffer_next = 32'd0;
            barcode_buffer_next = 12'd0;
            barcode_bits_count_next = 4'd0;
            decode_symbol_idx_next = 2'd0;
            K_value_next = 8'd0;
            S_value_next = 8'd0;
            D_value_next = 8'd0;
            barcode_found_next = 1'b0;
                weight_counter_next = 4'd0;
            out_valid1_reg_next = 1'b0;
            out_valid2_reg_next = 1'b0;
            out_valid3_reg_next = 1'b0;
            out_valid4_reg_next = 1'b0;
            o_exe_finish_reg_next = 1'b0;
            end
        end
        
        LOAD_IMG: begin
            // Write one pixel per cycle from buffer
            // Select which SRAM based on load_counter % 8
            sram_cen = 8'hFF;  // Start with all disabled
            sram_cen[load_counter[2:0]] = 1'b0;  // Enable the selected SRAM
            sram_wen = 1'b0;
            // Set address for the selected SRAM (all get the same address, but only one is enabled)
            sram_addr[load_counter[2:0]] = load_counter[11:3];  // Address within the SRAM (divide by 8)
            
            // Select current pixel from buffer
            case (pixel_idx)
                2'd0: sram_d = input_buffer[31:24];
                2'd1: sram_d = input_buffer[23:16];
                2'd2: sram_d = input_buffer[15:8];
                2'd3: sram_d = input_buffer[7:0];
            endcase
            
            // Shift in LSB for barcode decoding
            barcode_buffer_next = {barcode_buffer[10:0], current_lsb};
            load_counter_next = load_counter + 1;
            pixel_idx_next = pixel_idx + 1;
            
            // Decode barcode after accumulating 11 bits
            if (barcode_bits_count >= 4'd11) begin
                if (!barcode_found) begin
                    // Check for Start Code C: 11010011100
                    if (barcode_buffer[10:0] == 11'b11010011100) begin
                        barcode_found_next = 1'b1;
                        barcode_buffer_next = {11'd0, current_lsb};
                        barcode_bits_count_next = 4'd1;
                        decode_symbol_idx_next = 2'd0;
                    end else begin
                        barcode_bits_count_next = 4'd11;
                    end
                end else begin
                    // Decode data symbols
                    if (symbol_valid) begin
                        case (decode_symbol_idx) //synopsys full_case parallel_case
                            2'd0: K_value_next = decoded_value;
                            2'd1: S_value_next = decoded_value;
                            2'd2: D_value_next = decoded_value;
                            default: begin
                                K_value_next = K_value;
                                S_value_next = S_value;
                                D_value_next = D_value;
                            end
                        endcase
                        decode_symbol_idx_next = decode_symbol_idx + 1;
                        barcode_buffer_next = {11'd0, current_lsb};
                        barcode_bits_count_next = 4'd1;
                    end else begin
                        barcode_found_next = 1'b0;
                        barcode_bits_count_next = 4'd11;
                    end
                end
            end else begin
                barcode_bits_count_next = barcode_bits_count + 1;
            end
            

            if (pixel_idx == 2'd2) begin
                in_ready_reg_next = 1'b1;  // Ready for next input
            end else if (pixel_idx == 2'd3) begin
                pixel_idx_next = 2'd0;      // Reset counter
                in_ready_reg_next = 1'b0;
            end else begin
                in_ready_reg_next = 1'b0;  // Still processing current 4 pixels
            end
            
            // Capture new input when ready
            if (i_in_valid && in_ready_reg) begin
                input_buffer_next = i_in_data;
            end
            
            // Done loading when all 4096 pixels are stored
            if (load_counter == 12'd4095) begin
                state_next = OUTPUT_RESULT;  // Skip DECODE_BARCODE state!
                in_ready_reg_next = 1'b0;

                if (K_value == 8'd3 && 
                  (S_value == 8'd1 || S_value == 8'd2) && 
                  (D_value == 8'd1 || D_value == 8'd2)) begin
                    out_data1_reg_next = K_value;
                    out_data2_reg_next = S_value;
                    out_data3_reg_next = D_value;
                end else begin
                    out_data1_reg_next = 8'd0;
                    out_data2_reg_next = 8'd0;
                    out_data3_reg_next = 8'd0;
                end
                out_valid1_reg_next = 1'b1;
                out_valid2_reg_next = 1'b1;
                out_valid3_reg_next = 1'b1;
            end
        end
        
        OUTPUT_RESULT: begin
            state_next = LOAD_WEIGHT;
            out_valid1_reg_next = 1'b0;
            out_valid2_reg_next = 1'b0;
            out_valid3_reg_next = 1'b0;
            out_data1_reg_next = 8'd0;
            out_data2_reg_next = 8'd0;
            out_data3_reg_next = 8'd0;
            weight_counter_next = 4'd0;
            in_ready_reg_next = 1'b1;
        end
        
        LOAD_WEIGHT: begin
            // Load 4 weights per cycle for 3 cycles (total 9 weights)
            // Clear out_valid signals from OUTPUT_RESULT
            out_valid1_reg_next = 1'b0;
            out_valid2_reg_next = 1'b0;
            out_valid3_reg_next = 1'b0;
            
            if (i_in_valid) begin
                case (weight_counter)//synopsys full_case
                    4'd0: begin  // First cycle: load weights 0-3
                        weight_next[0] = i_in_data[31:24];  // weight[0] in MSB
                        weight_next[1] = i_in_data[23:16];  // weight[1]
                        weight_next[2] = i_in_data[15:8];   // weight[2]
                        weight_next[3] = i_in_data[7:0];    // weight[3] in LSB
                        weight_counter_next = 4'd1;

                    end
                    4'd1: begin  // Second cycle: load weights 4-7
                        weight_next[4] = i_in_data[31:24];  // weight[4] in MSB
                        weight_next[5] = i_in_data[23:16];  // weight[5]
                        weight_next[6] = i_in_data[15:8];   // weight[6]
                        weight_next[7] = i_in_data[7:0];    // weight[7] in LSB
                        weight_counter_next = 4'd2;
                    end
                    4'd2: begin  // Third cycle: load weight 8
                        weight_next[8] = i_in_data[31:24];  // weight[8] in MSB
                        weight_counter_next = 4'd3;
                        state_next = COMPUTE;
                        
                        // Initialize convolution control
                        load_row_next = 6'd0;
                        load_col_next = 6'd0;
                        out_row_next = 6'd0;
                        out_col_next = 6'd0;
                        kernel_idx_next = 4'd0;
                        conv_acc_next = 20'sd0;
                        conv_phase_next = 2'd0;  // Bootstrap phase
                        out_channel_next = 2'd0;
                        store_last_elem_next = 1'b0;
                    end
                    default: begin
                        weight_counter_next = weight_counter;
                    end
                endcase
            end
        end
        
        COMPUTE: begin
            // Three-phase circular buffer loading with overlapped computation
            // Phase 0: Bootstrap - Load first 2 rows (128 cycles)
            // Phase 1: Overlap - Load rows 2-63 while computing outputs (3968 cycles)
            // Phase 2: Finish - Complete computation for last 2 rows (128 cycles)

            if (D_value == 8'd1) begin
              if (S_value == 8'd1) begin
                case (conv_phase)
                    // ===================================================================
                    // PHASE 0: BOOTSTRAP - Load rows 0 and 1 without computation
                    // ===================================================================
                    2'd0: begin
                        // Issue SRAM read request
                        // Calculate which SRAM and address within SRAM
                        pixel_addr = {load_row, load_col};
                        sram_cen = 8'hFF;
                        sram_cen[pixel_addr[2:0]] = 1'b0;  // Enable selected SRAM
                        sram_wen = 1'b1;
                        sram_addr[pixel_addr[2:0]] = pixel_addr[11:3];  // Address within selected SRAM

                        // Store data from PREVIOUS cycle (SRAM has 1-cycle read latency)
                        if (load_col > 6'd0 || load_row > 6'd0) begin
                            if (load_col == 6'd0) begin
                                // Just started new row, store last column of previous row
                                prev_addr = {load_row - 6'd1, 6'd63};
                                line_buffer_next[load_row - 6'd1][6'd63] = sram_q[prev_addr[2:0]];
                            end else begin
                                // Store to current row at previous column
                                prev_addr = {load_row, load_col - 6'd1};
                                line_buffer_next[load_row][load_col - 6'd1] = sram_q[prev_addr[2:0]];
                            end
                        end

                        // Advance to next pixel position
                        if (load_col == 6'd63) begin
                            // End of current row
                            if (load_row == 6'd1) begin
                                // Completed loading first 2 rows, transition to overlap phase
                                conv_phase_next = 2'd1;
                                load_col_next = 6'd0;
                                load_row_next = 6'd2;
                                out_row_next = 6'd0;
                                out_col_next = 6'd0;
                                // Preload first 3x3 window for output position (0,0)
                                load_3x3_window(7'sd0, 7'sd0, 7'sd1, S_value);
                            end else begin
                                // Move to next row
                              conv_phase_next = 2'd0;
                              load_col_next = 6'd0;
                              load_row_next = load_row + 6'd1;
                            end
                        end else begin
                            // Move to next column
                            load_col_next = load_col + 6'd1;
                        end
                    end

                    // ===================================================================
                    // PHASE 1: OVERLAP - Load rows 2-63 while computing convolution
                    // ===================================================================
                    2'd1: begin
                        if (load_row <= 6'd63) begin
                            // Issue SRAM read for next pixel
                            pixel_addr = {load_row, load_col};
                            sram_cen = 8'hFF;
                            sram_cen[pixel_addr[2:0]] = 1'b0;  // Enable selected SRAM
                            sram_wen = 1'b1;
                            sram_addr[pixel_addr[2:0]] = pixel_addr[11:3];  // Address within selected SRAM

                            // Store data from PREVIOUS cycle into circular buffer
                            if (load_col > 6'd0 || load_row >= 6'd2) begin
                                if (load_col == 6'd0) begin
                                    // Store last column of previous row
                                    prev_addr = {load_row - 6'd1, 6'd63};
                                    line_buffer_next[(load_row - 6'd1) % 4][6'd63] = sram_q[prev_addr[2:0]];
                                end else begin
                                    // Store current position
                                    prev_addr = {load_row, load_col - 6'd1};
                                    line_buffer_next[load_row % 4][load_col - 6'd1] = sram_q[prev_addr[2:0]];
                                end
                            end

                            // Advance to next position and output convolution result
                            if (load_col == 6'd63) begin
                                // End of current row
                                load_col_next = 6'd0;
                                out_col_next = 6'd0;

                                if (load_row == 6'd63) begin
                                    // Finished loading all 64 rows, transition to finish phase
                                    conv_phase_next = 2'd2;
                                    store_last_elem_next = 1'b1;
                                    state_next = COMPUTE;
                                    out_row_next = out_row + 6'd1;
                                    // Preload 3x3 window for next row
                                    load_3x3_window($signed({1'b0, out_row_next}), 
                                                          $signed({1'b0, out_col_next}), 7'sd1, S_value);
                                    // Output current convolution result
                                    set_output_channel(out_col % 4, conv_result, {out_row, out_col},
                                                       out_data1_reg, out_data2_reg, out_data3_reg, out_data4_reg,
                                                       out_addr1_reg, out_addr2_reg, out_addr3_reg, out_addr4_reg,
                                                       out_data1_reg_next, out_data2_reg_next, out_data3_reg_next, out_data4_reg_next,
                                                       out_addr1_reg_next, out_addr2_reg_next, out_addr3_reg_next, out_addr4_reg_next,
                                                       out_valid1_reg_next, out_valid2_reg_next, out_valid3_reg_next, out_valid4_reg_next);
                                end else begin
                                    // Move to next row
                                    load_row_next = load_row + 6'd1;
                                    out_row_next = out_row + 6'd1;
                                    // Preload 3x3 window for next row
                                    load_3x3_window($signed({1'b0, out_row_next}), 
                                                          $signed({1'b0, out_col_next}), 7'sd1, S_value);
                                    // Output current convolution result
                                    set_output_channel(out_col % 4, conv_result, {out_row, out_col},
                                                       out_data1_reg, out_data2_reg, out_data3_reg, out_data4_reg,
                                                       out_addr1_reg, out_addr2_reg, out_addr3_reg, out_addr4_reg,
                                                       out_data1_reg_next, out_data2_reg_next, out_data3_reg_next, out_data4_reg_next,
                                                       out_addr1_reg_next, out_addr2_reg_next, out_addr3_reg_next, out_addr4_reg_next,
                                                       out_valid1_reg_next, out_valid2_reg_next, out_valid3_reg_next, out_valid4_reg_next);
                                end
                            end else begin
                                // Move to next column
                                load_col_next = load_col + 6'd1;
                                out_col_next = out_col + 6'd1;
                                // Preload 3x3 window for next column
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd1, S_value);
                                // Output current convolution result
                                set_output_channel(out_col % 4, conv_result, {out_row, out_col},
                                                   out_data1_reg, out_data2_reg, out_data3_reg, out_data4_reg,
                                                   out_addr1_reg, out_addr2_reg, out_addr3_reg, out_addr4_reg,
                                                   out_data1_reg_next, out_data2_reg_next, out_data3_reg_next, out_data4_reg_next,
                                                   out_addr1_reg_next, out_addr2_reg_next, out_addr3_reg_next, out_addr4_reg_next,
                                                   out_valid1_reg_next, out_valid2_reg_next, out_valid3_reg_next, out_valid4_reg_next);
                            end
                        end
                    end

                    // ===================================================================
                    // PHASE 2: FINISH - Complete computation for final rows (62-63)
                    // ===================================================================
                    2'd2: begin
                        // Handle last element storage (only once in first cycle of phase 2)
                        if (store_last_elem) begin
                            // Store the final SRAM value that just arrived
                            // Row 63, Col 63 maps to line_buffer[3][63] in circular buffer
                            last_addr = {6'd63, 6'd63};  // Address of last pixel
                            line_buffer_next[3][63] = sram_q[last_addr[2:0]];
                            store_last_elem_next = 1'b0;
                        end

                        if (out_row <= 6'd63) begin
                            // Continue outputting convolution results
                            if (out_col == 6'd63) begin
                                // End of current output row
                                out_col_next = 6'd0;
                                out_row_next = out_row + 6'd1;
                                // Preload 3x3 window for next row
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd1, S_value);
                                // Output current convolution result
                                set_output_channel(out_col % 4, conv_result, {out_row, out_col},
                                                   out_data1_reg, out_data2_reg, out_data3_reg, out_data4_reg,
                                                   out_addr1_reg, out_addr2_reg, out_addr3_reg, out_addr4_reg,
                                                   out_data1_reg_next, out_data2_reg_next, out_data3_reg_next, out_data4_reg_next,
                                                   out_addr1_reg_next, out_addr2_reg_next, out_addr3_reg_next, out_addr4_reg_next,
                                                   out_valid1_reg_next, out_valid2_reg_next, out_valid3_reg_next, out_valid4_reg_next);

                                // Check if all outputs are complete
                                if (out_row == 6'd63) begin
                                    state_next = OUTPUT;
                                end else begin
                                    state_next = COMPUTE;
                                end
                            end else begin
                                // Move to next output column
                                out_col_next = out_col + 6'd1;
                                // Preload 3x3 window for next column
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd1, S_value);
                                // Output current convolution result
                                set_output_channel(out_col % 4, conv_result, {out_row, out_col},
                                                   out_data1_reg, out_data2_reg, out_data3_reg, out_data4_reg,
                                                   out_addr1_reg, out_addr2_reg, out_addr3_reg, out_addr4_reg,
                                                   out_data1_reg_next, out_data2_reg_next, out_data3_reg_next, out_data4_reg_next,
                                                   out_addr1_reg_next, out_addr2_reg_next, out_addr3_reg_next, out_addr4_reg_next,
                                                   out_valid1_reg_next, out_valid2_reg_next, out_valid3_reg_next, out_valid4_reg_next);
                            end
                        end else begin
                            // All convolution outputs complete
                            state_next = OUTPUT;
                        end
                    end

                    // ===================================================================
                    // DEFAULT: Should not reach here
                    // ===================================================================
                    default: begin
                    state_next = OUTPUT;
                end
                endcase
              end else if (S_value == 8'd2) begin
                case (conv_phase)
                    // ===================================================================
                    // PHASE 0: BOOTSTRAP - Load rows 0 and 1 without computation
                    // For stride=2, load 4 consecutive pixels per cycle (col, col+1, col+2, col+3)
                    // ===================================================================
                    2'd0: begin
                        // Issue 4 SRAM read requests for 4 consecutive pixels (load 4 pixels per cycle)
                        // Pixels at col, col+1, col+2, col+3 (they are in different SRAMs)
                        pixel_addr = {load_row, load_col};
                        sram_cen = 8'hFF;
                        sram_wen = 1'b1;
                        
                        // Enable 4 consecutive SRAMs and set their addresses
                        sram_cen[pixel_addr[2:0]] = 1'b0;
                        sram_addr[pixel_addr[2:0]] = pixel_addr[11:3];
                        
                        sram_cen[(pixel_addr[2:0] + 3'd1) % 8] = 1'b0;
                        sram_addr[(pixel_addr[2:0] + 3'd1) % 8] = (pixel_addr + 12'd1) >> 3;
                        
                        sram_cen[(pixel_addr[2:0] + 3'd2) % 8] = 1'b0;
                        sram_addr[(pixel_addr[2:0] + 3'd2) % 8] = (pixel_addr + 12'd2) >> 3;
                        
                        sram_cen[(pixel_addr[2:0] + 3'd3) % 8] = 1'b0;
                        sram_addr[(pixel_addr[2:0] + 3'd3) % 8] = (pixel_addr + 12'd3) >> 3;

                        // Store data from PREVIOUS cycle (SRAM has 1-cycle read latency)
                        // Store 4 pixels at positions col-4, col-3, col-2, col-1
                        if (load_col >= 6'd4 || load_row > 6'd0) begin
                            if (load_col < 6'd4) begin
                                // Storing pixels that wrap from previous row (end of previous row)
                                // When load_col=0, store pixels 60, 61, 62, 63 of previous row
                                prev_addr = {load_row - 6'd1, 6'd60};
                                line_buffer_next[load_row - 6'd1][6'd60] = sram_q[prev_addr[2:0]];
                                
                                prev_addr = {load_row - 6'd1, 6'd61};
                                line_buffer_next[load_row - 6'd1][6'd61] = sram_q[prev_addr[2:0]];
                                
                                prev_addr = {load_row - 6'd1, 6'd62};
                                line_buffer_next[load_row - 6'd1][6'd62] = sram_q[prev_addr[2:0]];
                                
                                prev_addr = {load_row - 6'd1, 6'd63};
                                line_buffer_next[load_row - 6'd1][6'd63] = sram_q[prev_addr[2:0]];
                            end else begin
                                // Normal case: store 4 pixels to current row at col-4, col-3, col-2, col-1
                                prev_addr = {load_row, load_col - 6'd4};
                                line_buffer_next[load_row][load_col - 6'd4] = sram_q[prev_addr[2:0]];
                                
                                prev_addr = {load_row, load_col - 6'd3};
                                line_buffer_next[load_row][load_col - 6'd3] = sram_q[prev_addr[2:0]];
                                
                                prev_addr = {load_row, load_col - 6'd2};
                                line_buffer_next[load_row][load_col - 6'd2] = sram_q[prev_addr[2:0]];
                                
                                prev_addr = {load_row, load_col - 6'd1};
                                line_buffer_next[load_row][load_col - 6'd1] = sram_q[prev_addr[2:0]];
                            end
                        end

                        // Advance to next pixel position (increment by 4)
                        if (load_col >= 6'd60) begin
                            // End of current row (or close to it)
                            if (load_row == 6'd1) begin
                                // Completed loading first 2 rows, transition to overlap phase
                                conv_phase_next = 2'd1;
                                load_col_next = 6'd0;
                                load_row_next = 6'd2;
                                out_row_next = 6'd0;
                                out_col_next = 6'd0;
                                // Preload first 3x3 window for output position (0,0)
                                load_3x3_window(7'sd0, 7'sd0, 7'sd1, S_value);
                            end else begin
                                // Move to next row
                              conv_phase_next = 2'd0;
                              load_col_next = 6'd0;
                              load_row_next = load_row + 6'd1;
                            end
                        end else begin
                            // Move to next 4 columns
                            load_col_next = load_col + 6'd4;
                        end
                    end

                    // ===================================================================
                    // PHASE 1: OVERLAP - Load rows 2-63 while computing convolution
                    // ===================================================================
                    2'd1: begin
                        if (load_row <= 6'd63) begin
                            // Issue SRAM read for next 4 pixels
                            pixel_addr = {load_row, load_col};
                            sram_cen = 8'hFF;
                            sram_wen = 1'b1;
                            
                            // Enable 4 consecutive SRAMs and set their addresses
                            sram_cen[pixel_addr[2:0]] = 1'b0;
                            sram_addr[pixel_addr[2:0]] = pixel_addr[11:3];
                            
                            sram_cen[(pixel_addr[2:0] + 3'd1) % 8] = 1'b0;
                            sram_addr[(pixel_addr[2:0] + 3'd1) % 8] = (pixel_addr + 12'd1) >> 3;
                            
                            sram_cen[(pixel_addr[2:0] + 3'd2) % 8] = 1'b0;
                            sram_addr[(pixel_addr[2:0] + 3'd2) % 8] = (pixel_addr + 12'd2) >> 3;
                            
                            sram_cen[(pixel_addr[2:0] + 3'd3) % 8] = 1'b0;
                            sram_addr[(pixel_addr[2:0] + 3'd3) % 8] = (pixel_addr + 12'd3) >> 3;

                            // Store data from PREVIOUS cycle into circular buffer (4 pixels)
                            // For stride=2, use 6-line circular buffer
                            if (load_col >= 6'd4 || load_row >= 6'd2) begin
                                if (load_col < 6'd4) begin
                                    // Storing pixels that wrap from previous row (end of previous row)
                                    // When load_col=0, store pixels 60, 61, 62, 63 of previous row
                                    prev_addr = {load_row - 6'd1, 6'd60};
                                    line_buffer_next[(load_row - 6'd1) % 6][6'd60] = sram_q[prev_addr[2:0]];
                                    
                                    prev_addr = {load_row - 6'd1, 6'd61};
                                    line_buffer_next[(load_row - 6'd1) % 6][6'd61] = sram_q[prev_addr[2:0]];
                                    
                                    prev_addr = {load_row - 6'd1, 6'd62};
                                    line_buffer_next[(load_row - 6'd1) % 6][6'd62] = sram_q[prev_addr[2:0]];
                                    
                                    prev_addr = {load_row - 6'd1, 6'd63};
                                    line_buffer_next[(load_row - 6'd1) % 6][6'd63] = sram_q[prev_addr[2:0]];
                                end else begin
                                    // Normal case: store 4 pixels to current row
                                    prev_addr = {load_row, load_col - 6'd4};
                                    line_buffer_next[load_row % 6][load_col - 6'd4] = sram_q[prev_addr[2:0]];
                                    
                                    prev_addr = {load_row, load_col - 6'd3};
                                    line_buffer_next[load_row % 6][load_col - 6'd3] = sram_q[prev_addr[2:0]];
                                    
                                    prev_addr = {load_row, load_col - 6'd2};
                                    line_buffer_next[load_row % 6][load_col - 6'd2] = sram_q[prev_addr[2:0]];
                                    
                                    prev_addr = {load_row, load_col - 6'd1};
                                    line_buffer_next[load_row % 6][load_col - 6'd1] = sram_q[prev_addr[2:0]];
                                end
                            end

                            // Advance load_col/load_row (loading logic - increment by 4 per cycle)
                            if (load_col >= 6'd60) begin
                                // End of current row loading
                                load_col_next = 6'd0;
                                if (load_row == 6'd63) begin
                                    // Finished loading all 64 rows, transition to finish phase
                                    conv_phase_next = 2'd2;
                                    store_last_elem_next = 1'b1;
                                    state_next = COMPUTE;
                                end else begin
                                    // Move to next row
                                    load_row_next = load_row + 6'd1;
                                end
                            end else begin
                                // Move to next 4 columns
                                load_col_next = load_col + 6'd4;
                            end
                            
                            // Advance out_col/out_row (output logic - stride=2, increment by 2)
                            if (out_col == 6'd62) begin
                                // End of current output row
                                out_col_next = 6'd0;
                                out_row_next = out_row + 6'd2;
                                // Preload 3x3 window for next row
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd1, S_value);
                                // Output current convolution result
                                output_channel = (out_col>>1)%4;
                                case( output_channel )
                                  2'd0: begin
                                    out_data1_reg_next = conv_result;
                                    out_addr1_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid1_reg_next = 1'b1;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd1: begin
                                    out_data2_reg_next = conv_result;
                                    out_addr2_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid2_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd2: begin
                                    out_data3_reg_next = conv_result;
                                    out_addr3_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid3_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd3: begin
                                    out_data4_reg_next = conv_result;
                                    out_addr4_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid4_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                  end
                                endcase
                            end else begin
                                // Move to next output column (stride=2)
                                out_col_next = out_col + 6'd2;
                                // Preload 3x3 window for next column
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd1, S_value);
                                // Output current convolution result
                                output_channel = (out_col>>1)%4;
                                case( output_channel )
                                  2'd0: begin
                                    out_data1_reg_next = conv_result;
                                    out_addr1_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid1_reg_next = 1'b1;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd1: begin
                                    out_data2_reg_next = conv_result;
                                    out_addr2_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid2_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd2: begin
                                    out_data3_reg_next = conv_result;
                                    out_addr3_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid3_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd3: begin
                                    out_data4_reg_next = conv_result;
                                    out_addr4_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid4_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                  end
                                endcase
                            end
                        end
                    end

                    // ===================================================================
                    // PHASE 2: FINISH - Complete computation for final rows (stride=2)
                    // ===================================================================
                    2'd2: begin
                        // Handle last 4 elements storage (only once in first cycle of phase 2)
                        // When we finished loading at load_col=60, we read pixels 60,61,62,63
                        // Due to 1-cycle SRAM latency, they arrive now
                        if (store_last_elem) begin
                            // Store the final 4 pixels of row 63 (60, 61, 62, 63)
                            // Row 63 maps to buffer[63 % 6] = buffer[3]
                            last_addr = {6'd63, 6'd60};
                            line_buffer_next[63 % 6][6'd60] = sram_q[last_addr[2:0]];
                            
                            last_addr = {6'd63, 6'd61};
                            line_buffer_next[63 % 6][6'd61] = sram_q[last_addr[2:0]];
                            
                            last_addr = {6'd63, 6'd62};
                            line_buffer_next[63 % 6][6'd62] = sram_q[last_addr[2:0]];
                            
                            last_addr = {6'd63, 6'd63};
                            line_buffer_next[63 % 6][6'd63] = sram_q[last_addr[2:0]];
                            
                            store_last_elem_next = 1'b0;
                        end

                        if (out_row <= 6'd62) begin
                            // Continue outputting convolution results (stride=2: up to row 62, col 62)
                            if (out_col == 6'd62) begin
                                // End of current output row
                                out_col_next = 6'd0;
                                out_row_next = out_row + 6'd2;
                                // Preload 3x3 window for next row
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd1, S_value);
                                // Output current convolution result
                                output_channel = (out_col>>1)%4;
                                case( output_channel )
                                  2'd0: begin
                                    out_data1_reg_next = conv_result;
                                    out_addr1_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid1_reg_next = 1'b1;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd1: begin
                                    out_data2_reg_next = conv_result;
                                    out_addr2_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid2_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd2: begin
                                    out_data3_reg_next = conv_result;
                                    out_addr3_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid3_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd3: begin
                                    out_data4_reg_next = conv_result;
                                    out_addr4_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid4_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                  end
                                endcase

                                // Check if all outputs are complete (stride=2: last output is at 62,62)
                                if (out_row == 6'd62) begin
                                    state_next = OUTPUT;
                                end else begin
                                    state_next = COMPUTE;
                                end
                            end else begin
                                // Move to next output column (stride=2)
                                out_col_next = out_col + 6'd2;
                                // Preload 3x3 window for next column
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd1, S_value);
                                // Output current convolution result
                                output_channel = (out_col>>1)%4;
                                case( output_channel )
                                  2'd0: begin
                                    out_data1_reg_next = conv_result;
                                    out_addr1_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid1_reg_next = 1'b1;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd1: begin
                                    out_data2_reg_next = conv_result;
                                    out_addr2_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid2_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd2: begin
                                    out_data3_reg_next = conv_result;
                                    out_addr3_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid3_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd3: begin
                                    out_data4_reg_next = conv_result;
                                    out_addr4_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid4_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                  end
                                endcase
                            end
                        end else begin
                            // All convolution outputs complete
                            state_next = OUTPUT;
                        end
                    end

                    // ===================================================================
                    // DEFAULT: Should not reach here
                    // ===================================================================
                    default: begin
                    state_next = OUTPUT;
                end
                endcase
              end
            end else if(D_value == 8'd2) begin
              if(S_value == 8'd1) begin
                case (conv_phase)
                    // ===================================================================
                    // PHASE 0: BOOTSTRAP - Load rows 0 and 1 without computation
                    // ===================================================================
                    2'd0: begin
                        // Issue SRAM read request
                        // Calculate which SRAM and address within SRAM
                        pixel_addr = {load_row, load_col};
                        sram_cen = 8'hFF;
                        sram_cen[pixel_addr[2:0]] = 1'b0;  // Enable selected SRAM
                        sram_wen = 1'b1;
                        sram_addr[pixel_addr[2:0]] = pixel_addr[11:3];  // Address within selected SRAM

                        // Store data from PREVIOUS cycle (SRAM has 1-cycle read latency)
                        if (load_col > 6'd0 || load_row > 6'd0) begin
                            if (load_col == 6'd0) begin
                                // Just started new row, store last column of previous row
                                prev_addr = {load_row - 6'd1, 6'd63};
                                line_buffer_next[load_row - 6'd1][6'd63] = sram_q[prev_addr[2:0]];
                            end else begin
                                // Store to current row at previous column
                                prev_addr = {load_row, load_col - 6'd1};
                                line_buffer_next[load_row][load_col - 6'd1] = sram_q[prev_addr[2:0]];
                            end
                        end

                        // Advance to next pixel position
                        if (load_col == 6'd63) begin
                            // End of current row
                            if (load_row == 6'd2) begin
                                // Completed loading first 2 rows, transition to overlap phase
                                conv_phase_next = 2'd1;
                                load_col_next = 6'd0;
                                load_row_next = 6'd3;
                                out_row_next = 6'd0;
                                out_col_next = 6'd0;
                                // Preload first 3x3 window for output position (0,0)
                                load_3x3_window(7'sd0, 7'sd0, 7'sd2, S_value);
                            end else begin
                                // Move to next row
                              conv_phase_next = 2'd0;
                              load_col_next = 6'd0;
                              load_row_next = load_row + 6'd1;
                            end
                        end else begin
                            // Move to next column
                            load_col_next = load_col + 6'd1;
                        end
                    end

                    // ===================================================================
                    // PHASE 1: OVERLAP - Load rows 2-63 while computing convolution
                    // ===================================================================
                    2'd1: begin
                        if (load_row <= 6'd63) begin
                            // Issue SRAM read for next pixel
                            pixel_addr = {load_row, load_col};
                            sram_cen = 8'hFF;
                            sram_cen[pixel_addr[2:0]] = 1'b0;  // Enable selected SRAM
                            sram_wen = 1'b1;
                            sram_addr[pixel_addr[2:0]] = pixel_addr[11:3];  // Address within selected SRAM

                            // Store data from PREVIOUS cycle into circular buffer
                            if (load_col > 6'd0 || load_row >= 6'd2) begin
                                if (load_col == 6'd0) begin
                                    // Store last column of previous row
                                    prev_addr = {load_row - 6'd1, 6'd63};
                                    line_buffer_next[(load_row - 6'd1) % 6][6'd63] = sram_q[prev_addr[2:0]];
                                end else begin
                                    // Store current position
                                    prev_addr = {load_row, load_col - 6'd1};
                                    line_buffer_next[load_row % 6][load_col - 6'd1] = sram_q[prev_addr[2:0]];
                                end
                            end

                            // Advance to next position and output convolution result
                            if (load_col == 6'd63) begin
                                // End of current row
                                load_col_next = 6'd0;
                                out_col_next = 6'd0;

                                if (load_row == 6'd63) begin
                                    // Finished loading all 64 rows, transition to finish phase
                                    conv_phase_next = 2'd2;
                                    store_last_elem_next = 1'b1;
                                    state_next = COMPUTE;
                                    out_row_next = out_row + 6'd1;
                                    // Preload 3x3 window for next row
                                    load_3x3_window($signed({1'b0, out_row_next}), 
                                                          $signed({1'b0, out_col_next}), 7'sd2, S_value);
                                    // Output current convolution result
                                    set_output_channel(out_col % 4, conv_result, {out_row, out_col},
                                                       out_data1_reg, out_data2_reg, out_data3_reg, out_data4_reg,
                                                       out_addr1_reg, out_addr2_reg, out_addr3_reg, out_addr4_reg,
                                                       out_data1_reg_next, out_data2_reg_next, out_data3_reg_next, out_data4_reg_next,
                                                       out_addr1_reg_next, out_addr2_reg_next, out_addr3_reg_next, out_addr4_reg_next,
                                                       out_valid1_reg_next, out_valid2_reg_next, out_valid3_reg_next, out_valid4_reg_next);
                                end else begin
                                    // Move to next row
                                    load_row_next = load_row + 6'd1;
                                    out_row_next = out_row + 6'd1;
                                    // Preload 3x3 window for next row
                                    load_3x3_window($signed({1'b0, out_row_next}), 
                                                          $signed({1'b0, out_col_next}), 7'sd2, S_value);
                                    // Output current convolution result
                                    set_output_channel(out_col % 4, conv_result, {out_row, out_col},
                                                       out_data1_reg, out_data2_reg, out_data3_reg, out_data4_reg,
                                                       out_addr1_reg, out_addr2_reg, out_addr3_reg, out_addr4_reg,
                                                       out_data1_reg_next, out_data2_reg_next, out_data3_reg_next, out_data4_reg_next,
                                                       out_addr1_reg_next, out_addr2_reg_next, out_addr3_reg_next, out_addr4_reg_next,
                                                       out_valid1_reg_next, out_valid2_reg_next, out_valid3_reg_next, out_valid4_reg_next);
                                end
                            end else begin
                                // Move to next column
                                load_col_next = load_col + 6'd1;
                                out_col_next = out_col + 6'd1;
                                // Preload 3x3 window for next column
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd2, S_value);
                                // Output current convolution result
                                set_output_channel(out_col % 4, conv_result, {out_row, out_col},
                                                   out_data1_reg, out_data2_reg, out_data3_reg, out_data4_reg,
                                                   out_addr1_reg, out_addr2_reg, out_addr3_reg, out_addr4_reg,
                                                   out_data1_reg_next, out_data2_reg_next, out_data3_reg_next, out_data4_reg_next,
                                                   out_addr1_reg_next, out_addr2_reg_next, out_addr3_reg_next, out_addr4_reg_next,
                                                   out_valid1_reg_next, out_valid2_reg_next, out_valid3_reg_next, out_valid4_reg_next);
                            end
                        end
                    end

                    // ===================================================================
                    // PHASE 2: FINISH - Complete computation for final rows (62-63)
                    // ===================================================================
                    2'd2: begin
                        // Handle last element storage (only once in first cycle of phase 2)
                        if (store_last_elem) begin
                            // Store the final SRAM value that just arrived
                            // Row 63, Col 63 maps to line_buffer[3][63] in circular buffer
                            last_addr = {6'd63, 6'd63};  // Address of last pixel
                            line_buffer_next[3][63] = sram_q[last_addr[2:0]];
                            store_last_elem_next = 1'b0;
                        end

                        if (out_row <= 6'd63) begin
                            // Continue outputting convolution results
                            if (out_col == 6'd63) begin
                                // End of current output row
                                out_col_next = 6'd0;
                                out_row_next = out_row + 6'd1;
                                // Preload 3x3 window for next row
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd2, S_value);
                                // Output current convolution result
                                set_output_channel(out_col % 4, conv_result, {out_row, out_col},
                                                   out_data1_reg, out_data2_reg, out_data3_reg, out_data4_reg,
                                                   out_addr1_reg, out_addr2_reg, out_addr3_reg, out_addr4_reg,
                                                   out_data1_reg_next, out_data2_reg_next, out_data3_reg_next, out_data4_reg_next,
                                                   out_addr1_reg_next, out_addr2_reg_next, out_addr3_reg_next, out_addr4_reg_next,
                                                   out_valid1_reg_next, out_valid2_reg_next, out_valid3_reg_next, out_valid4_reg_next);

                                // Check if all outputs are complete
                                if (out_row == 6'd63) begin
                                    state_next = OUTPUT;
                                end else begin
                                    state_next = COMPUTE;
                                end
                            end else begin
                                // Move to next output column
                                out_col_next = out_col + 6'd1;
                                // Preload 3x3 window for next column
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd2, S_value);
                                // Output current convolution result
                                set_output_channel(out_col % 4, conv_result, {out_row, out_col},
                                                   out_data1_reg, out_data2_reg, out_data3_reg, out_data4_reg,
                                                   out_addr1_reg, out_addr2_reg, out_addr3_reg, out_addr4_reg,
                                                   out_data1_reg_next, out_data2_reg_next, out_data3_reg_next, out_data4_reg_next,
                                                   out_addr1_reg_next, out_addr2_reg_next, out_addr3_reg_next, out_addr4_reg_next,
                                                   out_valid1_reg_next, out_valid2_reg_next, out_valid3_reg_next, out_valid4_reg_next);
                            end
                        end else begin
                            // All convolution outputs complete
                            state_next = OUTPUT;
                        end
                    end

                    // ===================================================================
                    // DEFAULT: Should not reach here
                    // ===================================================================
                    default: begin
                    state_next = OUTPUT;
                end
                endcase
              end else if(S_value == 8'd2) begin
                case (conv_phase)
                    // ===================================================================
                    // PHASE 0: BOOTSTRAP - Load rows 0 and 1 without computation
                    // For stride=2, load 4 consecutive pixels per cycle (col, col+1, col+2, col+3)
                    // ===================================================================
                    2'd0: begin
                        // Issue 4 SRAM read requests for 4 consecutive pixels (load 4 pixels per cycle)
                        // Pixels at col, col+1, col+2, col+3 (they are in different SRAMs)
                        pixel_addr = {load_row, load_col};
                        sram_cen = 8'hFF;
                        sram_wen = 1'b1;
                        
                        // Enable 4 consecutive SRAMs and set their addresses
                        sram_cen[pixel_addr[2:0]] = 1'b0;
                        sram_addr[pixel_addr[2:0]] = pixel_addr[11:3];
                        
                        sram_cen[(pixel_addr[2:0] + 3'd1) % 8] = 1'b0;
                        sram_addr[(pixel_addr[2:0] + 3'd1) % 8] = (pixel_addr + 12'd1) >> 3;
                        
                        sram_cen[(pixel_addr[2:0] + 3'd2) % 8] = 1'b0;
                        sram_addr[(pixel_addr[2:0] + 3'd2) % 8] = (pixel_addr + 12'd2) >> 3;
                        
                        sram_cen[(pixel_addr[2:0] + 3'd3) % 8] = 1'b0;
                        sram_addr[(pixel_addr[2:0] + 3'd3) % 8] = (pixel_addr + 12'd3) >> 3;

                        // Store data from PREVIOUS cycle (SRAM has 1-cycle read latency)
                        // Store 4 pixels at positions col-4, col-3, col-2, col-1
                        if (load_col >= 6'd4 || load_row > 6'd0) begin
                            if (load_col < 6'd4) begin
                                // Storing pixels that wrap from previous row (end of previous row)
                                // When load_col=0, store pixels 60, 61, 62, 63 of previous row
                                prev_addr = {load_row - 6'd1, 6'd60};
                                line_buffer_next[load_row - 6'd1][6'd60] = sram_q[prev_addr[2:0]];
                                
                                prev_addr = {load_row - 6'd1, 6'd61};
                                line_buffer_next[load_row - 6'd1][6'd61] = sram_q[prev_addr[2:0]];
                                
                                prev_addr = {load_row - 6'd1, 6'd62};
                                line_buffer_next[load_row - 6'd1][6'd62] = sram_q[prev_addr[2:0]];
                                
                                prev_addr = {load_row - 6'd1, 6'd63};
                                line_buffer_next[load_row - 6'd1][6'd63] = sram_q[prev_addr[2:0]];
                            end else begin
                                // Normal case: store 4 pixels to current row at col-4, col-3, col-2, col-1
                                prev_addr = {load_row, load_col - 6'd4};
                                line_buffer_next[load_row][load_col - 6'd4] = sram_q[prev_addr[2:0]];
                                
                                prev_addr = {load_row, load_col - 6'd3};
                                line_buffer_next[load_row][load_col - 6'd3] = sram_q[prev_addr[2:0]];
                                
                                prev_addr = {load_row, load_col - 6'd2};
                                line_buffer_next[load_row][load_col - 6'd2] = sram_q[prev_addr[2:0]];
                                
                                prev_addr = {load_row, load_col - 6'd1};
                                line_buffer_next[load_row][load_col - 6'd1] = sram_q[prev_addr[2:0]];
                            end
                        end

                        // Advance to next pixel position (increment by 4)
                        if (load_col >= 6'd60) begin
                            // End of current row (or close to it)
                            if (load_row == 6'd2) begin
                                // Completed loading first 3 rows, transition to overlap phase
                                conv_phase_next = 2'd1;
                                load_col_next = 6'd0;
                                load_row_next = 6'd3;
                                out_row_next = 6'd0;
                                out_col_next = 6'd0;
                                // Preload first 3x3 window for output position (0,0)
                                load_3x3_window(7'sd0, 7'sd0, 7'sd2, S_value);
                            end else begin
                                // Move to next row
                              conv_phase_next = 2'd0;
                              load_col_next = 6'd0;
                              load_row_next = load_row + 6'd1;
                            end
                        end else begin
                            // Move to next 4 columns
                            load_col_next = load_col + 6'd4;
                        end
                    end

                    // ===================================================================
                    // PHASE 1: OVERLAP - Load rows 2-63 while computing convolution
                    // ===================================================================
                    2'd1: begin
                        if (load_row <= 6'd63) begin
                            // Issue SRAM read for next 4 pixels
                            pixel_addr = {load_row, load_col};
                            sram_cen = 8'hFF;
                            sram_wen = 1'b1;
                            
                            // Enable 4 consecutive SRAMs and set their addresses
                            sram_cen[pixel_addr[2:0]] = 1'b0;
                            sram_addr[pixel_addr[2:0]] = pixel_addr[11:3];
                            
                            sram_cen[(pixel_addr[2:0] + 3'd1) % 8] = 1'b0;
                            sram_addr[(pixel_addr[2:0] + 3'd1) % 8] = (pixel_addr + 12'd1) >> 3;
                            
                            sram_cen[(pixel_addr[2:0] + 3'd2) % 8] = 1'b0;
                            sram_addr[(pixel_addr[2:0] + 3'd2) % 8] = (pixel_addr + 12'd2) >> 3;
                            
                            sram_cen[(pixel_addr[2:0] + 3'd3) % 8] = 1'b0;
                            sram_addr[(pixel_addr[2:0] + 3'd3) % 8] = (pixel_addr + 12'd3) >> 3;

                            // Store data from PREVIOUS cycle into circular buffer (4 pixels)
                            // For stride=2, use 6-line circular buffer
                            if (load_col >= 6'd4 || load_row >= 6'd2) begin
                                if (load_col < 6'd4) begin
                                    // Storing pixels that wrap from previous row (end of previous row)
                                    // When load_col=0, store pixels 60, 61, 62, 63 of previous row
                                    prev_addr = {load_row - 6'd1, 6'd60};
                                    line_buffer_next[(load_row - 6'd1) % 8][6'd60] = sram_q[prev_addr[2:0]];
                                    
                                    prev_addr = {load_row - 6'd1, 6'd61};
                                    line_buffer_next[(load_row - 6'd1) % 8][6'd61] = sram_q[prev_addr[2:0]];
                                    
                                    prev_addr = {load_row - 6'd1, 6'd62};
                                    line_buffer_next[(load_row - 6'd1) % 8][6'd62] = sram_q[prev_addr[2:0]];
                                    
                                    prev_addr = {load_row - 6'd1, 6'd63};
                                    line_buffer_next[(load_row - 6'd1) % 8][6'd63] = sram_q[prev_addr[2:0]];
                                end else begin
                                    // Normal case: store 4 pixels to current row
                                    prev_addr = {load_row, load_col - 6'd4};
                                    line_buffer_next[load_row % 8][load_col - 6'd4] = sram_q[prev_addr[2:0]];
                                    
                                    prev_addr = {load_row, load_col - 6'd3};
                                    line_buffer_next[load_row % 8][load_col - 6'd3] = sram_q[prev_addr[2:0]];
                                    
                                    prev_addr = {load_row, load_col - 6'd2};
                                    line_buffer_next[load_row % 8][load_col - 6'd2] = sram_q[prev_addr[2:0]];
                                    
                                    prev_addr = {load_row, load_col - 6'd1};
                                    line_buffer_next[load_row % 8][load_col - 6'd1] = sram_q[prev_addr[2:0]];
                                end
                            end

                            // Advance load_col/load_row (loading logic - increment by 4 per cycle)
                            if (load_col >= 6'd60) begin
                                // End of current row loading
                                load_col_next = 6'd0;
                                if (load_row == 6'd63) begin
                                    // Finished loading all 64 rows, transition to finish phase
                                    conv_phase_next = 2'd2;
                                    store_last_elem_next = 1'b1;
                                    state_next = COMPUTE;
                                end else begin
                                    // Move to next row
                                    load_row_next = load_row + 6'd1;
                                end
                            end else begin
                                // Move to next 4 columns
                                load_col_next = load_col + 6'd4;
                            end
                            
                            // Advance out_col/out_row (output logic - stride=2, increment by 2)
                            if (out_col == 6'd62) begin
                                // End of current output row
                                out_col_next = 6'd0;
                                out_row_next = out_row + 6'd2;
                                // Preload 3x3 window for next row
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd2, S_value);
                                // Output current convolution result
                                output_channel = (out_col>>1)%4;
                                case( output_channel )
                                  2'd0: begin
                                    out_data1_reg_next = conv_result;
                                    out_addr1_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid1_reg_next = 1'b1;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd1: begin
                                    out_data2_reg_next = conv_result;
                                    out_addr2_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid2_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd2: begin
                                    out_data3_reg_next = conv_result;
                                    out_addr3_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid3_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd3: begin
                                    out_data4_reg_next = conv_result;
                                    out_addr4_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid4_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                  end
                                endcase
                            end else begin
                                // Move to next output column (stride=2)
                                out_col_next = out_col + 6'd2;
                                // Preload 3x3 window for next column
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd2, S_value);
                                // Output current convolution result
                                output_channel = (out_col>>1)%4;
                                case( output_channel )
                                  2'd0: begin
                                    out_data1_reg_next = conv_result;
                                    out_addr1_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid1_reg_next = 1'b1;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd1: begin
                                    out_data2_reg_next = conv_result;
                                    out_addr2_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid2_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd2: begin
                                    out_data3_reg_next = conv_result;
                                    out_addr3_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid3_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd3: begin
                                    out_data4_reg_next = conv_result;
                                    out_addr4_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid4_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                  end
                                endcase
                            end
                        end
                    end

                    // ===================================================================
                    // PHASE 2: FINISH - Complete computation for final rows (stride=2)
                    // ===================================================================
                    2'd2: begin
                        // Handle last 4 elements storage (only once in first cycle of phase 2)
                        // When we finished loading at load_col=60, we read pixels 60,61,62,63
                        // Due to 1-cycle SRAM latency, they arrive now
                        if (store_last_elem) begin
                            // Store the final 4 pixels of row 63 (60, 61, 62, 63)
                            // Row 63 maps to buffer[63 % 6] = buffer[3]
                            last_addr = {6'd63, 6'd60};
                            line_buffer_next[63 % 8][6'd60] = sram_q[last_addr[2:0]];
                            
                            last_addr = {6'd63, 6'd61};
                            line_buffer_next[63 % 8][6'd61] = sram_q[last_addr[2:0]];
                            
                            last_addr = {6'd63, 6'd62};
                            line_buffer_next[63 % 8][6'd62] = sram_q[last_addr[2:0]];
                            
                            last_addr = {6'd63, 6'd63};
                            line_buffer_next[63 % 8][6'd63] = sram_q[last_addr[2:0]];
                            
                            store_last_elem_next = 1'b0;
                        end

                        if (out_row <= 6'd62) begin
                            // Continue outputting convolution results (stride=2: up to row 62, col 62)
                            if (out_col == 6'd62) begin
                                // End of current output row
                                out_col_next = 6'd0;
                                out_row_next = out_row + 6'd2;
                                // Preload 3x3 window for next row
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd2, S_value);
                                // Output current convolution result
                                output_channel = (out_col>>1)%4;
                                case( output_channel )
                                  2'd0: begin
                                    out_data1_reg_next = conv_result;
                                    out_addr1_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid1_reg_next = 1'b1;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd1: begin
                                    out_data2_reg_next = conv_result;
                                    out_addr2_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid2_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd2: begin
                                    out_data3_reg_next = conv_result;
                                    out_addr3_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid3_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd3: begin
                                    out_data4_reg_next = conv_result;
                                    out_addr4_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid4_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                  end
                                endcase

                                // Check if all outputs are complete (stride=2: last output is at 62,62)
                                if (out_row == 6'd62) begin
                                    state_next = OUTPUT;
                                end else begin
                                    state_next = COMPUTE;
                                end
                            end else begin
                                // Move to next output column (stride=2)
                                out_col_next = out_col + 6'd2;
                                // Preload 3x3 window for next column
                                load_3x3_window($signed({1'b0, out_row_next}), 
                                                      $signed({1'b0, out_col_next}), 7'sd2, S_value);
                                // Output current convolution result
                                output_channel = (out_col>>1)%4;
                                case( output_channel )
                                  2'd0: begin
                                    out_data1_reg_next = conv_result;
                                    out_addr1_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid1_reg_next = 1'b1;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd1: begin
                                    out_data2_reg_next = conv_result;
                                    out_addr2_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid2_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd2: begin
                                    out_data3_reg_next = conv_result;
                                    out_addr3_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid3_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid4_reg_next = 1'b0;
                                  end
                                  2'd3: begin
                                    out_data4_reg_next = conv_result;
                                    out_addr4_reg_next = {out_row[5:1], out_col[5:1]};
                                    out_valid4_reg_next = 1'b1;
                                    out_valid1_reg_next = 1'b0;
                                    out_valid2_reg_next = 1'b0;
                                    out_valid3_reg_next = 1'b0;
                                  end
                                endcase
                            end
                        end else begin
                            // All convolution outputs complete
                            state_next = OUTPUT;
                        end
                    end

                    // ===================================================================
                    // DEFAULT: Should not reach here
                    // ===================================================================
                    default: begin
                    state_next = OUTPUT;
                end
                endcase
              end
            end
        end


        
        OUTPUT: begin
            // All outputs written in COMPUTE state, go directly to FINISH
            state_next = FINISH;
        end
        
        FINISH: begin
            // Final state - clear output valids and set execution finish flag
            out_valid1_reg_next = 1'b0;
            out_valid2_reg_next = 1'b0;
            out_valid3_reg_next = 1'b0;
            out_valid4_reg_next = 1'b0;
            o_exe_finish_reg_next = 1'b1;
        end
        
        default: begin
            state_next = IDLE;
        end
    endcase
end

// ========================================
// Sequential Logic
// ========================================
always @(posedge i_clk or negedge i_rst_n) begin : seq_logic
    if (!i_rst_n) begin
        state <= IDLE;
        load_counter <= 12'd0;
        pixel_idx <= 2'd0;
        input_buffer <= 32'd0;
        barcode_buffer <= 12'd0;
        barcode_bits_count <= 4'd0;
        decode_symbol_idx <= 2'd0;
        K_value <= 8'd0;
        S_value <= 8'd0;
        D_value <= 8'd0;
        barcode_found <= 1'b0;
        in_ready_reg <= 1'b0;
        weight_counter <= 4'd0;
        load_row <= 6'd0;
        load_col <= 6'd0;
        out_row <= 6'd0;
        out_col <= 6'd0;
        kernel_idx <= 4'd0;
        conv_acc <= 20'sd0;
        conv_phase <= 2'd0;
        out_channel <= 2'd0;
        store_last_elem <= 1'b0;
        weight[0] <= 8'd0;
        weight[1] <= 8'd0;
        weight[2] <= 8'd0;
        weight[3] <= 8'd0;
        weight[4] <= 8'd0;
        weight[5] <= 8'd0;
        weight[6] <= 8'd0;
        weight[7] <= 8'd0;
        weight[8] <= 8'd0;
        out_data1_reg <= 8'd0;
        out_data2_reg <= 8'd0;
        out_data3_reg <= 8'd0;
        out_data4_reg <= 8'd0;
        out_addr1_reg <= 12'd0;
        out_addr2_reg <= 12'd0;
        out_addr3_reg <= 12'd0;
        out_addr4_reg <= 12'd0;
        out_valid1_reg <= 1'b0;
        out_valid2_reg <= 1'b0;
        out_valid3_reg <= 1'b0;
        out_valid4_reg <= 1'b0;
        o_exe_finish_reg <= 1'b0;
        p00 <= 8'd0;
        p01 <= 8'd0;
        p02 <= 8'd0;
        p10 <= 8'd0;
        p11 <= 8'd0;
        p12 <= 8'd0;
        p20 <= 8'd0;
        p21 <= 8'd0;
        p22 <= 8'd0;
        for (i = 0; i < LINE_BUFFER_ROWS; i = i + 1) begin
            for (j = 0; j < COLS; j = j + 1) begin
                line_buffer[i][j] <= 8'd0;
            end
        end
    end else begin
        state <= state_next;
        load_counter <= load_counter_next;
        pixel_idx <= pixel_idx_next;
        input_buffer <= input_buffer_next;
        barcode_buffer <= barcode_buffer_next;
        barcode_bits_count <= barcode_bits_count_next;
        decode_symbol_idx <= decode_symbol_idx_next;
        K_value <= K_value_next;
        S_value <= S_value_next;
        D_value <= D_value_next;
        barcode_found <= barcode_found_next;
        in_ready_reg <= in_ready_reg_next;
        weight_counter <= weight_counter_next;
        load_row <= load_row_next;
        load_col <= load_col_next;
        out_row <= out_row_next;
        out_col <= out_col_next;
        kernel_idx <= kernel_idx_next;
        conv_acc <= conv_acc_next;
        conv_phase <= conv_phase_next;
        out_channel <= out_channel_next;
        store_last_elem <= store_last_elem_next;
        weight[0] <= weight_next[0];
        weight[1] <= weight_next[1];
        weight[2] <= weight_next[2];
        weight[3] <= weight_next[3];
        weight[4] <= weight_next[4];
        weight[5] <= weight_next[5];
        weight[6] <= weight_next[6];
        weight[7] <= weight_next[7];
        weight[8] <= weight_next[8];
        out_data1_reg <= out_data1_reg_next;
        out_data2_reg <= out_data2_reg_next;
        out_data3_reg <= out_data3_reg_next;
        out_data4_reg <= out_data4_reg_next;
        out_addr1_reg <= out_addr1_reg_next;
        out_addr2_reg <= out_addr2_reg_next;
        out_addr3_reg <= out_addr3_reg_next;
        out_addr4_reg <= out_addr4_reg_next;
        out_valid1_reg <= out_valid1_reg_next;
        out_valid2_reg <= out_valid2_reg_next;
        out_valid3_reg <= out_valid3_reg_next;
        out_valid4_reg <= out_valid4_reg_next;
        o_exe_finish_reg <= o_exe_finish_reg_next;
        p00 <= p00_next;
        p01 <= p01_next;
        p02 <= p02_next;
        p10 <= p10_next;
        p11 <= p11_next;
        p12 <= p12_next;
        p20 <= p20_next;
        p21 <= p21_next;
        p22 <= p22_next;
        for (i = 0; i < LINE_BUFFER_ROWS; i = i + 1) begin
            for (j = 0; j < COLS; j = j + 1) begin
                line_buffer[i][j] <= line_buffer_next[i][j];
            end
        end
    end
end

endmodule



