#!/bin/bash
# Common test functions

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Path to the llm_globber executable
LLM_GLOBBER="../target/release/llm_globber"

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get number of CPU cores
get_cpu_cores() {
    if command_exists nproc; then
        nproc
    elif [ -f /proc/cpuinfo ]; then
        grep -c ^processor /proc/cpuinfo
    elif command_exists sysctl && sysctl -n hw.ncpu >/dev/null 2>&1; then
        sysctl -n hw.ncpu
    else
        echo 4  # Default if we can't detect
    fi
}

# Function to print section header
print_header() {
    echo -e "\n${BLUE}===== $1 =====${NC}"
}

# Function to print test result
print_result() {
    if [ "$2" = "true" ] || [ "$2" = "0" ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
    fi
}
