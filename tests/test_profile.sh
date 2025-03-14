#!/bin/bash

# Test profiling functionality of LLM Globber
# This test runs the tool with xctrace to collect performance data

# Create output directory and ensure test files directory exists
mkdir -p test_output
mkdir -p test_files

# Generate large test files for better profiling
echo "Generating large test files for profiling..."

# Function to generate a large file with repeated content - much faster version
generate_large_file() {
    local filename=$1
    local size_mb=$2
    local template=$3
    
    echo "Generating $filename ($size_mb MB)..."
    
    # Create a small header with the template and some code-like content
    {
        echo "$template"
        echo "/* File: $filename */"
        echo "/* Generated for profiling tests */"
        echo ""
        echo "#include <stdio.h>"
        echo "#include <stdlib.h>"
        echo ""
        echo "void function_example() {"
        echo "    int x = 42;"
        echo "    for (int i = 0; i < 1000; i++) {"
        echo "        x += i * 42;"
        echo "    }"
        echo "    return x;"
        echo "}"
        echo ""
        # Add some unique content to prevent compression
        date +"%Y-%m-%d %H:%M:%S.%N"
        echo ""
    } > "$filename"
    
    # Use dd to quickly generate a large file by creating a block of zeros
    # bs=1M means 1 megabyte blocks, count is the number of blocks
    # We subtract 1 from size_mb because we already wrote a small header
    dd if=/dev/zero bs=1M count=$((size_mb - 1)) >> "$filename" 2>/dev/null
    
    # Get actual file size
    local actual_size=$(du -m "$filename" | cut -f1)
    echo "Created $filename: $actual_size MB"
}

# Create test files directory if it doesn't exist
mkdir -p test_files

# Generate large C and header files (10MB and 5MB)
generate_large_file "test_files/test1.c" 10 "/* This is a large C file for profiling */"
generate_large_file "test_files/test1.h" 5 "/* This is a large header file for profiling */"

# Generate additional files to increase processing load
generate_large_file "test_files/extra1.c" 8 "/* Extra C file 1 */"
generate_large_file "test_files/extra2.c" 8 "/* Extra C file 2 */"
generate_large_file "test_files/utils.h" 4 "/* Utility header file */"

# Test case: Performance profiling
echo "Test case: Performance profiling with xctrace"

# Files to test - include all generated files for more processing
TEST_FILES="test_files/test1.c test_files/test1.h test_files/extra1.c test_files/extra2.c test_files/utils.h"

# Expected output: create a simplified expected output
# We won't include the full file contents since they're large
EXPECTED_OUTPUT="test_output/expected_profile.txt"
echo "" > $EXPECTED_OUTPUT

# Add headers for each file but not the full content (too large)
for file in $TEST_FILES; do
    echo "'''--- $(pwd)/$file ---" >> $EXPECTED_OUTPUT
    # Just add the first line of each file as a marker
    head -n 1 "$file" >> $EXPECTED_OUTPUT
    echo "[... large file content omitted for test ...]" >> $EXPECTED_OUTPUT
    echo "" >> $EXPECTED_OUTPUT
    echo "'''" >> $EXPECTED_OUTPUT
    echo "" >> $EXPECTED_OUTPUT
done

# Run llm_globber with absolute path to ensure it works
OUTPUT_DIR="$(pwd)/test_output"
echo "Using output directory: $OUTPUT_DIR"
# Ensure the directory exists
mkdir -p "$OUTPUT_DIR"

# Create a timestamp for the trace file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TRACE_DIR="$OUTPUT_DIR/traces"
mkdir -p "$TRACE_DIR"
TRACE_FILE="$TRACE_DIR/llm_globber_profile_$TIMESTAMP.trace"

# Build the command to run
EXECUTABLE="../target/release/llm_globber"
ARGS="-o $OUTPUT_DIR -n profile_test -u -j 1 -v $TEST_FILES"

echo "Running xctrace with Time Profiler template on: $EXECUTABLE $ARGS"
# Run with xcrun xctrace to collect performance data
xcrun xctrace record --template "Time Profiler" --output "$TRACE_FILE" --launch -- "$EXECUTABLE" $ARGS

# Check if xctrace was successful
if [ $? -ne 0 ]; then
    echo "Error: xctrace failed to run"
    exit 1
fi

echo "Performance trace saved to: $TRACE_FILE"

# Find the generated output file (most recent in the directory)
ACTUAL_OUTPUT=$(ls -t test_output/profile_test_*.txt | head -1)

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

# Check if all files appear in the output
echo "Checking output file for all test files..."
all_files_found=true

for file in $TEST_FILES; do
    if ! grep -q "$file" "$ACTUAL_OUTPUT"; then
        echo "FAILED: File $file not found in output"
        all_files_found=false
    fi
done

if [ "$all_files_found" = true ]; then
    # Check if test1.c appears before test1.h (basic order check)
    C_LINE=$(grep -n "test_files/test1.c" "$ACTUAL_OUTPUT" | head -1 | cut -d':' -f1)
    H_LINE=$(grep -n "test_files/test1.h" "$ACTUAL_OUTPUT" | head -1 | cut -d':' -f1)
    
    if [ -z "$C_LINE" ] || [ -z "$H_LINE" ]; then
        echo "FAILED: Couldn't find line numbers for test files"
        exit 1
    fi
    
    if [ "$C_LINE" -lt "$H_LINE" ]; then
        echo "Profile test passed: Files processed successfully"
        echo "Trace file size: $(du -h "$TRACE_FILE" | cut -f1)"
        echo "You can open the trace file in Instruments.app with:"
        echo "open \"$TRACE_FILE\""
        exit 0
    else
        echo "FAILED: Profile test - Files appear in wrong order"
        echo "test1.c should appear before test1.h"
        exit 1
    fi
else
    echo "FAILED: Not all test files were found in the output"
    exit 1
fi
