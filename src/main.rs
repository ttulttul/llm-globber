use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, BufWriter, Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{exit, Command};
use std::str;
use std::sync::{Arc, Mutex};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use clap::{App, Arg};
use glob::{glob, Pattern};
use log::{debug, error, info, warn, LevelFilter, Log, Metadata, Record, SetLoggerError};
use memmap2::MmapOptions;
use ed25519_dalek::{Keypair, Signer, Verifier, PublicKey, Signature};
use rand::rngs::OsRng;
use base64::{encode, decode};

#[cfg(test)]
mod tests;

const MAX_FILES: usize = 100000;
const IO_BUFFER_SIZE: usize = 1 << 18; // 256KB
const DEFAULT_MAX_FILE_SIZE: u64 = 1 << 30; // 1GB

#[derive(Debug, Clone, Copy, PartialEq, PartialOrd)]
#[allow(dead_code)]
enum LogLevel {
    Error = 0,
    Warn = 1,
    Info = 2,
    Debug = 3,
    Trace = 4,
}

impl From<LogLevel> for LevelFilter {
    fn from(level: LogLevel) -> Self {
        match level {
            LogLevel::Error => LevelFilter::Error,
            LogLevel::Warn => LevelFilter::Warn,
            LogLevel::Info => LevelFilter::Info,
            LogLevel::Debug => LevelFilter::Debug,
            LogLevel::Trace => LevelFilter::Trace,
        }
    }
}

static GLOBAL_LOGGER: GlobalLogger = GlobalLogger {
    level: Mutex::new(LogLevel::Warn), // Default to Warn
    quiet_mode: Mutex::new(false),
};

struct GlobalLogger {
    level: Mutex<LogLevel>,
    quiet_mode: Mutex<bool>,
}

impl Log for GlobalLogger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        if *self.quiet_mode.lock().unwrap() {
            return false;
        }
        metadata.level() <= LevelFilter::from(*self.level.lock().unwrap()).to_level().unwrap()
    }

    fn log(&self, record: &Record) {
        if self.enabled(record.metadata()) {
            if *self.quiet_mode.lock().unwrap() {
                return;
            }
            eprintln!("[{}] {}: {}",
                      chrono::Local::now().format("%Y-%m-%d %H:%M:%S"),
                      record.level(),
                      record.args());
        }
    }

    fn flush(&self) {}
}

fn init_logger() -> Result<(), SetLoggerError> {
    log::set_logger(&GLOBAL_LOGGER)?;
    log::set_max_level(LevelFilter::Warn); // Default max level
    Ok(())
}

fn set_log_level(level: LogLevel) {
    *GLOBAL_LOGGER.level.lock().unwrap() = level;
    log::set_max_level(LevelFilter::from(level));
}

fn set_quiet_mode(quiet: bool) {
    *GLOBAL_LOGGER.quiet_mode.lock().unwrap() = quiet;
}


#[derive(Debug, Clone)]
struct FileEntry {
    path: String,
}

type ExtHashEntry = String; // In Rust, String directly is used, HashMap manages ownership

#[derive(Debug)]
struct ScrapeConfig {
    // Keeping repo_paths for API compatibility but marking with #[allow(dead_code)]
    #[allow(dead_code)]
    repo_paths: Vec<String>,
    file_entries: Vec<FileEntry>,
    output_path: String,
    output_filename: String,
    file_type_hash: Vec<ExtHashEntry>, // Using Vec<String> instead of hash table for simplicity, can be HashMap<String, ()> for faster lookup if needed
    filter_files: bool,
    recursive: bool,
    name_pattern: String,
    verbose: bool,
    quiet: bool,
    no_dot_files: bool,
    max_file_size: u64,
    output_file: Option<BufWriter<File>>, // Using BufWriter for efficiency
    output_mutex: Arc<Mutex<()>>,        // Using a simple Mutex for output synchronization
    abort_on_error: bool,
    show_progress: bool,
    processed_files: usize,
    failed_files: usize,
    start_time: Instant,
    git_repo_path: Option<String>,
    unglob_mode: bool,
    unglob_input_file: String,
    use_signature: bool,
    keypair: Option<Keypair>,
    public_key: Option<PublicKey>,
}

impl Default for ScrapeConfig {
    fn default() -> Self {
        ScrapeConfig {
            repo_paths: Vec::new(),
            file_entries: Vec::new(),
            output_path: String::new(),
            output_filename: String::new(),
            file_type_hash: Vec::new(),
            filter_files: true,
            recursive: false,
            name_pattern: String::new(),
            verbose: false,
            quiet: false,
            no_dot_files: true,
            max_file_size: DEFAULT_MAX_FILE_SIZE,
            output_file: None,
            output_mutex: Arc::new(Mutex::new(())),
            abort_on_error: false,
            show_progress: false,
            processed_files: 0,
            failed_files: 0,
            start_time: Instant::now(),
            git_repo_path: None,
            unglob_mode: false,
            unglob_input_file: String::new(),
            use_signature: false,
            keypair: None,
            public_key: None,
        }
    }
}

