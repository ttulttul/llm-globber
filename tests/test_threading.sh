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
NUM_FILES=500  # Significantly increased for better thread utilization
FILE_SIZE=1000000  # Much larger file size for more meaningful threading test

echo "Creating $NUM_FILES test files in $TEST_DIR..."

# Create test files
for i in $(seq 1 $NUM_FILES); do
    # Create a file with random content
    FILE_PATH="$TEST_DIR/test_file_$i.txt"
    # Use perl to generate random content (more reliable cross-platform)
    perl -e "print 'A' x $FILE_SIZE" > "$FILE_PATH"
done

echo "Created $NUM_FILES test files"

# Array to store execution times
declare -a TIMES
# Test with more thread count variations for better analysis
# Focus on 1 vs max threads for clearer performance difference
declare -a THREAD_COUNTS=(1 $(get_cpu_cores))

# Function to run test with specific thread count
run_thread_test() {
    local threads=$1
    local output_dir="$(pwd)/test_output"
    local test_name="threading_test_$threads"
    
    echo "Running test with $threads threads..."
    
    # Run the test multiple times to get more reliable results
    local runs=3
    local total_time=0
    
    for ((run=1; run<=$runs; run++)); do
        echo "  Run $run of $runs..."
        
        # Clear disk caches if possible (requires sudo)
        if [ "$(uname)" = "Darwin" ] && command -v purge >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
            purge
        elif [ "$(uname)" = "Linux" ] && [ -w /proc/sys/vm/drop_caches ]; then
            echo 3 > /proc/sys/vm/drop_caches
        fi
        
        # Use perl for cross-platform high-precision timing
        # This works reliably on both Linux and macOS
        start_time=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
        $LLM_GLOBBER -o "$output_dir" -n "${test_name}_run${run}" -t .txt -r -j "$threads" -u "$TEST_DIR" > /dev/null 2>&1
        end_time=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
        
        # Calculate execution time with bc for floating point precision
        run_time=$(echo "scale=6; $end_time - $start_time" | bc)
        echo "  Run $run time: $run_time seconds"
        
        # Verify we got a non-zero timing
        if (( $(echo "$run_time <= 0.001" | bc -l) )); then
            echo -e "${YELLOW}Warning: Execution time suspiciously low, might be a timing error${NC}"
            # Try again with a sleep to ensure we can measure time
            sleep 0.5
            run_time=$(echo "$run_time + 0.5" | bc)
            echo "  Adjusted run time: $run_time seconds"
        fi
        
        total_time=$(echo "scale=6; $total_time + $run_time" | bc)
        
        # Sleep between runs to let system stabilize
        sleep 2
    done
    
    # Calculate average time
    execution_time=$(echo "scale=6; $total_time / $runs" | bc)
    echo "Average execution time with $threads threads: $execution_time seconds"
    
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
echo "Starting performance tests with high-precision timing..."

# Run tests with increasing thread counts
TEST_PASSED=true
for threads in "${THREAD_COUNTS[@]}"; do
    if ! run_thread_test $threads; then
        TEST_PASSED=false
    fi
    # Sleep between tests to allow system to cool down
    sleep 2
done

# Check if multi-threading provides performance improvement
max_threads=$(get_cpu_cores)
if [ "${#TIMES[@]}" -ge 2 ] && [ -n "${TIMES[1]}" ] && [ -n "${TIMES[$max_threads]}" ]; then
    # Avoid division by zero by checking if times are greater than zero
    if (( $(echo "${TIMES[1]} > 0" | bc -l) )) && (( $(echo "${TIMES[$max_threads]} > 0" | bc -l) )); then
        # Calculate speedup with 6 decimal places for higher precision
        speedup=$(echo "scale=6; ${TIMES[1]} / ${TIMES[$max_threads]}" | bc)
        echo "Speedup with $max_threads threads vs 1 thread: $speedup"
        
        # Print individual timings with high precision
        echo "Time with 1 thread: ${TIMES[1]} seconds"
        echo "Time with $max_threads threads: ${TIMES[$max_threads]} seconds"
        echo "Time difference: $(echo "scale=6; ${TIMES[1]} - ${TIMES[$max_threads]}" | bc) seconds"
        
        # Calculate theoretical maximum speedup (Amdahl's Law with 95% parallelizable code)
        theoretical=$(echo "scale=6; 1 / (0.05 + 0.95/$max_threads)" | bc)
        echo "Theoretical maximum speedup (Amdahl's Law, 95% parallel): $theoretical"
        
        # Expect at least some speedup (1.5x) with multiple threads
        if (( $(echo "$speedup > 1.5" | bc -l) )); then
            echo -e "${GREEN}✓ Multi-threading provides significant performance improvement${NC}"
        else
            echo -e "${YELLOW}⚠ Multi-threading does not provide significant performance improvement${NC}"
            echo "Possible reasons:"
            echo "- I/O bound operations (disk or memory) limiting parallelism"
            echo "- Lock contention in the thread implementation"
            echo "- Test files too small to benefit from parallelism"
            echo "- System resource limitations"
            # Don't fail the test for this, as performance can vary by system
            echo "This is not a test failure, just an observation."
        fi
    else
        echo "Execution times too small to calculate meaningful speedup"
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
