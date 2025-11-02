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
// SRAM Signals
// ========================================
wire [7:0] sram_q;
reg [11:0] sram_addr;
reg [7:0] sram_d;
reg sram_cen, sram_wen;

sram_4096x8 u_sram (
    .Q(sram_q),
    .CLK(i_clk),
    .CEN(sram_cen),
    .WEN(sram_wen),
    .A(sram_addr),
    .D(sram_d)
);

// ========================================
// State Machine
// ========================================
localparam IDLE = 4'd0;
localparam LOAD_IMG = 4'd1;
localparam DECODE_BARCODE = 4'd2;
localparam OUTPUT_RESULT = 4'd3;
localparam LOAD_WEIGHT = 4'd4;
localparam COMPUTE = 4'd5;
localparam OUTPUT = 4'd6;
localparam FINISH = 4'd7;

reg [3:0] state, state_next;

// ========================================
// Counters and Control Signals
// ========================================
reg [11:0] load_counter, load_counter_next;
reg [1:0] pixel_idx, pixel_idx_next;
reg [31:0] input_buffer, input_buffer_next;
reg [11:0] decode_addr, decode_addr_next;
reg [11:0] barcode_buffer, barcode_buffer_next;
reg [3:0] barcode_bits_count, barcode_bits_count_next;
reg [1:0] decode_symbol_idx, decode_symbol_idx_next;
reg in_ready_reg, in_ready_reg_next;
reg sram_read_valid, sram_read_valid_next;

// Helper signals for barcode decoding
wire current_lsb;
reg [7:0] decoded_value;
reg symbol_valid;

