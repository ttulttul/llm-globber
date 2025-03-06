#!/bin/bash

# Test multi-threaded performance of LLM Globber
# This test creates many test files and measures processing time with different thread counts

# Source common test functions
source "$(dirname "$0")/test_common.sh"

# Check if llm_globber executable exists
check_executable

# Create output directory
mkdir -p test_output

# Test case: Multi-threaded performance
echo "Test case: Multi-threaded performance"

# Create a temporary test directory with many files
TEST_DIR="test_output/threading_test_files"
mkdir -p "$TEST_DIR"

# Number of test files to create
NUM_FILES=50  # Reduced for faster test runs
FILE_SIZE=5000  # Characters per file

echo "Creating $NUM_FILES test files in $TEST_DIR..."

# Create test files
for i in $(seq 1 $NUM_FILES); do
    # Create a file with random content
    FILE_PATH="$TEST_DIR/test_file_$i.txt"
    head -c $FILE_SIZE /dev/urandom | tr -dc 'a-zA-Z0-9\n' > "$FILE_PATH"
done

echo "Created $NUM_FILES test files"

# Array to store execution times
declare -a TIMES
declare -a THREAD_COUNTS=(1 2 4)

# Function to run test with specific thread count
run_thread_test() {
    local threads=$1
    local output_dir="$(pwd)/test_output"
    local test_name="threading_test_$threads"
    
    echo "Running test with $threads threads..."
    
    # Time the execution
    start_time=$(date +%s.%N)
    
    # Run llm_globber with specified thread count
    $LLM_GLOBBER -o "$output_dir" -n "$test_name" -t .txt -r -j "$threads" -u "$TEST_DIR" > /dev/null 2>&1
    
    end_time=$(date +%s.%N)
    execution_time=$(echo "$end_time - $start_time" | bc)
    
    echo "Execution time with $threads threads: $execution_time seconds"
    TIMES[$threads]=$execution_time
    
    # Verify the output file exists and contains the expected number of files
    local output_file=$(find "$output_dir" -name "${test_name}_*.txt" -type f -print | sort -r | head -1)
    if [ -z "$output_file" ]; then
        echo -e "${RED}FAILED: No output file generated for thread count $threads${NC}"
        return 1
    fi
    
    local file_count=$(grep -c "^'''\-\-\-" "$output_file")
    if [ "$file_count" -ne "$NUM_FILES" ]; then
        echo -e "${RED}FAILED: Expected $NUM_FILES files, but found $file_count in output${NC}"
        return 1
    fi
    
    return 0
}

# Run tests with different thread counts
echo "Starting performance tests..."

# Run tests with increasing thread counts
TEST_PASSED=true
for threads in "${THREAD_COUNTS[@]}"; do
    if ! run_thread_test $threads; then
        TEST_PASSED=false
    fi
done

# Check if multi-threading provides performance improvement
if [ "${#TIMES[@]}" -ge 2 ] && [ -n "${TIMES[1]}" ] && [ -n "${TIMES[4]}" ]; then
    speedup=$(echo "${TIMES[1]} / ${TIMES[4]}" | bc -l)
    echo "Speedup with 4 threads vs 1 thread: $speedup"
    
    # Expect at least some speedup (1.2x) with 4 threads
    if (( $(echo "$speedup > 1.2" | bc -l) )); then
        echo -e "${GREEN}✓ Multi-threading provides performance improvement${NC}"
    else
        echo -e "${RED}✗ Multi-threading does not provide significant performance improvement${NC}"
        # Don't fail the test for this, as performance can vary by system
        echo "This is not a test failure, just an observation."
    fi
fi

# Clean up
echo "Cleaning up test files..."
rm -rf "$TEST_DIR"

if [ "$TEST_PASSED" = true ]; then
    echo -e "${GREEN}Threading performance test completed successfully${NC}"
    exit 0
else
    echo -e "${RED}Threading performance test failed${NC}"
    exit 1
fi