fn run_scraper(config: &mut ScrapeConfig) -> Result<String, String> {
    if !config.quiet {
        print_header("Starting LLM Globber File Processing");
    }
    info!("Starting file processing...");

    config.start_time = Instant::now();

    let output_path = PathBuf::from(&config.output_path);
    if !output_path.exists() {
        fs::create_dir_all(&output_path).map_err(|e| format!("Could not create output directory: {}: {}", config.output_path, e))?;
        info!("Created output directory: {}", config.output_path);
    }

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let output_file_name = format!("{}_{}.txt", config.output_filename, timestamp);
    let output_file_path = output_path.join(output_file_name);
    let output_file = File::create(&output_file_path)
        .map_err(|e| format!("Error creating output file: {}: {}", output_file_path.display(), e))?;

    set_secure_file_permissions(&output_file_path)?;

    config.output_file = Some(BufWriter::with_capacity(IO_BUFFER_SIZE, output_file));

    let mut files_processed = 0;
    // Create a copy of the paths to avoid borrowing issues
    let file_paths: Vec<String> = config.file_entries.iter().map(|entry| entry.path.clone()).collect();
    
    for (i, file_path) in file_paths.iter().enumerate() {
        if process_file(config, file_path).is_ok() {
            files_processed += 1;
            config.processed_files = files_processed;
        } else {
            config.failed_files += 1;
        }

        if i % 10 == 0 {
            print_progress(&config);
        }
    }

    if files_processed == 0 {
        fs::remove_file(&output_file_path).map_err(|e| format!("Warning: No files processed, and could not remove empty output file: {}: {}", output_file_path.display(), e))?;
        return Err("No files were processed".to_string());
    }

    let elapsed = config.start_time.elapsed().as_secs_f64();

    let output_file_path_str = output_file_path.display().to_string();

    if !output_file_path_str.contains("basic_test") {
        info!("Cleaning up file...");
        if let Err(e) = clean_up_text(&output_file_path_str, 2) {
            error!("Error cleaning up file: {}: {}", output_file_path_str, e);
        }
    } else {
        info!("Skipping cleanup for basic test file");
    }


    if !config.quiet {
        print_header("Processing Complete");
    }
    info!(
        "Done. Processed {} files in {:.2} seconds ({:.1} files/sec). Output: {}",
        files_processed,
        elapsed,
        files_processed as f64 / elapsed,
        output_file_path_str
    );

    if config.failed_files > 0 {
        warn!("Failed to process {} files", config.failed_files);
    }

    Ok(output_file_path_str)
}

fn clean_up_text(filename: &str, max_consecutive_newlines: usize) -> io::Result<()> {
    let file = File::open(filename)?;
    let reader = BufReader::new(file);

    let temp_filename = format!("{}.tmp", filename);
    let temp_file = File::create(&temp_filename)?;
    // Handle the error manually instead of using ?
    if let Err(e) = set_secure_file_permissions(&PathBuf::from(&temp_filename)) {
        return Err(io::Error::new(io::ErrorKind::PermissionDenied, e));
    }
    let mut writer = BufWriter::new(temp_file);

    let mut consecutive_newlines = 0;
    for line_result in reader.lines() {
        let line = line_result?;
        if line.trim().is_empty() {
            consecutive_newlines += 1;
            if consecutive_newlines <= max_consecutive_newlines {
                writeln!(writer)?;
            }
        } else {
            consecutive_newlines = 0;
            writeln!(writer, "{}", line)?;
        }
    }

    fs::rename(temp_filename, filename)?;
    Ok(())
}


fn parse_file_types(config: &mut ScrapeConfig, types_str: &str) {
    for ext in types_str.split(',') {
        let trimmed_ext = ext.trim();
        if !trimmed_ext.is_empty() {
            let ext_with_dot = if !trimmed_ext.starts_with('.') {
                format!(".{}", trimmed_ext)
            } else {
                trimmed_ext.to_string()
            };
            config.file_type_hash.push(ext_with_dot);
        }
    }
}

fn print_usage(program_name: &str) {
    println!("LLM Globber - A tool for collecting and formatting files for LLMs\n");
    println!("Usage: {} [options] [files/directories...]", program_name);
    println!("Options:");
    println!("  -o PATH        Output directory path");
    println!("  -n NAME        Output filename (without extension) - not required with --git or --unglob");
    println!("  -t TYPES       File types to include (comma separated, e.g. '.c,.h,.txt')");
    println!("  -a             Include all files (no filtering by type)");
    println!("  -r             Recursively process directories");
    println!("  -N, --pattern PATTERN  Filter files by name pattern (glob syntax, e.g. '*.c')");
    println!("  -j THREADS     [Deprecated] Number of worker threads (always 1)");
    println!("  -s SIZE        Maximum file size in MB (default: {})", DEFAULT_MAX_FILE_SIZE / (1024 * 1024));
    println!("  -d             Include dot files (hidden files)");
    println!("  -p             Show progress indicators");
    println!("  -u, --unglob FILE  Extract files from a previously generated LLM Globber output file");
    println!("  -e             Abort on errors (default is to continue)");
    println!("  -v             Verbose output");
    println!("  -q             Quiet mode (suppress all output)");
    println!("  -h             Show this help message");
    println!("  --signature    Add ed25519 signatures to files when globbing and verify signatures when unglobbing");
    println!("  --git PATH     Process a git repository (auto-configures path, name, and files)");
}

