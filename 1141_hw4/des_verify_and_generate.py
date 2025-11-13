#!/usr/bin/env python3
"""
DES Encryption/Decryption Simulator
Verifies correctness with pattern1_data and generates golden data for pattern2_data
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


def des_encrypt(plaintext, key, decrypt=False, verbose=False):
    """DES encryption/decryption"""
    # Generate subkeys
    subkeys = generate_subkeys(key, decrypt)
    
    if verbose:
        mode = "DECRYPT" if decrypt else "ENCRYPT"
        print(f"\n{'='*80}")
        print(f"DES {mode} - Cycle-by-Cycle Simulation")
        print(f"{'='*80}")
        print(f"Input:  {plaintext:016X}")
        print(f"Key:    {key:016X}")
        print(f"{'='*80}")
        
        print("\nSubkeys generated:")
        for i, sk in enumerate(subkeys):
            print(f"  K{i+1:2d}: {sk:012X}")
    
    # Initial permutation
    ip_data = permute(plaintext, IP, 64)
    l = ip_data >> 32
    r = ip_data & 0xFFFFFFFF
    
    if verbose:
        print(f"\nAfter Initial Permutation: {ip_data:016X}")
        print(f"  L0 = {l:08X}")
        print(f"  R0 = {r:08X}")
        print()
    
    # 16 rounds
    for round_num in range(16):
        l_prev = l
        r_prev = r
        
        l_next = r
        f_result = f_function(r, subkeys[round_num])
        r_next = l ^ f_result
        l = l_next
        r = r_next
        
        if verbose:
            print(f"Cycle {round_num + 1}: Round {round_num + 1}")
            print(f"  Input:  L{round_num} = {l_prev:08X}, R{round_num} = {r_prev:08X}")
            print(f"  F(R{round_num}, K{round_num + 1}) = {f_result:08X}")
            print(f"  Output: L{round_num + 1} = R{round_num} = {l:08X}")
            print(f"          R{round_num + 1} = L{round_num} XOR F(R{round_num}, K{round_num + 1}) = {r:08X}")
    
    if verbose:
        print(f"\nAfter 16 rounds:")
        print(f"  L16 = {l:08X}")
        print(f"  R16 = {r:08X}")
    
    # Swap L and R before final permutation
    pre_fp = (r << 32) | l
    
    if verbose:
        print(f"  Swapped: R16||L16 = {pre_fp:016X}")
    
    # Final permutation
    ciphertext = permute(pre_fp, FP, 64)
    
    if verbose:
        print(f"\nAfter Final Permutation:")
        print(f"  Output = {ciphertext:016X}")
        print(f"{'='*80}\n")
    
    return ciphertext


def des_decrypt(ciphertext, key, verbose=False):
    """DES decryption"""
    return des_encrypt(ciphertext, key, decrypt=True, verbose=verbose)


def verify_pattern1(verbose=False):
    """Verify DES implementation with pattern1_data"""
    print("="*80)
    print("VERIFYING WITH PATTERN1_DATA")
    print("="*80)
    
    # Read all pattern files
    with open('00_TESTBED/pattern1_data/pattern1.dat', 'r') as f:
        patterns = [line.strip() for line in f.readlines()]
    
    with open('00_TESTBED/pattern1_data/f1.dat', 'r') as f:
        f1_expected = [line.strip() for line in f.readlines()]
    
    with open('00_TESTBED/pattern1_data/f2.dat', 'r') as f:
        f2_expected = [line.strip() for line in f.readlines()]
    
    errors = []
    
    for i, pattern_line in enumerate(patterns):
        # Parse input: [127:64] = key, [63:0] = data
        key_hex = pattern_line[:16]
        data_hex = pattern_line[16:32]
        
        key = int(key_hex, 16)
        data = int(data_hex, 16)
        
        if verbose:
            print(f"\n{'#'*80}")
            print(f"TEST CASE {i+1}/{len(patterns)}")
            print(f"{'#'*80}")
            print(f"Pattern Input: {pattern_line}")
            print(f"  Key:  {key_hex}")
            print(f"  Data: {data_hex}")
        
        # f1.dat: ENCRYPT the data from pattern1.dat
        # pattern1.dat contains plaintext, f1 should contain ciphertext
        encrypted = des_encrypt(data, key, decrypt=False, verbose=verbose)
        
        # f2.dat: DECRYPT the data from pattern1.dat
        # pattern1.dat contains ciphertext in this context, f2 should contain plaintext
        decrypted = des_decrypt(data, key, verbose=verbose)
        
        # Check f1.dat - [127:64] = key, [63:0] = encrypted data
        f1_expected_data = int(f1_expected[i][16:32], 16)
        
        if encrypted != f1_expected_data:
            errors.append(f"Line {i+1} f1.dat ENCRYPT: Expected {f1_expected_data:016X}, Got {encrypted:016X}")
        else:
            if verbose:
                print(f"✓ f1.dat ENCRYPT: Match! Result = {encrypted:016X}")
        
        # Check f2.dat - [127:64] = key, [63:0] = decrypted data
        f2_expected_data = int(f2_expected[i][16:32], 16)
        
        if decrypted != f2_expected_data:
            errors.append(f"Line {i+1} f2.dat DECRYPT: Expected {f2_expected_data:016X}, Got {decrypted:016X}")
        else:
            if verbose:
                print(f"✓ f2.dat DECRYPT: Match! Result = {decrypted:016X}")
        
        # Progress indicator
        if not verbose and (i + 1) % 10 == 0:
            print(f"Verified {i+1}/{len(patterns)} test cases...")
    
    print(f"\nTotal test cases: {len(patterns)}")
    
    if errors:
        print(f"\n*** VERIFICATION FAILED ***")
        print(f"Errors found: {len(errors)}")
        for error in errors[:10]:  # Show first 10 errors
            print(f"  {error}")
        if len(errors) > 10:
            print(f"  ... and {len(errors) - 10} more errors")
        return False
    else:
        print("\n*** ALL TESTS PASSED ***")
        print("DES implementation is correct!")
        return True


def generate_pattern2_golden(verbose=False):
    """Generate golden data for pattern2_data"""
    print("\n" + "="*80)
    print("GENERATING GOLDEN DATA FOR PATTERN2_DATA")
    print("="*80)
    
    # Read pattern2.dat
    with open('00_TESTBED/pattern2_data/pattern2.dat', 'r') as f:
        patterns = [line.strip() for line in f.readlines()]
    
    f1_data = []  # DES ENCRYPT results
    f2_data = []  # DES DECRYPT results
    
    for i, pattern_line in enumerate(patterns):
        # Parse input: [127:64] = key, [63:0] = data
        key_hex = pattern_line[:16]
        data_hex = pattern_line[16:32]
        
        key = int(key_hex, 16)
        data = int(data_hex, 16)
        
        if verbose:
            print(f"\n{'#'*80}")
            print(f"PATTERN2 TEST CASE {i+1}/{len(patterns)}")
            print(f"{'#'*80}")
            print(f"Pattern Input: {pattern_line}")
            print(f"  Key:  {key_hex}")
            print(f"  Data: {data_hex}")
        
        # f1: Encrypt the data
        encrypted = des_encrypt(data, key, decrypt=False, verbose=verbose)
        f1_line = f"{key:016X}{encrypted:016X}"
        f1_data.append(f1_line)
        
        if verbose:
            print(f"Generated f1: {f1_line}")
        
        # f2: Decrypt the data
        decrypted = des_decrypt(data, key, verbose=verbose)
        f2_line = f"{key:016X}{decrypted:016X}"
        f2_data.append(f2_line)
        
        if verbose:
            print(f"Generated f2: {f2_line}")
        
        # Progress indicator
        if not verbose and (i + 1) % 10 == 0:
            print(f"Generated {i+1}/{len(patterns)} test cases...")
    
    # Write output files
    with open('00_TESTBED/pattern2_data/f1.dat', 'w') as f:
        f.write('\n'.join(f1_data) + '\n')
    
    with open('00_TESTBED/pattern2_data/f2.dat', 'w') as f:
        f.write('\n'.join(f2_data) + '\n')
    
    print(f"\nGenerated {len(patterns)} test cases")
    print("Output files created:")
    print("  - 00_TESTBED/pattern2_data/f1.dat (DES ENCRYPT results)")
    print("  - 00_TESTBED/pattern2_data/f2.dat (DES DECRYPT results)")
    print("\n*** GOLDEN DATA GENERATION COMPLETE ***")
    print("\nNote: f3.dat (CRC) and f4.dat (SORT) require separate implementations")


def main():
    import sys
    
    # Check for verbose flag
    verbose = '--verbose' in sys.argv or '-v' in sys.argv
    
    # Check for specific test case number
    test_case = None
    for arg in sys.argv:
        if arg.startswith('--case='):
            try:
                test_case = int(arg.split('=')[1])
            except:
                pass
    
    print("DES Encryption/Decryption Simulator")
    print("="*80)
    
    if verbose:
        print("VERBOSE MODE: Cycle-by-cycle output enabled")
        print("="*80)
    
    # Step 1: Verify with pattern1_data
    if test_case is not None:
        print(f"\nRunning single test case: {test_case}")
        verify_single_test_case(test_case, verbose=True)
    elif verify_pattern1(verbose=verbose):
        # Step 2: Generate golden data for pattern2_data
        generate_pattern2_golden(verbose=verbose)
    else:
        print("\nSkipping pattern2 generation due to verification errors.")


def verify_single_test_case(case_num, verbose=True):
    """Verify a single test case with detailed output"""
    # Read pattern files
    with open('00_TESTBED/pattern1_data/pattern1.dat', 'r') as f:
        patterns = [line.strip() for line in f.readlines()]
    
    with open('00_TESTBED/pattern1_data/f1.dat', 'r') as f:
        f1_expected = [line.strip() for line in f.readlines()]
    
    with open('00_TESTBED/pattern1_data/f2.dat', 'r') as f:
        f2_expected = [line.strip() for line in f.readlines()]
    
    if case_num < 1 or case_num > len(patterns):
        print(f"Error: Test case {case_num} out of range (1-{len(patterns)})")
        return
    
    i = case_num - 1
    pattern_line = patterns[i]
    
    # Parse input
    key_hex = pattern_line[:16]
    data_hex = pattern_line[16:32]
    
    key = int(key_hex, 16)
    data = int(data_hex, 16)
    
    print(f"\n{'#'*80}")
    print(f"TEST CASE {case_num}")
    print(f"{'#'*80}")
    print(f"Pattern Input: {pattern_line}")
    print(f"  Key:  {key_hex}")
    print(f"  Data: {data_hex}")
    
    # Encrypt
    print("\n" + ">"*80)
    print("TESTING f1.dat: DES ENCRYPT")
    print(">"*80)
    encrypted = des_encrypt(data, key, decrypt=False, verbose=verbose)
    f1_expected_data = int(f1_expected[i][16:32], 16)
    
    if encrypted == f1_expected_data:
        print(f"\n✓ f1.dat ENCRYPT: PASS")
        print(f"  Expected: {f1_expected_data:016X}")
        print(f"  Got:      {encrypted:016X}")
    else:
        print(f"\n✗ f1.dat ENCRYPT: FAIL")
        print(f"  Expected: {f1_expected_data:016X}")
        print(f"  Got:      {encrypted:016X}")
    
    # Decrypt
    print("\n" + ">"*80)
    print("TESTING f2.dat: DES DECRYPT")
    print(">"*80)
    decrypted = des_decrypt(data, key, verbose=verbose)
    f2_expected_data = int(f2_expected[i][16:32], 16)
    
    if decrypted == f2_expected_data:
        print(f"\n✓ f2.dat DECRYPT: PASS")
        print(f"  Expected: {f2_expected_data:016X}")
        print(f"  Got:      {decrypted:016X}")
    else:
        print(f"\n✗ f2.dat DECRYPT: FAIL")
        print(f"  Expected: {f2_expected_data:016X}")
        print(f"  Got:      {decrypted:016X}")


if __name__ == "__main__":
    main()
