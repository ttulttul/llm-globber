#!/bin/bash
# Test verbose and quiet modes

# Source common test functions
source "$(dirname "$0")/test_common.sh"

echo "Testing verbose and quiet modes..."

# Setup
setup_test
mkdir -p input
echo "Test content" > input/test.txt

# Test verbose mode
echo "Testing verbose mode..."
../llm_globber -o output -n verbose_test -v input/test.txt > verbose_output.txt 2>&1
if ! grep -q "INFO:" verbose_output.txt; then
  echo "FAIL: Verbose mode should show INFO messages"
  exit 1
fi
if ! grep -q "DEBUG:" verbose_output.txt; then
  echo "FAIL: Verbose mode should show DEBUG messages"
  exit 1
fi
echo "Verbose mode test passed"

# Test quiet mode
echo "Testing quiet mode..."
../llm_globber -o output -n quiet_test -q input/test.txt > quiet_output.txt 2>&1
if [ -s quiet_output.txt ]; then
  echo "FAIL: Quiet mode should not produce any output"
  cat quiet_output.txt
  exit 1
fi
echo "Quiet mode test passed"

# Test default mode (should show warnings and errors, but not info or debug)
echo "Testing default mode..."
../llm_globber -o output -n default_test input/test.txt > default_output.txt 2>&1
if grep -q "INFO:" default_output.txt; then
  echo "FAIL: Default mode should not show INFO messages"
  exit 1
fi
if grep -q "DEBUG:" default_output.txt; then
  echo "FAIL: Default mode should not show DEBUG messages"
  exit 1
fi
echo "Default mode test passed"

# Clean up
cleanup_test

echo "All verbose and quiet mode tests passed!"
exit 0
