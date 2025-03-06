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

#define MAX_PATH_LEN 1024
#define MAX_FILES 1000
#define MAX_FILE_TYPES 20
#define MAX_FILE_TYPE_LEN 10
#define MAX_BUFFER_SIZE 8192

typedef struct {
    char* repo_paths[MAX_FILES];
    int repo_path_count;
    char output_path[MAX_PATH_LEN];
    char output_filename[MAX_PATH_LEN];
    char file_types[MAX_FILE_TYPES][MAX_FILE_TYPE_LEN];
    int file_type_count;
    int filter_files;
    int recursive;
    char name_pattern[MAX_PATH_LEN];
} ScrapeConfig;

// Function prototypes
char* run_scraper(ScrapeConfig *config);
int ends_with(const char *str, const char *suffix);
void clean_up_text(const char *filename);
void parse_file_types(ScrapeConfig *config, const char *types_str);
void print_usage(const char *program_name);
void process_directory(ScrapeConfig *config, const char *dir_path, char **file_paths, int *file_count);

// Check if a string ends with a specific suffix
int ends_with(const char *str, const char *suffix) {
    if (!str || !suffix) return 0;
    
    size_t str_len = strlen(str);
    size_t suffix_len = strlen(suffix);
    
    if (suffix_len > str_len) return 0;
    
    return strncmp(str + str_len - suffix_len, suffix, suffix_len) == 0;
}

// Parse comma-separated file types into the config
void parse_file_types(ScrapeConfig *config, const char *types_str) {
    if (!types_str || strlen(types_str) == 0) {
        return;
    }
    
    char *types_copy = strdup(types_str);
    char *token = strtok(types_copy, ",");
    config->file_type_count = 0;
    
    while (token != NULL && config->file_type_count < MAX_FILE_TYPES) {
        // Trim whitespace
        char *start = token;
        while (isspace(*start)) start++;
        
        char *end = start + strlen(start) - 1;
        while (end > start && isspace(*end)) end--;
        *(end + 1) = '\0';
        
        if (strlen(start) > 0 && strlen(start) < MAX_FILE_TYPE_LEN) {
            strncpy(config->file_types[config->file_type_count], start, MAX_FILE_TYPE_LEN - 1);
            config->file_types[config->file_type_count][MAX_FILE_TYPE_LEN - 1] = '\0';
            config->file_type_count++;
        }
        
        token = strtok(NULL, ",");
    }
    
    free(types_copy);
}

// Remove excessive newlines
void clean_up_text(const char *filename) {
    FILE *file = fopen(filename, "r");
    if (!file) {
        printf("Error opening file for cleanup: %s\n", filename);
        return;
    }
    
    // Read file into memory
    char *buffer = malloc(MAX_BUFFER_SIZE);
    size_t buffer_size = MAX_BUFFER_SIZE;
    size_t content_size = 0;
    size_t bytes_read;
    
    while ((bytes_read = fread(buffer + content_size, 1, buffer_size - content_size, file)) > 0) {
        content_size += bytes_read;
        if (content_size >= buffer_size - 1) {
            buffer_size *= 2;
            buffer = realloc(buffer, buffer_size);
            if (!buffer) {
                printf("Memory allocation error during cleanup\n");
                fclose(file);
                return;
            }
        }
    }
    
    buffer[content_size] = '\0';
    fclose(file);
    
    // Process the content - replace 3 or more consecutive newlines with 2
    regex_t regex;
    if (regcomp(&regex, "\n{3,}", REG_EXTENDED) != 0) {
        printf("Could not compile regex for cleanup\n");
        free(buffer);
        return;
    }
    
    regmatch_t matches[1];
    char *processed = malloc(buffer_size);
    size_t pos = 0;
    size_t last_pos = 0;
    
    while (regexec(&regex, buffer + pos, 1, matches, 0) == 0) {
        size_t match_start = pos + matches[0].rm_so;
        size_t match_end = pos + matches[0].rm_eo;
        
        // Copy everything up to the match
        strncat(processed, buffer + last_pos, match_start - last_pos);
        
        // Add two newlines
        strcat(processed, "\n\n");
        
        // Update positions
        last_pos = match_end;
        pos = match_end;
    }
    
    // Add the rest of the string
    strcat(processed, buffer + last_pos);
    
    regfree(&regex);
    
    // Write back to file
    file = fopen(filename, "w");
    if (!file) {
        printf("Error opening file for writing after cleanup: %s\n", filename);
        free(buffer);
        free(processed);
        return;
    }
    
    fputs(processed, file);
    fclose(file);
    
    free(buffer);
    free(processed);
}

