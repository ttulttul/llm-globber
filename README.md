# Folder to Text

A command-line utility that combines multiple files into a single text document with clear file separators. This tool is useful for creating compilations of code or text files for documentation, analysis, or sharing.

## Features

- Combine multiple files into a single text document
- Filter files by file extension
- Add clear file separators with filenames
- Handle binary files with safe character replacement
- Clean up excessive newlines in the output
- Timestamp output files for version tracking

## Installation

### Prerequisites

- GCC or compatible C compiler
- Make (optional, for using the provided Makefile)

### Building from Source

1. Clone the repository or download the source files
2. Build using make:
```bash
make
```

Or compile manually:
```bash
gcc -Wall -Wextra -O2 -o folder_to_text folder_to_text.c
```

## Usage

```
./folder_to_text [options] [files...]
```

### Options

- `-o PATH` - Output directory path (required)
- `-n NAME` - Output filename without extension (required)
- `-t TYPES` - File types to include, comma separated (e.g., `.c,.h,.txt`)
- `-a` - Include all files (disable filtering by file type)
- `-r` - Recursively process directories
- `-name PATTERN` - Filter files by name pattern using glob syntax (e.g., `*.c`)
- `-h` - Show help message

### Examples

Combine C source files and headers into a single document:
```bash
./folder_to_text -o ./output -n project_source -t .c,.h src/main.c include/header.h src/utils.c
```

Combine all files from a project regardless of type:
```bash
./folder_to_text -o ./output -n project_all -a src/* include/* docs/*
```

Recursively find and combine all C files in a project:
```bash
./folder_to_text -o ./output -n project_c_files -name "*.c" -r src/ lib/
```

Recursively find and combine all header files:
```bash
./folder_to_text -o ./output -n project_headers -name "*.h" -r .
```

Combine specific file types recursively:
```bash
./folder_to_text -o ./output -n project_docs -t .md,.txt -r docs/
```

## Output Format

The output file will be named according to the pattern `NAME_TIMESTAMP.txt`, where:
- `NAME` is the value provided with the `-n` option
- `TIMESTAMP` is the current date and time in format `YYYYMMDDHHMMSS`

Each file in the output will be formatted as:

```
'''--- filename.ext ---
[file content]
'''
```

## File Type Filtering

By default, the program filters files based on their extensions. Only files with extensions matching those provided with the `-t` option will be included.

To disable filtering and include all files, use the `-a` option.

## Error Handling

- The program will report errors when files cannot be read
- Non-UTF-8 characters in files will be replaced with the Unicode replacement character (�)
- Appropriate error messages will be displayed if required parameters are missing

## License

MIT License

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
