#!/bin/bash

# Test the unglob functionality of LLM Globber
# This test checks if the tool correctly extracts files from a previously generated output

set -e  # Exit on any error

# Create output directory and ensure test files directory exists
mkdir -p test_output
mkdir -p test_files

# Clean up any previous test files
rm -f test_files/unglob_test*.txt
rm -f test_output/unglob_test_*.txt

# Create test files with different content
echo "This is test file 1" > test_files/unglob_test1.txt
echo "This is test file 2 with more content" > test_files/unglob_test2.txt
echo "This is test file 3 with even more content than the others" > test_files/unglob_test3.txt

# Create a subdirectory with a file
mkdir -p test_files/subdir
echo "This is a file in a subdirectory" > test_files/subdir/unglob_test4.txt

# For robustness, manually create a listing of the files that will be globbed
FILES_TO_GLOB="test_files/unglob_test1.txt test_files/unglob_test2.txt test_files/unglob_test3.txt test_files/subdir/unglob_test4.txt"

echo "Test case: Unglob functionality"

# Step 1: Run llm_globber to create a globbed file
OUTPUT_DIR="$(pwd)/test_output"
echo "Using output directory: $OUTPUT_DIR"

echo "Running: ../target/release/llm_globber -o \"$OUTPUT_DIR\" -n unglob_test -v $FILES_TO_GLOB"
../target/release/llm_globber -o "$OUTPUT_DIR" -n unglob_test -v $FILES_TO_GLOB

# Find the generated output file
GLOBBED_FILE=$(ls -t test_output/unglob_test_*.txt | head -1)

if [ -z "$GLOBBED_FILE" ]; then
    echo "Error: No output file was generated"
    exit 1
fi

echo "Created globbed file: $GLOBBED_FILE"

# Step 2: Save original file checksums
echo "Calculating checksums of original files..."
ORIGINAL_CHECKSUMS=$(find test_files -type f -name "unglob_test*.txt" -o -path "*/subdir/*" | sort | xargs md5sum)
echo "$ORIGINAL_CHECKSUMS"

# Step 3: Move original files to backup
echo "Moving original files to backup..."
mkdir -p test_files_backup
cp -r test_files/* test_files_backup/
rm -f test_files/unglob_test*.txt
rm -rf test_files/subdir

# Create a directory structure that matches the expected output
mkdir -p test_files

# Step 4: Run unglob to extract files
echo "Running unglob to extract files..."
echo "Command: ../target/release/llm_globber -u $GLOBBED_FILE -o test_files -v"
../target/release/llm_globber -u "$GLOBBED_FILE" -o test_files -v

# Debug: Show the content of the globbed file
echo "Debug: Content of globbed file:"
head -n 20 "$GLOBBED_FILE"

# Step 5: Verify extracted files
echo "Verifying extracted files..."
# Use find with -not -path to exclude any nested test_files directories
EXTRACTED_CHECKSUMS=$(find test_files -type f \( -name "unglob_test*.txt" -o -path "*/subdir/*" \) -not -path "*/test_files/test_files/*" | sort | xargs md5sum)
echo "$EXTRACTED_CHECKSUMS"

# Compare checksums
if [ "$ORIGINAL_CHECKSUMS" = "$EXTRACTED_CHECKSUMS" ]; then
    echo "SUCCESS: All files were correctly extracted with matching content"
else
    echo "FAILURE: Extracted files do not match original files"
    echo "Original checksums:"
    echo "$ORIGINAL_CHECKSUMS"
    echo "Extracted checksums:"
    echo "$EXTRACTED_CHECKSUMS"
    exit 1
fi
