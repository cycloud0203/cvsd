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
    
    // Internal registers
    reg [1:0] state, next_state;
    reg [DATA_W-1:0] result_reg;
    reg out_valid_reg;
    reg signed [ACC_W-1:0] accumulator;  // 36-bit accumulator
    
    // Matrix transpose registers
    reg [1:0] matrix [7:0][7:0];  // 8x8 matrix, each element is 2 bits
    reg [2:0] input_count;        // Count of received input cycles (0-7)
    reg [2:0] output_count;       // Count of output cycles (0-7)
    reg [INST_W-1:0] current_inst; // Store current instruction for multi-cycle operations
    
    // Temporary variables for overflow detection and operations
    reg signed [DATA_W:0] temp_result;    // 17-bit for overflow detection
    reg signed [31:0] mult_result;        // 32-bit multiplication result
    reg signed [ACC_W-1:0] mult_extended;  // 36-bit sign-extended multiplication result
    reg signed [ACC_W:0] acc_sum;         // 37-bit for accumulator overflow detection
    reg signed [25:0] rounded_result;     // 26-bit for rounding operation
    
    
        
    // Output assignments
    assign o_busy = (state == BUSY) || (state == MATRIX_INPUT) || (state == MATRIX_OUTPUT);
    assign o_out_valid = out_valid_reg;
    assign o_data = result_reg;
    
    // Next state logic
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
                if (i_in_valid && input_count == 3'd7) begin
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
    
    // ALU operation and output register
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            result_reg <= {DATA_W{1'b0}};
            out_valid_reg <= 1'b0;
            accumulator <= {ACC_W{1'b0}};  // Initialize accumulator to 0
            input_count <= 3'd0;
            output_count <= 3'd0;
            current_inst <= 4'd0;
            // Initialize matrix to all zeros
            for (int i = 0; i < 8; i = i + 1) begin
                for (int j = 0; j < 8; j = j + 1) begin
                    matrix[i][j] <= 2'b00;
                end
            end
            $display("accumulator initial value: %d", accumulator);
        end else begin
            if (state == IDLE && i_in_valid) begin
                // Perform ALU operation based on instruction
                case (i_inst)
                    4'b0000: begin  // Addition for fixed-point numbers with saturation
                        temp_result = $signed(i_data_a) + $signed(i_data_b);
                        if (temp_result > $signed(MAX_VALUE)) begin
                            result_reg <= MAX_VALUE;
                        end else if (temp_result < $signed(MIN_VALUE)) begin
                            result_reg <= MIN_VALUE;
                        end else begin
                            result_reg <= temp_result[DATA_W-1:0];
                        end
                    end
                    4'b0001: begin  // Subtraction for fixed-point numbers with saturation
                        temp_result = $signed(i_data_a) - $signed(i_data_b);
                        if (temp_result > $signed(MAX_VALUE)) begin
                            result_reg <= MAX_VALUE;
                        end else if (temp_result < $signed(MIN_VALUE)) begin
                            result_reg <= MIN_VALUE;
                        end else begin
                            result_reg <= temp_result[DATA_W-1:0];
                        end
                    end
                    4'b0010: begin  // Multiplication and accumulation for fixed-point numbers
                        // Calculate multiplication result from data_a * data_b
                        mult_result = $signed(i_data_a) * $signed(i_data_b);
                        //$display("mult_result: %d", mult_result);

                        // Extend multiplication result to 36 bits
                        mult_extended = {{4{mult_result[31]}}, mult_result};
                        //$display("mult_extended: %d", mult_extended);

                        // Add the accumulator to the mult_result  
                        acc_sum = $signed(accumulator) + $signed(mult_extended);
                        
                        // PATH 1: Saturate and update the 36-bit accumulator
                        if (acc_sum > $signed(ACC_MAX_VALUE)) begin
                            accumulator <= ACC_MAX_VALUE;
                        end else if (acc_sum < $signed(ACC_MIN_VALUE)) begin
                            accumulator <= ACC_MIN_VALUE;
                        end else begin
                            accumulator <= acc_sum[ACC_W-1:0];
                        end
                        
                        // PATH 2: Round first, then saturate for 16-bit output
                        // Round to nearest representable number with 10-bit fraction
                        // Tie-breaking: round half toward positive infinity
                        // Check bits [9:0] for rounding decision
                        if (acc_sum[9:0] >= 10'd512) begin
                            // Round up (toward positive infinity for ties)
                            rounded_result = acc_sum[35:10] + 1'b1;
                        end else begin
                            // Round down (truncate)
                            rounded_result = acc_sum[35:10];
                        end

                        // Saturate rounded result to 16-bit output range
                        if (rounded_result > $signed(MAX_VALUE)) begin
                            result_reg <= MAX_VALUE;
                        end else if (rounded_result < $signed(MIN_VALUE)) begin
                            result_reg <= MIN_VALUE;
                        end else begin
                            result_reg <= rounded_result[15:0];
                        end
                    end
                    4'b0011: begin  // Taylor expansion of sin function on fixed-point numbers
                        // calculate the Taylor expansion of sin function on fixed-point numbers
                        // sin(x) = x - 1/6*x^3 + 1/120*x^5 (n = 2)
                        localparam [15:0] coeff_6 = 16'b0000000010101011;   // 1/6 in Q6.10 = 171/1024 ≈ 0.1670
                        localparam [15:0] coeff_120 = 16'b0000000000001001; // 1/120 in Q6.10 = 9/1024 ≈ 0.0088

                        reg signed [31:0] x_squared;      // x^2 in Q12.20
                        reg signed [47:0] x_cubed;        // x^3 in Q18.30
                        reg signed [63:0] x_fifth;        // x^5 in Q30.50  
                        reg signed [63:0] term2_full;     // (1/6)*x^3 in Q24.40
                        reg signed [79:0] term3_full;     // (1/120)*x^5 in Q36.60
                        reg signed [31:0] x_extended;     // x in Q12.20 for high precision calc
                        reg signed [31:0] term2_q1220;    // (1/6)*x^3 in Q12.20
                        reg signed [31:0] term3_q1220;    // (1/120)*x^5 in Q12.20
                        reg signed [32:0] sin_high_prec;  // High precision result in Q12.20
                        reg signed [25:0] rounded_result; // Rounded result before saturation
                        reg signed [16:0] sin_result;     // Final result with overflow detection

                        // Extend x to higher precision (Q12.20)
                        x_extended = $signed(i_data_a) << 10;  // Convert Q6.10 to Q12.20
                        
                        // Calculate x^2 in Q12.20
                        x_squared = $signed(i_data_a) * $signed(i_data_a);  // Q6.10 * Q6.10 = Q12.20
 
                        // Calculate x^3 in Q18.30
                        x_cubed = $signed(i_data_a) * x_squared;  // Q6.10 * Q12.20 = Q18.30
                        
                        // Calculate x^5 in Q30.50
                        x_fifth = x_squared * x_cubed;  // Q12.20 * Q18.30 = Q30.50
                        
                        // Calculate (1/6)*x^3 in Q24.40
                        term2_full = $signed(coeff_6) * x_cubed;  // Q6.10 * Q18.30 = Q24.40
                        term2_q1220 = term2_full >>> 20;  // Convert Q24.40 to Q12.20
                        
                        // Calculate (1/120)*x^5 in Q36.60
                        term3_full = $signed(coeff_120) * x_fifth;  // Q6.10 * Q30.50 = Q36.60
                        term3_q1220 = term3_full >>> 40;  // Convert Q36.60 to Q12.20
                        
                        // High precision calculation in Q12.20
                        // sin(x) = x - (1/6)*x^3 + (1/120)*x^5
                        sin_high_prec = x_extended - term2_q1220 + term3_q1220;
                        
                        // Rounding from Q12.20 to Q6.10
                        // Check bits [9:0] for rounding decision (tie-breaking: round half up)
                        if (sin_high_prec[9:0] >= 10'd512) begin
                            // Round up
                            rounded_result = sin_high_prec[31:10] + 1'b1;
                        end else begin
                            // Round down (truncate)
                            rounded_result = sin_high_prec[31:10];
                        end
                        
                        // Convert to 17-bit for saturation check
                        sin_result = rounded_result[16:0];
                        
                        // Saturation check
                        if (sin_result > $signed(MAX_VALUE)) begin
                            result_reg <= MAX_VALUE;
                        end else if (sin_result < $signed(MIN_VALUE)) begin
                            result_reg <= MIN_VALUE;
                        end else begin
                            result_reg <= sin_result[15:0];
                        end
                    end
                    4'b0100: begin // Binary to gray code 
                        // calculate the gray code of the binary input
                        // gray code = (binary >> 1) ^ binary
                        // data_a is unsigned integer
                        result_reg <= (i_data_a >> 1) ^ i_data_a;
                    end
                    4'b0101: begin // LRCW shift
                        // count CPOP of data_a, 0 <= CPOP <= 16
                        integer cpop;
                        reg [DATA_W-1:0] temp_data;
                        cpop = 0;
                        for (int i = 0; i < DATA_W; i = i + 1) begin
                            if (i_data_a[i] == 1'b1) begin
                                cpop = cpop + 1;
                            end
                        end

                        //$display("CPOP of data_a: %d", cpop);

                        // Initialize temp_data with i_data_b
                        temp_data = i_data_b;
                        
                        // do LRCW shift on temp_data
                        for (int i = 0; i < cpop; i = i + 1) begin
                            temp_data = temp_data << 1;
                            temp_data = ~temp_data;
                        end

                        result_reg <= temp_data;
                    end
                    4'b0110: begin // right rotate
                        reg [2*DATA_W-1:0] temp_data; // 32-bit temp data
                        temp_data = {i_data_a, i_data_a};
                        // data_b is shift amount between 0 and 16(inclusive)
                        temp_data = temp_data >> i_data_b;
                        result_reg <= temp_data[DATA_W-1:0];
                    end
                    4'b0111: begin // Count leading MSB zeros
                        // count leading zeros of data_a from MSB
                        reg [15:0] cnt;
                        cnt = 16'd0;
                        for (int i = 15; i >= 0; i = i - 1) begin
                            if (i_data_a[i] == 1'b0) begin
                                cnt = cnt + 16'd1;
                            end else begin
                                break;
                            end
                        end
                        result_reg <= cnt;
                    end
                    4'b1000: begin // Reverse Match4 (Custom bit level operation)
                        reg [15:0] temp_data;
                        // for bit 13~15: 0
                        temp_data[15:13] = 3'b000;
                        // Explicit comparisons to avoid synthesis issues with variable indices
                        temp_data[0]  = (i_data_a[3:0]   == i_data_b[15:12]);
                        temp_data[1]  = (i_data_a[4:1]   == i_data_b[14:11]);
                        temp_data[2]  = (i_data_a[5:2]   == i_data_b[13:10]);
                        temp_data[3]  = (i_data_a[6:3]   == i_data_b[12:9]);
                        temp_data[4]  = (i_data_a[7:4]   == i_data_b[11:8]);
                        temp_data[5]  = (i_data_a[8:5]   == i_data_b[10:7]);
                        temp_data[6]  = (i_data_a[9:6]   == i_data_b[9:6]);
                        temp_data[7]  = (i_data_a[10:7]  == i_data_b[8:5]);
                        temp_data[8]  = (i_data_a[11:8]  == i_data_b[7:4]);
                        temp_data[9]  = (i_data_a[12:9]  == i_data_b[6:3]);
                        temp_data[10] = (i_data_a[13:10] == i_data_b[5:2]);
                        temp_data[11] = (i_data_a[14:11] == i_data_b[4:1]);
                        temp_data[12] = (i_data_a[15:12] == i_data_b[3:0]);
                        result_reg <= temp_data;
                    end
                    4'b1001: begin // Transpose an 8*8 matrix
                        // Initialize matrix transpose operation
                        current_inst <= i_inst;
                        input_count <= 3'd0;
                        output_count <= 3'd0;
                        // Store first column of matrix
                        matrix[0][0] <= i_data_a[15:14];  // Row 0
                        matrix[1][0] <= i_data_a[13:12];  // Row 1
                        matrix[2][0] <= i_data_a[11:10];  // Row 2
                        matrix[3][0] <= i_data_a[9:8];   // Row 3
                        matrix[4][0] <= i_data_a[7:6];   // Row 4
                        matrix[5][0] <= i_data_a[5:4];   // Row 5
                        matrix[6][0] <= i_data_a[3:2];   // Row 6
                        matrix[7][0] <= i_data_a[1:0];   // Row 7
                        result_reg <= {DATA_W{1'b0}};
                    end
                    default: begin
                        result_reg <= {DATA_W{1'b0}};  // Default to zero for unsupported instructions
                    end
                endcase
                out_valid_reg <= 1'b1;
            end else if (state == MATRIX_INPUT && i_in_valid) begin
                // Collect matrix input data (columns 1-7)
                input_count <= input_count + 1'b1;
                // Store column data based on input_count
                case (input_count)
                    3'd0: begin  // Column 1
                        matrix[0][1] <= i_data_a[15:14];
                        matrix[1][1] <= i_data_a[13:12];
                        matrix[2][1] <= i_data_a[11:10];
                        matrix[3][1] <= i_data_a[9:8];
                        matrix[4][1] <= i_data_a[7:6];
                        matrix[5][1] <= i_data_a[5:4];
                        matrix[6][1] <= i_data_a[3:2];
                        matrix[7][1] <= i_data_a[1:0];
                    end
                    3'd1: begin  // Column 2
                        matrix[0][2] <= i_data_a[15:14];
                        matrix[1][2] <= i_data_a[13:12];
                        matrix[2][2] <= i_data_a[11:10];
                        matrix[3][2] <= i_data_a[9:8];
                        matrix[4][2] <= i_data_a[7:6];
                        matrix[5][2] <= i_data_a[5:4];
                        matrix[6][2] <= i_data_a[3:2];
                        matrix[7][2] <= i_data_a[1:0];
                    end
                    3'd2: begin  // Column 3
                        matrix[0][3] <= i_data_a[15:14];
                        matrix[1][3] <= i_data_a[13:12];
                        matrix[2][3] <= i_data_a[11:10];
                        matrix[3][3] <= i_data_a[9:8];
                        matrix[4][3] <= i_data_a[7:6];
                        matrix[5][3] <= i_data_a[5:4];
                        matrix[6][3] <= i_data_a[3:2];
                        matrix[7][3] <= i_data_a[1:0];
                    end
                    3'd3: begin  // Column 4
                        matrix[0][4] <= i_data_a[15:14];
                        matrix[1][4] <= i_data_a[13:12];
                        matrix[2][4] <= i_data_a[11:10];
                        matrix[3][4] <= i_data_a[9:8];
                        matrix[4][4] <= i_data_a[7:6];
                        matrix[5][4] <= i_data_a[5:4];
                        matrix[6][4] <= i_data_a[3:2];
                        matrix[7][4] <= i_data_a[1:0];
                    end
                    3'd4: begin  // Column 5
                        matrix[0][5] <= i_data_a[15:14];
                        matrix[1][5] <= i_data_a[13:12];
                        matrix[2][5] <= i_data_a[11:10];
                        matrix[3][5] <= i_data_a[9:8];
                        matrix[4][5] <= i_data_a[7:6];
                        matrix[5][5] <= i_data_a[5:4];
                        matrix[6][5] <= i_data_a[3:2];
                        matrix[7][5] <= i_data_a[1:0];
                    end
                    3'd5: begin  // Column 6
                        matrix[0][6] <= i_data_a[15:14];
                        matrix[1][6] <= i_data_a[13:12];
                        matrix[2][6] <= i_data_a[11:10];
                        matrix[3][6] <= i_data_a[9:8];
                        matrix[4][6] <= i_data_a[7:6];
                        matrix[5][6] <= i_data_a[5:4];
                        matrix[6][6] <= i_data_a[3:2];
                        matrix[7][6] <= i_data_a[1:0];
                    end
                    3'd6: begin  // Column 7
                        matrix[0][7] <= i_data_a[15:14];
                        matrix[1][7] <= i_data_a[13:12];
                        matrix[2][7] <= i_data_a[11:10];
                        matrix[3][7] <= i_data_a[9:8];
                        matrix[4][7] <= i_data_a[7:6];
                        matrix[5][7] <= i_data_a[5:4];
                        matrix[6][7] <= i_data_a[3:2];
                        matrix[7][7] <= i_data_a[1:0];
                    end
                endcase
                out_valid_reg <= 1'b0;
            end else if (state == MATRIX_OUTPUT) begin
                // Output transposed matrix data
                output_count <= output_count + 1'b1;
                // Output row as column vector (transpose operation)
                case (output_count)
                    3'd0: begin  // Output row 0 as column vector
                        result_reg <= {matrix[0][0], matrix[0][1], matrix[0][2], matrix[0][3], 
                                     matrix[0][4], matrix[0][5], matrix[0][6], matrix[0][7]};
                    end
                    3'd1: begin  // Output row 1 as column vector
                        result_reg <= {matrix[1][0], matrix[1][1], matrix[1][2], matrix[1][3], 
                                     matrix[1][4], matrix[1][5], matrix[1][6], matrix[1][7]};
                    end
                    3'd2: begin  // Output row 2 as column vector
                        result_reg <= {matrix[2][0], matrix[2][1], matrix[2][2], matrix[2][3], 
                                     matrix[2][4], matrix[2][5], matrix[2][6], matrix[2][7]};
                    end
                    3'd3: begin  // Output row 3 as column vector
                        result_reg <= {matrix[3][0], matrix[3][1], matrix[3][2], matrix[3][3], 
                                     matrix[3][4], matrix[3][5], matrix[3][6], matrix[3][7]};
                    end
                    3'd4: begin  // Output row 4 as column vector
                        result_reg <= {matrix[4][0], matrix[4][1], matrix[4][2], matrix[4][3], 
                                     matrix[4][4], matrix[4][5], matrix[4][6], matrix[4][7]};
                    end
                    3'd5: begin  // Output row 5 as column vector
                        result_reg <= {matrix[5][0], matrix[5][1], matrix[5][2], matrix[5][3], 
                                     matrix[5][4], matrix[5][5], matrix[5][6], matrix[5][7]};
                    end
                    3'd6: begin  // Output row 6 as column vector
                        result_reg <= {matrix[6][0], matrix[6][1], matrix[6][2], matrix[6][3], 
                                     matrix[6][4], matrix[6][5], matrix[6][6], matrix[6][7]};
                    end
                    3'd7: begin  // Output row 7 as column vector
                        result_reg <= {matrix[7][0], matrix[7][1], matrix[7][2], matrix[7][3], 
                                     matrix[7][4], matrix[7][5], matrix[7][6], matrix[7][7]};
                    end
                endcase
                out_valid_reg <= 1'b1;
            end else begin
                out_valid_reg <= 1'b0;
            end
        end
    end

    // State machine
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end



    
endmodule
