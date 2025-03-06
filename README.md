# LLM Globber

LLM Globber is a command-line utility for collecting files from various locations, filtering them by type or name pattern, and outputting their contents to a single text file. This is particularly useful for preparing local files to be submitted to a Language Learning Model (LLM) for analysis.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Features

- Collect files from multiple directories or specific file paths
- Filter files by extension or name pattern
- Recursively process directories
- Automatically detect and properly handle binary files
- Clean up output file by removing excessive newlines
- Add file headers to the output for better organization
- Generate timestamped output files to prevent overwriting
- Robust error handling and reporting

## Installation

```bash
# Compile the source
gcc -o llm_globber llm_globber.c -Wall -Wextra -O2

# Install to system (optional)
sudo cp llm_globber /usr/local/bin/
```

## Usage

```
Usage: llm_globber [options] [files/directories...]
Options:
  -o PATH        Output directory path
  -n NAME        Output filename (without extension)
  -t TYPES       File types to include (comma separated, e.g. '.c,.h,.txt')
  -a             Include all files (no filtering by type)
  -r             Recursively process directories
  -name PATTERN  Filter files by name pattern (glob syntax, e.g. '*.c')
  -v             Verbose output
  -h             Show this help message
```

## Examples

### Process all C source files in the current directory

```bash
llm_globber -o output -n c_sources -t .c .
```

### Process all files in a project directory recursively

```bash
llm_globber -o output -n project_files -a -r /path/to/project
```

### Process only files that match a specific pattern

```bash
llm_globber -o output -n config_files -name "*config*" /path/to/project
```

### Process specific files

```bash
llm_globber -o output -n important_files file1.c file2.h file3.txt
```

## Safety Features

- Path sanitization to prevent directory traversal attacks
- Binary file detection with automatic handling
- Dot file warnings to prevent accidental inclusion of sensitive configuration files
- Secure memory management with checks on all allocation paths
- Proper error handling and reporting
- Secure file permissions for output files

## Performance Optimizations

- Efficient file I/O with optimized buffer sizes
- Streaming file processing to minimize memory usage
- Dynamic memory allocation that scales with input size
- Optimized string processing and file cleanup
- Efficient directory traversal

## Output Format

The output file will have the following format:

```
*Local Files*

'''--- file1.c ---
[Contents of file1.c]
'''

'''--- file2.h ---
[Contents of file2.h]
'''

...
```

## Binary File Handling

When a binary file is detected, its contents are not included in the output file, but instead it's marked as:

```
'''--- binary_file.bin ---
[Binary file - contents omitted]
'''
```

This prevents corruption of the output file and makes it more suitable for use with LLMs.
