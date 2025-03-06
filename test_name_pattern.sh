#!/bin/bash

# Test name pattern filtering of LLM Globber
# This test checks if the tool correctly filters files by name pattern

# Create output directory
mkdir -p test_output

# Test case: Name pattern filtering
echo "Test case: Name pattern filtering"

# Directory to test
TEST_DIR="test_files"

# Expected output: manually find and concatenate all files matching "test*.c"
EXPECTED_OUTPUT="test_output/expected_name_pattern.txt"
echo "*Local Files*" > $EXPECTED_OUTPUT

# Find all files matching the pattern
PATTERN_FILES=$(find $TEST_DIR -name "test*.c" | sort)

# Add each file to the expected output
for file in $PATTERN_FILES; do
    filename=$(basename "$file")
    echo "" >> $EXPECTED_OUTPUT
    echo "'''--- $filename ---" >> $EXPECTED_OUTPUT
    cat "$file" >> $EXPECTED_OUTPUT
    echo "" >> $EXPECTED_OUTPUT
    echo "'''" >> $EXPECTED_OUTPUT
done

# Run llm_globber with name pattern filter
./llm_globber -o test_output -n name_pattern_test -name "test*.c" -r $TEST_DIR

# Find the generated output file (most recent in the directory)
ACTUAL_OUTPUT=$(ls -t test_output/name_pattern_test_*.txt | head -1)

if [ -z "$ACTUAL_OUTPUT" ]; then
    echo "Error: No output file was generated"
    exit 1
fi

# Count the number of file headers in the output
EXPECTED_FILE_COUNT=$(grep -c "^'''\-\-\-" $EXPECTED_OUTPUT)
ACTUAL_FILE_COUNT=$(grep -c "^'''\-\-\-" $ACTUAL_OUTPUT)

if [ "$EXPECTED_FILE_COUNT" = "$ACTUAL_FILE_COUNT" ]; then
    # Check if all files match the pattern
    NON_MATCHING_FILES=$(grep "^'''\-\-\-" $ACTUAL_OUTPUT | grep -v "test.*\.c \-\-\-")
    
    if [ -z "$NON_MATCHING_FILES" ]; then
        echo "Name pattern test passed: Found $ACTUAL_FILE_COUNT matching files as expected"
        exit 0
    else
        echo "Name pattern test failed: Found files not matching the pattern"
        echo "$NON_MATCHING_FILES"
        exit 1
    fi
else
    echo "Name pattern test failed: Expected $EXPECTED_FILE_COUNT matching files, but found $ACTUAL_FILE_COUNT"
    echo "Expected files:"
    grep "^'''\-\-\-" $EXPECTED_OUTPUT
    echo "Actual files:"
    grep "^'''\-\-\-" $ACTUAL_OUTPUT
    exit 1
fi
