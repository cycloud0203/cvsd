// ====================================================================
// Convolution 3x3 Module
// ====================================================================
// Performs 3x3 convolution with fixed-point arithmetic
// - Pixels: 8-bit unsigned [7:0]
// - Weights: 8-bit signed Q1.7 format [7:0]
// - Output: 8-bit unsigned [7:0], clamped to 0-255
//
// Operation:
// 1. Multiply each of 9 pixels with corresponding weight
// 2. Accumulate all 9 products
// 3. Round the result
// 4. Clamp to [0, 255]
// ====================================================================

module conv_3x3 (
    // 3x3 window of pixels (row-major order)
    input  [7:0] p00, p01, p02,  // Top row
    input  [7:0] p10, p11, p12,  // Middle row
    input  [7:0] p20, p21, p22,  // Bottom row
    
    // 3x3 kernel weights (row-major order, Q1.7 signed)
    input  [7:0] w00, w01, w02,  // Top row
    input  [7:0] w10, w11, w12,  // Middle row
    input  [7:0] w20, w21, w22,  // Bottom row
    
    // Output
    output [7:0] result          // Clamped to [0, 255]
);

    // ================================================================
    // Step 1: Multiply each pixel with its weight
    // ================================================================
    // Pixel: 8-bit unsigned [7:0]
    // Weight: 8-bit signed Q1.7 [7:0] (1 sign bit, 7 fractional bits)
    // Product: 16-bit signed [15:0]
    
    wire signed [15:0] prod00, prod01, prod02;
    wire signed [15:0] prod10, prod11, prod12;
    wire signed [15:0] prod20, prod21, prod22;
    
    // Convert unsigned pixel to signed, then multiply
    assign prod00 = $signed({1'b0, p00}) * $signed(w00);
    assign prod01 = $signed({1'b0, p01}) * $signed(w01);
    assign prod02 = $signed({1'b0, p02}) * $signed(w02);
    
    assign prod10 = $signed({1'b0, p10}) * $signed(w10);
    assign prod11 = $signed({1'b0, p11}) * $signed(w11);
    assign prod12 = $signed({1'b0, p12}) * $signed(w12);
    
    assign prod20 = $signed({1'b0, p20}) * $signed(w20);
    assign prod21 = $signed({1'b0, p21}) * $signed(w21);
    assign prod22 = $signed({1'b0, p22}) * $signed(w22);
    
    // ================================================================
    // Step 2: Accumulate all products
    // ================================================================
    // Sum needs to be wide enough to hold 9 products
    // Each product is 16 bits, sum of 9 needs ~20 bits
    
    wire signed [19:0] sum;
    
    assign sum = prod00 + prod01 + prod02 +
                 prod10 + prod11 + prod12 +
                 prod20 + prod21 + prod22;
    
    // ================================================================
    // Step 3: Round
    // ================================================================
    // Weights are Q1.7 (7 fractional bits)
    // So we need to divide by 2^7 = 128
    // Rounding: add 64 (half of 128) before shifting
    
    wire signed [19:0] sum_rounded;
    assign sum_rounded = sum + 20'sd64;
    
    // Shift right by 7 to divide by 128
    wire signed [19:0] sum_shifted;
    assign sum_shifted = sum_rounded >>> 7;  // Arithmetic right shift
    
    // ================================================================
    // Step 4: Clamp to [0, 255]
    // ================================================================
    
    wire [7:0] result_clamped;
    
    assign result_clamped = (sum_shifted < 0) ? 8'd0 :
                            (sum_shifted > 255) ? 8'd255 :
                            sum_shifted[7:0];
    
    assign result = result_clamped;

endmodule

