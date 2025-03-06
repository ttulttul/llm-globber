#!/bin/bash
# Common test functions

# Setup test environment
setup_test() {
  rm -rf output
  mkdir -p output
}

# Clean up test environment
cleanup_test() {
  rm -f verbose_output.txt quiet_output.txt default_output.txt
  rm -rf input
}
