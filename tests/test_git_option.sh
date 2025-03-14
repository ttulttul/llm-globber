#!/bin/bash

# Test the --git option of LLM Globber
# This test creates a temporary git repository with test files
# and verifies that llm_globber can process it correctly

# Source common test functions
source "$(dirname "$0")/test_common.sh"

# Setup test environment
setup_test

# Check if git is installed
if ! command_exists git; then
    echo -e "${RED}Error: git is not installed. This test requires git.${NC}"
    exit 1
fi

# Create a temporary directory for the git repository
TEST_REPO="test_git_repo"
rm -rf "$TEST_REPO"
mkdir -p "$TEST_REPO"

# Initialize git repository
cd "$TEST_REPO" || exit 1
git init > /dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"

# Create some test files
echo "// This is a C file" > test.c
echo "int main() { return 0; }" >> test.c

echo "# This is a Python file" > test.py
echo "def main():" >> test.py
echo "    print('Hello, world!')" >> test.py

echo "# This is a README file" > README.md
echo "Test Git Repository" >> README.md

# Create a subdirectory with more files
mkdir -p "subdir"
echo "// Another C file in a subdirectory" > "subdir/another.c"
echo "void function() {}" >> "subdir/another.c"

# Add files to git
git add .
git commit -m "Initial commit" > /dev/null 2>&1

# Go back to the original directory
cd ..

# Path to output directory
OUTPUT_DIR="$(pwd)/output"
mkdir -p "$OUTPUT_DIR"

# Run llm_globber with --git option
print_header "Running llm_globber with --git option"
"$LLM_GLOBBER" --git "$TEST_REPO" -o "$OUTPUT_DIR" -v

# Check if the command was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: llm_globber failed with --git option${NC}"
    cleanup_test
    exit 1
fi

# Find the generated output file (most recent in the directory)
OUTPUT_FILE=$(ls -t "$OUTPUT_DIR"/test_git_repo_*.txt 2>/dev/null | head -1)

if [ -z "$OUTPUT_FILE" ]; then
    echo -e "${RED}Error: No output file was generated${NC}"
    cleanup_test
    exit 1
fi

# Check if the output file contains all the test files
print_header "Verifying output file contents"

# Function to check if a file is in the output
check_file_in_output() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    
    if grep -q "'''--- .*$file_name" "$OUTPUT_FILE"; then
        print_result "Found $file_name in output" true
        return 0
    else
        print_result "File $file_name not found in output" false
        return 1
    fi
}

# Check each test file
FAILED=0
check_file_in_output "$TEST_REPO/test.c" || FAILED=1
check_file_in_output "$TEST_REPO/test.py" || FAILED=1
check_file_in_output "$TEST_REPO/README.md" || FAILED=1
check_file_in_output "$TEST_REPO/subdir/another.c" || FAILED=1

# Clean up
print_header "Cleaning up"
rm -rf "$TEST_REPO"
cleanup_test

# Report results
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
