# LLM Globber

A command-line utility that combines multiple files into a single text document with clear file separators. This tool is specifically designed for preparing source code to be pasted into Large Language Models (LLMs) like Google Gemini 2.0 Thinking, allowing the LLM to analyze your entire codebase within its context window.

## Features

- Combine multiple files into a single text document for LLM analysis
- Filter files by file extension to focus on relevant code
- Add clear file separators with filenames for better LLM understanding
- Handle binary files with safe character replacement
- Clean up excessive newlines to optimize token usage
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
gcc -Wall -Wextra -O2 -o llm_globber llm_globber.c
```

## Usage

```
./llm_globber [options] [files...]
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

Combine C source files and headers into a single document for LLM analysis:
```bash
./llm_globber -o ./output -n project_source -t .c,.h src/main.c include/header.h src/utils.c
```

Combine all files from a project regardless of type:
```bash
./llm_globber -o ./output -n project_all -a src/* include/* docs/*
```

Recursively find and combine all C files in a project:
```bash
./llm_globber -o ./output -n project_c_files -name "*.c" -r src/ lib/
```

Recursively find and combine all header files:
```bash
./llm_globber -o ./output -n project_headers -name "*.h" -r .
```

Combine specific file types recursively:
```bash
./llm_globber -o ./output -n project_docs -t .md,.txt -r docs/
```

Prepare your entire codebase for LLM analysis:
```bash
./llm_globber -o ./output -n for_llm -t .py,.js,.html,.css,.md -r .
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

Copyright (c) 2025 Ken Simpson. All Rights Reserved.

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