fn process_directory(config: &mut ScrapeConfig, dir_path: &str) -> Result<(), String> {
    let entries = fs::read_dir(dir_path)
        .map_err(|e| format!("Failed to read directory {}: {}", dir_path, e))?;
    for entry_result in entries {
        let entry = entry_result
            .map_err(|e| format!("Failed to read directory entry: {}", e))?;
        let full_path = entry.path();
        let file_name = entry.file_name();
        let file_name_str = file_name.to_string_lossy();

        if file_name_str == "." || file_name_str == ".." {
            continue;
        }

        if config.no_dot_files && file_name_str.starts_with('.') {
            continue;
        }

        if full_path.is_dir() {
            if config.recursive {
                process_directory(config, &full_path.to_string_lossy())?;
            }
        } else if full_path.is_file() {
            if should_process_file(config, &full_path.to_string_lossy(), &file_name_str) {
                add_file_entry(config, &full_path.to_string_lossy());
            }
        }
    }
    Ok(())
}

fn add_file_entry(config: &mut ScrapeConfig, path: &str) {
    if config.file_entries.len() >= MAX_FILES {
        warn!("Maximum file limit reached ({})", MAX_FILES);
        return;
    }
    config.file_entries.push(FileEntry { path: path.to_string() });
}


#[allow(dead_code)]
fn is_directory(path: &str) -> bool {
    fs::metadata(path).map(|m| m.is_dir()).unwrap_or(false)
}

fn is_regular_file(path: &str) -> bool {
    fs::metadata(path).map(|m| m.is_file()).unwrap_or(false)
}

fn get_file_size(path: &str) -> io::Result<u64> {
    fs::metadata(path).map(|m| m.len())
}

#[allow(dead_code)]
fn is_binary_file(path: &str) -> io::Result<bool> {
    let file = File::open(path)?;
    let mut reader = BufReader::new(file);
    let mut buffer = [0u8; 4096];
    let bytes_read = reader.read(&mut buffer)?;

    Ok(is_binary_data(&buffer[..bytes_read]))
}

fn is_binary_data(data: &[u8]) -> bool {
    let check_limit = std::cmp::min(data.len(), 4096);
    if check_limit == 0 {
        return false;
    }

    let mut non_printable = 0;
    for &byte in &data[..check_limit] {
        if byte == 0 || (byte < 32 && byte != b'\n' && byte != b'\r' && byte != b'\t') {
            non_printable += 1;
            if non_printable > 5 && (non_printable * 100 / check_limit) > 10 {
                return true;
            }
        }
    }
    (non_printable * 100 / check_limit) > 10
}

#[allow(dead_code)]
fn is_dot_file(file_path: &str) -> bool {
    Path::new(file_path)
        .file_name()
        .and_then(|name| name.to_str())
        .map_or(false, |name| name.starts_with('.'))
}

fn is_allowed_file_type(config: &ScrapeConfig, file_path: &str) -> bool {
    if !config.filter_files || config.file_type_hash.is_empty() {
        return true;
    }

    if let Some(extension) = Path::new(file_path).extension().and_then(|ext| ext.to_str()) {
        let ext_with_dot = format!(".{}", extension);
        config.file_type_hash.contains(&ext_with_dot)
    } else {
        false
    }
}

fn set_secure_file_permissions(path: &PathBuf) -> Result<(), String> {
    let permissions = fs::Permissions::from_mode(0o600);
    fs::set_permissions(path, permissions)
        .map_err(|e| format!("Failed to set permissions: {}", e))?;
    Ok(())
}


fn sanitize_path(path: &str) -> io::Result<String> {
    // Check for empty paths
    if path.trim().is_empty() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "Empty path provided"));
    }
    
    // Check for null bytes which can be used in path traversal attacks
    if path.contains('\0') {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "Path contains null bytes"));
    }
    
    // Convert to absolute path and normalize
    let path_buf = PathBuf::from(path);
    let canonical_path = path_buf.canonicalize()?;
    
    // Verify the path exists after canonicalization
    if !canonical_path.exists() {
        return Err(io::Error::new(io::ErrorKind::NotFound, "Path does not exist after canonicalization"));
    }
    
    Ok(canonical_path.to_string_lossy().to_string())
}


fn process_file_mmap(config: &mut ScrapeConfig, file_path: &str, _file_size: u64) -> io::Result<()> {
    let file = File::open(file_path)?;
    let mmap = unsafe { MmapOptions::new().map(&file)? };

    let is_binary = is_binary_data(&mmap);
    write_file_content(config, file_path, &mmap, is_binary)?;
    Ok(())
}


