`timescale 1ns/10ps

module des_core (
    input         clk,          // Clock
    input         rst,          // Reset
    input         en,           // Enable signal for clock gating
    input         start,        // Start computation
    input  [63:0] data_in,      // 64-bit plaintext/ciphertext
    input  [63:0] key_in,       // 64-bit key
    input         decrypt,      // 0: encrypt, 1: decrypt
    output [63:0] data_out,     // 64-bit output
    output        done          // Computation done flag
);

// ========================================
// State Machine
// ========================================
localparam IDLE    = 2'd0;
localparam COMPUTE = 2'd1;
localparam DONE    = 2'd2;

reg [1:0] state, state_next;
reg [3:0] round_cnt, round_cnt_next;  // 0-15 for 16 rounds
reg [31:0] l_reg, l_reg_next;
reg [31:0] r_reg, r_reg_next;
reg [63:0] output_reg, output_reg_next;
reg done_reg, done_reg_next;

// ========================================
// Initial Permutation (IP)
// ========================================
function [63:0] initial_permutation;
    input [63:0] data;
    begin
        // DES bit 1-64 maps to Verilog bit 63-0
        initial_permutation = {
            data[6], data[14], data[22], data[30], data[38], data[46], data[54], data[62],
            data[4], data[12], data[20], data[28], data[36], data[44], data[52], data[60],
            data[2], data[10], data[18], data[26], data[34], data[42], data[50], data[58],
            data[0], data[8], data[16], data[24], data[32], data[40], data[48], data[56],
            data[7], data[15], data[23], data[31], data[39], data[47], data[55], data[63],
            data[5], data[13], data[21], data[29], data[37], data[45], data[53], data[61],
            data[3], data[11], data[19], data[27], data[35], data[43], data[51], data[59],
            data[1], data[9], data[17], data[25], data[33], data[41], data[49], data[57]
        };
    end
endfunction

// ========================================
// Final Permutation (FP) - Inverse of IP
// ========================================
function [63:0] final_permutation;
    input [63:0] data;
    begin
        // DES bit 1-64 maps to Verilog bit 63-0
        final_permutation = {
            data[24], data[56], data[16], data[48], data[8], data[40], data[0], data[32],
            data[25], data[57], data[17], data[49], data[9], data[41], data[1], data[33],
            data[26], data[58], data[18], data[50], data[10], data[42], data[2], data[34],
            data[27], data[59], data[19], data[51], data[11], data[43], data[3], data[35],
            data[28], data[60], data[20], data[52], data[12], data[44], data[4], data[36],
            data[29], data[61], data[21], data[53], data[13], data[45], data[5], data[37],
            data[30], data[62], data[22], data[54], data[14], data[46], data[6], data[38],
            data[31], data[63], data[23], data[55], data[15], data[47], data[7], data[39]
        };
    end
endfunction

// ========================================
// Permuted Choice 1 (PC1) - Key schedule
// ========================================
function [55:0] pc1;
    input [63:0] key;
    begin
        // DES bit 1-64 maps to Verilog bit 63-0
        // PC1 selects 56 bits from 64-bit key (drops parity bits)
        pc1 = {
            key[7], key[15], key[23], key[31], key[39], key[47], key[55],
            key[63], key[6], key[14], key[22], key[30], key[38], key[46],
            key[54], key[62], key[5], key[13], key[21], key[29], key[37],
            key[45], key[53], key[61], key[4], key[12], key[20], key[28],
            key[1], key[9], key[17], key[25], key[33], key[41], key[49],
            key[57], key[2], key[10], key[18], key[26], key[34], key[42],
            key[50], key[58], key[3], key[11], key[19], key[27], key[35],
            key[43], key[51], key[59], key[36], key[44], key[52], key[60]
        };
    end
endfunction

// ========================================
// Permuted Choice 2 (PC2) - Subkey generation
// ========================================
function [47:0] pc2;
    input [55:0] key;
    begin
        // PC2 selects 48 bits from 56-bit key
        pc2 = {
            key[42], key[39], key[45], key[32], key[55], key[51],
            key[53], key[28], key[41], key[50], key[35], key[46],
            key[33], key[37], key[44], key[52], key[30], key[48],
            key[40], key[49], key[29], key[36], key[43], key[54],
            key[15], key[4], key[25], key[19], key[9], key[1],
            key[26], key[16], key[5], key[11], key[23], key[8],
            key[12], key[7], key[17], key[0], key[22], key[3],
            key[10], key[14], key[6], key[20], key[27], key[24]
        };
    end
endfunction

// ========================================
// Expansion (E) - Expand 32 bits to 48 bits
// ========================================
function [47:0] expansion;
    input [31:0] data;
    begin
        // DES bit 1-32 maps to Verilog bit 31-0
        expansion = {
            data[0], data[31], data[30], data[29], data[28], data[27],
            data[28], data[27], data[26], data[25], data[24], data[23],
            data[24], data[23], data[22], data[21], data[20], data[19],
            data[20], data[19], data[18], data[17], data[16], data[15],
            data[16], data[15], data[14], data[13], data[12], data[11],
            data[12], data[11], data[10], data[9], data[8], data[7],
            data[8], data[7], data[6], data[5], data[4], data[3],
            data[4], data[3], data[2], data[1], data[0], data[31]
        };
    end
endfunction

// ========================================
// S-Boxes (8 S-boxes, each 6-bit input to 4-bit output)
// ========================================
function [3:0] sbox1;
    input [5:0] data;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {data[5], data[0]};
        col = data[4:1];
        case ({row, col})
            6'h00: sbox1 = 4'hE; 6'h01: sbox1 = 4'h4; 6'h02: sbox1 = 4'hD; 6'h03: sbox1 = 4'h1;
            6'h04: sbox1 = 4'h2; 6'h05: sbox1 = 4'hF; 6'h06: sbox1 = 4'hB; 6'h07: sbox1 = 4'h8;
            6'h08: sbox1 = 4'h3; 6'h09: sbox1 = 4'hA; 6'h0A: sbox1 = 4'h6; 6'h0B: sbox1 = 4'hC;
            6'h0C: sbox1 = 4'h5; 6'h0D: sbox1 = 4'h9; 6'h0E: sbox1 = 4'h0; 6'h0F: sbox1 = 4'h7;
            6'h10: sbox1 = 4'h0; 6'h11: sbox1 = 4'hF; 6'h12: sbox1 = 4'h7; 6'h13: sbox1 = 4'h4;
            6'h14: sbox1 = 4'hE; 6'h15: sbox1 = 4'h2; 6'h16: sbox1 = 4'hD; 6'h17: sbox1 = 4'h1;
            6'h18: sbox1 = 4'hA; 6'h19: sbox1 = 4'h6; 6'h1A: sbox1 = 4'hC; 6'h1B: sbox1 = 4'hB;
            6'h1C: sbox1 = 4'h9; 6'h1D: sbox1 = 4'h5; 6'h1E: sbox1 = 4'h3; 6'h1F: sbox1 = 4'h8;
            6'h20: sbox1 = 4'h4; 6'h21: sbox1 = 4'h1; 6'h22: sbox1 = 4'hE; 6'h23: sbox1 = 4'h8;
            6'h24: sbox1 = 4'hD; 6'h25: sbox1 = 4'h6; 6'h26: sbox1 = 4'h2; 6'h27: sbox1 = 4'hB;
            6'h28: sbox1 = 4'hF; 6'h29: sbox1 = 4'hC; 6'h2A: sbox1 = 4'h9; 6'h2B: sbox1 = 4'h7;
            6'h2C: sbox1 = 4'h3; 6'h2D: sbox1 = 4'hA; 6'h2E: sbox1 = 4'h5; 6'h2F: sbox1 = 4'h0;
            6'h30: sbox1 = 4'hF; 6'h31: sbox1 = 4'hC; 6'h32: sbox1 = 4'h8; 6'h33: sbox1 = 4'h2;
            6'h34: sbox1 = 4'h4; 6'h35: sbox1 = 4'h9; 6'h36: sbox1 = 4'h1; 6'h37: sbox1 = 4'h7;
            6'h38: sbox1 = 4'h5; 6'h39: sbox1 = 4'hB; 6'h3A: sbox1 = 4'h3; 6'h3B: sbox1 = 4'hE;
            6'h3C: sbox1 = 4'hA; 6'h3D: sbox1 = 4'h0; 6'h3E: sbox1 = 4'h6; 6'h3F: sbox1 = 4'hD;
        endcase
    end
endfunction

function [3:0] sbox2;
    input [5:0] data;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {data[5], data[0]};
        col = data[4:1];
        case ({row, col})
            6'h00: sbox2 = 4'hF; 6'h01: sbox2 = 4'h1; 6'h02: sbox2 = 4'h8; 6'h03: sbox2 = 4'hE;
            6'h04: sbox2 = 4'h6; 6'h05: sbox2 = 4'hB; 6'h06: sbox2 = 4'h3; 6'h07: sbox2 = 4'h4;
            6'h08: sbox2 = 4'h9; 6'h09: sbox2 = 4'h7; 6'h0A: sbox2 = 4'h2; 6'h0B: sbox2 = 4'hD;
            6'h0C: sbox2 = 4'hC; 6'h0D: sbox2 = 4'h0; 6'h0E: sbox2 = 4'h5; 6'h0F: sbox2 = 4'hA;
            6'h10: sbox2 = 4'h3; 6'h11: sbox2 = 4'hD; 6'h12: sbox2 = 4'h4; 6'h13: sbox2 = 4'h7;
            6'h14: sbox2 = 4'hF; 6'h15: sbox2 = 4'h2; 6'h16: sbox2 = 4'h8; 6'h17: sbox2 = 4'hE;
            6'h18: sbox2 = 4'hC; 6'h19: sbox2 = 4'h0; 6'h1A: sbox2 = 4'h1; 6'h1B: sbox2 = 4'hA;
            6'h1C: sbox2 = 4'h6; 6'h1D: sbox2 = 4'h9; 6'h1E: sbox2 = 4'hB; 6'h1F: sbox2 = 4'h5;
            6'h20: sbox2 = 4'h0; 6'h21: sbox2 = 4'hE; 6'h22: sbox2 = 4'h7; 6'h23: sbox2 = 4'hB;
            6'h24: sbox2 = 4'hA; 6'h25: sbox2 = 4'h4; 6'h26: sbox2 = 4'hD; 6'h27: sbox2 = 4'h1;
            6'h28: sbox2 = 4'h5; 6'h29: sbox2 = 4'h8; 6'h2A: sbox2 = 4'hC; 6'h2B: sbox2 = 4'h6;
            6'h2C: sbox2 = 4'h9; 6'h2D: sbox2 = 4'h3; 6'h2E: sbox2 = 4'h2; 6'h2F: sbox2 = 4'hF;
            6'h30: sbox2 = 4'hD; 6'h31: sbox2 = 4'h8; 6'h32: sbox2 = 4'hA; 6'h33: sbox2 = 4'h1;
            6'h34: sbox2 = 4'h3; 6'h35: sbox2 = 4'hF; 6'h36: sbox2 = 4'h4; 6'h37: sbox2 = 4'h2;
            6'h38: sbox2 = 4'hB; 6'h39: sbox2 = 4'h6; 6'h3A: sbox2 = 4'h7; 6'h3B: sbox2 = 4'hC;
            6'h3C: sbox2 = 4'h0; 6'h3D: sbox2 = 4'h5; 6'h3E: sbox2 = 4'hE; 6'h3F: sbox2 = 4'h9;
        endcase
    end
endfunction

function [3:0] sbox3;
    input [5:0] data;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {data[5], data[0]};
        col = data[4:1];
        case ({row, col})
            6'h00: sbox3 = 4'hA; 6'h01: sbox3 = 4'h0; 6'h02: sbox3 = 4'h9; 6'h03: sbox3 = 4'hE;
            6'h04: sbox3 = 4'h6; 6'h05: sbox3 = 4'h3; 6'h06: sbox3 = 4'hF; 6'h07: sbox3 = 4'h5;
            6'h08: sbox3 = 4'h1; 6'h09: sbox3 = 4'hD; 6'h0A: sbox3 = 4'hC; 6'h0B: sbox3 = 4'h7;
            6'h0C: sbox3 = 4'hB; 6'h0D: sbox3 = 4'h4; 6'h0E: sbox3 = 4'h2; 6'h0F: sbox3 = 4'h8;
            6'h10: sbox3 = 4'hD; 6'h11: sbox3 = 4'h7; 6'h12: sbox3 = 4'h0; 6'h13: sbox3 = 4'h9;
            6'h14: sbox3 = 4'h3; 6'h15: sbox3 = 4'h4; 6'h16: sbox3 = 4'h6; 6'h17: sbox3 = 4'hA;
            6'h18: sbox3 = 4'h2; 6'h19: sbox3 = 4'h8; 6'h1A: sbox3 = 4'h5; 6'h1B: sbox3 = 4'hE;
            6'h1C: sbox3 = 4'hC; 6'h1D: sbox3 = 4'hB; 6'h1E: sbox3 = 4'hF; 6'h1F: sbox3 = 4'h1;
            6'h20: sbox3 = 4'hD; 6'h21: sbox3 = 4'h6; 6'h22: sbox3 = 4'h4; 6'h23: sbox3 = 4'h9;
            6'h24: sbox3 = 4'h8; 6'h25: sbox3 = 4'hF; 6'h26: sbox3 = 4'h3; 6'h27: sbox3 = 4'h0;
            6'h28: sbox3 = 4'hB; 6'h29: sbox3 = 4'h1; 6'h2A: sbox3 = 4'h2; 6'h2B: sbox3 = 4'hC;
            6'h2C: sbox3 = 4'h5; 6'h2D: sbox3 = 4'hA; 6'h2E: sbox3 = 4'hE; 6'h2F: sbox3 = 4'h7;
            6'h30: sbox3 = 4'h1; 6'h31: sbox3 = 4'hA; 6'h32: sbox3 = 4'hD; 6'h33: sbox3 = 4'h0;
            6'h34: sbox3 = 4'h6; 6'h35: sbox3 = 4'h9; 6'h36: sbox3 = 4'h8; 6'h37: sbox3 = 4'h7;
            6'h38: sbox3 = 4'h4; 6'h39: sbox3 = 4'hF; 6'h3A: sbox3 = 4'hE; 6'h3B: sbox3 = 4'h3;
            6'h3C: sbox3 = 4'hB; 6'h3D: sbox3 = 4'h5; 6'h3E: sbox3 = 4'h2; 6'h3F: sbox3 = 4'hC;
        endcase
    end
endfunction

function [3:0] sbox4;
    input [5:0] data;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {data[5], data[0]};
        col = data[4:1];
        case ({row, col})
            6'h00: sbox4 = 4'h7; 6'h01: sbox4 = 4'hD; 6'h02: sbox4 = 4'hE; 6'h03: sbox4 = 4'h3;
            6'h04: sbox4 = 4'h0; 6'h05: sbox4 = 4'h6; 6'h06: sbox4 = 4'h9; 6'h07: sbox4 = 4'hA;
            6'h08: sbox4 = 4'h1; 6'h09: sbox4 = 4'h2; 6'h0A: sbox4 = 4'h8; 6'h0B: sbox4 = 4'h5;
            6'h0C: sbox4 = 4'hB; 6'h0D: sbox4 = 4'hC; 6'h0E: sbox4 = 4'h4; 6'h0F: sbox4 = 4'hF;
            6'h10: sbox4 = 4'hD; 6'h11: sbox4 = 4'h8; 6'h12: sbox4 = 4'hB; 6'h13: sbox4 = 4'h5;
            6'h14: sbox4 = 4'h6; 6'h15: sbox4 = 4'hF; 6'h16: sbox4 = 4'h0; 6'h17: sbox4 = 4'h3;
            6'h18: sbox4 = 4'h4; 6'h19: sbox4 = 4'h7; 6'h1A: sbox4 = 4'h2; 6'h1B: sbox4 = 4'hC;
            6'h1C: sbox4 = 4'h1; 6'h1D: sbox4 = 4'hA; 6'h1E: sbox4 = 4'hE; 6'h1F: sbox4 = 4'h9;
            6'h20: sbox4 = 4'hA; 6'h21: sbox4 = 4'h6; 6'h22: sbox4 = 4'h9; 6'h23: sbox4 = 4'h0;
            6'h24: sbox4 = 4'hC; 6'h25: sbox4 = 4'hB; 6'h26: sbox4 = 4'h7; 6'h27: sbox4 = 4'hD;
            6'h28: sbox4 = 4'hF; 6'h29: sbox4 = 4'h1; 6'h2A: sbox4 = 4'h3; 6'h2B: sbox4 = 4'hE;
            6'h2C: sbox4 = 4'h5; 6'h2D: sbox4 = 4'h2; 6'h2E: sbox4 = 4'h8; 6'h2F: sbox4 = 4'h4;
            6'h30: sbox4 = 4'h3; 6'h31: sbox4 = 4'hF; 6'h32: sbox4 = 4'h0; 6'h33: sbox4 = 4'h6;
            6'h34: sbox4 = 4'hA; 6'h35: sbox4 = 4'h1; 6'h36: sbox4 = 4'hD; 6'h37: sbox4 = 4'h8;
            6'h38: sbox4 = 4'h9; 6'h39: sbox4 = 4'h4; 6'h3A: sbox4 = 4'h5; 6'h3B: sbox4 = 4'hB;
            6'h3C: sbox4 = 4'hC; 6'h3D: sbox4 = 4'h7; 6'h3E: sbox4 = 4'h2; 6'h3F: sbox4 = 4'hE;
        endcase
    end
endfunction

function [3:0] sbox5;
    input [5:0] data;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {data[5], data[0]};
        col = data[4:1];
        case ({row, col})
            6'h00: sbox5 = 4'h2; 6'h01: sbox5 = 4'hC; 6'h02: sbox5 = 4'h4; 6'h03: sbox5 = 4'h1;
            6'h04: sbox5 = 4'h7; 6'h05: sbox5 = 4'hA; 6'h06: sbox5 = 4'hB; 6'h07: sbox5 = 4'h6;
            6'h08: sbox5 = 4'h8; 6'h09: sbox5 = 4'h5; 6'h0A: sbox5 = 4'h3; 6'h0B: sbox5 = 4'hF;
            6'h0C: sbox5 = 4'hD; 6'h0D: sbox5 = 4'h0; 6'h0E: sbox5 = 4'hE; 6'h0F: sbox5 = 4'h9;
            6'h10: sbox5 = 4'hE; 6'h11: sbox5 = 4'hB; 6'h12: sbox5 = 4'h2; 6'h13: sbox5 = 4'hC;
            6'h14: sbox5 = 4'h4; 6'h15: sbox5 = 4'h7; 6'h16: sbox5 = 4'hD; 6'h17: sbox5 = 4'h1;
            6'h18: sbox5 = 4'h5; 6'h19: sbox5 = 4'h0; 6'h1A: sbox5 = 4'hF; 6'h1B: sbox5 = 4'hA;
            6'h1C: sbox5 = 4'h3; 6'h1D: sbox5 = 4'h9; 6'h1E: sbox5 = 4'h8; 6'h1F: sbox5 = 4'h6;
            6'h20: sbox5 = 4'h4; 6'h21: sbox5 = 4'h2; 6'h22: sbox5 = 4'h1; 6'h23: sbox5 = 4'hB;
            6'h24: sbox5 = 4'hA; 6'h25: sbox5 = 4'hD; 6'h26: sbox5 = 4'h7; 6'h27: sbox5 = 4'h8;
            6'h28: sbox5 = 4'hF; 6'h29: sbox5 = 4'h9; 6'h2A: sbox5 = 4'hC; 6'h2B: sbox5 = 4'h5;
            6'h2C: sbox5 = 4'h6; 6'h2D: sbox5 = 4'h3; 6'h2E: sbox5 = 4'h0; 6'h2F: sbox5 = 4'hE;
            6'h30: sbox5 = 4'hB; 6'h31: sbox5 = 4'h8; 6'h32: sbox5 = 4'hC; 6'h33: sbox5 = 4'h7;
            6'h34: sbox5 = 4'h1; 6'h35: sbox5 = 4'hE; 6'h36: sbox5 = 4'h2; 6'h37: sbox5 = 4'hD;
            6'h38: sbox5 = 4'h6; 6'h39: sbox5 = 4'hF; 6'h3A: sbox5 = 4'h0; 6'h3B: sbox5 = 4'h9;
            6'h3C: sbox5 = 4'hA; 6'h3D: sbox5 = 4'h4; 6'h3E: sbox5 = 4'h5; 6'h3F: sbox5 = 4'h3;
        endcase
    end
endfunction

function [3:0] sbox6;
    input [5:0] data;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {data[5], data[0]};
        col = data[4:1];
        case ({row, col})
            6'h00: sbox6 = 4'hC; 6'h01: sbox6 = 4'h1; 6'h02: sbox6 = 4'hA; 6'h03: sbox6 = 4'hF;
            6'h04: sbox6 = 4'h9; 6'h05: sbox6 = 4'h2; 6'h06: sbox6 = 4'h6; 6'h07: sbox6 = 4'h8;
            6'h08: sbox6 = 4'h0; 6'h09: sbox6 = 4'hD; 6'h0A: sbox6 = 4'h3; 6'h0B: sbox6 = 4'h4;
            6'h0C: sbox6 = 4'hE; 6'h0D: sbox6 = 4'h7; 6'h0E: sbox6 = 4'h5; 6'h0F: sbox6 = 4'hB;
            6'h10: sbox6 = 4'hA; 6'h11: sbox6 = 4'hF; 6'h12: sbox6 = 4'h4; 6'h13: sbox6 = 4'h2;
            6'h14: sbox6 = 4'h7; 6'h15: sbox6 = 4'hC; 6'h16: sbox6 = 4'h9; 6'h17: sbox6 = 4'h5;
            6'h18: sbox6 = 4'h6; 6'h19: sbox6 = 4'h1; 6'h1A: sbox6 = 4'hD; 6'h1B: sbox6 = 4'hE;
            6'h1C: sbox6 = 4'h0; 6'h1D: sbox6 = 4'hB; 6'h1E: sbox6 = 4'h3; 6'h1F: sbox6 = 4'h8;
            6'h20: sbox6 = 4'h9; 6'h21: sbox6 = 4'hE; 6'h22: sbox6 = 4'hF; 6'h23: sbox6 = 4'h5;
            6'h24: sbox6 = 4'h2; 6'h25: sbox6 = 4'h8; 6'h26: sbox6 = 4'hC; 6'h27: sbox6 = 4'h3;
            6'h28: sbox6 = 4'h7; 6'h29: sbox6 = 4'h0; 6'h2A: sbox6 = 4'h4; 6'h2B: sbox6 = 4'hA;
            6'h2C: sbox6 = 4'h1; 6'h2D: sbox6 = 4'hD; 6'h2E: sbox6 = 4'hB; 6'h2F: sbox6 = 4'h6;
            6'h30: sbox6 = 4'h4; 6'h31: sbox6 = 4'h3; 6'h32: sbox6 = 4'h2; 6'h33: sbox6 = 4'hC;
            6'h34: sbox6 = 4'h9; 6'h35: sbox6 = 4'h5; 6'h36: sbox6 = 4'hF; 6'h37: sbox6 = 4'hA;
            6'h38: sbox6 = 4'hB; 6'h39: sbox6 = 4'hE; 6'h3A: sbox6 = 4'h1; 6'h3B: sbox6 = 4'h7;
            6'h3C: sbox6 = 4'h6; 6'h3D: sbox6 = 4'h0; 6'h3E: sbox6 = 4'h8; 6'h3F: sbox6 = 4'hD;
        endcase
    end
endfunction

function [3:0] sbox7;
    input [5:0] data;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {data[5], data[0]};
        col = data[4:1];
        case ({row, col})
            6'h00: sbox7 = 4'h4; 6'h01: sbox7 = 4'hB; 6'h02: sbox7 = 4'h2; 6'h03: sbox7 = 4'hE;
            6'h04: sbox7 = 4'hF; 6'h05: sbox7 = 4'h0; 6'h06: sbox7 = 4'h8; 6'h07: sbox7 = 4'hD;
            6'h08: sbox7 = 4'h3; 6'h09: sbox7 = 4'hC; 6'h0A: sbox7 = 4'h9; 6'h0B: sbox7 = 4'h7;
            6'h0C: sbox7 = 4'h5; 6'h0D: sbox7 = 4'hA; 6'h0E: sbox7 = 4'h6; 6'h0F: sbox7 = 4'h1;
            6'h10: sbox7 = 4'hD; 6'h11: sbox7 = 4'h0; 6'h12: sbox7 = 4'hB; 6'h13: sbox7 = 4'h7;
            6'h14: sbox7 = 4'h4; 6'h15: sbox7 = 4'h9; 6'h16: sbox7 = 4'h1; 6'h17: sbox7 = 4'hA;
            6'h18: sbox7 = 4'hE; 6'h19: sbox7 = 4'h3; 6'h1A: sbox7 = 4'h5; 6'h1B: sbox7 = 4'hC;
            6'h1C: sbox7 = 4'h2; 6'h1D: sbox7 = 4'hF; 6'h1E: sbox7 = 4'h8; 6'h1F: sbox7 = 4'h6;
            6'h20: sbox7 = 4'h1; 6'h21: sbox7 = 4'h4; 6'h22: sbox7 = 4'hB; 6'h23: sbox7 = 4'hD;
            6'h24: sbox7 = 4'hC; 6'h25: sbox7 = 4'h3; 6'h26: sbox7 = 4'h7; 6'h27: sbox7 = 4'hE;
            6'h28: sbox7 = 4'hA; 6'h29: sbox7 = 4'hF; 6'h2A: sbox7 = 4'h6; 6'h2B: sbox7 = 4'h8;
            6'h2C: sbox7 = 4'h0; 6'h2D: sbox7 = 4'h5; 6'h2E: sbox7 = 4'h9; 6'h2F: sbox7 = 4'h2;
            6'h30: sbox7 = 4'h6; 6'h31: sbox7 = 4'hB; 6'h32: sbox7 = 4'hD; 6'h33: sbox7 = 4'h8;
            6'h34: sbox7 = 4'h1; 6'h35: sbox7 = 4'h4; 6'h36: sbox7 = 4'hA; 6'h37: sbox7 = 4'h7;
            6'h38: sbox7 = 4'h9; 6'h39: sbox7 = 4'h5; 6'h3A: sbox7 = 4'h0; 6'h3B: sbox7 = 4'hF;
            6'h3C: sbox7 = 4'hE; 6'h3D: sbox7 = 4'h2; 6'h3E: sbox7 = 4'h3; 6'h3F: sbox7 = 4'hC;
        endcase
    end
endfunction

function [3:0] sbox8;
    input [5:0] data;
    reg [1:0] row;
    reg [3:0] col;
    begin
        row = {data[5], data[0]};
        col = data[4:1];
        case ({row, col})
            6'h00: sbox8 = 4'hD; 6'h01: sbox8 = 4'h2; 6'h02: sbox8 = 4'h8; 6'h03: sbox8 = 4'h4;
            6'h04: sbox8 = 4'h6; 6'h05: sbox8 = 4'hF; 6'h06: sbox8 = 4'hB; 6'h07: sbox8 = 4'h1;
            6'h08: sbox8 = 4'hA; 6'h09: sbox8 = 4'h9; 6'h0A: sbox8 = 4'h3; 6'h0B: sbox8 = 4'hE;
            6'h0C: sbox8 = 4'h5; 6'h0D: sbox8 = 4'h0; 6'h0E: sbox8 = 4'hC; 6'h0F: sbox8 = 4'h7;
            6'h10: sbox8 = 4'h1; 6'h11: sbox8 = 4'hF; 6'h12: sbox8 = 4'hD; 6'h13: sbox8 = 4'h8;
            6'h14: sbox8 = 4'hA; 6'h15: sbox8 = 4'h3; 6'h16: sbox8 = 4'h7; 6'h17: sbox8 = 4'h4;
            6'h18: sbox8 = 4'hC; 6'h19: sbox8 = 4'h5; 6'h1A: sbox8 = 4'h6; 6'h1B: sbox8 = 4'hB;
            6'h1C: sbox8 = 4'h0; 6'h1D: sbox8 = 4'hE; 6'h1E: sbox8 = 4'h9; 6'h1F: sbox8 = 4'h2;
            6'h20: sbox8 = 4'h7; 6'h21: sbox8 = 4'hB; 6'h22: sbox8 = 4'h4; 6'h23: sbox8 = 4'h1;
            6'h24: sbox8 = 4'h9; 6'h25: sbox8 = 4'hC; 6'h26: sbox8 = 4'hE; 6'h27: sbox8 = 4'h2;
            6'h28: sbox8 = 4'h0; 6'h29: sbox8 = 4'h6; 6'h2A: sbox8 = 4'hA; 6'h2B: sbox8 = 4'hD;
            6'h2C: sbox8 = 4'hF; 6'h2D: sbox8 = 4'h3; 6'h2E: sbox8 = 4'h5; 6'h2F: sbox8 = 4'h8;
            6'h30: sbox8 = 4'h2; 6'h31: sbox8 = 4'h1; 6'h32: sbox8 = 4'hE; 6'h33: sbox8 = 4'h7;
            6'h34: sbox8 = 4'h4; 6'h35: sbox8 = 4'hA; 6'h36: sbox8 = 4'h8; 6'h37: sbox8 = 4'hD;
            6'h38: sbox8 = 4'hF; 6'h39: sbox8 = 4'hC; 6'h3A: sbox8 = 4'h9; 6'h3B: sbox8 = 4'h0;
            6'h3C: sbox8 = 4'h3; 6'h3D: sbox8 = 4'h5; 6'h3E: sbox8 = 4'h6; 6'h3F: sbox8 = 4'hB;
        endcase
    end
endfunction

// ========================================
// P-Box Permutation (after S-boxes)
// ========================================
function [31:0] pbox;
    input [31:0] data;
    begin
        // DES bit 1-32 maps to Verilog bit 31-0
        pbox = {
            data[16], data[25], data[12], data[11], data[3], data[20], data[4], data[15],
            data[31], data[17], data[9], data[6], data[27], data[14], data[1], data[22],
            data[30], data[24], data[8], data[18], data[0], data[5], data[29], data[23],
            data[13], data[19], data[2], data[26], data[10], data[21], data[28], data[7]
        };
    end
endfunction

// ========================================
// F-function (Feistel function)
// ========================================
function [31:0] f_function;
    input [31:0] r;
    input [47:0] subkey;
    reg [47:0] expanded;
    reg [47:0] xored;
    reg [31:0] sbox_out;
    begin
        // Expansion
        expanded = expansion(r);
        
        // XOR with subkey
        xored = expanded ^ subkey;
        
        // S-boxes
        sbox_out = {
            sbox1(xored[47:42]),
            sbox2(xored[41:36]),
            sbox3(xored[35:30]),
            sbox4(xored[29:24]),
            sbox5(xored[23:18]),
            sbox6(xored[17:12]),
            sbox7(xored[11:6]),
            sbox8(xored[5:0])
        };
        
        // P-box permutation
        f_function = pbox(sbox_out);
    end
endfunction

// ========================================
// Key Schedule - Generate all 16 subkeys
// ========================================
function [767:0] generate_subkeys;  // 16 subkeys * 48 bits = 768 bits
    input [63:0] key;
    input decrypt_mode;
    reg [27:0] c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16;
    reg [27:0] d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13, d14, d15, d16;
    reg [55:0] cd;
    reg [47:0] k0, k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15;
    begin
        // PC1
        cd = pc1(key);
        c0 = cd[55:28];
        d0 = cd[27:0];
        
        // Generate 16 subkeys with explicit shifts
        // Shift schedule: rounds 1,2,9,16 shift by 1, others by 2
        
        // Round 1: shift by 1
        c1 = {c0[26:0], c0[27]};
        d1 = {d0[26:0], d0[27]};
        k0 = pc2({c1, d1});
        
        // Round 2: shift by 1
        c2 = {c1[26:0], c1[27]};
        d2 = {d1[26:0], d1[27]};
        k1 = pc2({c2, d2});
        
        // Round 3: shift by 2
        c3 = {c2[25:0], c2[27:26]};
        d3 = {d2[25:0], d2[27:26]};
        k2 = pc2({c3, d3});
        
        // Round 4: shift by 2
        c4 = {c3[25:0], c3[27:26]};
        d4 = {d3[25:0], d3[27:26]};
        k3 = pc2({c4, d4});
        
        // Round 5: shift by 2
        c5 = {c4[25:0], c4[27:26]};
        d5 = {d4[25:0], d4[27:26]};
        k4 = pc2({c5, d5});
        
        // Round 6: shift by 2
        c6 = {c5[25:0], c5[27:26]};
        d6 = {d5[25:0], d5[27:26]};
        k5 = pc2({c6, d6});
        
        // Round 7: shift by 2
        c7 = {c6[25:0], c6[27:26]};
        d7 = {d6[25:0], d6[27:26]};
        k6 = pc2({c7, d7});
        
        // Round 8: shift by 2
        c8 = {c7[25:0], c7[27:26]};
        d8 = {d7[25:0], d7[27:26]};
        k7 = pc2({c8, d8});
        
        // Round 9: shift by 1
        c9 = {c8[26:0], c8[27]};
        d9 = {d8[26:0], d8[27]};
        k8 = pc2({c9, d9});
        
        // Round 10: shift by 2
        c10 = {c9[25:0], c9[27:26]};
        d10 = {d9[25:0], d9[27:26]};
        k9 = pc2({c10, d10});
        
        // Round 11: shift by 2
        c11 = {c10[25:0], c10[27:26]};
        d11 = {d10[25:0], d10[27:26]};
        k10 = pc2({c11, d11});
        
        // Round 12: shift by 2
        c12 = {c11[25:0], c11[27:26]};
        d12 = {d11[25:0], d11[27:26]};
        k11 = pc2({c12, d12});
        
        // Round 13: shift by 2
        c13 = {c12[25:0], c12[27:26]};
        d13 = {d12[25:0], d12[27:26]};
        k12 = pc2({c13, d13});
        
        // Round 14: shift by 2
        c14 = {c13[25:0], c13[27:26]};
        d14 = {d13[25:0], d13[27:26]};
        k13 = pc2({c14, d14});
        
        // Round 15: shift by 2
        c15 = {c14[25:0], c14[27:26]};
        d15 = {d14[25:0], d14[27:26]};
        k14 = pc2({c15, d15});
        
        // Round 16: shift by 1
        c16 = {c15[26:0], c15[27]};
        d16 = {d15[26:0], d15[27]};
        k15 = pc2({c16, d16});
        
        // Pack subkeys (encryption: forward order, decryption: reverse order)
        if (decrypt_mode) begin
            generate_subkeys = {
                k15, k14, k13, k12, k11, k10, k9, k8,
                k7, k6, k5, k4, k3, k2, k1, k0
            };
        end else begin
            generate_subkeys = {
                k0, k1, k2, k3, k4, k5, k6, k7,
                k8, k9, k10, k11, k12, k13, k14, k15
            };
        end
    end
endfunction

// ========================================
// Subkey storage
// ========================================
wire [767:0] all_subkeys;
wire [47:0] subkey [0:15];

assign all_subkeys = generate_subkeys(key_in, decrypt);

// Extract individual subkeys
genvar i;
generate
    for (i = 0; i < 16; i = i + 1) begin : subkey_extract
        assign subkey[i] = all_subkeys[767 - i*48 -: 48];
    end
endgenerate

// ========================================
// Combinational Logic - FSM and Datapath
// ========================================
wire [63:0] ip_data;
wire [31:0] f_out;

assign ip_data = initial_permutation(data_in);
assign f_out = f_function(r_reg, subkey[round_cnt]);

always @(*) begin
    // Default assignments
    state_next = state;
    round_cnt_next = round_cnt;
    l_reg_next = l_reg;
    r_reg_next = r_reg;
    output_reg_next = output_reg;
    done_reg_next = 1'b0;
    
    case (state)
        IDLE: begin
            if (start) begin
                // Load initial values after IP
                l_reg_next = ip_data[63:32];
                r_reg_next = ip_data[31:0];
                round_cnt_next = 4'd0;
                state_next = COMPUTE;
            end
        end
        
        COMPUTE: begin
            if (round_cnt < 4'd15) begin
                // Perform one round: L' = R, R' = L XOR f(R, K)
                l_reg_next = r_reg;
                r_reg_next = l_reg ^ f_out;
                round_cnt_next = round_cnt + 4'd1;
                state_next = COMPUTE;
            end else begin
                // Last round (round 15): perform round and prepare output
                l_reg_next = r_reg;
                r_reg_next = l_reg ^ f_out;
                state_next = DONE;
            end
        end
        
        DONE: begin
            // Apply final permutation (swap L and R first)
            output_reg_next = final_permutation({r_reg, l_reg});
            done_reg_next = 1'b1;
            
            // Check if starting new computation
            if (start) begin
                l_reg_next = ip_data[63:32];
                r_reg_next = ip_data[31:0];
                round_cnt_next = 4'd0;
                state_next = COMPUTE;
            end else begin
                state_next = IDLE;
            end
        end
        
        default: state_next = IDLE;
    endcase
end

// ========================================
// Sequential Logic
// ========================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= IDLE;
        round_cnt <= 4'd0;
        l_reg <= 32'd0;
        r_reg <= 32'd0;
        output_reg <= 64'd0;
        done_reg <= 1'b0;
    end else if (en) begin
        state <= state_next;
        round_cnt <= round_cnt_next;
        l_reg <= l_reg_next;
        r_reg <= r_reg_next;
        output_reg <= output_reg_next;
        done_reg <= done_reg_next;
    end
end

// ========================================
// Output Assignment
// ========================================
assign data_out = output_reg;
assign done = done_reg;

endmodule
