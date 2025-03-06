#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include <libgen.h>
#include <ctype.h>
#include <regex.h>
#include <errno.h>
#include <fnmatch.h>
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>

// Constants with reasonable limits
#define MAX_PATH_LEN PATH_MAX
#define MAX_FILES 10000
#define MAX_FILE_TYPES 50
#define MAX_FILE_TYPE_LEN 20
#define INITIAL_BUFFER_SIZE (1 << 20)  // 1MB initial buffer size for better performance
#define IO_BUFFER_SIZE (1 << 16)       // 64KB IO buffer for faster reads/writes

// Logging levels
typedef enum {
    LOG_ERROR,
    LOG_WARN,
    LOG_INFO,
    LOG_DEBUG
} LogLevel;

// Global logging level
static LogLevel g_log_level = LOG_INFO;

typedef struct {
    char** repo_paths;         // Dynamically allocated array of paths
    size_t repo_path_count;    // Current number of paths
    size_t repo_path_capacity; // Allocated capacity
    char output_path[MAX_PATH_LEN];
    char output_filename[MAX_PATH_LEN];
    char** file_types;         // Dynamically allocated array of file types
    size_t file_type_count;    // Current number of types
    size_t file_type_capacity; // Allocated capacity
    int filter_files;
    int recursive;
    char name_pattern[MAX_PATH_LEN];
    int verbose;               // Verbosity flag
} ScrapeConfig;

// Function prototypes
char* run_scraper(ScrapeConfig *config);
int ends_with(const char *str, const char *suffix);
int clean_up_text(const char *filename, int max_consecutive_newlines);
void parse_file_types(ScrapeConfig *config, const char *types_str);
void print_usage(const char *program_name);
void process_directory(ScrapeConfig *config, const char *dir_path);
void log_message(LogLevel level, const char *format, ...);
void* safe_malloc(size_t size);
void* safe_realloc(void *ptr, size_t size);
char* safe_strdup(const char *str);
int is_directory(const char *path);
int is_regular_file(const char *path);
void add_repo_path(ScrapeConfig *config, const char *path);
void free_config(ScrapeConfig *config);
int init_config(ScrapeConfig *config);
int sanitize_path(char *path, size_t max_len);
size_t get_file_size(FILE *file);
int is_binary_file(const char *path);
int is_dot_file(const char *file_path);
int process_file(FILE *output, const char *file_path, int detect_binary);

// Safe logging function
void log_message(LogLevel level, const char *format, ...) {
    if (level > g_log_level) {
        return;
    }

    va_list args;
    va_start(args, format);
    
    switch (level) {
        case LOG_ERROR:
            fprintf(stderr, "ERROR: ");
            break;
        case LOG_WARN:
            fprintf(stderr, "WARNING: ");
            break;
        case LOG_INFO:
            fprintf(stderr, "INFO: ");
            break;
        case LOG_DEBUG:
            fprintf(stderr, "DEBUG: ");
            break;
    }
    
    vfprintf(stderr, format, args);
    fprintf(stderr, "\n");
    va_end(args);
}

// Safe memory allocation with error checking
void* safe_malloc(size_t size) {
    void *ptr = malloc(size);
    if (!ptr && size > 0) {
        log_message(LOG_ERROR, "Memory allocation failed (requested %zu bytes)", size);
        exit(EXIT_FAILURE);
    }
    return ptr;
}

// Safe realloc with error checking
void* safe_realloc(void *ptr, size_t size) {
    void *new_ptr = realloc(ptr, size);
    if (!new_ptr && size > 0) {
        log_message(LOG_ERROR, "Memory reallocation failed (requested %zu bytes)", size);
        free(ptr); // Free the original pointer
        exit(EXIT_FAILURE);
    }
    return new_ptr;
}

// Safe strdup
char* safe_strdup(const char *str) {
    if (!str) return NULL;
    
    size_t len = strlen(str) + 1;
    char *new_str = safe_malloc(len);
    memcpy(new_str, str, len);
    return new_str;
}

