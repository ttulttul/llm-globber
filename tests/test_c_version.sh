#!/bin/bash

# Test script for the C version of LLM Globber
# This script runs basic tests on the C implementation

# Source common test functions
source "$(dirname "$0")/test_common.sh"

# Path to the C version executable
C_GLOBBER="../llm_globber_c"

# Check if the C executable exists
if [ ! -f "$C_GLOBBER" ]; then
    echo -e "${RED}Error: C version executable not found. Please compile it first.${NC}"
    echo "Run 'make c-version' to compile the C program."
    exit 1
fi

# Create test directory structure if it doesn't exist
mkdir -p test_files/c_test
mkdir -p test_output

# Create test files with content
echo "This is a C test file for the C version" > test_files/c_test/test1.c
echo "This is a header file for the C version" > test_files/c_test/test1.h
echo "This is a text file for the C version" > test_files/c_test/notes.txt

# Test basic functionality
print_header "Testing C version basic functionality"

# Run the C version with basic options
"$C_GLOBBER" -o test_output -n c_version_test -t .c,.h test_files/c_test/test1.c test_files/c_test/test1.h

# Find the generated output file
OUTPUT_FILE=$(find test_output -name "c_version_test_*.txt" | sort -r | head -1)

if [ -z "$OUTPUT_FILE" ]; then
    print_result "C version basic test" false
    echo -e "${RED}No output file was generated${NC}"
    exit 1
fi

# Check if the output file contains the expected content
if grep -q "test1.c" "$OUTPUT_FILE" && grep -q "test1.h" "$OUTPUT_FILE"; then
    print_result "C version basic test" true
else
    print_result "C version basic test" false
    echo -e "${RED}Output file does not contain expected content${NC}"
    echo "Output file content:"
    cat "$OUTPUT_FILE"
    exit 1
fi

# Test file type filtering
print_header "Testing C version file type filtering"

# Run with only .c file type (adding -r flag to process directory recursively)
"$C_GLOBBER" -o test_output -n c_version_filter_test -t .c -r test_files/c_test

# Find the generated output file
FILTER_OUTPUT=$(find test_output -name "c_version_filter_test_*.txt" | sort -r | head -1)

if [ -z "$FILTER_OUTPUT" ]; then
    print_result "C version filter test" false
    echo -e "${RED}No output file was generated for filter test${NC}"
    exit 1
fi

# Check if the output contains only .c files
if grep -q "test1.c" "$FILTER_OUTPUT" && ! grep -q "test1.h" "$FILTER_OUTPUT"; then
    print_result "C version filter test" true
else
    print_result "C version filter test" false
    echo -e "${RED}Filter test failed - output contains wrong files${NC}"
    echo "Output file content:"
    cat "$FILTER_OUTPUT"
    exit 1
fi

# Clean up
rm -rf test_files/c_test
rm -f test_output/c_version_*

echo -e "${GREEN}All C version tests passed!${NC}"
exit 0
