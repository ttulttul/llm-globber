#!/bin/bash

# Test file type filtering of LLM Globber
# This test checks if the tool correctly filters files by extension

# Create output directory
mkdir -p test_output

# Test case: File type filtering
echo "Test case: File type filtering"

# Directory to test
TEST_DIR="test_files"

# Expected output: manually find and concatenate all .h files
EXPECTED_OUTPUT="test_output/expected_file_types.txt"
echo "" > $EXPECTED_OUTPUT

# Find all .h files in the test directory (non-recursively)
H_FILES=$(find $TEST_DIR -maxdepth 1 -name "*.h")

# Add each file to the expected output
for file in $H_FILES; do
    filename=$(basename "$file")
    echo "" >> $EXPECTED_OUTPUT
    echo "'''--- $filename ---" >> $EXPECTED_OUTPUT
    cat "$file" >> $EXPECTED_OUTPUT
    echo "" >> $EXPECTED_OUTPUT
    echo "'''" >> $EXPECTED_OUTPUT
done

# Run llm_globber with file type filter
OUTPUT_DIR="$(pwd)/test_output"
echo "Using output directory: $OUTPUT_DIR"
# Ensure the directory exists
mkdir -p "$OUTPUT_DIR"
# Run with individual .h files instead of directory
# Use -u flag to disable sandbox mode for testing
echo "Running: ../target/release/llm_globber -o $OUTPUT_DIR -n file_types_test -t .h -u $H_FILES"
../target/release/llm_globber -o "$OUTPUT_DIR" -n file_types_test -t .h -u $H_FILES

# Find the generated output file (most recent in the directory)
ACTUAL_OUTPUT=$(ls -t test_output/file_types_test_*.txt | head -1)

if [ -z "$ACTUAL_OUTPUT" ]; then
    echo "Error: No output file was generated"
    exit 1
fi

# Count the number of file headers in the output
EXPECTED_FILE_COUNT=$(grep -c "^'''\-\-\-" $EXPECTED_OUTPUT)
ACTUAL_FILE_COUNT=$(grep -c "^'''\-\-\-" $ACTUAL_OUTPUT)

if [ "$EXPECTED_FILE_COUNT" = "$ACTUAL_FILE_COUNT" ]; then
    # Check if all files are .h files
    NON_H_FILES=$(grep "^'''\-\-\-" $ACTUAL_OUTPUT | grep -v "\.h \-\-\-")
    
    if [ -z "$NON_H_FILES" ]; then
        echo "File types test passed: Found $ACTUAL_FILE_COUNT .h files as expected"
        exit 0
    else
        echo "FAILED: File types test - Found non-.h files in the output"
        echo "$NON_H_FILES"
        exit 1
    fi
else
    echo "FAILED: File types test - Expected $EXPECTED_FILE_COUNT .h files, but found $ACTUAL_FILE_COUNT"
    exit 1
fi
