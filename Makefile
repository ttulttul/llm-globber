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
	chmod +x test_llm_globber.sh test_basic.sh test_recursive.sh test_file_types.sh test_name_pattern.sh test_dotfiles.sh
	./test_llm_globber.sh

.PHONY: all clean test
