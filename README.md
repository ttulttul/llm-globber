# LLM Globber

LLM Globber is a command-line utility written in Rust for collecting files from various locations, filtering them, and outputting their contents to a single text file. This tool is designed to prepare local files for analysis by Language Learning Models (LLMs).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Features

- **Collect Files:** Gathers files from specified directories and file paths.
- **File Type Filtering:** Includes or excludes files based on comma-separated file type extensions (e.g., `.c,.h,.txt`).
- **Name Pattern Filtering:** Filters files based on glob patterns in their names (e.g., `*.config*`).
- **Recursive Directory Processing:** Traverses directories recursively to find files.
- **Binary File Handling:** Detects binary files and omits their content from the output, noting them as binary.
- **Dot File Handling:** Option to include or exclude dot files (hidden files).
- **File Size Limit:** Skips files exceeding a specified maximum size.
- **Progress Indication:** Shows progress during file processing.
- **Verbose and Quiet Modes:** Controls the verbosity of output logging.
- **Error Handling:** Robust error handling with options to abort on error or continue.
- **Output Cleanup:** Reduces excessive newlines in the output file for cleaner text.
- **Secure File Handling:** Uses secure file permissions for output files and sanitizes input paths.
- **Efficient I/O:** Employs buffered I/O and memory mapping for performance.

## Installation

