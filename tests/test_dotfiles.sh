#!/bin/bash

# Test dotfile detection and handling of LLM Globber
# This test checks if the tool correctly identifies and warns about dotfiles

# Create output directory
mkdir -p test_output

# Test case: Dotfile detection
echo "Test case: Dotfile detection"

# Create test directory with dotfiles
TEST_DIR="test_files/dotfiles"
mkdir -p "$TEST_DIR"

# Create test files
echo "Regular file content" > "$TEST_DIR/regular.txt"
echo "Dotfile content" > "$TEST_DIR/.dotfile"
echo "Hidden config content" > "$TEST_DIR/.config"

# Run llm_globber with all files option and recursive flag
OUTPUT_DIR="$(pwd)/test_output"
# Ensure the directory exists
mkdir -p "$OUTPUT_DIR"

# Capture both stdout and stderr
# Use -u flag to disable sandbox mode for testing
OUTPUT=$(../llm_globber -o "$OUTPUT_DIR" -n dotfile_test -a -r -u "$TEST_DIR" 2>&1)
echo "$OUTPUT"  # Display the output for debugging

# Check if warning was generated
if echo "$OUTPUT" | grep -q "WARNING: Including dot file"; then
    echo "✓ Dotfile warning detected"
    WARNING_TEST_PASSED=true
else
    echo "✗ FAILED: No dotfile warning detected"
    WARNING_TEST_PASSED=false
fi

# Find the generated output file
ACTUAL_OUTPUT=$(find "$OUTPUT_DIR" -name "dotfile_test_*.txt" -type f -print | sort -r | head -1)

if [ -z "$ACTUAL_OUTPUT" ]; then
    echo "Error: No output file was generated"
    ls -la "$OUTPUT_DIR"  # List directory contents for debugging
    exit 1
fi

echo "Found output file: $ACTUAL_OUTPUT"

# Check if the output file contains the dotfiles
DOTFILE_COUNT=$(grep -c "'''\-\-\- \.dotfile \-\-\-" "$ACTUAL_OUTPUT")
CONFIG_COUNT=$(grep -c "'''\-\-\- \.config \-\-\-" "$ACTUAL_OUTPUT")

if [ "$DOTFILE_COUNT" -eq 1 ] && [ "$CONFIG_COUNT" -eq 1 ]; then
    echo "✓ Dotfiles correctly included in output"
    CONTENT_TEST_PASSED=true
else
    echo "✗ FAILED: Dotfiles not correctly included in output"
    echo "Dotfile count: $DOTFILE_COUNT, Config count: $CONFIG_COUNT"
    CONTENT_TEST_PASSED=false
fi

# Clean up
rm -rf "$TEST_DIR"
rm -f "$OUTPUT_DIR/dotfile_test"*.txt

# Final result
if [ "$WARNING_TEST_PASSED" = true ] && [ "$CONTENT_TEST_PASSED" = true ]; then
    echo "Dotfile test passed: Warnings generated and content included"
    exit 0
else
    echo "Dotfile test failed"
    exit 1
fi
