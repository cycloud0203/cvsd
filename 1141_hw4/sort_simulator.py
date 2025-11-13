#!/usr/bin/env python3
"""
Sort simulator for 128-bit data.
Sorts 16 bytes in descending order.
"""

def hex_to_bytes(hex_string):
    """
    Convert 32-character hex string to list of 16 bytes.
    
    Args:
        hex_string: 32-character hex string (128 bits)
    
    Returns:
        List of 16 bytes (integers 0-255)
    """
    # Remove any whitespace
    hex_string = hex_string.strip()
    
    # Check if valid length
    if len(hex_string) != 32:
        raise ValueError(f'Hex string must be 32 characters, got {len(hex_string)}')
    
    # Convert to bytes
    bytes_list = []
    for i in range(0, 32, 2):
        byte_hex = hex_string[i:i+2]
        bytes_list.append(int(byte_hex, 16))
    
    return bytes_list

def bytes_to_hex(bytes_list):
    """
    Convert list of 16 bytes to 32-character hex string.
    
    Args:
        bytes_list: List of 16 bytes (integers 0-255)
    
    Returns:
        32-character hex string (uppercase)
    """
    return ''.join(f'{byte:02X}' for byte in bytes_list)

def sort_bytes_descending(hex_string):
    """
    Sort 16 bytes in descending order.
    
    Args:
        hex_string: 32-character hex string (128 bits)
    
    Returns:
        32-character hex string with bytes sorted in descending order
    """
    # Convert to bytes
    bytes_list = hex_to_bytes(hex_string)
    
    # Sort in descending order
    sorted_bytes = sorted(bytes_list, reverse=True)
    
    # Convert back to hex
    return bytes_to_hex(sorted_bytes)

def process_file(input_file, output_file):
    """
    Process an input file and generate sorted output.
    
    Args:
        input_file: Path to input file with hex strings
        output_file: Path to output file for sorted results
    """
    with open(input_file, 'r') as f_in, open(output_file, 'w') as f_out:
        for line_num, line in enumerate(f_in, 1):
            line = line.strip()
            
            # Skip empty lines
            if not line:
                f_out.write('\n')
                continue
            
            try:
                # Sort the bytes
                sorted_hex = sort_bytes_descending(line)
                f_out.write(f'{sorted_hex}\n')
            except Exception as e:
                print(f'Error processing line {line_num}: {e}')
                print(f'Line content: {line}')
                raise
    
    print(f'Processed {input_file} -> {output_file}')

def verify_against_golden(test_output, golden_output):
    """
    Verify test output against golden output.
    
    Args:
        test_output: Path to test output file
        golden_output: Path to golden output file
    
    Returns:
        True if files match, False otherwise
    """
    with open(test_output, 'r') as f_test, open(golden_output, 'r') as f_golden:
        test_lines = f_test.readlines()
        golden_lines = f_golden.readlines()
    
    if len(test_lines) != len(golden_lines):
        print(f'Error: Line count mismatch!')
        print(f'Test: {len(test_lines)} lines, Golden: {len(golden_lines)} lines')
        return False
    
    mismatches = []
    for i, (test_line, golden_line) in enumerate(zip(test_lines, golden_lines), 1):
        test_line = test_line.strip()
        golden_line = golden_line.strip()
        
        if test_line != golden_line:
            mismatches.append((i, test_line, golden_line))
    
    if mismatches:
        print(f'\nFound {len(mismatches)} mismatches:')
        for line_num, test, golden in mismatches[:10]:  # Show first 10 mismatches
            print(f'Line {line_num}:')
            print(f'  Test:   {test}')
            print(f'  Golden: {golden}')
        if len(mismatches) > 10:
            print(f'  ... and {len(mismatches) - 10} more')
        return False
    else:
        print(f'\nVerification PASSED! All {len(test_lines)} lines match.')
        return True

if __name__ == '__main__':
    import sys
    import os
    
    print('='*60)
    print('Sort Simulator - Testing and Verification')
    print('='*60)
    
    # Test with pattern1_data
    print('\n[1] Testing with pattern1_data...')
    pattern1_input = '00_TESTBED/pattern1_data/pattern1.dat'
    pattern1_output = '00_TESTBED/pattern1_data/f4_test.dat'
    pattern1_golden = '00_TESTBED/pattern1_data/f4.dat'
    
    if os.path.exists(pattern1_input):
        process_file(pattern1_input, pattern1_output)
        
        print('\n[2] Verifying against golden output...')
        if verify_against_golden(pattern1_output, pattern1_golden):
            print('\n SUCCESS: Sort algorithm verified!')
            # Clean up test file
            os.remove(pattern1_output)
        else:
            print('\n ERROR: Verification failed!')
            sys.exit(1)
    else:
        print(f'Warning: {pattern1_input} not found. Skipping verification.')
    
    # Generate output for pattern2_data
    print('\n[3] Generating golden output for pattern2_data...')
    pattern2_input = '00_TESTBED/pattern2_data/pattern2.dat'
    pattern2_output = '00_TESTBED/pattern2_data/f4.dat'
    
    if os.path.exists(pattern2_input):
        process_file(pattern2_input, pattern2_output)
        print(f'\n SUCCESS: Generated golden output for pattern2!')
        print(f'Output file: {pattern2_output}')
    else:
        print(f'\nWarning: {pattern2_input} not found.')
        print('Please run generate_pattern2.py first.')
    
    print('\n' + '='*60)
    print('Sort Simulator Complete!')
    print('='*60)