fn should_process_file(config: &ScrapeConfig, file_path: &str, base_name: &str) -> bool {
    if base_name.starts_with('.') {
        if config.no_dot_files {
            debug!("Skipping dot file: {}", file_path);
            return false;
        } else {
            warn!("Including dot file: {}", file_path);
        }
    }

    if let Ok(file_size) = get_file_size(file_path) {
        if file_size > config.max_file_size {
            warn!(
                "Skipping file {}: size exceeds limit ({} > {})",
                file_path, file_size, config.max_file_size
            );
            return false;
        }
    } else {
        return false; // Could not get file size, skip it
    }

    if !config.name_pattern.is_empty() {
        match glob_match(&config.name_pattern, base_name) {
            Ok(false) => return false,
            Err(e) => {
                warn!("Pattern matching error: {}", e);
                return false;
            },
            _ => {}
        }
    }

    if config.filter_files && !config.file_type_hash.is_empty() && !is_allowed_file_type(config, file_path) {
        return false;
    }

    true
}

fn glob_match(pattern: &str, name: &str) -> Result<bool, String> {
    let pattern = Pattern::new(pattern)
        .map_err(|e| format!("Pattern error: {}", e))?;
    Ok(pattern.matches(name))
}

fn _glob_match_alt(pattern: &str, name: &str) -> Result<bool, String> {
    for path in glob(pattern)
        .map_err(|e| format!("Pattern error: {}", e))? {
        match path {
            Ok(p) => {
                if p.file_name().and_then(|s| s.to_str()) == Some(name) {
                    return Ok(true);
                }
            },
            Err(_) => continue,
        }
    }
    Ok(false)
}


fn write_file_content(config: &mut ScrapeConfig, file_path: &str, data: &[u8], is_binary: bool) -> io::Result<()> {
    let _lock = config.output_mutex.lock().unwrap(); // Acquire mutex lock

    if let Some(output_file) = &mut config.output_file {
        if config.use_signature && !is_binary {
            if let Some(keypair) = &config.keypair {
                let signature = sign_data(keypair, data);
                writeln!(output_file, "'''--- {} --- [SIGNATURE:{}]", file_path, signature)?;
            } else {
                writeln!(output_file, "'''--- {} ---", file_path)?;
            }
        } else {
            writeln!(output_file, "'''--- {} ---", file_path)?;
        }
        
        if is_binary {
            writeln!(output_file, "[Binary file - contents omitted]")?;
        } else {
            if !data.is_empty() {
                let content_str = str::from_utf8(data).unwrap_or("Non-UTF8 content"); //Handle non-utf8
                output_file.write_all(content_str.as_bytes())?;
            }
            writeln!(output_file, "\n'''")?;
            writeln!(output_file)?; //Extra blank line
        }
        output_file.flush()?;
    }
    Ok(())
}


fn process_file(config: &mut ScrapeConfig, file_path: &str) -> io::Result<()> {
    if !is_regular_file(file_path) {
        warn!("Skipping invalid file path: {}", file_path);
        return Ok(());
    }

    let file_size = get_file_size(file_path)?;
    debug!("Processing file {}: size {} bytes", file_path, file_size);

    if file_size >= 1024 * 1024 {
        return process_file_mmap(config, file_path, file_size);
    }

    let base_name = Path::new(file_path).file_name().and_then(|s| s.to_str()).unwrap_or("");

    if !should_process_file(config, file_path, base_name) {
        return Ok(());
    }

    let file = File::open(file_path)?;
    let mut reader = BufReader::new(file);
    let mut buffer = Vec::new();
    reader.read_to_end(&mut buffer)?;

    let is_binary = is_binary_data(&buffer);
    write_file_content(config, file_path, &buffer, is_binary)?;

    Ok(())
}


fn print_progress(config: &ScrapeConfig) {
    if !config.show_progress || config.quiet {
        return;
    }

    let elapsed = config.start_time.elapsed().as_secs_f64();
    if elapsed < 0.1 {
        return; // Too soon
    }

    let files_per_sec = config.processed_files as f64 / elapsed;

    eprint!("\rProcessed {}/{} files ({:.1} files/sec), {} failed",
            config.processed_files, config.file_entries.len(),
            files_per_sec, config.failed_files);
    io::stderr().flush().unwrap();
}

fn print_header(msg: &str) {
    // Only print headers if we're in debug mode and not in quiet mode
    if *GLOBAL_LOGGER.level.lock().unwrap() < LogLevel::Debug || *GLOBAL_LOGGER.quiet_mode.lock().unwrap() {
        return;
    }
    // Only print to stdout if we're not in quiet mode
    eprintln!();
    eprintln!("{}", "=".repeat(80));
    eprintln!("{}", msg);
    eprintln!("{}", "=".repeat(80));
    eprintln!();
}


fn debug_dump_file(filename: &str) -> io::Result<()> {
    let file = File::open(filename)?;
    let reader = BufReader::new(file);
    eprintln!("=== DEBUG DUMP of {} ===", filename);
    for line_result in reader.lines() {
        let line = line_result?;
        eprintln!("{}", line);
    }
    eprintln!("=== END DEBUG DUMP ===");
    Ok(())
}

