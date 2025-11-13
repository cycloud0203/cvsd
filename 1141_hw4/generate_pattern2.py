#!/usr/bin/env python3
"""
Generate pattern2_data with random 128-bit hexadecimal numbers.
"""

import random
import os

def generate_random_128bit_hex():
    """Generate a random 128-bit number as a 32-character hex string."""
    # Generate 16 random bytes (128 bits)
    random_bytes = [random.randint(0, 255) for _ in range(16)]
    # Convert to hex string (uppercase, no 0x prefix)
    hex_string = ''.join(f'{byte:02X}' for byte in random_bytes)
    return hex_string

def generate_pattern2(num_patterns=64, output_dir='00_TESTBED/pattern2_data'):
    """
    Generate pattern2.dat file with random 128-bit hex numbers.
    
    Args:
        num_patterns: Number of test patterns to generate (default: 65)
        output_dir: Output directory path
    """
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Generate pattern2.dat
    pattern2_path = os.path.join(output_dir, 'pattern2.dat')
    
    with open(pattern2_path, 'w') as f:
        for i in range(num_patterns):
            hex_data = generate_random_128bit_hex()
            f.write(f'{hex_data}\n')
    
    print(f'Generated {num_patterns} random 128-bit patterns in {pattern2_path}')
    return pattern2_path

if __name__ == '__main__':
    # Set random seed for reproducibility (optional - comment out for true randomness)
    random.seed(42)
    
    # Generate pattern2
    pattern2_path = generate_pattern2(num_patterns=65)
    
    print(f'\nPattern2 data generation complete!')
    print(f'File created: {pattern2_path}')


