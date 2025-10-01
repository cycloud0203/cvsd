module alu #(
    parameter INST_W = 4,
    parameter INT_W  = 6,
    parameter FRAC_W = 10,
    parameter DATA_W = INT_W + FRAC_W
)(
    input                      i_clk,
    input                      i_rst_n,
    input                      i_in_valid,
    output                     o_busy,
    input         [INST_W-1:0] i_inst,
    input  signed [DATA_W-1:0] i_data_a,
    input  signed [DATA_W-1:0] i_data_b,
    output                     o_out_valid,
    output        [DATA_W-1:0] o_data
);

    // State machine states
    localparam IDLE = 2'b00;
    localparam BUSY = 2'b01;
    localparam MATRIX_INPUT = 2'b10;
    localparam MATRIX_OUTPUT = 2'b11;
    
    // Saturation values for 16-bit signed numbers
    localparam signed [DATA_W-1:0] MAX_VALUE = 16'h7FFF; // 0111_1111_1111_1111
    localparam signed [DATA_W-1:0] MIN_VALUE = 16'h8000; // 1000_0000_0000_0000
    
    // 36-bit accumulator parameters (16-bit int + 20-bit fraction)
    localparam ACC_W = 36;
    localparam ACC_INT_W = 16;
    localparam ACC_FRAC_W = 20;
    localparam signed [ACC_W-1:0] ACC_MAX_VALUE = 36'h7_FFFF_FFFF; // 2^35 - 1
    localparam signed [ACC_W-1:0] ACC_MIN_VALUE = 36'h8_0000_0000; // -2^35
    
    // State registers
    reg [1:0] state, next_state;
    reg [DATA_W-1:0] result_reg, next_result_reg;
    reg out_valid_reg, next_out_valid_reg;
    reg signed [ACC_W-1:0] accumulator, next_accumulator;
    
    // Matrix transpose registers
    reg [1:0] matrix_mem [0:63]; // Flattened 8x8 matrix, each element is 2 bits (64 elements total)
    reg [1:0] next_matrix_mem [0:63];
    reg [2:0] input_count, next_input_count;
    reg [2:0] output_count, next_output_count;
    reg [INST_W-1:0] current_inst, next_current_inst;
    
    // Combinational logic variables - declared at module level
    reg signed [DATA_W:0] temp_result;           // 17-bit for overflow detection
    reg signed [31:0] mult_result;               // 32-bit multiplication result
    reg signed [ACC_W-1:0] mult_extended;        // 36-bit sign-extended multiplication result
    reg signed [ACC_W:0] acc_sum;                // 37-bit for accumulator overflow detection
    reg signed [25:0] rounded_result_mac;        // 26-bit for MAC rounding operation
    
    // Sin function variables
    reg signed [31:0] x_squared;      // x^2 in Q12.20
    reg signed [47:0] x_cubed;        // x^3 in Q18.30
    reg signed [79:0] x_fifth;        // x^5 in Q30.50 (80 bits)
    reg signed [63:0] term2_full;     // (1/6)*x^3 in Q24.40
    reg signed [95:0] term3_full;     // (1/120)*x^5 in Q36.60 (96 bits)
    reg signed [31:0] x_extended;     // x in Q12.20 for high precision calc
    reg signed [31:0] term2_q1220;    // (1/6)*x^3 in Q12.20
    reg signed [31:0] term3_q1220;    // (1/120)*x^5 in Q12.20
    reg signed [32:0] sin_high_prec;  // High precision result in Q12.20
    reg signed [25:0] rounded_result_sin; // Rounded result before saturation for sin
    reg signed [16:0] sin_result;     // Final result with overflow detection
    
    // Sin function coefficients
    localparam [15:0] coeff_6 = 16'b0000000010101011;   // 1/6 in Q6.10 = 171/1024 ≈ 0.1670
    localparam [15:0] coeff_120 = 16'b0000000000001001; // 1/120 in Q6.10 = 9/1024 ≈ 0.0088
    
    // LRCW shift variables
    integer cpop;
    reg [DATA_W-1:0] temp_data_lrcw;
    reg temp_bit;
    
    // Count leading zeros variables
    reg [15:0] cnt_clz;
    reg found_one;
    
    // Reverse Match4 variables
    reg [15:0] temp_data_match4;
    
    // Right rotate variables
    reg [2*DATA_W-1:0] temp_data_rotate;
    
    // Matrix indexing variables
    integer row_idx, col_idx, matrix_addr;
    integer i_idx, j_idx; // Loop indices
    
    // Generate block for matrix initialization
    genvar i, j;
    
    //==========================================================================
    // Output Logic (Combinational)
    //==========================================================================
    assign o_busy = (state == BUSY) || (state == MATRIX_OUTPUT);
    assign o_out_valid = out_valid_reg;
    assign o_data = result_reg;
    
    //==========================================================================
    // Next State Logic (Combinational)
    //==========================================================================
    always @(*) begin
        case (state)
            IDLE: begin
                if (i_in_valid) begin
                    if (i_inst == 4'b1001) begin
                        next_state = MATRIX_INPUT;
                    end else begin
                        next_state = BUSY;
                    end
                end else begin
                    next_state = IDLE;
                end
            end
            BUSY: begin
                next_state = IDLE;  // Single cycle operation
            end
            MATRIX_INPUT: begin
                if (i_in_valid && input_count == 3'd6) begin
                    next_state = MATRIX_OUTPUT;
                end else begin
                    next_state = MATRIX_INPUT;
                end
            end
            MATRIX_OUTPUT: begin
                if (output_count == 3'd7) begin
                    next_state = IDLE;
                end else begin
                    next_state = MATRIX_OUTPUT;
                end
            end
            default: next_state = IDLE;
        endcase
    end
    
    //==========================================================================
    // ALU Operation Logic (Combinational)
    //==========================================================================
    always @(*) begin
        // Default assignments
        next_result_reg = result_reg;
        next_out_valid_reg = 1'b0;
        next_accumulator = accumulator;
        next_input_count = input_count;
        next_output_count = output_count;
        next_current_inst = current_inst;
        
        // Copy current matrix state by default
        for (i_idx = 0; i_idx < 64; i_idx = i_idx + 1) begin
            next_matrix_mem[i_idx] = matrix_mem[i_idx];
        end
        
        if (state == IDLE && i_in_valid) begin
            // Perform ALU operation based on instruction
            case (i_inst)
                4'b0000: begin  // Addition for fixed-point numbers with saturation
                    temp_result = i_data_a + i_data_b;
                    if (temp_result > MAX_VALUE) begin
                        next_result_reg = MAX_VALUE;
                    end else if (temp_result < MIN_VALUE) begin
                        next_result_reg = MIN_VALUE;
                    end else begin
                        next_result_reg = temp_result[DATA_W-1:0];
                    end
                end
                4'b0001: begin  // Subtraction for fixed-point numbers with saturation
                    temp_result = i_data_a - i_data_b;
                    if (temp_result > MAX_VALUE) begin
                        next_result_reg = MAX_VALUE;
                    end else if (temp_result < MIN_VALUE) begin
                        next_result_reg = MIN_VALUE;
                    end else begin
                        next_result_reg = temp_result[DATA_W-1:0];
                    end
                end
                4'b0010: begin  // Multiplication and accumulation for fixed-point numbers
                    // Calculate multiplication result from data_a * data_b
                    mult_result = i_data_a * i_data_b;

                    // Extend multiplication result to 36 bits
                    mult_extended = {{4{mult_result[31]}}, mult_result};

                    // Add the accumulator to the mult_result  
                    acc_sum = accumulator + mult_extended;
                    
                    // PATH 1: Saturate and update the 36-bit accumulator
                    if (acc_sum > ACC_MAX_VALUE) begin
                        next_accumulator = ACC_MAX_VALUE;
                    end else if (acc_sum < ACC_MIN_VALUE) begin
                        next_accumulator = ACC_MIN_VALUE;
                    end else begin
                        next_accumulator = acc_sum[ACC_W-1:0];
                    end
                    
                    // PATH 2: Round first, then saturate for 16-bit output
                    // Round to nearest representable number with 10-bit fraction
                    // Tie-breaking: round half toward positive infinity
                    // Check bits [9:0] for rounding decision
                    if (acc_sum[9:0] >= 10'd512) begin
                        // Round up (toward positive infinity for ties)
                        rounded_result_mac = acc_sum[35:10] + 1'b1;
                    end else begin
                        // Round down (truncate)
                        rounded_result_mac = acc_sum[35:10];
                    end

                    // Saturate rounded result to 16-bit output range
                    if (rounded_result_mac > MAX_VALUE) begin
                        next_result_reg = MAX_VALUE;
                    end else if (rounded_result_mac < MIN_VALUE) begin
                        next_result_reg = MIN_VALUE;
                    end else begin
                        next_result_reg = rounded_result_mac[15:0];
                    end
                end
                4'b0011: begin  // Taylor expansion of sin function on fixed-point numbers
                    // calculate the Taylor expansion of sin function on fixed-point numbers
                    // sin(x) = x - 1/6*x^3 + 1/120*x^5 (n = 2)

                    // Extend x to higher precision (Q12.20)
                    x_extended = {{6{i_data_a[15]}}, i_data_a, 10'b0};  // Sign-extend and convert Q6.10 to Q12.20
                    
                    // Calculate x^2 in Q12.20
                    x_squared = i_data_a * i_data_a;  // Q6.10 * Q6.10 = Q12.20

                    // Calculate x^3 in Q18.30
                    x_cubed = i_data_a * x_squared;  // Q6.10 * Q12.20 = Q18.30
                    
                    // Calculate x^5 in Q30.50
                    x_fifth = x_squared * x_cubed;  // Q12.20 * Q18.30 = Q30.50
                    
                    // Calculate (1/6)*x^3 in Q24.40
                    term2_full = coeff_6 * x_cubed;  // Q6.10 * Q18.30 = Q24.40
                    term2_q1220 = term2_full[51:20] ;  // Convert Q24.40 to Q12.20
                    
                    // Calculate (1/120)*x^5 in Q36.60
                    term3_full = coeff_120 * x_fifth;  // Q6.10 * Q30.50 = Q36.60
                    term3_q1220 = term3_full[71:40];  // Convert Q36.60 to Q12.20
                    
                    // High precision calculation in Q12.20
                    // sin(x) = x - (1/6)*x^3 + (1/120)*x^5
                    sin_high_prec = x_extended - term2_q1220 + term3_q1220;
                    
                    // Rounding from Q12.20 to Q6.10
                    // Check bits [9:0] for rounding decision (tie-breaking: round half up)
                    if (sin_high_prec[9:0] >= 10'd512) begin
                        // Round up
                        rounded_result_sin = {{4{sin_high_prec[31]}}, sin_high_prec[31:10]} + 1'b1;
                    end else begin
                        // Round down (truncate)
                        rounded_result_sin = {{4{sin_high_prec[31]}}, sin_high_prec[31:10]};
                    end
                    
                    // Convert to 17-bit for saturation check
                    sin_result = rounded_result_sin[16:0];
                    
                    // Saturation check
                    if (sin_result > MAX_VALUE) begin
                        next_result_reg = MAX_VALUE;
                    end else if (sin_result < MIN_VALUE) begin
                        next_result_reg = MIN_VALUE;
                    end else begin
                        next_result_reg = sin_result[15:0];
                    end
                end
                4'b0100: begin // Binary to gray code 
                    // calculate the gray code of the binary input
                    // gray code = (binary >> 1) ^ binary
                    // data_a is unsigned integer
                    next_result_reg = (i_data_a >> 1) ^ i_data_a;
                end
                4'b0101: begin // LRCW shift
                    // count CPOP of data_a, 0 <= CPOP <= 16
                    cpop = 0;
                    for (i_idx = 0; i_idx < DATA_W; i_idx = i_idx + 1) begin
                        if (i_data_a[i_idx] == 1'b1) begin
                            cpop = cpop + 1;
                        end
                    end

                    // Initialize temp_data with i_data_b
                    temp_data_lrcw = i_data_b;
                    
                    // do LRCW shift on temp_data
                    // Perform cpop times: left shift temp_data_lrcw by 1, and set LSB to inverted original MSB
                    for (i_idx = 0; i_idx < cpop && i_idx < DATA_W; i_idx = i_idx + 1) begin
                        temp_bit = ~temp_data_lrcw[15]; // Invert MSB (bit 15)
                        temp_data_lrcw = {temp_data_lrcw[14:0], temp_bit}; // Shift left and insert new LSB
                    end

                    next_result_reg = temp_data_lrcw;
                end
                4'b0110: begin // right rotate
                    // Concatenate i_data_a with itself, then right shift by i_data_b to perform right rotate
                    // Only one assignment to temp_data_rotate
                    temp_data_rotate = ({i_data_a, i_data_a} >> i_data_b);
                    next_result_reg = temp_data_rotate[DATA_W-1:0];
                end
                4'b0111: begin // Count leading MSB zeros
                    // count leading zeros of data_a from MSB using flag-based approach
                    cnt_clz = 16'd0;
                    found_one = 1'b0;
                    for (i_idx = 15; i_idx >= 0; i_idx = i_idx - 1) begin
                        if (!found_one && i_data_a[i_idx] == 1'b0) begin
                            cnt_clz = cnt_clz + 16'd1;
                        end else if (!found_one && i_data_a[i_idx] == 1'b1) begin
                            found_one = 1'b1;
                        end
                    end
                    next_result_reg = cnt_clz;
                end
                4'b1000: begin // Reverse Match4 (Custom bit level operation)
                    // for bit 13~15: 0
                    temp_data_match4[15:13] = 3'b000;
                    // Explicit comparisons to avoid synthesis issues with variable indices
                    temp_data_match4[0]  = (i_data_a[3:0]   == i_data_b[15:12]);
                    temp_data_match4[1]  = (i_data_a[4:1]   == i_data_b[14:11]);
                    temp_data_match4[2]  = (i_data_a[5:2]   == i_data_b[13:10]);
                    temp_data_match4[3]  = (i_data_a[6:3]   == i_data_b[12:9]);
                    temp_data_match4[4]  = (i_data_a[7:4]   == i_data_b[11:8]);
                    temp_data_match4[5]  = (i_data_a[8:5]   == i_data_b[10:7]);
                    temp_data_match4[6]  = (i_data_a[9:6]   == i_data_b[9:6]);
                    temp_data_match4[7]  = (i_data_a[10:7]  == i_data_b[8:5]);
                    temp_data_match4[8]  = (i_data_a[11:8]  == i_data_b[7:4]);
                    temp_data_match4[9]  = (i_data_a[12:9]  == i_data_b[6:3]);
                    temp_data_match4[10] = (i_data_a[13:10] == i_data_b[5:2]);
                    temp_data_match4[11] = (i_data_a[14:11] == i_data_b[4:1]);
                    temp_data_match4[12] = (i_data_a[15:12] == i_data_b[3:0]);
                    next_result_reg = temp_data_match4;
                end
                4'b1001: begin // Transpose an 8*8 matrix
                    // Initialize matrix transpose operation
                    next_current_inst = i_inst;
                    next_input_count = 3'd0;
                    next_output_count = 3'd0;
                    // Store first column of matrix (row 0-7, column 0)
                    next_matrix_mem[0*8 + 0] = i_data_a[15:14];  // matrix[0][0]
                    next_matrix_mem[1*8 + 0] = i_data_a[13:12];  // matrix[1][0]
                    next_matrix_mem[2*8 + 0] = i_data_a[11:10];  // matrix[2][0]
                    next_matrix_mem[3*8 + 0] = i_data_a[9:8];   // matrix[3][0]
                    next_matrix_mem[4*8 + 0] = i_data_a[7:6];   // matrix[4][0]
                    next_matrix_mem[5*8 + 0] = i_data_a[5:4];   // matrix[5][0]
                    next_matrix_mem[6*8 + 0] = i_data_a[3:2];   // matrix[6][0]
                    next_matrix_mem[7*8 + 0] = i_data_a[1:0];   // matrix[7][0]
                    next_result_reg = {DATA_W{1'b0}};
                end
                default: begin
                    next_result_reg = {DATA_W{1'b0}};  // Default to zero for unsupported instructions
                end
            endcase
            // Only set out_valid for single-cycle instructions, not for matrix transpose
            if (i_inst != 4'b1001) begin
                next_out_valid_reg = 1'b1;
            end else begin
                next_out_valid_reg = 1'b0;
            end
        end else if (state == MATRIX_INPUT && i_in_valid) begin
            // Collect matrix input data (columns 1-7)
            next_input_count = input_count + 1'b1;
            // Store column data based on input_count
            case (input_count)
                3'd0: begin  // Column 1
                    next_matrix_mem[0*8 + 1] = i_data_a[15:14]; // matrix[0][1]
                    next_matrix_mem[1*8 + 1] = i_data_a[13:12]; // matrix[1][1]
                    next_matrix_mem[2*8 + 1] = i_data_a[11:10]; // matrix[2][1]
                    next_matrix_mem[3*8 + 1] = i_data_a[9:8];   // matrix[3][1]
                    next_matrix_mem[4*8 + 1] = i_data_a[7:6];   // matrix[4][1]
                    next_matrix_mem[5*8 + 1] = i_data_a[5:4];   // matrix[5][1]
                    next_matrix_mem[6*8 + 1] = i_data_a[3:2];   // matrix[6][1]
                    next_matrix_mem[7*8 + 1] = i_data_a[1:0];   // matrix[7][1]
                end
                3'd1: begin  // Column 2
                    next_matrix_mem[0*8 + 2] = i_data_a[15:14]; // matrix[0][2]
                    next_matrix_mem[1*8 + 2] = i_data_a[13:12]; // matrix[1][2]
                    next_matrix_mem[2*8 + 2] = i_data_a[11:10]; // matrix[2][2]
                    next_matrix_mem[3*8 + 2] = i_data_a[9:8];   // matrix[3][2]
                    next_matrix_mem[4*8 + 2] = i_data_a[7:6];   // matrix[4][2]
                    next_matrix_mem[5*8 + 2] = i_data_a[5:4];   // matrix[5][2]
                    next_matrix_mem[6*8 + 2] = i_data_a[3:2];   // matrix[6][2]
                    next_matrix_mem[7*8 + 2] = i_data_a[1:0];   // matrix[7][2]
                end
                3'd2: begin  // Column 3
                    next_matrix_mem[0*8 + 3] = i_data_a[15:14]; // matrix[0][3]
                    next_matrix_mem[1*8 + 3] = i_data_a[13:12]; // matrix[1][3]
                    next_matrix_mem[2*8 + 3] = i_data_a[11:10]; // matrix[2][3]
                    next_matrix_mem[3*8 + 3] = i_data_a[9:8];   // matrix[3][3]
                    next_matrix_mem[4*8 + 3] = i_data_a[7:6];   // matrix[4][3]
                    next_matrix_mem[5*8 + 3] = i_data_a[5:4];   // matrix[5][3]
                    next_matrix_mem[6*8 + 3] = i_data_a[3:2];   // matrix[6][3]
                    next_matrix_mem[7*8 + 3] = i_data_a[1:0];   // matrix[7][3]
                end
                3'd3: begin  // Column 4
                    next_matrix_mem[0*8 + 4] = i_data_a[15:14]; // matrix[0][4]
                    next_matrix_mem[1*8 + 4] = i_data_a[13:12]; // matrix[1][4]
                    next_matrix_mem[2*8 + 4] = i_data_a[11:10]; // matrix[2][4]
                    next_matrix_mem[3*8 + 4] = i_data_a[9:8];   // matrix[3][4]
                    next_matrix_mem[4*8 + 4] = i_data_a[7:6];   // matrix[4][4]
                    next_matrix_mem[5*8 + 4] = i_data_a[5:4];   // matrix[5][4]
                    next_matrix_mem[6*8 + 4] = i_data_a[3:2];   // matrix[6][4]
                    next_matrix_mem[7*8 + 4] = i_data_a[1:0];   // matrix[7][4]
                end
                3'd4: begin  // Column 5
                    next_matrix_mem[0*8 + 5] = i_data_a[15:14]; // matrix[0][5]
                    next_matrix_mem[1*8 + 5] = i_data_a[13:12]; // matrix[1][5]
                    next_matrix_mem[2*8 + 5] = i_data_a[11:10]; // matrix[2][5]
                    next_matrix_mem[3*8 + 5] = i_data_a[9:8];   // matrix[3][5]
                    next_matrix_mem[4*8 + 5] = i_data_a[7:6];   // matrix[4][5]
                    next_matrix_mem[5*8 + 5] = i_data_a[5:4];   // matrix[5][5]
                    next_matrix_mem[6*8 + 5] = i_data_a[3:2];   // matrix[6][5]
                    next_matrix_mem[7*8 + 5] = i_data_a[1:0];   // matrix[7][5]
                end
                3'd5: begin  // Column 6
                    next_matrix_mem[0*8 + 6] = i_data_a[15:14]; // matrix[0][6]
                    next_matrix_mem[1*8 + 6] = i_data_a[13:12]; // matrix[1][6]
                    next_matrix_mem[2*8 + 6] = i_data_a[11:10]; // matrix[2][6]
                    next_matrix_mem[3*8 + 6] = i_data_a[9:8];   // matrix[3][6]
                    next_matrix_mem[4*8 + 6] = i_data_a[7:6];   // matrix[4][6]
                    next_matrix_mem[5*8 + 6] = i_data_a[5:4];   // matrix[5][6]
                    next_matrix_mem[6*8 + 6] = i_data_a[3:2];   // matrix[6][6]
                    next_matrix_mem[7*8 + 6] = i_data_a[1:0];   // matrix[7][6]
                end
                3'd6: begin  // Column 7
                    next_matrix_mem[0*8 + 7] = i_data_a[15:14]; // matrix[0][7]
                    next_matrix_mem[1*8 + 7] = i_data_a[13:12]; // matrix[1][7]
                    next_matrix_mem[2*8 + 7] = i_data_a[11:10]; // matrix[2][7]
                    next_matrix_mem[3*8 + 7] = i_data_a[9:8];   // matrix[3][7]
                    next_matrix_mem[4*8 + 7] = i_data_a[7:6];   // matrix[4][7]
                    next_matrix_mem[5*8 + 7] = i_data_a[5:4];   // matrix[5][7]
                    next_matrix_mem[6*8 + 7] = i_data_a[3:2];   // matrix[6][7]
                    next_matrix_mem[7*8 + 7] = i_data_a[1:0];   // matrix[7][7]
                end
            endcase
            next_out_valid_reg = 1'b0;
        end else if (state == MATRIX_OUTPUT) begin
            // Output transposed matrix data
            next_output_count = output_count + 1'b1;
            // Output row as column vector (transpose operation)
            case (output_count)
                3'd0: begin  // Output row 0 as column vector
                    next_result_reg = {matrix_mem[0*8+0], matrix_mem[0*8+1], matrix_mem[0*8+2], matrix_mem[0*8+3], 
                                     matrix_mem[0*8+4], matrix_mem[0*8+5], matrix_mem[0*8+6], matrix_mem[0*8+7]};
                end
                3'd1: begin  // Output row 1 as column vector
                    next_result_reg = {matrix_mem[1*8+0], matrix_mem[1*8+1], matrix_mem[1*8+2], matrix_mem[1*8+3], 
                                     matrix_mem[1*8+4], matrix_mem[1*8+5], matrix_mem[1*8+6], matrix_mem[1*8+7]};
                end
                3'd2: begin  // Output row 2 as column vector
                    next_result_reg = {matrix_mem[2*8+0], matrix_mem[2*8+1], matrix_mem[2*8+2], matrix_mem[2*8+3], 
                                     matrix_mem[2*8+4], matrix_mem[2*8+5], matrix_mem[2*8+6], matrix_mem[2*8+7]};
                end
                3'd3: begin  // Output row 3 as column vector
                    next_result_reg = {matrix_mem[3*8+0], matrix_mem[3*8+1], matrix_mem[3*8+2], matrix_mem[3*8+3], 
                                     matrix_mem[3*8+4], matrix_mem[3*8+5], matrix_mem[3*8+6], matrix_mem[3*8+7]};
                end
                3'd4: begin  // Output row 4 as column vector
                    next_result_reg = {matrix_mem[4*8+0], matrix_mem[4*8+1], matrix_mem[4*8+2], matrix_mem[4*8+3], 
                                     matrix_mem[4*8+4], matrix_mem[4*8+5], matrix_mem[4*8+6], matrix_mem[4*8+7]};
                end
                3'd5: begin  // Output row 5 as column vector
                    next_result_reg = {matrix_mem[5*8+0], matrix_mem[5*8+1], matrix_mem[5*8+2], matrix_mem[5*8+3], 
                                     matrix_mem[5*8+4], matrix_mem[5*8+5], matrix_mem[5*8+6], matrix_mem[5*8+7]};
                end
                3'd6: begin  // Output row 6 as column vector
                    next_result_reg = {matrix_mem[6*8+0], matrix_mem[6*8+1], matrix_mem[6*8+2], matrix_mem[6*8+3], 
                                     matrix_mem[6*8+4], matrix_mem[6*8+5], matrix_mem[6*8+6], matrix_mem[6*8+7]};
                end
                3'd7: begin  // Output row 7 as column vector
                    next_result_reg = {matrix_mem[7*8+0], matrix_mem[7*8+1], matrix_mem[7*8+2], matrix_mem[7*8+3], 
                                     matrix_mem[7*8+4], matrix_mem[7*8+5], matrix_mem[7*8+6], matrix_mem[7*8+7]};
                end
            endcase
            next_out_valid_reg = 1'b1;
        end
    end
    
    //==========================================================================
    // Sequential Logic - State Machine
    //==========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    //==========================================================================
    // Sequential Logic - Data Registers
    //==========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            result_reg <= {DATA_W{1'b0}};
            out_valid_reg <= 1'b0;
            accumulator <= {ACC_W{1'b0}};
            input_count <= 3'd0;
            output_count <= 3'd0;
            current_inst <= 4'd0;
        end else begin
            result_reg <= next_result_reg;
            out_valid_reg <= next_out_valid_reg;
            accumulator <= next_accumulator;
            input_count <= next_input_count;
            output_count <= next_output_count;
            current_inst <= next_current_inst;
        end
    end
    
    //==========================================================================
    // Sequential Logic - Matrix Memory
    //==========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            // Initialize matrix to all zeros using a loop
            for (i_idx = 0; i_idx < 64; i_idx = i_idx + 1) begin
                matrix_mem[i_idx] <= 2'b00;
            end
        end else begin
            // Update matrix memory from combinational logic
            for (i_idx = 0; i_idx < 64; i_idx = i_idx + 1) begin
                matrix_mem[i_idx] <= next_matrix_mem[i_idx];
            end
        end
    end

endmodule