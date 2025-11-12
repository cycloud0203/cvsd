#!/usr/bin/env python3
"""
DES Encryption Simulator - Cycle-by-cycle simulation
Matches the pipelined Verilog implementation in des_core.v
"""

# Initial Permutation (IP)
IP = [
    58, 50, 42, 34, 26, 18, 10, 2,
    60, 52, 44, 36, 28, 20, 12, 4,
    62, 54, 46, 38, 30, 22, 14, 6,
    64, 56, 48, 40, 32, 24, 16, 8,
    57, 49, 41, 33, 25, 17, 9, 1,
    59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5,
    63, 55, 47, 39, 31, 23, 15, 7
]

# Final Permutation (FP) - Inverse of IP
FP = [
    40, 8, 48, 16, 56, 24, 64, 32,
    39, 7, 47, 15, 55, 23, 63, 31,
    38, 6, 46, 14, 54, 22, 62, 30,
    37, 5, 45, 13, 53, 21, 61, 29,
    36, 4, 44, 12, 52, 20, 60, 28,
    35, 3, 43, 11, 51, 19, 59, 27,
    34, 2, 42, 10, 50, 18, 58, 26,
    33, 1, 41, 9, 49, 17, 57, 25
]

# Permuted Choice 1 (PC1) - Key schedule
PC1 = [
    57, 49, 41, 33, 25, 17, 9,
    1, 58, 50, 42, 34, 26, 18,
    10, 2, 59, 51, 43, 35, 27,
    19, 11, 3, 60, 52, 44, 36,
    63, 55, 47, 39, 31, 23, 15,
    7, 62, 54, 46, 38, 30, 22,
    14, 6, 61, 53, 45, 37, 29,
    21, 13, 5, 28, 20, 12, 4
]

# Permuted Choice 2 (PC2) - Subkey generation
PC2 = [
    14, 17, 11, 24, 1, 5,
    3, 28, 15, 6, 21, 10,
    23, 19, 12, 4, 26, 8,
    16, 7, 27, 20, 13, 2,
    41, 52, 31, 37, 47, 55,
    30, 40, 51, 45, 33, 48,
    44, 49, 39, 56, 34, 53,
    46, 42, 50, 36, 29, 32
]

# Expansion (E)
E = [
    32, 1, 2, 3, 4, 5,
    4, 5, 6, 7, 8, 9,
    8, 9, 10, 11, 12, 13,
    12, 13, 14, 15, 16, 17,
    16, 17, 18, 19, 20, 21,
    20, 21, 22, 23, 24, 25,
    24, 25, 26, 27, 28, 29,
    28, 29, 30, 31, 32, 1
]

# P-box permutation (after S-boxes)
P = [
    16, 7, 20, 21, 29, 12, 28, 17,
    1, 15, 23, 26, 5, 18, 31, 10,
    2, 8, 24, 14, 32, 27, 3, 9,
    19, 13, 30, 6, 22, 11, 4, 25
]

# S-boxes (8 S-boxes, each with 4 rows and 16 columns)
S_BOXES = [
    # S1
    [
        [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7],
        [0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8],
        [4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0],
        [15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13]
    ],
    # S2
    [
        [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10],
        [3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5],
        [0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15],
        [13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9]
    ],
    # S3
    [
        [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8],
        [13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1],
        [13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7],
        [1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12]
    ],
    # S4
    [
        [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15],
        [13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9],
        [10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4],
        [3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14]
    ],
    # S5
    [
        [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9],
        [14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6],
        [4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14],
        [11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3]
    ],
    # S6
    [
        [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11],
        [10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8],
        [9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6],
        [4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13]
    ],
    # S7
    [
        [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1],
        [13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6],
        [1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2],
        [6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12]
    ],
    # S8
    [
        [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7],
        [1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2],
        [7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8],
        [2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11]
    ]
]

# Shift schedule for key generation
SHIFT_SCHEDULE = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1]


def permute(data, table, input_bits):
    """Apply a permutation table to data"""
    result = 0
    for i, pos in enumerate(table):
        bit = (data >> (input_bits - pos)) & 1
        result |= bit << (len(table) - 1 - i)
    return result


def left_rotate(val, shift, bits=28):
    """Left rotate a value by shift positions"""
    mask = (1 << bits) - 1
    return ((val << shift) | (val >> (bits - shift))) & mask


def generate_subkeys(key, decrypt=False):
    """Generate 16 subkeys from the main key"""
    # Apply PC1
    key_56 = permute(key, PC1, 64)
    
    # Split into C and D
    c = key_56 >> 28
    d = key_56 & 0xFFFFFFF
    
    subkeys = []
    
    # Generate 16 subkeys
    for round_num in range(16):
        # Rotate C and D
        c = left_rotate(c, SHIFT_SCHEDULE[round_num], 28)
        d = left_rotate(d, SHIFT_SCHEDULE[round_num], 28)
        
        # Combine and apply PC2
        cd = (c << 28) | d
        subkey = permute(cd, PC2, 56)
        subkeys.append(subkey)
    
    # For decryption, reverse the subkey order
    if decrypt:
        subkeys.reverse()
    
    return subkeys


def sbox_lookup(data, sbox_num):
    """Perform S-box lookup"""
    # Extract row (bits 0 and 5) and column (bits 1-4)
    row = ((data >> 5) & 1) << 1 | (data & 1)
    col = (data >> 1) & 0xF
    return S_BOXES[sbox_num][row][col]


