CC = gcc
CFLAGS = -Wall -Wextra -O2
TARGET = llm_globber
SRCS = llm_globber.c
OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)

test: $(TARGET)
	chmod +x tests/test_llm_globber.sh tests/test_basic.sh tests/test_recursive.sh tests/test_file_types.sh tests/test_name_pattern.sh tests/test_dotfiles.sh tests/test_verbose_quiet.sh
	cd tests && ./test_llm_globber.sh

.PHONY: all clean test