// Initialize configuration with default values
int init_config(ScrapeConfig *config) {
    if (!config) return 0;
    
    memset(config, 0, sizeof(ScrapeConfig));
    
    // Set default values
    config->filter_files = 1;
    config->recursive = 0;
    config->verbose = 0;
    
    // Initialize dynamic arrays
    config->repo_path_capacity = 10; // Start with space for 10 paths
    config->repo_paths = safe_malloc(config->repo_path_capacity * sizeof(char*));
    
    config->file_type_capacity = 10; // Start with space for 10 file types
    config->file_types = safe_malloc(config->file_type_capacity * sizeof(char*));
    
    return 1;
}

// Free all allocated memory in the config
void free_config(ScrapeConfig *config) {
    if (!config) return;
    
    // Free repository paths
    for (size_t i = 0; i < config->repo_path_count; i++) {
        free(config->repo_paths[i]);
    }
    free(config->repo_paths);
    
    // Free file types
    for (size_t i = 0; i < config->file_type_count; i++) {
        free(config->file_types[i]);
    }
    free(config->file_types);
}

// Add a repository path to the config
void add_repo_path(ScrapeConfig *config, const char *path) {
    if (!config || !path) return;
    
    // Expand the array if needed
    if (config->repo_path_count >= config->repo_path_capacity) {
        config->repo_path_capacity *= 2;
        config->repo_paths = safe_realloc(config->repo_paths, 
                                      config->repo_path_capacity * sizeof(char*));
    }
    
    // Add the new path
    config->repo_paths[config->repo_path_count++] = safe_strdup(path);
}

// Check if a string ends with a specific suffix (case sensitive)
int ends_with(const char *str, const char *suffix) {
    if (!str || !suffix) return 0;
    
    size_t str_len = strlen(str);
    size_t suffix_len = strlen(suffix);
    
    if (suffix_len > str_len) return 0;
    
    return strncmp(str + str_len - suffix_len, suffix, suffix_len) == 0;
}

// Check if a path is a directory
int is_directory(const char *path) {
    if (!path) return 0;
    
    struct stat path_stat;
    if (stat(path, &path_stat) != 0) {
        log_message(LOG_DEBUG, "Cannot stat path: %s - %s", path, strerror(errno));
        return 0;
    }
    return S_ISDIR(path_stat.st_mode);
}

// Check if a path is a regular file
int is_regular_file(const char *path) {
    if (!path) return 0;
    
    struct stat path_stat;
    if (stat(path, &path_stat) != 0) {
        log_message(LOG_DEBUG, "Cannot stat path: %s - %s", path, strerror(errno));
        return 0;
    }
    return S_ISREG(path_stat.st_mode);
}

// Sanitize path to prevent directory traversal attacks
int sanitize_path(char *path, size_t max_len) {
    if (!path) return 0;
    
    // Resolve path to absolute path
    char resolved_path[MAX_PATH_LEN];
    if (realpath(path, resolved_path) == NULL) {
        log_message(LOG_ERROR, "Invalid path: %s - %s", path, strerror(errno));
        return 0;
    }
    
    // Check path length
    if (strlen(resolved_path) >= max_len) {
        log_message(LOG_ERROR, "Path too long: %s", path);
        return 0;
    }
    
    // Copy resolved path back
    strncpy(path, resolved_path, max_len - 1);
    path[max_len - 1] = '\0';
    
    return 1;
}

// Parse comma-separated file types into the config
void parse_file_types(ScrapeConfig *config, const char *types_str) {
    if (!config || !types_str || strlen(types_str) == 0) {
        return;
    }
    
    char *types_copy = safe_strdup(types_str);
    char *saveptr;
    char *token = strtok_r(types_copy, ",", &saveptr);
    
    while (token != NULL) {
        // Trim whitespace
        char *start = token;
        while (isspace((unsigned char)*start)) start++;
        
        char *end = start + strlen(start) - 1;
        while (end > start && isspace((unsigned char)*end)) end--;
        *(end + 1) = '\0';
        
        if (strlen(start) > 0) {
            // Expand array if needed
            if (config->file_type_count >= config->file_type_capacity) {
                config->file_type_capacity *= 2;
                config->file_types = safe_realloc(config->file_types, 
                                              config->file_type_capacity * sizeof(char*));
            }
            
            // Add the file type
            config->file_types[config->file_type_count++] = safe_strdup(start);
        }
        
        token = strtok_r(NULL, ",", &saveptr);
    }
    
    free(types_copy);
}

