#!/bin/bash

# Test profiling functionality of LLM Globber
# This test runs the tool with xctrace to collect performance data

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

# Test case: Performance profiling
echo "Test case: Performance profiling with xctrace"

# Files to test
TEST_FILES="test_files/test1.c test_files/test1.h"

# Expected output: manually concatenate the files
EXPECTED_OUTPUT="test_output/expected_profile.txt"
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

# Create a timestamp for the trace file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TRACE_DIR="$OUTPUT_DIR/traces"
mkdir -p "$TRACE_DIR"
TRACE_FILE="$TRACE_DIR/llm_globber_profile_$TIMESTAMP.trace"

# Build the command to run
EXECUTABLE="../target/release/llm_globber"
ARGS="-o $OUTPUT_DIR -n profile_test -u -j 1 -v $(pwd)/test_files/test1.c $(pwd)/test_files/test1.h"

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

# Check if test1.c appears before test1.h in the output file
if grep -A 1 "test_files/test1.c" "$ACTUAL_OUTPUT" | grep -q "This is a C file" && \
   grep -A 1 "test_files/test1.h" "$ACTUAL_OUTPUT" | grep -q "This is a header file"; then
    # Now check the order: test1.c should come before test1.h
    C_LINE=$(grep -n "test_files/test1.c" "$ACTUAL_OUTPUT" | cut -d':' -f1)
    H_LINE=$(grep -n "test_files/test1.h" "$ACTUAL_OUTPUT" | cut -d':' -f1)
    
    if [ "$C_LINE" -lt "$H_LINE" ]; then
        # Check if line counts match
        if [ "$EXPECTED_LINES" -eq "$ACTUAL_LINES" ]; then
            echo "Profile test passed: Files appear in correct order and line counts match"
            echo "You can open the trace file in Instruments.app with:"
            echo "open \"$TRACE_FILE\""
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
        echo "FAILED: Profile test - Files appear in wrong order"
        echo "test1.c should appear before test1.h"
        exit 1
    fi
else
    echo "FAILED: Profile test - Content does not match expected output"
    echo "Expected to find 'This is a C file' after test1.c and 'This is a header file' after test1.h"
    exit 1
fi
