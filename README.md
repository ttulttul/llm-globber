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
    -n, --name <NAME>          Output filename (without extension)
    -N, --pattern <PATTERN>    Filter files by name pattern (glob syntax, e.g., '*.c')
    -o, --output <PATH>        Output directory path
    -p, --progress             Show progress indicators
    -q, --quiet                Quiet mode (suppress all output)
    -r, --recursive            Recursively process directories
    -s, --size <SIZE_MB>       Maximum file size in MB (default: 1024)
    -t, --types <TYPES>        File types to include (comma separated, e.g., '.c,.h,.txt')
    -v, --verbose              Verbose output
    -V, --version              Print version information
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
