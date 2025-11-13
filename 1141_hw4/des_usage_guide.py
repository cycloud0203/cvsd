#!/usr/bin/env python3
"""
DES Simulator Usage Examples
"""

import subprocess
import sys

def print_help():
    """Print usage information"""
    print("""
DES Encryption/Decryption Simulator - Usage Guide
================================================================

MODES OF OPERATION:
------------------

1. REGULAR MODE (Default)
   Runs all tests without detailed output
   
   Command: python3 des_verify_and_generate.py
   
   Output:
   - Verifies all 64 pattern1 test cases
   - Generates golden data for pattern2
   - Shows progress every 10 test cases
   

2. VERBOSE MODE
   Shows cycle-by-cycle L and R values for encrypt and decrypt
   
   Command: python3 des_verify_and_generate.py --verbose
   or:      python3 des_verify_and_generate.py -v
   
   Output:
   - Detailed cycle-by-cycle simulation
   - Shows L and R values after each round
   - Shows all 16 subkeys
   - Shows Initial and Final Permutation results
   - For ALL test cases (generates very large output)
   

3. SINGLE TEST CASE MODE
   Runs one test case with full verbose output
   
   Command: python3 des_verify_and_generate.py --case=N
   
   Examples:
   - python3 des_verify_and_generate.py --case=1  (first test)
   - python3 des_verify_and_generate.py --case=10 (tenth test)
   - python3 des_verify_and_generate.py --case=64 (last test)
   
   Output:
   - Complete cycle-by-cycle trace for test case N
   - Shows both ENCRYPT and DECRYPT operations
   - Shows L and R values for all 16 rounds
   

EXAMPLES:
---------

# Run all tests quietly (default)
python3 des_verify_and_generate.py

# Run all tests with verbose output (WARNING: very long output!)
python3 des_verify_and_generate.py --verbose

# Debug a specific test case (recommended for debugging)
python3 des_verify_and_generate.py --case=1

# Save verbose output to file
python3 des_verify_and_generate.py --case=1 > test_case_1_output.txt

# Run first 5 test cases
for i in {1..5}; do
    python3 des_verify_and_generate.py --case=$i > test_case_${i}.txt
done


OUTPUT EXPLANATION:
-------------------

For each test case, the simulator shows:

ENCRYPT (f1.dat):
  - Subkeys K1-K16 (in order for encryption)
  - Initial Permutation result
  - L0, R0 initial values
  - For each cycle 1-16:
    * Input L and R values
    * F-function result
    * Output L and R values
  - Final L16, R16 values
  - Swapped R16||L16
  - Final Permutation result (ciphertext)

DECRYPT (f2.dat):
  - Subkeys K1-K16 (in REVERSE order for decryption)
  - Same structure as encryption
  - Final Permutation result (plaintext)


DATA FORMAT:
------------

Pattern files (pattern1.dat, pattern2.dat):
  - 32 hex characters per line
  - Bits [127:64] = 64-bit key
  - Bits [63:0]   = 64-bit data

Output files (f1.dat, f2.dat):
  - Same format as pattern files
  - f1.dat: encryption results (fn_sel=001)
  - f2.dat: decryption results (fn_sel=010)


VERIFICATION:
-------------

The simulator verifies correctness by:
1. Reading pattern1.dat test vectors
2. Computing encrypt/decrypt for each test
3. Comparing with expected f1.dat and f2.dat
4. Reporting PASS/FAIL for each test

All 64 test cases must pass before generating pattern2 golden data.


FILES GENERATED:
----------------

After successful verification:
  - 00_TESTBED/pattern2_data/f1.dat (64 lines)
  - 00_TESTBED/pattern2_data/f2.dat (64 lines)

================================================================
""")

def run_example(example_num):
    """Run a specific example"""
    if example_num == 1:
        print("Example 1: Running all tests (regular mode)")
        print("="*60)
        subprocess.run([sys.executable, "des_verify_and_generate.py"])
    
    elif example_num == 2:
        print("Example 2: Running single test case")
        print("="*60)
        subprocess.run([sys.executable, "des_verify_and_generate.py", "--case=1"])
    
    elif example_num == 3:
        print("Example 3: Running first 3 test cases")
        print("="*60)
        for i in range(1, 4):
            print(f"\n{'='*60}")
            print(f"Test Case {i}")
            print('='*60)
            subprocess.run([sys.executable, "des_verify_and_generate.py", f"--case={i}"])
    
    else:
        print(f"Unknown example number: {example_num}")
        print("Available examples: 1, 2, 3")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        if sys.argv[1] == "--help" or sys.argv[1] == "-h":
            print_help()
        elif sys.argv[1] == "--example":
            if len(sys.argv) > 2:
                try:
                    run_example(int(sys.argv[2]))
                except ValueError:
                    print("Error: Example number must be an integer")
            else:
                print("Error: Please specify example number (1, 2, or 3)")
        else:
            print("Unknown option. Use --help for usage information.")
    else:
        print_help()
