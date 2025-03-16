#!/bin/bash

# Test the signature functionality of LLM Globber
# This test checks if the tool correctly signs files when globbing and verifies signatures when unglobbing

set -e  # Exit on any error

# For robustness, manually create a listing of the files that will be globbed
FILES_TO_GLOB="test_files/sig_test1.txt test_files/sig_test2.txt test_files/sig_test3.txt test_files/subdir/sig_test4.txt"
LLM_GLOBBER="../target/release/llm_globber"

# Create output directory and ensure test files directory exists
mkdir -p test_output
mkdir -p test_files

# Clean up any previous test files
rm -f $FILES_TO_GLOB

# Create test files with different content
echo "This is signature test file 1" > test_files/sig_test1.txt
echo "This is signature test file 2 with more content" > test_files/sig_test2.txt
echo "This is signature test file 3 with even more content than the others" > test_files/sig_test3.txt

# Create a subdirectory with a file
mkdir -p test_files/subdir
echo "This is a signature test file in a subdirectory" > test_files/subdir/sig_test4.txt

echo "Test case: Signature functionality"

# Step 1: Run llm_globber to create a globbed file with signatures
OUTPUT_DIR="$(pwd)/test_output"
echo "Using output directory: $OUTPUT_DIR"

echo "Running: $LLM_GLOBBER -o \"$OUTPUT_DIR\" -n sig_test -v --signature $FILES_TO_GLOB"
$LLM_GLOBBER -o "$OUTPUT_DIR" -n sig_test -v --signature $FILES_TO_GLOB

# Find the generated output file
GLOBBED_FILE=$(ls -t test_output/sig_test_*.txt | head -1)

if [ -z "$GLOBBED_FILE" ]; then
    echo "Error: No output file was generated"
    exit 1
fi

echo "Created globbed file with signatures: $GLOBBED_FILE"

# Check that the globbed file starts with a public key
# Read the first line of the file
read -r first_line < "$GLOBBED_FILE"

# Check if the first line matches the exact header pattern
if [[ ! "$first_line" =~ ^\'\'\'---\ PUBLIC_KEY\ ---\ \[KEY:[A-Za-z0-9+/]+={0,2}\]$ ]]; then
  echo "Error: File header does not match expected public key header." >&2
  exit 1
fi

# Step 2: Save original file checksums
echo "Calculating checksums of original files..."
ORIGINAL_CHECKSUMS=$(md5sum $FILES_TO_GLOB)
echo "$ORIGINAL_CHECKSUMS"

# Step 3: Move original files to backup
echo "Moving original files to backup..."
mkdir -p test_files_backup_sig
mv $FILES_TO_GLOB test_files_backup_sig

# Ensure the test_files directory hasn't gotten whacked somehow
if [[ -d "test_files" && -r "test_files" ]]; then
    echo "Directory 'test_files' exists and is readable."
else
    echo "Error: 'test_files' directory is missing or not readable."
    exit 1
fi

# Step 4: Run unglob to extract files with signature verification
echo "Running unglob to extract files with signature verification..."
echo "Command: ../target/release/llm_globber -u $GLOBBED_FILE -o test_files -v --signature"
$LLM_GLOBBER -u "$GLOBBED_FILE" -o test_files -v --signature

# Step 5: Verify extracted files
echo "Verifying extracted files..."
EXTRACTED_CHECKSUMS=$(md5sum $FILES_TO_GLOB)
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

# Step 6: Test tampering detection
echo "Testing tampering detection..."

# Create a tampered version of the globbed file
TAMPERED_FILE="${GLOBBED_FILE}.tampered"
cp "$GLOBBED_FILE" "$TAMPERED_FILE"

# Tamper with the content of one file in the globbed file
if grep -q "This is signature test file 2" "$TAMPERED_FILE"; then
    # Read the file into a variable
    file_contents=$(<"$TAMPERED_FILE")
    # Replace all occurrences (use single slash for first occurrence only)
    file_contents="${file_contents//This is signature test file 2/This is TAMPERED signature test file 2}"
    # Write the modified contents back to the file
    printf "%s" "$file_contents" > "$TAMPERED_FILE"
else
    echo "FAILURE: Couldn't tamper with the file because it did not contain the right content."
    exit 1
fi

# Clean up extracted files
rm $FILES_TO_GLOB

# Try to unglob the tampered file
echo "Command: $LLM_GLOBBER -u $TAMPERED_FILE -o test_files -v --signature"
if $LLM_GLOBBER -u "$TAMPERED_FILE" -o test_files -v --signature; then
    echo "FAILURE: Tampering was not detected!"
    exit 1
else
    echo "SUCCESS: Tampering was correctly detected"
fi

echo "All signature tests passed successfully!"