// Decoded values
reg [7:0] K_value, K_value_next;
reg [7:0] S_value, S_value_next;
reg [7:0] D_value, D_value_next;
reg barcode_found, barcode_found_next;

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
// State Machine Logic
// ========================================
always @(*) begin
    state_next = state;
    load_counter_next = load_counter;
    pixel_idx_next = pixel_idx;
    input_buffer_next = input_buffer;
    decode_addr_next = decode_addr;
    barcode_buffer_next = barcode_buffer;
    barcode_bits_count_next = barcode_bits_count;
    decode_symbol_idx_next = decode_symbol_idx;
    K_value_next = K_value;
    S_value_next = S_value;
    D_value_next = D_value;
    barcode_found_next = barcode_found;
    in_ready_reg_next = in_ready_reg;
    sram_read_valid_next = sram_read_valid;
    
    sram_addr = 12'd0;
    sram_d = 8'd0;
    sram_cen = 1'b1;
    sram_wen = 1'b1;
    
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
                decode_addr_next = 12'd0;
                barcode_buffer_next = 12'd0;
                barcode_bits_count_next = 4'd0;
                decode_symbol_idx_next = 2'd0;
                K_value_next = 8'd0;
                S_value_next = 8'd0;
                D_value_next = 8'd0;
                barcode_found_next = 1'b0;
                sram_read_valid_next = 1'b0;
                out_valid1_reg_next = 1'b0;
                out_valid2_reg_next = 1'b0;
                out_valid3_reg_next = 1'b0;
                out_valid4_reg_next = 1'b0;
                o_exe_finish_reg_next = 1'b0;
            end
        end
        
        LOAD_IMG: begin
            // Write one pixel per cycle from buffer
            sram_cen = 1'b0;
            sram_wen = 1'b0;
            sram_addr = load_counter;
            
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
                        case (decode_symbol_idx)
                            2'd0: K_value_next = decoded_value;
                            2'd1: S_value_next = decoded_value;
                            2'd2: D_value_next = decoded_value;
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
            end
        end
        
        DECODE_BARCODE: begin
            // Read from SRAM to get LSBs for barcode
            sram_cen = 1'b0;
            sram_wen = 1'b1;
            sram_addr = decode_addr;
            
            // Process SRAM data with one cycle latency
            if (sram_read_valid) begin
                barcode_buffer_next = {barcode_buffer[10:0], sram_q[0]};
                barcode_bits_count_next = barcode_bits_count + 1;
                
                // Check when we have exactly 11 bits accumulated
                if (barcode_bits_count == 4'd10) begin
                    // We're shifting in the 11th bit, check the complete 11-bit pattern
                    if (!barcode_found) begin
                        // Check for Start Code C: 11010011100
                        if ({barcode_buffer[9:0], sram_q[0]} == 11'b11010011100) begin
                            barcode_found_next = 1'b1;
                            barcode_buffer_next = 12'd0;
                            barcode_bits_count_next = 4'd0;
                            decode_symbol_idx_next = 2'd0;
                        end
                    end else begin
                        // Decode symbols
                        if ({barcode_buffer[9:0], sram_q[0]} == 11'b11001101100) begin // Value 1
                            if (decode_symbol_idx == 2'd0) K_value_next = 8'd1;
                            else if (decode_symbol_idx == 2'd1) S_value_next = 8'd1;
                            else if (decode_symbol_idx == 2'd2) D_value_next = 8'd1;
                            decode_symbol_idx_next = decode_symbol_idx + 1;
                            barcode_bits_count_next = 4'd0;
                            barcode_buffer_next = 12'd0;
                        end else if ({barcode_buffer[9:0], sram_q[0]} == 11'b11001100110) begin // Value 2
                            if (decode_symbol_idx == 2'd0) K_value_next = 8'd2;
                            else if (decode_symbol_idx == 2'd1) S_value_next = 8'd2;
                            else if (decode_symbol_idx == 2'd2) D_value_next = 8'd2;
                            decode_symbol_idx_next = decode_symbol_idx + 1;
                            barcode_bits_count_next = 4'd0;
                            barcode_buffer_next = 12'd0;
                        end else if ({barcode_buffer[9:0], sram_q[0]} == 11'b10010011000) begin // Value 3
                            if (decode_symbol_idx == 2'd0) K_value_next = 8'd3;
                            else if (decode_symbol_idx == 2'd1) S_value_next = 8'd3;
                            else if (decode_symbol_idx == 2'd2) D_value_next = 8'd3;
                            decode_symbol_idx_next = decode_symbol_idx + 1;
                            barcode_bits_count_next = 4'd0;
                            barcode_buffer_next = 12'd0;
                        end
                        
                        // Check if we've decoded all 3 symbols
                        if (decode_symbol_idx == 2'd2 && 
                            ({barcode_buffer[9:0], sram_q[0]} == 11'b11001101100 ||
                             {barcode_buffer[9:0], sram_q[0]} == 11'b11001100110 ||
                             {barcode_buffer[9:0], sram_q[0]} == 11'b10010011000)) begin
                            state_next = OUTPUT_RESULT;
                        end
                    end
                end
            end
            
            sram_read_valid_next = 1'b1;
            
            // Move to next pixel (scan entire image)
            decode_addr_next = decode_addr + 1;
            
            // If we've scanned all pixels and haven't found complete barcode, output what we have
            if (decode_addr == 12'd4095) begin
                state_next = OUTPUT_RESULT;
            end
        end
        
        OUTPUT_RESULT: begin
            // Validate: K must be 3, S and D must be 1 or 2
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
            state_next = FINISH;
        end
        
        FINISH: begin
            out_valid1_reg_next = 1'b0;
            out_valid2_reg_next = 1'b0;
            out_valid3_reg_next = 1'b0;
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
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        state <= IDLE;
        load_counter <= 12'd0;
        pixel_idx <= 2'd0;
        input_buffer <= 32'd0;
        decode_addr <= 12'd0;
        barcode_buffer <= 12'd0;
        barcode_bits_count <= 4'd0;
        decode_symbol_idx <= 2'd0;
        K_value <= 8'd0;
        S_value <= 8'd0;
        D_value <= 8'd0;
        barcode_found <= 1'b0;
        in_ready_reg <= 1'b0;
        sram_read_valid <= 1'b0;
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
    end else begin
        state <= state_next;
        load_counter <= load_counter_next;
        pixel_idx <= pixel_idx_next;
        input_buffer <= input_buffer_next;
        decode_addr <= decode_addr_next;
        barcode_buffer <= barcode_buffer_next;
        barcode_bits_count <= barcode_bits_count_next;
        decode_symbol_idx <= decode_symbol_idx_next;
        K_value <= K_value_next;
        S_value <= S_value_next;
        D_value <= D_value_next;
        barcode_found <= barcode_found_next;
        in_ready_reg <= in_ready_reg_next;
        sram_read_valid <= sram_read_valid_next;
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
    end
end

endmodule