Ensure you have Rust installed. If not, follow the instructions at [https://rust-lang.org/tools/install](https://rust-lang.org/tools/install).

To build and install `llm_globber`, use Cargo, Rust's package manager:

```bash
cargo build --release
```

This command builds an optimized executable in the target/release/ directory.

For easier access, you can copy the executable to a directory in your system's PATH, such as /usr/local/bin/ or ~/.local/bin/:

```bash
sudo cp target/release/llm_globber /usr/local/bin/
# or
mkdir -p ~/.local/bin
cp target/release/llm_globber ~/.local/bin
export PATH="$HOME/.local/bin:$PATH" # Add to your shell config file (e.g., .bashrc, .zshrc)
```

Alternatively, you can use cargo install to build and install the binary in ~/.cargo/bin (make sure ~/.cargo/bin is in your PATH):

```bash
cargo install --path .
```

## Usage

```
llm_globber 0.1.0
Ken Simpson
Collects and formats files for LLMs

USAGE:
    llm_globber [OPTIONS] <FILES/DIRECTORIES>...

ARGS:
    <FILES/DIRECTORIES>...    Files or directories to process

OPTIONS:
    -a, --all                  Include all files (no filtering by type)
    -d, --dot                  Include dot files (hidden files)
    -e, --abort-on-error       Abort on errors (default is to continue)
    -h, --help                 Show this help message
    -j, --threads <THREADS>    [Deprecated] Number of worker threads (always 1)
    -n, --name <NAME>          Output filename (without extension) - not required with --git
    -N, --pattern <PATTERN>    Filter files by name pattern (glob syntax, e.g., '*.c')
    -o, --output <PATH>        Output directory path
    -p, --progress             Show progress indicators (disabled by default)
    -q, --quiet                Quiet mode (suppress all output)
    -r, --recursive            Recursively process directories
    -s, --size <SIZE_MB>       Maximum file size in MB (default: 1024)
    -t, --types <TYPES>        File types to include (comma separated, e.g., '.c,.h,.txt')
    -v, --verbose              Verbose output
    -V, --version              Print version information
    --git <PATH>               Process a git repository (auto-configures path, name, and files)
```

### Examples

```bash
# Process all C source files in the current directory
llm_globber -o output -n c_sources -t .c .

# Process all files in a project directory recursively
llm_globber -o output -n project_files -a -r /path/to/project

# Process only files that match a specific pattern
llm_globber -o output -n config_files -N "*config*" /path/to/project

# Process specific files
llm_globber -o output -n important_files file1.c file2.h file3.txt

# Process files with verbose output
llm_globber -o output -n debug_files -v -r /path/to/project

# Process files silently (no output)
llm_globber -o output -n silent_run -q -r /path/to/project

# Abort on error
llm_globber -o output -n strict_run -e -r /path/to/project

# Include dot files
llm_globber -o output -n dotfile_run -d -r /path/to/config_dir

# Process a git repository (automatically uses tracked files)
llm_globber --git /path/to/repo -o output
```
## Safety Features

- **Memory Safety:** Implemented in Rust, ensuring memory safety and preventing common vulnerabilities like buffer overflows.
- **Path Sanitization:** Sanitizes input paths to prevent directory traversal attacks, including checks for null bytes and empty paths.
- **Binary File Detection:** Detects and handles binary files safely, preventing output corruption by omitting binary content.
- **Dot File Warnings:** Provides warnings when including dot files to remind users about potentially sensitive hidden files.
- **Secure File Permissions:** Sets restrictive permissions (0600) on output files to protect sensitive data.
- **Error Handling:** Comprehensive error handling to gracefully manage issues during file processing and provide informative error messages.

## Performance Optimizations

- **Efficient File I/O:** Utilizes BufReader and BufWriter for efficient buffered input and output operations.
- **Memory Mapping (mmap):** Employs memory mapping for processing large files, reducing memory overhead and improving speed.
- **Streaming File Processing:** Processes files in a streaming manner, minimizing memory usage, especially for large files.
- **Optimized String Handling:** Leverages Rust's efficient string processing capabilities.
- **Parallel Processing (Future):** Although the current version uses a single thread, the codebase is structured to be easily extensible for parallel processing in future versions, if needed.

## Output Format

The output file will have the following format:

```
'''--- file1.c ---
[Contents of file1.c]
'''

'''--- file2.h ---
[Contents of file2.h]
'''

...
```

Each file's content is enclosed within `'''--- <filepath> ---` and `'''` markers, making it easy to parse and identify individual file contents. An extra blank line is added after each file block for better readability.

## Binary File Handling

When a binary file is detected, its contents are not included in the output file. Instead, the output file will contain:

```
'''--- binary_file.bin ---
[Binary file - contents omitted]
'''
```

This ensures that the output file remains a clean text file, suitable for LLM ingestion, and avoids potential issues with binary data in text-based models.

## Changes

**2025-03-14**
- feat: Add --git option and clarify -n flag in usage documentation
- docs: Update README with --progress default and new --git option
- feat: Add support for automatic filename when using --git flag
- feat: Add git repository processing with --git option

**2025-03-10**
- Avoid divide-by-zero error

**2025-03-06**
- refactor: Fix test failures by adding recursive flag
- test: Add comprehensive Rust tests for llm_globber functionality
- fix: Resolve executable path and fix unused variable warning in tests
- fix: Resolve cargo test executable path resolution issue
- feat: Add Rust native testing for name pattern filtering
- feat: Enhance path sanitization with null byte and empty path checks
- docs: Clean up README with improved code formatting and markdown structure
- docs: Update README with Rust implementation and enhanced features
- chore: Add Rust-specific files to .gitignore
- Got Rust version going
- fix: Resolve name pattern argument parsing conflict by changing flag to --pattern
- feat: Add short option '-N' for name pattern filter and fix test script quoting
- refactor: Remove short flag from name_pattern argument
- fix: Resolve test script issues with name pattern and file type filtering
- feat: Add warning message for included dotfiles in Rust implementation
- chore: Update author name in CLI application metadata
- refactor: Modify dotfile test to be more flexible with warning detection
- refactor: Update test scripts to use Rust executable in target/release
- refactor: Add #[allow(dead_code)] to LogLevel enum to suppress warning
- refactor: Remove unused constants and mark unused functions with allow(dead_code)
- fix: Remove redundant `return false` in `should_process_file` function
- fix: Resolve Rust compilation errors in file processing and glob matching
- fix: Resolve Rust compilation errors and remove unused imports
- refactor: Update import statements to remove unused dependencies
- fix: Resolve multiple compilation errors in Rust project
- feat: Implement initial Rust-based file scraper for LLM data collection
- refactor: Update simplelog dependency to version 0.12
- chore: Initialize Rust project with Cargo.toml
- feat: Add new file processing functions for file handling and filtering
- refactor: Consolidate file processing logic with helper functions
- refactor: Remove dead code and comments in llm_globber.c
- refactor: Remove file size check when adding files without name pattern
- refactor: Move file size check inside add_file_entry() function
- fix: Correct pointer access to struct member in file size comparison
- refactor: Simplify file processing and remove deprecated threading options
- fix: Remove reference to non-existent thread_mode field in config initialization
- refactor: Remove unused code and deprecated threading features
- fix: Remove duplicate directory opening in process_directory function
- fix: Remove is_safe_path function prototype from function declarations
- refactor: Remove `is_safe_path` function and related checks
- refactor: Replace __attribute__((unused)) with (void) casting in is_safe_path
- style: Align function parameter declaration in is_safe_path
- style: Remove trailing whitespace in is_safe_path function signature
- fix: Suppress unused parameter warnings in is_safe_path function
- refactor: Remove sandbox-related code and options
- feat: Conditionally print headers only in verbose mode
- feat: Enable debug dump only in verbose mode
- fix: Add extra blank line between file entries and fix quiet mode debug dump
- fix: Add file flushing and verbose debugging to diagnose output issues
- refactor: Conditionally skip file cleanup for basic test files
- fix: Adjust file processing to match expected test output format
- test: Add line count validation to basic test script
- test: Add debug output for line count comparison
- fix: Update test script to use absolute file paths for correct matching
- test: Add verbose logging for test file creation
- fix: Ensure test directories and files are created before running tests
- fix: Remove extra newline in file header output
- refactor: Remove multithreading support and simplify processing logic
- fix: Preserve file processing order in single-threaded mode
- fix: Change default log level to WARN to prevent INFO messages in default mode
- refactor: Move test scripts into tests subdirectory
- fix: Update test scripts to correctly reference llm_globber executable
- chore: Make test scripts executable
- fix: Resolve output directory handling and test script path issues
- feat: Add verbose and quiet flags to control logging output
- fix: Add -u flag to disable sandbox mode in test scripts
- fix: Improve test error reporting with more descriptive failure messages
- test: Add multi-threaded performance test script for llm_globber
- fix: Modify test script to correctly capture stderr for verbose mode tests
- fix: Update test_dotfiles.sh to correctly validate dotfile inclusion
- fix: Correct dotfile filename handling in output generation
- fix: Ensure dotfiles are correctly processed and included in output
- test: Add comprehensive dotfile test to verify warning and inclusion
- fix: Use absolute paths in test scripts to resolve output directory issues
- chore: Make test_dotfiles.sh executable
- test: Add verbose and quiet mode tests
- feat: Add test_llm_globber.sh to run all tests
- chore: Make test_llm_globber.sh executable
- refactor: Remove hardcoded "*Local Files*" header from scraper and tests
- fix: Add "*Local Files*" header to output and test files
- feat: Add name pattern filtering using fnmatch
- fix: Improve handling of empty file types string
- fix: Improve error reporting and file handling
- refactor: Improve variable names and function organization
- feat: Implement basic file scraping functionality.
- Initial commit
