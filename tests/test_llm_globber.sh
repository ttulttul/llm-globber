#!/bin/bash

# Main test script for LLM Globber
# This script runs all the test cases and reports results

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create test directory structure if it doesn't exist
mkdir -p test_files/dir1/subdir
mkdir -p test_files/dir2

# Check if directories were created successfully
if [ ! -d "test_files" ] || [ ! -d "test_files/dir1/subdir" ] || [ ! -d "test_files/dir2" ]; then
    echo -e "${RED}Error: Failed to create test directories${NC}"
    exit 1
fi

# Create test files with content
echo "This is a C file" > test_files/test1.c
echo "This is a header file" > test_files/test1.h
echo "This is a text file" > test_files/notes.txt
echo "This is a markdown file" > test_files/readme.md
echo "This is a nested C file" > test_files/dir1/nested.c
echo "This is a nested header file" > test_files/dir1/nested.h
echo "This is a deeply nested file" > test_files/dir1/subdir/deep.c
echo "This is another directory file" > test_files/dir2/other.c

# Make sure the llm_globber executable exists
if [ ! -f "../llm_globber" ]; then
    echo -e "${RED}Error: llm_globber executable not found. Please compile it first.${NC}"
    echo "Run 'make' to compile the program."
    exit 1
fi

# Create output directory
mkdir -p test_output

# Run all test scripts
echo "Running all LLM Globber tests..."

# Track test results
TOTAL_TESTS=0
PASSED_TESTS=0

# Run each test and collect results
for test_script in test_basic.sh test_recursive.sh test_file_types.sh test_name_pattern.sh test_dotfiles.sh test_verbose_quiet.sh ; do
    if [ -f "./$test_script" ]; then
        echo -e "\nRunning $test_script..."
        chmod +x ./$test_script
        ./$test_script
        
        if [ $? -eq 0 ]; then
            PASSED_TESTS=$((PASSED_TESTS + 1))
            echo -e "${GREEN}$test_script PASSED${NC}"
        else
            echo -e "${RED}$test_script FAILED${NC}"
        fi
        
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    else
        echo -e "${RED}Warning: Test script $test_script not found${NC}"
    fi
done

# Print summary
echo -e "\n----- Test Summary -----"
echo -e "Total tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$((TOTAL_TESTS - PASSED_TESTS))${NC}"

if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed. See individual test output above for details.${NC}"
    exit 1
fi