// Get file size in bytes
size_t get_file_size(FILE *file) {
    if (!file) return 0;
    
    long current_pos = ftell(file);
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    fseek(file, current_pos, SEEK_SET);
    
    return (size_t)size;
}

// Detect if a file is binary (contains null bytes or high proportion of non-printable characters)
int is_binary_file(const char *path) {
    if (!path) return 0;
    
    FILE *file = fopen(path, "rb");
    if (!file) {
        log_message(LOG_ERROR, "Cannot open file to check if binary: %s - %s", path, strerror(errno));
        return 0;
    }
    
    // Check first 4KB of file
    unsigned char buffer[4096];
    size_t bytes_read = fread(buffer, 1, sizeof(buffer), file);
    fclose(file);
    
    if (bytes_read == 0) return 0; // Empty file
    
    // Count non-printable characters (excluding common control chars)
    size_t non_printable = 0;
    for (size_t i = 0; i < bytes_read; i++) {
        // Consider null bytes, control characters outside common ones as indicators of binary
        if (buffer[i] == 0 || 
            (buffer[i] < 32 && buffer[i] != '\n' && buffer[i] != '\r' && buffer[i] != '\t')) {
            non_printable++;
        }
    }
    
    // If more than 10% of characters are non-printable, consider it binary
    return (non_printable * 100 / bytes_read) > 10;
}

// Clean up text files by replacing excessive newlines - returns 1 on success, 0 on failure
int clean_up_text(const char *filename, int max_consecutive_newlines) {
    if (!filename) return 0;
    
    FILE *file = fopen(filename, "r");
    if (!file) {
        log_message(LOG_ERROR, "Error opening file for cleanup: %s - %s", filename, strerror(errno));
        return 0;
    }
    
    // Get file size
    size_t file_size = get_file_size(file);
    if (file_size == 0) {
        fclose(file);
        return 1; // Empty file, nothing to do
    }
    
    // Create temporary output file
    char temp_filename[MAX_PATH_LEN];
    snprintf(temp_filename, sizeof(temp_filename), "%s.tmp", filename);
    
    FILE *temp_file = fopen(temp_filename, "w");
    if (!temp_file) {
        log_message(LOG_ERROR, "Error creating temporary file for cleanup: %s - %s", 
                   temp_filename, strerror(errno));
        fclose(file);
        return 0;
    }
    
    // Process the file a line at a time to avoid large memory allocations
    char *line = NULL;
    size_t line_size = 0;
    ssize_t read_size;
    
    int consecutive_newlines = 0;
    
    while ((read_size = getline(&line, &line_size, file)) != -1) {
        // Check if this is just a newline
        int is_newline = (read_size == 1 && line[0] == '\n') || 
                         (read_size == 2 && line[0] == '\r' && line[1] == '\n');
        
        if (is_newline) {
            consecutive_newlines++;
            if (consecutive_newlines <= max_consecutive_newlines) {
                fputs(line, temp_file);
            }
        } else {
            // Reset counter and write the line
            consecutive_newlines = 0;
            fputs(line, temp_file);
        }
    }
    
    // Clean up
    free(line);
    fclose(file);
    fclose(temp_file);
    
    // Replace original with temp file
    if (rename(temp_filename, filename) != 0) {
        log_message(LOG_ERROR, "Error replacing original file after cleanup: %s - %s", 
                   filename, strerror(errno));
        unlink(temp_filename); // Try to delete the temp file
        return 0;
    }
    
    return 1;
}

// Check if a file is a dot file (starts with a dot)
int is_dot_file(const char *file_path) {
    if (!file_path) return 0;
    
    char *path_copy = safe_strdup(file_path);
    char *base_name = basename(path_copy);
    int result = (base_name[0] == '.');
    free(path_copy);
    
    return result;
}

