#!/bin/bash

# Test multi-threaded performance of LLM Globber
# This test creates many test files and measures processing time with different thread counts

# Create output directory
mkdir -p test_output

# Test case: Multi-threaded performance
echo "Test case: Multi-threaded performance"

# Create a temporary test directory with many files
TEST_DIR="test_output/threading_test_files"
mkdir -p "$TEST_DIR"

# Number of test files to create
NUM_FILES=100
FILE_SIZE=10000  # Characters per file

echo "Creating $NUM_FILES test files in $TEST_DIR..."

# Create test files
for i in $(seq 1 $NUM_FILES); do
    # Create a file with random content
    FILE_PATH="$TEST_DIR/test_file_$i.txt"
    head -c $FILE_SIZE /dev/urandom | tr -dc 'a-zA-Z0-9\n' > "$FILE_PATH"
done

echo "Created $NUM_FILES test files"

# Function to run test with specific thread count
run_thread_test() {
    local threads=$1
    local output_dir="$(pwd)/test_output"
    local test_name="threading_test_$threads"
    
    echo "Running test with $threads threads..."
    
    # Clear disk cache to ensure fair comparison (requires sudo)
    # Uncomment if you have sudo access and want more accurate results
    # echo "Clearing disk cache..."
    # sudo sh -c "sync && echo 3 > /proc/sys/vm/drop_caches"
    
    # Time the execution
    start_time=$(date +%s.%N)
    
    # Run llm_globber with specified thread count
    ../llm_globber -o "$output_dir" -n "$test_name" -t .txt -r -j "$threads" -u "$TEST_DIR"
    
    end_time=$(date +%s.%N)
    execution_time=$(echo "$end_time - $start_time" | bc)
    
    echo "Execution time with $threads threads: $execution_time seconds"
    return 0
}

# Run tests with different thread counts
echo "Starting performance tests..."

# Single-threaded test
run_thread_test 1

# Multi-threaded tests
run_thread_test 2
run_thread_test 4
run_thread_test 8

# If available, test with number of CPU cores
CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
if [ "$CPU_CORES" -gt 8 ]; then
    run_thread_test "$CPU_CORES"
fi

# Clean up
echo "Cleaning up test files..."
rm -rf "$TEST_DIR"

echo "Threading performance test completed"
exit 0