// Process a directory recursively, collecting all matching files
void process_directory(ScrapeConfig *config, const char *dir_path, char **file_paths, int *file_count) {
    DIR *dir = opendir(dir_path);
    if (!dir) {
        printf("Error opening directory %s: %s\n", dir_path, strerror(errno));
        return;
    }
    
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL && *file_count < MAX_FILES) {
        // Skip . and ..
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        
        // Create full path
        char full_path[MAX_PATH_LEN];
        snprintf(full_path, MAX_PATH_LEN, "%s/%s", dir_path, entry->d_name);
        
        // Get file info
        struct stat path_stat;
        stat(full_path, &path_stat);
        
        if (S_ISDIR(path_stat.st_mode)) {
            // It's a directory - recurse if recursive option is enabled
            if (config->recursive) {
                process_directory(config, full_path, file_paths, file_count);
            }
        } else if (S_ISREG(path_stat.st_mode)) {
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
                for (int j = 0; j < config->file_type_count; j++) {
                    if (ends_with(entry->d_name, config->file_types[j])) {
                        include_file = 1;
                        break;
                    }
                }
            }
            
            // Add the file if it passed all filters
            if (include_file && *file_count < MAX_FILES) {
                file_paths[*file_count] = strdup(full_path);
                (*file_count)++;
            }
        }
    }
    
    closedir(dir);
}

// Run the scraper with the given configuration
char* run_scraper(ScrapeConfig *config) {
    printf("Fetching all files...\n");
    
    // Create output directory if it doesn't exist
    struct stat st = {0};
    if (stat(config->output_path, &st) == -1) {
        if (mkdir(config->output_path, 0755) != 0) {
            printf("Error: Could not create output directory: %s (%s)\n", 
                   config->output_path, strerror(errno));
            return NULL;
        }
    }
    
    // Generate timestamp
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    char timestamp[20];
    strftime(timestamp, sizeof(timestamp), "%Y%m%d%H%M%S", t);
    
    // Create output filename
    char output_file[MAX_PATH_LEN];
    snprintf(output_file, MAX_PATH_LEN, "%s/%s_%s.txt", 
             config->output_path, config->output_filename, timestamp);
    
    FILE *output = fopen(output_file, "w");
    if (!output) {
        printf("Error creating output file: %s\n", output_file);
        return NULL;
    }
    
    fprintf(output, "*Local Files*\n");
    
    // Process each file
    for (int i = 0; i < config->repo_path_count; i++) {
        char *file_path = config->repo_paths[i];
        int include_file = 1;
        
        // Check file type filter
        if (config->filter_files && config->file_type_count > 0) {
            include_file = 0;
            for (int j = 0; j < config->file_type_count; j++) {
                if (ends_with(file_path, config->file_types[j])) {
                    include_file = 1;
                    break;
                }
            }
        }
        
        if (!include_file) {
            printf("Skipping file %s: Does not match selected types.\n", file_path);
            continue;
        }
        
        // Get file basename for the header
        char *basename_copy = strdup(file_path);
        char *base_name = basename(basename_copy);
        
        fprintf(output, "\n'''--- %s ---\n", base_name);
        free(basename_copy);
        
        // Open and read file content
        FILE *input = fopen(file_path, "rb");
        if (!input) {
            printf("Error reading file %s: %s\n", file_path, strerror(errno));
            fprintf(output, "Error reading file\n'''\n");
            continue;
        }
        
        // Get file size
        fseek(input, 0, SEEK_END);
        long file_size = ftell(input);
        fseek(input, 0, SEEK_SET);
        printf("Processing file %s: size %ld bytes\n", file_path, file_size);
        
        // Read and write file content
        char buffer[4096];
        size_t bytes_read;
        
        while ((bytes_read = fread(buffer, 1, sizeof(buffer), input)) > 0) {
            // Try to write as text, replace non-UTF8 characters
            for (size_t j = 0; j < bytes_read; j++) {
                if (buffer[j] >= 32 && buffer[j] <= 126) { // ASCII printable
                    fputc(buffer[j], output);
                } else if (buffer[j] == '\n' || buffer[j] == '\r' || buffer[j] == '\t') {
                    fputc(buffer[j], output); // Control characters
                } else {
                    fputs("�", output); // Replacement character
                }
            }
        }
        
        fprintf(output, "\n'''\n");
        fclose(input);
    }
    
    fclose(output);
    
    printf("Cleaning up file...\n");
    clean_up_text(output_file);
    
    printf("Done. Output written to: %s\n", output_file);
    return strdup(output_file);
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
    printf("  -h             Show this help message\n");
}