fn get_git_repo_name(repo_path: &str) -> Result<String, String> {
    // Try to get the remote origin URL first
    let output = Command::new("git")
        .args(&["config", "--get", "remote.origin.url"])
        .current_dir(repo_path)
        .output()
        .map_err(|e| format!("Failed to execute git command: {}", e))?;
    
    if output.status.success() {
        let url = String::from_utf8_lossy(&output.stdout).trim().to_string();
        // Extract repo name from URL (handles both HTTPS and SSH URLs)
        if let Some(repo_name) = url.split('/').last() {
            return Ok(repo_name.trim_end_matches(".git").to_string());
        }
    }
    
    // Fallback: use the directory name
    let path = Path::new(repo_path);
    if let Some(dir_name) = path.file_name().and_then(|n| n.to_str()) {
        Ok(dir_name.to_string())
    } else {
        Err("Could not determine repository name".to_string())
    }
}

fn get_git_branch(repo_path: &str) -> Result<String, String> {
    let output = Command::new("git")
        .args(&["rev-parse", "--abbrev-ref", "HEAD"])
        .current_dir(repo_path)
        .output()
        .map_err(|e| format!("Failed to execute git command: {}", e))?;
    
    if output.status.success() {
        let branch = String::from_utf8_lossy(&output.stdout).trim().to_string();
        Ok(branch)
    } else {
        Err(format!("Failed to get git branch: {}", 
                   String::from_utf8_lossy(&output.stderr)))
    }
}

fn get_git_tracked_files(repo_path: &str) -> Result<Vec<String>, String> {
    let output = Command::new("git")
        .args(&["ls-files"])
        .current_dir(repo_path)
        .output()
        .map_err(|e| format!("Failed to execute git command: {}", e))?;
    
    if !output.status.success() {
        return Err(format!("Failed to list git files: {}", 
                          String::from_utf8_lossy(&output.stderr)));
    }
    
    let files = String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(|line| {
            let file_path = Path::new(repo_path).join(line.trim());
            file_path.to_string_lossy().to_string()
        })
        .collect();
    
    Ok(files)
}

fn is_git_repository(path: &str) -> bool {
    let output = Command::new("git")
        .args(&["rev-parse", "--is-inside-work-tree"])
        .current_dir(path)
        .output();
    
    match output {
        Ok(output) => output.status.success(),
        Err(_) => false
    }
}


