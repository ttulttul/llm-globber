#!/bin/bash

# Test basic functionality of LLM Globber
# This test checks if the tool correctly processes specified files

# Create output directory and ensure test files directory exists
mkdir -p test_output
mkdir -p test_files

# Ensure test files exist
if [ ! -f "test_files/test1.c" ]; then
    echo "Creating test_files/test1.c"
    echo "This is a C file" > test_files/test1.c
fi
if [ ! -f "test_files/test1.h" ]; then
    echo "Creating test_files/test1.h"
    echo "This is a header file" > test_files/test1.h
fi

# Test case: Basic file processing
echo "Test case: Basic file processing"

# Files to test
TEST_FILES="test_files/test1.c test_files/test1.h"

# Expected output: manually concatenate the files
EXPECTED_OUTPUT="test_output/expected_basic.txt"
echo "" > $EXPECTED_OUTPUT
echo "'''--- $(pwd)/test_files/test1.c ---" >> $EXPECTED_OUTPUT
cat test_files/test1.c >> $EXPECTED_OUTPUT
echo "" >> $EXPECTED_OUTPUT
echo "'''" >> $EXPECTED_OUTPUT
echo "" >> $EXPECTED_OUTPUT
echo "'''--- $(pwd)/test_files/test1.h ---" >> $EXPECTED_OUTPUT
cat test_files/test1.h >> $EXPECTED_OUTPUT
echo "" >> $EXPECTED_OUTPUT
echo "'''" >> $EXPECTED_OUTPUT

# Run llm_globber with absolute path to ensure it works
OUTPUT_DIR="$(pwd)/test_output"
echo "Using output directory: $OUTPUT_DIR"
# Ensure the directory exists
mkdir -p "$OUTPUT_DIR"
# Run with explicit paths to each test file
# Use -u flag to disable sandbox mode for testing
# Use -j 1 to force single-threaded mode to preserve file order
# Add -v for verbose output to help debug
echo "Running: ../target/release/llm_globber -o $OUTPUT_DIR -n basic_test -u -j 1 -v $(pwd)/test_files/test1.c $(pwd)/test_files/test1.h"
../target/release/llm_globber -o "$OUTPUT_DIR" -n basic_test -u -j 1 -v "$(pwd)/test_files/test1.c" "$(pwd)/test_files/test1.h"

# Find the generated output file (most recent in the directory)
ACTUAL_OUTPUT=$(ls -t test_output/basic_test_*.txt | head -1)

if [ -z "$ACTUAL_OUTPUT" ]; then
    echo "Error: No output file was generated"
    exit 1
fi

# Count lines in expected and actual output files
EXPECTED_LINES=$(wc -l < "$EXPECTED_OUTPUT")
ACTUAL_LINES=$(wc -l < "$ACTUAL_OUTPUT")

echo "EXPECTED_LINES=$EXPECTED_LINES"
echo "ACTUAL_LINES  =$ACTUAL_LINES"

# Debug: show file contents
echo "=== EXPECTED OUTPUT ==="
cat "$EXPECTED_OUTPUT"
echo "=== ACTUAL OUTPUT ==="
cat "$ACTUAL_OUTPUT"
echo "=== END DEBUG ==="

# Check if test1.c appears before test1.h in the output file
if grep -A 1 "test_files/test1.c" "$ACTUAL_OUTPUT" | grep -q "This is a C file" && \
   grep -A 1 "test_files/test1.h" "$ACTUAL_OUTPUT" | grep -q "This is a header file"; then
    # Now check the order: test1.c should come before test1.h
    C_LINE=$(grep -n "test_files/test1.c" "$ACTUAL_OUTPUT" | cut -d':' -f1)
    H_LINE=$(grep -n "test_files/test1.h" "$ACTUAL_OUTPUT" | cut -d':' -f1)
    
    if [ "$C_LINE" -lt "$H_LINE" ]; then
        # Check if line counts match
        if [ "$EXPECTED_LINES" -eq "$ACTUAL_LINES" ]; then
            echo "Basic test passed: Files appear in correct order and line counts match"
            exit 0
        else
            echo "FAILED: Line count mismatch"
            echo "Expected $EXPECTED_LINES lines, got $ACTUAL_LINES lines"
            echo "==== EXPECTED OUTPUT ===="
            cat "$EXPECTED_OUTPUT"
            echo "==== ACTUAL OUTPUT ===="
            cat "$ACTUAL_OUTPUT"
            exit 1
        fi
    else
        echo "FAILED: Basic test - Files appear in wrong order"
        echo "test1.c should appear before test1.h"
        exit 1
    fi
else
    echo "FAILED: Basic test - Content does not match expected output"
    echo "Expected to find 'This is a C file' after test1.c and 'This is a header file' after test1.h"
    exit 1
fi
