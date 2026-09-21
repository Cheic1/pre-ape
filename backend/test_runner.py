#!/usr/bin/env python3
"""Test runner script for Pre-APE API"""

import os
import sys
import pytest

def run_tests():
    """Run the test suite"""
    print("=== Running Pre-APE API Tests ===\n")
    
    # Get current directory
    current_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Run pytest with proper paths
    return pytest.main([
        "-v",
        "--tb=short",
        os.path.join(current_dir, "tests", "test_api.py")
    ])

if __name__ == "__main__":
    exit_code = run_tests()
    sys.exit(exit_code)