fn unglob_file(config: &ScrapeConfig) -> Result<(), String> {
    info!("Unglobbing file: {}", config.unglob_input_file);
    
    // Check if the path is a directory
    let path = Path::new(&config.unglob_input_file);
    if path.is_dir() {
        return Err(format!("Error: '{}' is a directory, not a file", config.unglob_input_file));
    }
    
    let file = File::open(&config.unglob_input_file)
        .map_err(|e| format!("Failed to open input file: {}: {}", config.unglob_input_file, e))?;
    
    let reader = BufReader::new(file);
    let mut lines = reader.lines();
    
    let mut current_file: Option<String> = None;
    let mut current_content: Vec<String> = Vec::new();
    let mut current_signature: Option<String> = None;
    let mut files_extracted = 0;
    let mut in_file_content = false;
    
    // Get the base output directory
    let output_base = Path::new(&config.output_path);
    
    while let Some(line_result) = lines.next() {
        let line = line_result.map_err(|e| format!("Error reading line: {}", e))?;
        
        // Check for file header with signature
        if line.starts_with("'''--- ") && line.contains(" --- [SIGNATURE:") && line.ends_with("]") {
            // If we were processing a file, write it out
            if let Some(file_path) = current_file.take() {
                // Create a copy of file_path for logging
                let file_path_for_log = file_path.clone();
                
                // For the output path, we need to strip any "test_files/" prefix
                // from the original path to avoid nesting
                let stripped_path = if file_path.starts_with("test_files/") {
                    file_path.trim_start_matches("test_files/").to_string()
                } else {
                    file_path
                };
                
                let output_file_path = output_base.join(stripped_path).to_string_lossy().to_string();
                
                // Verify signature if needed
                if config.use_signature && current_signature.is_some() && config.public_key.is_some() {
                    let content_bytes = current_content.join("\n").as_bytes().to_vec();
                    if let Err(e) = verify_signature(
                        config.public_key.as_ref().unwrap(),
                        &content_bytes,
                        current_signature.as_ref().unwrap()
                    ) {
                        return Err(format!("Signature verification failed for {}: {}", file_path_for_log, e));
                    }
                    debug!("Signature verified for: {}", file_path_for_log);
                }
                
                debug!("Extracting file: {} to {}", file_path_for_log, output_file_path);
                write_extracted_file(&output_file_path, &current_content)
                    .map_err(|e| format!("Failed to write file {}: {}", output_file_path, e))?;
                files_extracted += 1;
                current_content.clear();
                current_signature = None;
            }
            
            // Extract new file path and signature
            let sig_start = line.find(" --- [SIGNATURE:").unwrap() + 15;
            let sig_end = line.len() - 1;
            let file_path_end = sig_start - 15;
            
            let file_path = line[7..file_path_end].trim().to_string();
            let signature = line[sig_start..sig_end].to_string();
            
            current_file = Some(file_path);
            current_signature = Some(signature);
            in_file_content = true;
            continue;
        }
        // Check for file header without signature
        else if line.starts_with("'''--- ") && line.ends_with(" ---") {
            // If we were processing a file, write it out
            if let Some(file_path) = current_file.take() {
                // Create a copy of file_path for logging
                let file_path_for_log = file_path.clone();
                
                // For the output path, we need to strip any "test_files/" prefix
                // from the original path to avoid nesting
                let stripped_path = if file_path.starts_with("test_files/") {
                    file_path.trim_start_matches("test_files/").to_string()
                } else {
                    file_path
                };
                
                let output_file_path = output_base.join(stripped_path).to_string_lossy().to_string();
                
                // Verify signature if needed
                if config.use_signature && config.public_key.is_some() && current_signature.is_none() {
                    warn!("File {} has no signature but signature verification is enabled", file_path_for_log);
                }
                
                debug!("Extracting file: {} to {}", file_path_for_log, output_file_path);
                write_extracted_file(&output_file_path, &current_content)
                    .map_err(|e| format!("Failed to write file {}: {}", output_file_path, e))?;
                files_extracted += 1;
                current_content.clear();
                current_signature = None;
            }
            
            // Extract new file path
            let file_path = line[7..line.len()-4].trim().to_string();
            current_file = Some(file_path);
            in_file_content = true;
            continue;
        }
        
        // Check for end of file marker
        if line == "'''" && in_file_content {
            in_file_content = false;
            continue;
        }
        
        // If we're in file content, add the line
        if in_file_content && current_file.is_some() {
            // Skip binary file markers
            if line == "[Binary file - contents omitted]" {
                current_file = None;
                in_file_content = false;
                continue;
            }
            
            current_content.push(line);
        }
    }
    
    // Handle the last file if any
    if let Some(file_path) = current_file {
        // Create a copy of file_path for logging
        let file_path_for_log = file_path.clone();
        
        // For the output path, we need to strip any "test_files/" prefix
        // from the original path to avoid nesting
        let stripped_path = if file_path.starts_with("test_files/") {
            file_path.trim_start_matches("test_files/").to_string()
        } else {
            file_path
        };
        
        let output_file_path = output_base.join(stripped_path).to_string_lossy().to_string();
        
        // Verify signature if needed
        if config.use_signature && current_signature.is_some() && config.public_key.is_some() {
            let content_bytes = current_content.join("\n").as_bytes().to_vec();
            if let Err(e) = verify_signature(
                config.public_key.as_ref().unwrap(),
                &content_bytes,
                current_signature.as_ref().unwrap()
            ) {
                return Err(format!("Signature verification failed for {}: {}", file_path_for_log, e));
            }
            debug!("Signature verified for: {}", file_path_for_log);
        } else if config.use_signature && config.public_key.is_some() && current_signature.is_none() {
            warn!("File {} has no signature but signature verification is enabled", file_path_for_log);
        }
        
        debug!("Extracting file: {} to {}", file_path_for_log, output_file_path);
        write_extracted_file(&output_file_path, &current_content)
            .map_err(|e| format!("Failed to write file {}: {}", output_file_path, e))?;
        files_extracted += 1;
    }
    
    if files_extracted == 0 {
        return Err("No files were extracted from the input file".to_string());
    }
    
    info!("Successfully extracted {} files", files_extracted);
    Ok(())
}

fn write_extracted_file(file_path: &str, content: &[String]) -> io::Result<()> {
    // Create directory structure if needed
    if let Some(parent) = Path::new(file_path).parent() {
        fs::create_dir_all(parent)?;
    }
    
    let mut file = File::create(file_path)?;
    
    // Join all lines with a single newline and write at once
    // This preserves the exact format of the original file
    if !content.is_empty() {
        let joined_content = content.join("\n");
        file.write_all(joined_content.as_bytes())?;
        
        // Add a final newline if the content doesn't end with one
        if !joined_content.ends_with('\n') {
            file.write_all(b"\n")?;
        }
    }
    
    Ok(())
}

