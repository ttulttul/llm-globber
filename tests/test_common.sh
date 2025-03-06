#!/bin/bash
# Common test functions

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Path to the llm_globber executable
LLM_GLOBBER="../llm_globber"

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

# Function to check if the executable exists
check_executable() {
    if [ ! -f "$LLM_GLOBBER" ]; then
        echo -e "${RED}Error: llm_globber executable not found. Please compile it first.${NC}"
        echo "Run 'make' to compile the program."
        exit 1
    fi
}
