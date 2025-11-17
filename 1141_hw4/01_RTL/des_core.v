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

(* fsm_encoding = "auto" *) reg [1:0] state, state_next;
reg [3:0] round_cnt, round_cnt_next;  // 0-15 for 16 rounds
reg [31:0] l_reg, l_reg_next;
reg [31:0] r_reg, r_reg_next;
reg [63:0] output_reg, output_reg_next;
reg done_reg, done_reg_next;
reg [27:0] c_reg, c_reg_next;
reg [27:0] d_reg, d_reg_next;
reg [47:0] current_subkey_reg, current_subkey_next;
reg decrypt_reg, decrypt_reg_next;

// ========================================
// Initial Permutation (IP)
// ========================================
function automatic [63:0] initial_permutation;
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
function automatic [63:0] final_permutation;
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
function automatic [55:0] pc1;
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
function automatic [47:0] pc2;
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
// Key Schedule Helpers
// ========================================
function automatic [27:0] rotate_left28;
    input [27:0] value;
    input [1:0] amount;
    begin
        case (amount)
            2'd1: rotate_left28 = {value[26:0], value[27]};
            2'd2: rotate_left28 = {value[25:0], value[27:26]};
            default: rotate_left28 = value;
        endcase
    end
endfunction

function automatic [27:0] rotate_right28;
    input [27:0] value;
    input [1:0] amount;
    begin
        case (amount)
            2'd1: rotate_right28 = {value[0], value[27:1]};
            2'd2: rotate_right28 = {value[1:0], value[27:2]};
            default: rotate_right28 = value;
        endcase
    end
endfunction

function automatic [1:0] shift_amount;
    input [3:0] round_index;
    begin
        case (round_index)
            4'd0,
            4'd1,
            4'd8,
            4'd15: shift_amount = 2'd1;
            default: shift_amount = 2'd2;
        endcase
    end
endfunction

function automatic [55:0] compute_cd_after_16_shifts;
    input [55:0] cd_in;
    reg [27:0] c_tmp;
    reg [27:0] d_tmp;
    integer idx;
    begin
        c_tmp = cd_in[55:28];
        d_tmp = cd_in[27:0];
        for (idx = 0; idx < 16; idx = idx + 1) begin
            c_tmp = rotate_left28(c_tmp, shift_amount(idx[3:0]));
            d_tmp = rotate_left28(d_tmp, shift_amount(idx[3:0]));
        end
        compute_cd_after_16_shifts = {c_tmp, d_tmp};
    end
endfunction

// ========================================
// Expansion (E) - Expand 32 bits to 48 bits
// ========================================
function automatic [47:0] expansion;
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
function automatic [3:0] sbox1;
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

function automatic [3:0] sbox2;
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

function automatic [3:0] sbox3;
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

function automatic [3:0] sbox4;
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

function automatic [3:0] sbox5;
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

function automatic [3:0] sbox6;
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

function automatic [3:0] sbox7;
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

function automatic [3:0] sbox8;
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
function automatic [31:0] pbox;
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
function automatic [31:0] f_function;
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
// Key Schedule Seeds
// ========================================
wire [55:0] pc1_key;
wire [55:0] decrypt_cd_seed;
wire [27:0] c_seed_wire;
wire [27:0] d_seed_wire;

assign pc1_key = pc1(key_in);
assign decrypt_cd_seed = compute_cd_after_16_shifts(pc1_key);
assign c_seed_wire = pc1_key[55:28];
assign d_seed_wire = pc1_key[27:0];

// ========================================
// Combinational Logic - FSM and Datapath
// ========================================
wire [63:0] ip_data;
wire [31:0] f_out;

assign ip_data = initial_permutation(data_in);
assign f_out = f_function(r_reg, current_subkey_reg);

always @(*) begin
    // Default assignments
    state_next = state;
    round_cnt_next = round_cnt;
    l_reg_next = l_reg;
    r_reg_next = r_reg;
    output_reg_next = output_reg;
    done_reg_next = 1'b0;
    c_reg_next = c_reg;
    d_reg_next = d_reg;
    current_subkey_next = current_subkey_reg;
    decrypt_reg_next = decrypt_reg;
    
    case (state)
        IDLE: begin
            if (start) begin
                decrypt_reg_next = decrypt;
                l_reg_next = ip_data[63:32];
                r_reg_next = ip_data[31:0];
                round_cnt_next = 4'd0;
                if (decrypt) begin
                    c_reg_next = decrypt_cd_seed[55:28];
                    d_reg_next = decrypt_cd_seed[27:0];
                end else begin
                    c_reg_next = rotate_left28(c_seed_wire, shift_amount(4'd0));
                    d_reg_next = rotate_left28(d_seed_wire, shift_amount(4'd0));
                end
                current_subkey_next = pc2({c_reg_next, d_reg_next});
                state_next = COMPUTE;
            end
        end
        
        COMPUTE: begin
            if (round_cnt < 4'd15) begin
                // Perform one round: L' = R, R' = L XOR f(R, K)
                l_reg_next = r_reg;
                r_reg_next = l_reg ^ f_out;
                round_cnt_next = round_cnt + 4'd1;
                if (!decrypt_reg) begin
                    c_reg_next = rotate_left28(c_reg, shift_amount(round_cnt + 4'd1));
                    d_reg_next = rotate_left28(d_reg, shift_amount(round_cnt + 4'd1));
                end else begin
                    c_reg_next = rotate_right28(c_reg, shift_amount(4'd15 - round_cnt));
                    d_reg_next = rotate_right28(d_reg, shift_amount(4'd15 - round_cnt));
                end
                current_subkey_next = pc2({c_reg_next, d_reg_next});
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
                decrypt_reg_next = decrypt;
                l_reg_next = ip_data[63:32];
                r_reg_next = ip_data[31:0];
                round_cnt_next = 4'd0;
                if (decrypt) begin
                    c_reg_next = decrypt_cd_seed[55:28];
                    d_reg_next = decrypt_cd_seed[27:0];
                end else begin
                    c_reg_next = rotate_left28(c_seed_wire, shift_amount(4'd0));
                    d_reg_next = rotate_left28(d_seed_wire, shift_amount(4'd0));
                end
                current_subkey_next = pc2({c_reg_next, d_reg_next});
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
        c_reg <= 28'd0;
        d_reg <= 28'd0;
        current_subkey_reg <= 48'd0;
        decrypt_reg <= 1'b0;
    end else if (en) begin
        state <= state_next;
        round_cnt <= round_cnt_next;
        l_reg <= l_reg_next;
        r_reg <= r_reg_next;
        output_reg <= output_reg_next;
        done_reg <= done_reg_next;
        c_reg <= c_reg_next;
        d_reg <= d_reg_next;
        current_subkey_reg <= current_subkey_next;
        decrypt_reg <= decrypt_reg_next;
    end
end

// ========================================
// Output Assignment
// ========================================
assign data_out = output_reg;
assign done = done_reg;

endmodule