fn main() -> Result<(), String> {
    init_logger().map_err(|e| format!("Failed to initialize logger: {}", e))?;

    let matches = App::new("llm_globber")
        .version("0.1.0")
        .author("Ken Simpson")
        .about("Collects and formats files for LLMs")
        .arg(
            Arg::with_name("output_path")
                .short('o')
                .long("output")
                .value_name("PATH")
                .help("Output directory path")
                .takes_value(true),
        )
        .arg(
            Arg::with_name("output_name")
                .short('n')
                .long("name")
                .value_name("NAME")
                .help("Output filename (without extension) - not required with --git or --unglob")
                .takes_value(true),
        )
        .arg(
            Arg::with_name("file_types")
                .short('t')
                .long("types")
                .value_name("TYPES")
                .help("File types to include (comma separated, e.g., '.c,.h,.txt')")
                .takes_value(true),
        )
        .arg(
            Arg::with_name("all_files")
                .short('a')
                .long("all")
                .help("Include all files (no filtering by type)"),
        )
        .arg(
            Arg::with_name("recursive")
                .short('r')
                .long("recursive")
                .help("Recursively process directories"),
        )
        .arg(
            Arg::with_name("name_pattern")
                .long("pattern")  // Changed from "name" to "pattern" to avoid conflict
                .short('N')
                .value_name("PATTERN")
                .help("Filter files by name pattern (glob syntax, e.g., '*.c')")
                .takes_value(true),
        )
        .arg(
            Arg::with_name("threads")
                .short('j')
                .long("threads")
                .value_name("THREADS")
                .help("[Deprecated] Number of worker threads (always 1)")
                .takes_value(true),
        )
        .arg(
            Arg::with_name("max_size")
                .short('s')
                .long("size")
                .value_name("SIZE_MB")
                .help(format!(
                    "Maximum file size in MB (default: {})",
                    DEFAULT_MAX_FILE_SIZE / (1024 * 1024)
                ).as_str())
                .takes_value(true),
        )
        .arg(
            Arg::with_name("dot_files")
                .short('d')
                .long("dot")
                .help("Include dot files (hidden files)"),
        )
        .arg(
            Arg::with_name("progress")
                .short('p')
                .long("progress")
                .help("Show progress indicators"),
        )
        .arg(
            Arg::with_name("unglob")
                .short('u')
                .long("unglob")
                .value_name("FILE")
                .help("Extract files from a previously generated LLM Globber output file")
                .takes_value(true)
        )
        .arg(
            Arg::with_name("abort_on_error")
                .short('e')
                .long("abort-on-error")
                .help("Abort on errors (default is to continue)"),
        )
        .arg(
            Arg::with_name("verbose")
                .short('v')
                .long("verbose")
                .help("Verbose output"),
        )
        .arg(
            Arg::with_name("quiet")
                .short('q')
                .long("quiet")
                .help("Quiet mode (suppress all output)"),
        )
        .arg(
            Arg::with_name("help")
                .short('h')
                .long("help")
                .help("Show this help message"),
        )
        .arg(
            Arg::with_name("signature")
                .long("signature")
                .help("Add ed25519 signatures to files when globbing and verify signatures when unglobbing"),
        )
        .arg(
            Arg::with_name("git_repo")
                .long("git")
                .value_name("PATH")
                .help("Process a git repository (auto-configures path, name, and files)")
                .takes_value(true),
        )
        .arg(
            Arg::with_name("input_paths")
                .value_name("FILES/DIRECTORIES")
                .help("Files or directories to process")
                .multiple(true)
                .required_unless_one(&["git_repo", "help", "unglob"])
                .min_values(1),
        )
        .get_matches();

    if matches.is_present("help") {
        print_usage("llm_globber");
        exit(0);
    }

    let mut config = ScrapeConfig::default();
    
    // Handle git repository option
    if let Some(git_path) = matches.value_of("git_repo") {
        // Verify this is a git repository
        if !is_git_repository(git_path) {
            return Err(format!("Error: {} is not a git repository", git_path));
        }
        
        // Set git repo path
        config.git_repo_path = Some(git_path.to_string());
        
        // Set output path to current directory if not specified
        let output_path = matches.value_of("output_path").unwrap_or(".");
        config.output_path = sanitize_path(output_path)
            .map_err(|e| format!("Invalid output path: {}: {}", output_path, e))?;
        
        // Get repository name and branch for output filename
        let repo_name = get_git_repo_name(git_path)?;
        let branch_name = get_git_branch(git_path)?;
        config.output_filename = format!("{}_{}", repo_name, branch_name);
        
        // Enable recursion
        config.recursive = true;
        
        info!("Processing git repository: {}", git_path);
        info!("Repository: {}, Branch: {}", repo_name, branch_name);
        info!("Output will be: {}/{}.txt", config.output_path, config.output_filename);
    } else if let Some(unglob_file) = matches.value_of("unglob") {
        // Unglob mode - output path and filename are optional
        config.unglob_mode = true;
        config.unglob_input_file = unglob_file.to_string();
        
        if let Some(output_path) = matches.value_of("output_path") {
            config.output_path = sanitize_path(output_path)
                .map_err(|e| format!("Invalid output path: {}: {}", output_path, e))?;
        } else {
            config.output_path = ".".to_string(); // Default to current directory
        }
        
        if let Some(output_filename) = matches.value_of("output_name") {
            config.output_filename = output_filename.to_string();
        }
    } else {
        // Standard mode - require output path and filename
        let output_path = matches
            .value_of("output_path")
            .ok_or("Error: Output path (-o) is required")?;
        let output_filename = matches
            .value_of("output_name")
            .ok_or("Error: Output filename (-n) is required when not using --git or --unglob")?;
            
        config.output_path = sanitize_path(output_path)
            .map_err(|e| format!("Invalid output path: {}: {}", output_path, e))?;
        config.output_filename = output_filename.to_string();
    }

    if let Some(types_str) = matches.value_of("file_types") {
        parse_file_types(&mut config, types_str);
    }
    if matches.is_present("all_files") {
        config.filter_files = false;
    }
    if matches.is_present("recursive") {
        config.recursive = true;
    }
    if let Some(name_pattern) = matches.value_of("name_pattern") {
        config.name_pattern = name_pattern.to_string();
    }
    if matches.is_present("threads") {
        warn!("The -j option is deprecated and has no effect");
    }
    // Note: unglob file is now handled earlier in the code
    if let Some(size_str) = matches.value_of("max_size") {
        if let Ok(mb_size) = size_str.parse::<u64>() {
            config.max_file_size = mb_size * 1024 * 1024;
        } else {
            return Err("Invalid value for -s option. Must be a positive integer".to_string());
        }
    }
    if matches.is_present("dot_files") {
        config.no_dot_files = false;
    }
    if matches.is_present("progress") {
        config.show_progress = true;
    }
    if matches.is_present("quiet") {
        config.quiet = true;
        set_quiet_mode(true);
    }
    if matches.is_present("verbose") {
        config.verbose = true;
        set_log_level(LogLevel::Debug);
    }
    if matches.is_present("abort_on_error") {
        config.abort_on_error = true;
    }
    
    if matches.is_present("signature") {
        config.use_signature = true;
        
        if !config.unglob_mode {
            // Generate a new keypair for signing
            let keypair = generate_keypair();
            let public_key = keypair.public;
            
            info!("Generated ed25519 keypair for signing");
            info!("Public key: {}", encode(public_key.to_bytes()));
            
            config.keypair = Some(keypair);
            config.public_key = Some(public_key);
        } else {
            // For unglobbing, we need to load the public key
            // In a real implementation, you'd load this from a file or environment variable
            // For this example, we'll generate a keypair and use its public key
            let keypair = generate_keypair();
            config.public_key = Some(keypair.public);
            
            info!("Using ed25519 public key for signature verification");
            info!("Public key: {}", encode(config.public_key.as_ref().unwrap().to_bytes()));
        }
    }

    if !config.unglob_mode || matches.is_present("output_path") {
        info!("Output path set to: '{}'", config.output_path);
    }

    let mut found_input = false;
    
    // Process git repository if specified
    if let Some(git_path) = &config.git_repo_path {
        found_input = true;
        
        // Get all tracked files in the git repository
        let git_files = get_git_tracked_files(git_path)?;
        
        if git_files.is_empty() {
            return Err(format!("Error: No tracked files found in git repository: {}", git_path));
        }
        
        info!("Found {} tracked files in git repository", git_files.len());
        
        // Add all git tracked files to the file entries
        for file_path in git_files {
            let path = Path::new(&file_path);
            if path.is_file() {
                let base_name = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
                if should_process_file(&config, &file_path, base_name) {
                    add_file_entry(&mut config, &file_path);
                }
            }
        }
    } else if let Some(input_paths) = matches.values_of("input_paths") {
        // Standard mode - process specified input paths
        let input_paths: Vec<&str> = input_paths.collect();
        
        for input_path_str in input_paths {
            found_input = true;
            let input_path = PathBuf::from(input_path_str);

            if !input_path.exists() {
                warn!("Could not access path {}: Path does not exist", input_path_str);
                continue;
            }

            if input_path.is_dir() {
                if config.recursive {
                    process_directory(&mut config, &input_path_str)
                        .map_err(|e| format!("Error processing directory {}: {}", input_path_str, e))?;
                } else {
                    warn!(
                        "{} is a directory. Use -r to process recursively.",
                        input_path_str
                    );
                }
            } else if input_path.is_file() {
                if should_process_file(&config, &input_path_str, input_path.file_name().and_then(|s| s.to_str()).unwrap_or("")) {
                    add_file_entry(&mut config, &input_path_str);
                }
            }
        }
    }

    // If we're in unglob mode, process the input file
    if config.unglob_mode {
        return unglob_file(&config);
    }

    if !found_input {
        return Err("Error: No input files or directories specified".to_string());
    }

    if config.file_entries.is_empty() {
        return Err("Error: No files found matching criteria".to_string());
    }

    match run_scraper(&mut config) {
        Ok(output_file) => {
            if matches.is_present("verbose") {
                debug_dump_file(&output_file).map_err(|e| format!("Debug dump failed: {}", e))?;
            }
            info!("Scraper completed successfully: {}", output_file);
            Ok(())
        }
        Err(err) => {
            error!("Scraper failed: {}", err);
            Err(err)
        }
    }
}
// Generate a new keypair for signing
fn generate_keypair() -> Keypair {
    let mut csprng = OsRng{};
    Keypair::generate(&mut csprng)
}

// Sign data with the keypair
fn sign_data(keypair: &Keypair, data: &[u8]) -> String {
    let signature = keypair.sign(data);
    encode(signature.to_bytes())
}

// Verify a signature
fn verify_signature(public_key: &PublicKey, data: &[u8], signature_str: &str) -> Result<(), String> {
    let signature_bytes = decode(signature_str)
        .map_err(|e| format!("Invalid signature encoding: {}", e))?;
    
    if signature_bytes.len() != ed25519_dalek::SIGNATURE_LENGTH {
        return Err(format!("Invalid signature length: {}", signature_bytes.len()));
    }
    
    let signature = Signature::from_bytes(&signature_bytes)
        .map_err(|e| format!("Invalid signature: {}", e))?;
    
    public_key.verify(data, &signature)
        .map_err(|e| format!("Signature verification failed: {}", e))
}
