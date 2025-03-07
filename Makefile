# Makefile for Rust project

# Project name (should match your Cargo.toml package name)
PROJECT_NAME = llm_globber

# Executable name (will be placed in ./target/release or ./target/debug)
TARGET = ./target/release/$(PROJECT_NAME)

# Source files (Cargo.toml manages this, but we can list src/main.rs for clarity)
SRCS = src/main.rs

# Rust compiler (using cargo)
CARGO = cargo

# Build profile (release for optimized build, debug for development)
BUILD_PROFILE = release

all: $(TARGET)

$(TARGET): src/main.rs
	$(CARGO) build --$(BUILD_PROFILE)

clean:
	$(CARGO) clean

# Run Rust's built-in tests
rust-test:
	$(CARGO) test

# Run the legacy bash tests
bash-test: $(TARGET)
	chmod +x tests/test_llm_globber.sh tests/test_basic.sh tests/test_recursive.sh tests/test_file_types.sh tests/test_name_pattern.sh tests/test_dotfiles.sh tests/test_verbose_quiet.sh tests/test_common.sh
	cd tests && ./test_llm_globber.sh

# Run both test suites
test: rust-test bash-test

.PHONY: all clean test rust-test bash-test
