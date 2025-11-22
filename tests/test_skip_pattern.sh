#!/bin/bash

# Test skip pattern filtering of LLM Globber
# Ensures files matching provided glob patterns are excluded from output

set -euo pipefail

mkdir -p test_output

TEST_DIR="skip_test_files"
mkdir -p "$TEST_DIR/subdir"

# Create deterministic test files
echo "keep this content" > "$TEST_DIR/keep_file.txt"
echo "ignore this log" > "$TEST_DIR/skip_me.log"
echo "nested keep" > "$TEST_DIR/subdir/nested_keep.rs"
echo "nested temp" > "$TEST_DIR/subdir/skip_me.tmp"

OUTPUT_DIR="$(pwd)/test_output"

echo "Running skip pattern test"
../target/release/llm_globber \
    -o "$OUTPUT_DIR" \
    -n skip_pattern_test \
    -r "$TEST_DIR" \
    --skip-pattern "*.log" \
    --skip-pattern "*.tmp"

ACTUAL_OUTPUT=$(ls -t test_output/skip_pattern_test_*.txt | head -1)

if [ -z "$ACTUAL_OUTPUT" ]; then
    echo "FAILED: No output file was generated"
    exit 1
fi

# Confirm skipped files are absent
if grep -q "skip_me.log" "$ACTUAL_OUTPUT" || grep -q "skip_me.tmp" "$ACTUAL_OUTPUT"; then
    echo "FAILED: Skip pattern test - skipped files present in output"
    exit 1
fi

# Ensure expected files remain
EXPECTED_HEADERS=2
ACTUAL_HEADERS=$(grep -c "^'''---" "$ACTUAL_OUTPUT")

if [ "$ACTUAL_HEADERS" -ne "$EXPECTED_HEADERS" ]; then
    echo "FAILED: Skip pattern test - expected $EXPECTED_HEADERS files, found $ACTUAL_HEADERS"
    exit 1
fi

if ! grep -q "keep_file.txt" "$ACTUAL_OUTPUT" || ! grep -q "nested_keep.rs" "$ACTUAL_OUTPUT"; then
    echo "FAILED: Skip pattern test - expected files missing from output"
    exit 1
fi

echo "Skip pattern test passed"
exit 0
