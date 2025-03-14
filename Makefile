# Makefile for Rust and C versions

# Project name (should match your Cargo.toml package name)
PROJECT_NAME = llm_globber

# Executable name (will be placed in ./target/release or ./target/debug)
TARGET = ./target/release/$(PROJECT_NAME)

# C version
C_TARGET = ./$(PROJECT_NAME)_c
CC = gcc
CFLAGS = -Wall -Wextra -O2 -pthread

# Source files (Cargo.toml manages this, but we can list src/main.rs for clarity)
SRCS = src/main.rs

# Rust compiler (using cargo)
CARGO = cargo

# Build profile (release for optimized build, debug for development)
BUILD_PROFILE = release

all: $(TARGET) $(C_TARGET)

$(TARGET): src/main.rs
	$(CARGO) build --$(BUILD_PROFILE)

$(C_TARGET): llm_globber.c
	$(CC) $(CFLAGS) -o $(C_TARGET) llm_globber.c

clean:
	$(CARGO) clean
	rm -f $(C_TARGET)

# Run Rust's built-in tests
rust-test:
	$(CARGO) test

# Run the legacy bash tests
bash-test: $(TARGET)
	chmod +x tests/test_llm_globber.sh tests/test_basic.sh tests/test_recursive.sh tests/test_file_types.sh tests/test_name_pattern.sh tests/test_dotfiles.sh tests/test_verbose_quiet.sh tests/test_common.sh tests/test_c_version.sh
	cd tests && ./test_llm_globber.sh

# Run both test suites
test: rust-test bash-test

# Run just the C version tests
c-test: $(C_TARGET)
	chmod +x tests/test_c_version.sh tests/test_common.sh
	cd tests && ./test_c_version.sh

# Profile target for macOS using Instruments
profile: $(TARGET)
	instruments -t Time\ Profiler $(TARGET) -- --recursive .

.PHONY: all clean test rust-test bash-test c-test profile