// Process a file and write its contents to the output file
int process_file(FILE *output, const char *file_path, int detect_binary) {
    if (!output || !file_path) return 0;
    
    // Get file basename for the header
    char *path_copy = safe_strdup(file_path);
    char *base_name = basename(path_copy);
    
    // Check if this is a dot file and warn the user
    if (base_name[0] == '.') {
        log_message(LOG_WARN, "WARNING: Including dot file which may contain secrets: %s", file_path);
    }
    
    fprintf(output, "\n'''--- %s ---\n", base_name);
    free(path_copy);
    
    // Check for binary file if requested
    if (detect_binary && is_binary_file(file_path)) {
        fprintf(output, "[Binary file - contents omitted]\n'''\n");
        return 1;
    }
    
    // Open and read file content
    FILE *input = fopen(file_path, "rb");
    if (!input) {
        log_message(LOG_ERROR, "Error reading file %s: %s", file_path, strerror(errno));
        fprintf(output, "Error reading file\n'''\n");
        return 0;
    }
    
    // Get file size
    size_t file_size = get_file_size(input);
    log_message(LOG_INFO, "Processing file %s: size %zu bytes", file_path, file_size);
    
    // Use a larger buffer for better performance
    char buffer[IO_BUFFER_SIZE];
    size_t bytes_read;
    
    while ((bytes_read = fread(buffer, 1, sizeof(buffer), input)) > 0) {
        // Try to write as text, replace non-UTF8 characters
        for (size_t j = 0; j < bytes_read; j++) {
            if (buffer[j] >= 32 && buffer[j] <= 126) { // ASCII printable
                fputc(buffer[j], output);
            } else if (buffer[j] == '\n' || buffer[j] == '\r' || buffer[j] == '\t') {
                fputc(buffer[j], output); // Control characters
            } else {
                fputs("�", output); // Single replacement character (more efficient)
            }
        }
    }
    
    fprintf(output, "\n'''\n");
    fclose(input);
    
    return 1;
}

// Process a directory recursively, collecting all matching files
void process_directory(ScrapeConfig *config, const char *dir_path) {
    if (!config || !dir_path) return;
    
    DIR *dir = opendir(dir_path);
    if (!dir) {
        log_message(LOG_ERROR, "Error opening directory %s: %s", dir_path, strerror(errno));
        return;
    }
    
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        // Skip . and ..
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        
        // Create full path
        char full_path[MAX_PATH_LEN];
        int path_result = snprintf(full_path, MAX_PATH_LEN, "%s/%s", dir_path, entry->d_name);
        if (path_result < 0 || path_result >= MAX_PATH_LEN) {
            log_message(LOG_WARN, "Path too long: %s/%s", dir_path, entry->d_name);
            continue;
        }
        
        if (is_directory(full_path)) {
            // It's a directory - recurse if recursive option is enabled
            if (config->recursive) {
                process_directory(config, full_path);
            }
        } else if (is_regular_file(full_path)) {
            // It's a regular file - check if it matches our filters
            int include_file = 1;
            
            // Check name pattern filter if specified
            if (strlen(config->name_pattern) > 0) {
                if (fnmatch(config->name_pattern, entry->d_name, 0) != 0) {
                    include_file = 0;
                }
            }
            
            // Check file type filter if enabled
            if (include_file && config->filter_files && config->file_type_count > 0) {
                include_file = 0;
                for (size_t j = 0; j < config->file_type_count; j++) {
                    if (ends_with(entry->d_name, config->file_types[j])) {
                        include_file = 1;
                        break;
                    }
                }
            }
            
            // Add the file if it passed all filters
            if (include_file) {
                add_repo_path(config, full_path);
            }
        }
    }
    
    closedir(dir);
}

