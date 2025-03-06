#!/bin/bash

# Test basic functionality of LLM Globber
# This test checks if the tool correctly processes specified files

# Create output directory
mkdir -p test_output

# Test case: Basic file processing
echo "Test case: Basic file processing"

# Files to test
TEST_FILES="test_files/test1.c test_files/test1.h"

# Expected output: manually concatenate the files
EXPECTED_OUTPUT="test_output/expected_basic.txt"
echo "*Local Files*" > $EXPECTED_OUTPUT
echo "" >> $EXPECTED_OUTPUT
echo "'''--- test1.c ---" >> $EXPECTED_OUTPUT
cat test_files/test1.c >> $EXPECTED_OUTPUT
echo "" >> $EXPECTED_OUTPUT
echo "'''" >> $EXPECTED_OUTPUT
echo "" >> $EXPECTED_OUTPUT
echo "'''--- test1.h ---" >> $EXPECTED_OUTPUT
cat test_files/test1.h >> $EXPECTED_OUTPUT
echo "" >> $EXPECTED_OUTPUT
echo "'''" >> $EXPECTED_OUTPUT

# Run llm_globber
./llm_globber -o test_output -n basic_test $TEST_FILES

# Find the generated output file (most recent in the directory)
ACTUAL_OUTPUT=$(ls -t test_output/basic_test_*.txt | head -1)

if [ -z "$ACTUAL_OUTPUT" ]; then
    echo "Error: No output file was generated"
    exit 1
fi

# Compare content (ignoring timestamps in filenames)
EXPECTED_CONTENT=$(grep -v "^'''\-\-\-" $EXPECTED_OUTPUT | tr -d '\n')
ACTUAL_CONTENT=$(grep -v "^'''\-\-\-" $ACTUAL_OUTPUT | tr -d '\n')

if [ "$EXPECTED_CONTENT" = "$ACTUAL_CONTENT" ]; then
    echo "Basic test passed: Content matches expected output"
    exit 0
else
    echo "Basic test failed: Content does not match expected output"
    echo "Expected content (without filenames):"
    echo "$EXPECTED_CONTENT"
    echo "Actual content (without filenames):"
    echo "$ACTUAL_CONTENT"
    exit 1
fi