def f_function(r, subkey):
    """DES F-function"""
    # Expansion
    expanded = permute(r, E, 32)
    
    # XOR with subkey
    xored = expanded ^ subkey
    
    # Apply S-boxes
    sbox_output = 0
    for i in range(8):
        # Extract 6 bits for each S-box (from MSB to LSB)
        six_bits = (xored >> (42 - i * 6)) & 0x3F
        four_bits = sbox_lookup(six_bits, i)
        sbox_output |= four_bits << (28 - i * 4)
    
    # Apply P-box
    result = permute(sbox_output, P, 32)
    return result


def des_encrypt_cycle_by_cycle(plaintext, key, decrypt=False):
    """Simulate DES encryption cycle by cycle (pipelined)"""
    print(f"{'='*80}")
    print(f"DES Encryption Simulation - Cycle by Cycle")
    print(f"{'='*80}")
    print(f"Plaintext: {plaintext:016X}")
    print(f"Key:       {key:016X}")
    print(f"Mode:      {'Decrypt' if decrypt else 'Encrypt'}")
    print(f"{'='*80}\n")
    
    # Generate subkeys
    subkeys = generate_subkeys(key, decrypt)
    print("Subkeys generated:")
    for i, sk in enumerate(subkeys):
        print(f"  K{i+1:2d}: {sk:012X}")
    print()
    
    # Initial permutation
    ip_data = permute(plaintext, IP, 64)
    print(f"After Initial Permutation: {ip_data:016X}")
    l = ip_data >> 32
    r = ip_data & 0xFFFFFFFF
    print(f"  L0 = {l:08X}")
    print(f"  R0 = {r:08X}")
    print()
    
    # Pipeline simulation - 17 stages (0-16)
    # Stage 0: Load initial values
    # Stages 1-16: Process rounds 1-16
    
    l_pipe = [0] * 17
    r_pipe = [0] * 17
    
    # Cycle 0: Initialize with IP results
    print(f"Cycle 0: Initial values loaded")
    l_pipe[0] = l
    r_pipe[0] = r
    print(f"  l_pipe[0] = {l_pipe[0]:08X}, r_pipe[0] = {r_pipe[0]:08X}")
    print()
    
    # Simulate 16 cycles (each cycle advances the pipeline)
    for cycle in range(1, 17):
        print(f"Cycle {cycle}: Round {cycle} processing")
        
        # Process round (cycle-1) -> stage cycle
        # L[i+1] = R[i]
        # R[i+1] = L[i] XOR f(R[i], K[i])
        
        round_num = cycle - 1  # Round 0-15 (corresponding to K0-K15)
        
        if cycle <= 16:
            l_next = r_pipe[cycle-1]
            f_result = f_function(r_pipe[cycle-1], subkeys[round_num])
            r_next = l_pipe[cycle-1] ^ f_result
            
            l_pipe[cycle] = l_next
            r_pipe[cycle] = r_next
            
            print(f"  Input from stage {cycle-1}: L={l_pipe[cycle-1]:08X}, R={r_pipe[cycle-1]:08X}")
            print(f"  F(R{cycle-1}, K{cycle}) = {f_result:08X}")
            print(f"  L{cycle} = R{cycle-1} = {l_next:08X}")
            print(f"  R{cycle} = L{cycle-1} XOR F(R{cycle-1}, K{cycle}) = {r_next:08X}")
        print()
    
    # After 16 rounds, swap L and R and apply FP
    print(f"After 16 rounds:")
    print(f"  L16 = {l_pipe[16]:08X}")
    print(f"  R16 = {r_pipe[16]:08X}")
    
    # Note: In DES, we swap L and R before final permutation
    pre_fp = (r_pipe[16] << 32) | l_pipe[16]
    print(f"  Swapped: R16||L16 = {pre_fp:016X}")
    
    # Final permutation
    ciphertext = permute(pre_fp, FP, 64)
    print(f"\nAfter Final Permutation:")
    print(f"  Ciphertext = {ciphertext:016X}")
    print(f"{'='*80}\n")
    
    return ciphertext


def main():
    # Read first line from pattern1.dat
    with open('/Users/cloud_0203/cvsd/1141_hw4/00_TESTBED/pattern1_data/pattern1.dat', 'r') as f:
        first_line = f.readline().strip()
    
    print(f"Input from pattern1.dat: {first_line}")
    
    # Parse input - first 64 bits [127:64]: key, second 64 bits [63:0]: data
    key_hex = first_line[:16]
    data_hex = first_line[16:32]
    
    plaintext = int(data_hex, 16)
    key = int(key_hex, 16)
    
    # Run cycle-by-cycle simulation
    ciphertext = des_encrypt_cycle_by_cycle(plaintext, key, decrypt=False)
    
    # Read expected output from f1.dat
    with open('/Users/cloud_0203/cvsd/1141_hw4/00_TESTBED/pattern1_data/f1.dat', 'r') as f:
        expected_line = f.readline().strip()
    
    # f1.dat format: [127:64] = original key, [63:0] = encrypted data
    expected_hex = expected_line[16:32]  # Lower 64 bits are the encrypted output
    expected = int(expected_hex, 16)
    
    print(f"Expected output:    {expected:016X}")
    print(f"Simulated output:   {ciphertext:016X}")
    
    if ciphertext == expected:
        print("\n*** TEST PASSED ***")
    else:
        print("\n*** TEST FAILED ***")
        print(f"Difference: {ciphertext ^ expected:016X}")


if __name__ == "__main__":
    main()