// Run the scraper with the given configuration
char* run_scraper(ScrapeConfig *config) {
    if (!config) return NULL;
    
    log_message(LOG_INFO, "Starting file processing...");
    
    // Sanitize output path
    if (!sanitize_path(config->output_path, MAX_PATH_LEN)) {
        log_message(LOG_ERROR, "Invalid output path: %s", config->output_path);
        return NULL;
    }
    
    // Create output directory if it doesn't exist
    struct stat st = {0};
    if (stat(config->output_path, &st) == -1) {
        // Create directory with secure permissions (rwxr-x---)
        if (mkdir(config->output_path, 0750) != 0) {
            log_message(LOG_ERROR, "Could not create output directory: %s (%s)", 
                       config->output_path, strerror(errno));
            return NULL;
        }
        log_message(LOG_INFO, "Created output directory: %s", config->output_path);
    }
    
    // Generate timestamp
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    char timestamp[20];
    if (t == NULL || strftime(timestamp, sizeof(timestamp), "%Y%m%d%H%M%S", t) == 0) {
        log_message(LOG_ERROR, "Failed to generate timestamp");
        strncpy(timestamp, "00000000000000", sizeof(timestamp) - 1);
    }
    
    // Create output filename
    char output_file[MAX_PATH_LEN];
    int result = snprintf(output_file, MAX_PATH_LEN, "%s/%s_%s.txt", 
             config->output_path, config->output_filename, timestamp);
    
    if (result < 0 || result >= MAX_PATH_LEN) {
        log_message(LOG_ERROR, "Output path too long");
        return NULL;
    }
    
    FILE *output = fopen(output_file, "w");
    if (!output) {
        log_message(LOG_ERROR, "Error creating output file: %s - %s", output_file, strerror(errno));
        return NULL;
    }
    
    fprintf(output, "*Local Files*\n");
    
    // Process each file
    int files_processed = 0;
    for (size_t i = 0; i < config->repo_path_count; i++) {
        char *file_path = config->repo_paths[i];
        
        // Check if file exists and is readable
        if (!is_regular_file(file_path)) {
            log_message(LOG_WARN, "Skipping invalid file path: %s", file_path);
            continue;
        }
        
        // Check file type filter
        if (config->filter_files && config->file_type_count > 0) {
            int match = 0;
            for (size_t j = 0; j < config->file_type_count; j++) {
                if (ends_with(file_path, config->file_types[j])) {
                    match = 1;
                    break;
                }
            }
            
            if (!match) {
                log_message(LOG_DEBUG, "Skipping file %s: Does not match selected types", file_path);
                continue;
            }
        }
        
        // Process the file
        if (process_file(output, file_path, 1)) {
            files_processed++;
        }
    }
    
    fclose(output);
    
    if (files_processed == 0) {
        log_message(LOG_WARN, "No files were processed");
        // Remove empty output file
        unlink(output_file);
        return NULL;
    }
    
    log_message(LOG_INFO, "Cleaning up file...");
    if (!clean_up_text(output_file, 2)) {
        log_message(LOG_ERROR, "Error cleaning up file: %s", output_file);
        // Continue anyway
    }
    
    log_message(LOG_INFO, "Done. Processed %d files. Output written to: %s", 
               files_processed, output_file);
    
    return safe_strdup(output_file);
}

void print_usage(const char *program_name) {
    printf("Usage: %s [options] [files/directories...]\n", program_name);
    printf("Options:\n");
    printf("  -o PATH        Output directory path\n");
    printf("  -n NAME        Output filename (without extension)\n");
    printf("  -t TYPES       File types to include (comma separated, e.g. '.c,.h,.txt')\n");
    printf("  -a             Include all files (no filtering by type)\n");
    printf("  -r             Recursively process directories\n");
    printf("  -name PATTERN  Filter files by name pattern (glob syntax, e.g. '*.c')\n");
    printf("  -v             Verbose output\n");
    printf("  -h             Show this help message\n");
}