int main(int argc, char *argv[]) {
    ScrapeConfig config;
    memset(&config, 0, sizeof(ScrapeConfig));
    config.filter_files = 1; // Default to filtering files
    config.recursive = 0;    // Default to non-recursive
    
    int name_arg_index = -1;
    
    // Pre-parse arguments to find special options like -name that are non-standard
    for (int i = 1; i < argc - 1; i++) {
        if (strcmp(argv[i], "-name") == 0) {
            strncpy(config.name_pattern, argv[i+1], MAX_PATH_LEN - 1);
            name_arg_index = i; // Remember where we found this
            i++; // Skip the value
        }
    }
    
    // Use getopt to parse standard options
    int c;
    // Create a clean argv for getopt without the -name option and its value
    char *getopt_argv[argc];
    int getopt_argc = 0;
    
    for (int i = 0; i < argc; i++) {
        if (i == name_arg_index || i == name_arg_index + 1) {
            continue; // Skip the -name option and its value
        }
        getopt_argv[getopt_argc++] = argv[i];
    }
    
    optind = 1; // Reset getopt
    while ((c = getopt(getopt_argc, getopt_argv, "o:n:t:arh")) != -1) {
        switch (c) {
            case 'o':
                strncpy(config.output_path, optarg, MAX_PATH_LEN - 1);
                break;
            case 'n':
                strncpy(config.output_filename, optarg, MAX_PATH_LEN - 1);
                break;
            case 't':
                parse_file_types(&config, optarg);
                break;
            case 'a':
                config.filter_files = 0;
                break;
            case 'r':
                config.recursive = 1;
                break;
            case 'h':
                print_usage(argv[0]);
                return 0;
            default:
                print_usage(argv[0]);
                return 1;
        }
    }
    
    // Check required arguments
    if (strlen(config.output_path) == 0) {
        printf("Error: Output path (-o) is required\n");
        print_usage(argv[0]);
        return 1;
    }
    
    // Debug output
    printf("Debug: Output path set to: '%s'\n", config.output_path);
    
    // Ensure output path exists
    struct stat st = {0};
    if (stat(config.output_path, &st) == -1) {
        // Directory doesn't exist, try to create it
        if (mkdir(config.output_path, 0755) != 0) {
            printf("Error: Could not create output directory: %s (%s)\n", 
                   config.output_path, strerror(errno));
            return 1;
        }
        printf("Created output directory: %s\n", config.output_path);
    }
    
    if (strlen(config.output_filename) == 0) {
        printf("Error: Output filename (-n) is required\n");
        print_usage(argv[0]);
        return 1;
    }
    
    // Collect files and directories
    char *all_files[MAX_FILES];
    int file_count = 0;
    
    // Adjust optind to account for skipped -name arguments
    int real_optind = optind;
    if (name_arg_index >= 0 && name_arg_index < optind) {
        real_optind += 2; // Add 2 to account for -name and its value
    }
    
    // Process each file or directory argument
    for (int i = real_optind; i < argc; i++) {
        struct stat path_stat;
        if (stat(argv[i], &path_stat) != 0) {
            printf("Warning: Could not access path %s: %s\n", argv[i], strerror(errno));
            continue;
        }
        
        if (S_ISDIR(path_stat.st_mode)) {
            // It's a directory
            if (config.recursive) {
                process_directory(&config, argv[i], all_files, &file_count);
            } else {
                printf("Warning: %s is a directory. Use -r to process recursively.\n", argv[i]);
            }
        } else if (file_count < MAX_FILES) {
            // It's a file - add directly but check name pattern if specified
            if (strlen(config.name_pattern) > 0) {
                char *basename_copy = strdup(argv[i]);
                char *base_name = basename(basename_copy);
                if (fnmatch(config.name_pattern, base_name, 0) == 0) {
                    all_files[file_count++] = strdup(argv[i]);
                }
                free(basename_copy);
            } else {
                all_files[file_count++] = strdup(argv[i]);
            }
        }
    }
    
    if (file_count == 0) {
        printf("Error: No input files found matching criteria\n");
        print_usage(argv[0]);
        return 1;
    }
    
    // Copy files to config
    for (int i = 0; i < file_count && i < MAX_FILES; i++) {
        config.repo_paths[i] = all_files[i];
        config.repo_path_count++;
    }
    
    // Run the scraper
    char *output_file = run_scraper(&config);
    if (output_file) {
        free(output_file);
    }
    
    // Free allocated memory
    for (int i = 0; i < file_count; i++) {
        // No need to free config.repo_paths[i] as they point to the same memory
        // free(config.repo_paths[i]);
    }
    
    return 0;
}
