#!/bin/bash
# Test verbose and quiet modes

# Create output directory
mkdir -p test_output

# Test case: Verbose and quiet modes
echo "Test case: Verbose and quiet modes"

# Create test directory with a file
TEST_DIR="test_files/verbose_quiet"
mkdir -p "$TEST_DIR"
echo "Test content" > "$TEST_DIR/test.txt"

# Run llm_globber in verbose mode
OUTPUT_DIR="$(pwd)/test_output"
mkdir -p "$OUTPUT_DIR"

echo "Testing verbose mode..."
../llm_globber -o "$OUTPUT_DIR" -n verbose_test -v "$TEST_DIR/test.txt" 2> verbose_output.txt

# Check if verbose output contains INFO and DEBUG messages
if grep -q "INFO:" verbose_output.txt; then
  echo "✓ Verbose mode shows INFO messages"
  INFO_TEST_PASSED=true
else
  echo "✗ FAILED: Verbose mode should show INFO messages"
  cat verbose_output.txt
  INFO_TEST_PASSED=false
fi

# Run llm_globber in quiet mode
echo "Testing quiet mode..."
../llm_globber -o "$OUTPUT_DIR" -n quiet_test -q "$TEST_DIR/test.txt" 2> quiet_output.txt

# Check if quiet mode suppresses all output
if [ -s quiet_output.txt ]; then
  echo "✗ FAILED: Quiet mode should not produce any output"
  cat quiet_output.txt
  QUIET_TEST_PASSED=false
else
  echo "✓ Quiet mode suppresses all output"
  QUIET_TEST_PASSED=true
fi

# Run llm_globber in default mode
echo "Testing default mode..."
../llm_globber -o "$OUTPUT_DIR" -n default_test "$TEST_DIR/test.txt" 2> default_output.txt

# Check if default mode shows only warnings and errors
DEFAULT_TEST_PASSED=true
if grep -q "INFO:" default_output.txt; then
  echo "✗ FAILED: Default mode should not show INFO messages"
  DEFAULT_TEST_PASSED=false
fi
if grep -q "DEBUG:" default_output.txt; then
  echo "✗ FAILED: Default mode should not show DEBUG messages"
  DEFAULT_TEST_PASSED=false
fi
if [ "$DEFAULT_TEST_PASSED" = true ]; then
  echo "✓ Default mode correctly shows only warnings and errors"
fi

# Clean up
rm -rf "$TEST_DIR"
rm -f "$OUTPUT_DIR/verbose_test"*.txt "$OUTPUT_DIR/quiet_test"*.txt "$OUTPUT_DIR/default_test"*.txt
rm -f verbose_output.txt quiet_output.txt default_output.txt

# Final result
if [ "$INFO_TEST_PASSED" = true ] && [ "$QUIET_TEST_PASSED" = true ] && [ "$DEFAULT_TEST_PASSED" = true ]; then
  echo "All verbose and quiet mode tests passed!"
  exit 0
else
  echo "Some verbose and quiet mode tests failed"
  exit 1
fi