int main(int argc, char *argv[]) {
    ScrapeConfig config;
    if (!init_config(&config)) {
        log_message(LOG_ERROR, "Failed to initialize configuration");
        return EXIT_FAILURE;
    }
    
    // Process all arguments manually
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            strncpy(config.output_path, argv[i+1], MAX_PATH_LEN - 1);
            config.output_path[MAX_PATH_LEN - 1] = '\0';
            i++; // Skip the value
        } else if (strcmp(argv[i], "-n") == 0 && i + 1 < argc) {
            strncpy(config.output_filename, argv[i+1], MAX_PATH_LEN - 1);
            config.output_filename[MAX_PATH_LEN - 1] = '\0';
            i++; // Skip the value
        } else if (strcmp(argv[i], "-t") == 0 && i + 1 < argc) {
            parse_file_types(&config, argv[i+1]);
            i++; // Skip the value
        } else if (strcmp(argv[i], "-a") == 0) {
            config.filter_files = 0;
        } else if (strcmp(argv[i], "-r") == 0) {
            config.recursive = 1;
        } else if (strcmp(argv[i], "-name") == 0 && i + 1 < argc) {
            strncpy(config.name_pattern, argv[i+1], MAX_PATH_LEN - 1);
            config.name_pattern[MAX_PATH_LEN - 1] = '\0';
            i++; // Skip the value
        } else if (strcmp(argv[i], "-v") == 0) {
            config.verbose = 1;
            g_log_level = LOG_DEBUG;
        } else if (strcmp(argv[i], "-h") == 0) {
            print_usage(argv[0]);
            free_config(&config);
            return EXIT_SUCCESS;
        } else if (argv[i][0] == '-') {
            log_message(LOG_ERROR, "Unknown option: %s", argv[i]);
            print_usage(argv[0]);
            free_config(&config);
            return EXIT_FAILURE;
        }
    }
    
    // Check required arguments
    if (strlen(config.output_path) == 0) {
        log_message(LOG_ERROR, "Error: Output path (-o) is required");
        print_usage(argv[0]);
        free_config(&config);
        return EXIT_FAILURE;
    }
    
    // Debugging
    log_message(LOG_DEBUG, "Output path set to: '%s'", config.output_path);
    
    if (strlen(config.output_filename) == 0) {
        log_message(LOG_ERROR, "Error: Output filename (-n) is required");
        print_usage(argv[0]);
        free_config(&config);
        return EXIT_FAILURE;
    }
    
    // Process each file or directory argument
    int found_input = 0;
    for (int i = 1; i < argc; i++) {
        // Skip options and their values
        if (argv[i][0] == '-') {
            if (strcmp(argv[i], "-o") == 0 || 
                strcmp(argv[i], "-n") == 0 || 
                strcmp(argv[i], "-t") == 0 || 
                strcmp(argv[i], "-name") == 0) {
                i++; // Skip the value
            }
            continue;
        }
        
        found_input = 1;
        
        // Check if path exists
        struct stat path_stat;
        if (stat(argv[i], &path_stat) != 0) {
            log_message(LOG_WARN, "Could not access path %s: %s", argv[i], strerror(errno));
            continue;
        }
        
        if (S_ISDIR(path_stat.st_mode)) {
            // It's a directory
            if (config.recursive) {
                process_directory(&config, argv[i]);
            } else {
                log_message(LOG_WARN, "%s is a directory. Use -r to process recursively.", argv[i]);
            }
        } else if (S_ISREG(path_stat.st_mode)) {
            // It's a file - add directly but check name pattern if specified
            if (strlen(config.name_pattern) > 0) {
                char *path_copy = safe_strdup(argv[i]);
                char *base_name = basename(path_copy);
                if (fnmatch(config.name_pattern, base_name, 0) == 0) {
                    add_repo_path(&config, argv[i]);
                }
                free(path_copy);
            } else {
                add_repo_path(&config, argv[i]);
            }
        }
    }
    
    if (!found_input) {
        log_message(LOG_ERROR, "Error: No input files or directories specified");
        print_usage(argv[0]);
        free_config(&config);
        return EXIT_FAILURE;
    }
    
    if (config.repo_path_count == 0) {
        log_message(LOG_ERROR, "Error: No files found matching criteria");
        free_config(&config);
        return EXIT_FAILURE;
    }
    
    // Run the scraper
    char *output_file = run_scraper(&config);
    int result = EXIT_SUCCESS;
    
    if (!output_file) {
        log_message(LOG_ERROR, "Scraper failed");
        result = EXIT_FAILURE;
    } else {
        log_message(LOG_INFO, "Scraper completed successfully: %s", output_file);
        free(output_file);
    }
    
    // Clean up
    free_config(&config);
    
    return result;
}
