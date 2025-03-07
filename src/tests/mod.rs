#[cfg(test)]
mod tests {
    use std::fs::{self, File};
    use std::io::Write;
    use std::path::{Path, PathBuf};
    use std::process::Command;
    use tempfile::TempDir;

    // Helper function to create test files
    fn create_test_files(dir: &Path) -> Vec<PathBuf> {
        let files = vec![
            (dir.join("test1.c"), "This is a C test file"),
            (dir.join("test2.c"), "Another C test file"),
            (dir.join("helper.h"), "This is a header file"),
            (dir.join("readme.md"), "Documentation file"),
        ];

        for (path, content) in &files {
            let mut file = File::create(path).unwrap();
            writeln!(file, "{}", content).unwrap();
        }

        files.into_iter().map(|(path, _)| path).collect()
    }

    // Helper function to create a nested directory structure with files
    fn create_nested_test_files(dir: &Path) -> Vec<PathBuf> {
        // Create subdirectories
        let subdir1 = dir.join("dir1");
        let subdir2 = dir.join("dir1").join("subdir");
        let subdir3 = dir.join("dir2");
        
        fs::create_dir_all(&subdir1).unwrap();
        fs::create_dir_all(&subdir2).unwrap();
        fs::create_dir_all(&subdir3).unwrap();
        
        // Create files in root directory
        let mut files = vec![
            (dir.join("test1.c"), "This is a C file"),
            (dir.join("test1.h"), "This is a header file"),
            (dir.join("notes.txt"), "This is a text file"),
            (dir.join("readme.md"), "This is a markdown file"),
        ];
        
        // Create files in subdirectories
        files.extend(vec![
            (subdir1.join("nested.c"), "This is a nested C file"),
            (subdir1.join("nested.h"), "This is a nested header file"),
            (subdir2.join("deep.c"), "This is a deeply nested file"),
            (subdir3.join("other.c"), "This is another directory file"),
        ]);
        
        for (path, content) in &files {
            let mut file = File::create(path).unwrap();
            writeln!(file, "{}", content).unwrap();
        }
        
        files.into_iter().map(|(path, _)| path).collect()
    }
    
    // Helper function to create dotfiles
    fn create_dotfiles(dir: &Path) -> Vec<PathBuf> {
        let files = vec![
            (dir.join("regular.txt"), "Regular file content"),
            (dir.join(".dotfile"), "Dotfile content"),
            (dir.join(".config"), "Hidden config content"),
        ];
        
        for (path, content) in &files {
            let mut file = File::create(path).unwrap();
            writeln!(file, "{}", content).unwrap();
        }
        
        files.into_iter().map(|(path, _)| path).collect()
    }
    
    // Helper function to get the executable path
    fn get_executable_path() -> PathBuf {
        // Build the executable first if needed
        let status = Command::new("cargo")
            .args(["build", "--release"])
            .status()
            .expect("Failed to build llm_globber");
            
        assert!(status.success(), "Failed to build llm_globber");
        
        // Find the path to the executable in the target/release directory
        let executable_path = std::env::current_dir()
            .expect("Failed to get current directory")
            .join("target")
            .join("release")
            .join("llm_globber");
            
        assert!(executable_path.exists(), 
                "Executable not found at: {}", 
                executable_path.display());
                
        executable_path
    }
    
    // Helper function to find the most recent output file
    fn find_output_file(output_dir: &Path, prefix: &str) -> Option<PathBuf> {
        let entries = fs::read_dir(output_dir).ok()?
            .filter_map(|e| e.ok())
            .filter(|e| {
                e.file_name().to_string_lossy().starts_with(prefix)
            })
            .collect::<Vec<_>>();
            
        if entries.is_empty() {
            return None;
        }
        
        // Sort by modification time, most recent first
        let mut entries_with_time = entries.iter()
            .filter_map(|e| {
                e.metadata().ok().and_then(|m| {
                    m.modified().ok().map(|time| (e.path(), time))
                })
            })
            .collect::<Vec<_>>();
            
        entries_with_time.sort_by(|a, b| b.1.cmp(&a.1));
        
        entries_with_time.first().map(|(path, _)| path.clone())
    }

    #[test]
    fn test_name_pattern_filtering() {
        // Create a temporary directory for test files
        let temp_dir = TempDir::new().unwrap();
        let test_dir = temp_dir.path();
        
        // Create test files
        let _files = create_test_files(test_dir);
        
        // Create output directory
        let output_dir = temp_dir.path().join("output");
        fs::create_dir(&output_dir).unwrap();
        
        // Get executable path
        let executable_path = get_executable_path();
            
        // Run llm_globber with name pattern filter
        let output = Command::new(&executable_path)
            .args([
                "-o", output_dir.to_str().unwrap(),
                "-n", "name_pattern_test",
                "--pattern", "test*.c",
                "-r",
                test_dir.to_str().unwrap(),
            ])
            .output()
            .expect("Failed to execute llm_globber");
        
        // Check if command was successful
        assert!(output.status.success(), 
                "llm_globber failed: {}", 
                String::from_utf8_lossy(&output.stderr));
        
        // Find the generated output file
        let output_file = find_output_file(&output_dir, "name_pattern_test_")
            .expect("No output file was generated");
        
        // Read the output file
        let content = fs::read_to_string(&output_file).unwrap();
        
        // Verify that only test*.c files are included
        assert!(content.contains("test1.c"), "Output should contain test1.c");
        assert!(content.contains("test2.c"), "Output should contain test2.c");
        assert!(!content.contains("helper.h"), "Output should not contain helper.h");
        assert!(!content.contains("readme.md"), "Output should not contain readme.md");
        
        // Count the number of file headers in the output
        let file_headers = content.lines()
            .filter(|line| line.starts_with("'''---"))
            .collect::<Vec<_>>();
        
        assert_eq!(file_headers.len(), 2, "Expected exactly 2 matching files");
        
        // Verify all files match the pattern
        for header in file_headers {
            assert!(header.contains("test") && header.contains(".c"), 
                   "Found file not matching pattern: {}", header);
        }
    }
    
    #[test]
    fn test_file_types_filtering() {
        // Create a temporary directory for test files
        let temp_dir = TempDir::new().unwrap();
        let test_dir = temp_dir.path();
        
        // Create test files
        let _files = create_test_files(test_dir);
        
        // Create output directory
        let output_dir = temp_dir.path().join("output");
        fs::create_dir(&output_dir).unwrap();
        
        // Get executable path
        let executable_path = get_executable_path();
        
        // Run llm_globber with file type filter (.h files only) and recursive flag
        let output = Command::new(&executable_path)
            .args([
                "-o", output_dir.to_str().unwrap(),
                "-n", "file_types_test",
                "-t", ".h",
                "-r",
                test_dir.to_str().unwrap(),
            ])
            .output()
            .expect("Failed to execute llm_globber");
        
        // Check if command was successful
        assert!(output.status.success(), 
                "llm_globber failed: {}", 
                String::from_utf8_lossy(&output.stderr));
        
        // Find the generated output file
        let output_file = find_output_file(&output_dir, "file_types_test_")
            .expect("No output file was generated");
        
        // Read the output file
        let content = fs::read_to_string(&output_file).unwrap();
        
        // Verify that only .h files are included
        assert!(!content.contains("test1.c"), "Output should not contain test1.c");
        assert!(!content.contains("test2.c"), "Output should not contain test2.c");
        assert!(content.contains("helper.h"), "Output should contain helper.h");
        assert!(!content.contains("readme.md"), "Output should not contain readme.md");
        
        // Count the number of file headers in the output
        let file_headers = content.lines()
            .filter(|line| line.starts_with("'''---"))
            .collect::<Vec<_>>();
        
        assert_eq!(file_headers.len(), 1, "Expected exactly 1 matching file");
        
        // Verify all files have .h extension
        for header in file_headers {
            assert!(header.contains(".h"), "Found file without .h extension: {}", header);
        }
    }
    
    #[test]
    fn test_recursive_directory_processing() {
        // Create a temporary directory for test files
        let temp_dir = TempDir::new().unwrap();
        let test_dir = temp_dir.path();
        
        // Create nested test files
        let _files = create_nested_test_files(test_dir);
        
        // Create output directory
        let output_dir = temp_dir.path().join("output");
        fs::create_dir(&output_dir).unwrap();
        
        // Get executable path
        let executable_path = get_executable_path();
        
        // Run llm_globber with recursive option and .c file type filter
        let output = Command::new(&executable_path)
            .args([
                "-o", output_dir.to_str().unwrap(),
                "-n", "recursive_test",
                "-t", ".c",
                "-r",
                test_dir.to_str().unwrap(),
            ])
            .output()
            .expect("Failed to execute llm_globber");
        
        // Check if command was successful
        assert!(output.status.success(), 
                "llm_globber failed: {}", 
                String::from_utf8_lossy(&output.stderr));
        
        // Find the generated output file
        let output_file = find_output_file(&output_dir, "recursive_test_")
            .expect("No output file was generated");
        
        // Read the output file
        let content = fs::read_to_string(&output_file).unwrap();
        
        // Verify that all .c files are included, including those in subdirectories
        assert!(content.contains("test1.c"), "Output should contain test1.c");
        assert!(content.contains("nested.c"), "Output should contain nested.c");
        assert!(content.contains("deep.c"), "Output should contain deep.c");
        assert!(content.contains("other.c"), "Output should contain other.c");
        
        // Verify that non-.c files are not included
        assert!(!content.contains("test1.h"), "Output should not contain test1.h");
        assert!(!content.contains("nested.h"), "Output should not contain nested.h");
        assert!(!content.contains("notes.txt"), "Output should not contain notes.txt");
        assert!(!content.contains("readme.md"), "Output should not contain readme.md");
        
        // Count the number of file headers in the output
        let file_headers = content.lines()
            .filter(|line| line.starts_with("'''---"))
            .collect::<Vec<_>>();
        
        assert_eq!(file_headers.len(), 4, "Expected exactly 4 matching files");
    }
    
    #[test]
    fn test_dotfile_handling() {
        // Create a temporary directory for test files
        let temp_dir = TempDir::new().unwrap();
        let test_dir = temp_dir.path();
        
        // Create dotfiles
        let _files = create_dotfiles(test_dir);
        
        // Create output directory
        let output_dir = temp_dir.path().join("output");
        fs::create_dir(&output_dir).unwrap();
        
        // Get executable path
        let executable_path = get_executable_path();
        
        // First test: without -d flag (should exclude dotfiles)
        let output_without_d = Command::new(&executable_path)
            .args([
                "-o", output_dir.to_str().unwrap(),
                "-n", "no_dotfiles_test",
                "-a",
                "-r",
                test_dir.to_str().unwrap(),
            ])
            .output()
            .expect("Failed to execute llm_globber");
        
        assert!(output_without_d.status.success(), 
                "llm_globber failed: {}", 
                String::from_utf8_lossy(&output_without_d.stderr));
        
        // Find the generated output file
        let output_file_without_d = find_output_file(&output_dir, "no_dotfiles_test_")
            .expect("No output file was generated");
        
        // Read the output file
        let content_without_d = fs::read_to_string(&output_file_without_d).unwrap();
        
        // Verify that only regular files are included, not dotfiles
        assert!(content_without_d.contains("regular.txt"), "Output should contain regular.txt");
        assert!(!content_without_d.contains(".dotfile"), "Output should not contain .dotfile");
        assert!(!content_without_d.contains(".config"), "Output should not contain .config");
        
        // Second test: with -d flag (should include dotfiles)
        let output_with_d = Command::new(&executable_path)
            .args([
                "-o", output_dir.to_str().unwrap(),
                "-n", "with_dotfiles_test",
                "-a",
                "-d",
                "-r",
                test_dir.to_str().unwrap(),
            ])
            .output()
            .expect("Failed to execute llm_globber");
        
        assert!(output_with_d.status.success(), 
                "llm_globber failed: {}", 
                String::from_utf8_lossy(&output_with_d.stderr));
        
        // Find the generated output file
        let output_file_with_d = find_output_file(&output_dir, "with_dotfiles_test_")
            .expect("No output file was generated");
        
        // Read the output file
        let content_with_d = fs::read_to_string(&output_file_with_d).unwrap();
        
        // Verify that both regular files and dotfiles are included
        assert!(content_with_d.contains("regular.txt"), "Output should contain regular.txt");
        assert!(content_with_d.contains(".dotfile"), "Output should contain .dotfile");
        assert!(content_with_d.contains(".config"), "Output should contain .config");
    }
    
    #[test]
    fn test_verbose_and_quiet_modes() {
        // Create a temporary directory for test files
        let temp_dir = TempDir::new().unwrap();
        let test_dir = temp_dir.path();
        
        // Create a simple test file
        let test_file_path = test_dir.join("test.txt");
        let mut test_file = File::create(&test_file_path).unwrap();
        writeln!(test_file, "Test content").unwrap();
        
        // Create output directory
        let output_dir = temp_dir.path().join("output");
        fs::create_dir(&output_dir).unwrap();
        
        // Get executable path
        let executable_path = get_executable_path();
        
        // Test verbose mode
        let output_verbose = Command::new(&executable_path)
            .args([
                "-o", output_dir.to_str().unwrap(),
                "-n", "verbose_test",
                "-v",
                test_file_path.to_str().unwrap(),
            ])
            .output()
            .expect("Failed to execute llm_globber");
        
        assert!(output_verbose.status.success(), 
                "llm_globber failed in verbose mode: {}", 
                String::from_utf8_lossy(&output_verbose.stderr));
        
        // Check if verbose output contains INFO and DEBUG messages
        let stderr_verbose = String::from_utf8_lossy(&output_verbose.stderr);
        assert!(stderr_verbose.contains("INFO") || stderr_verbose.contains("DEBUG"), 
                "Verbose mode should show INFO or DEBUG messages");
        
        // Test quiet mode
        let output_quiet = Command::new(&executable_path)
            .args([
                "-o", output_dir.to_str().unwrap(),
                "-n", "quiet_test",
                "-q",
                test_file_path.to_str().unwrap(),
            ])
            .output()
            .expect("Failed to execute llm_globber");
        
        assert!(output_quiet.status.success(), 
                "llm_globber failed in quiet mode");
        
        // Check if quiet mode suppresses all output
        let stderr_quiet = String::from_utf8_lossy(&output_quiet.stderr);
        assert!(stderr_quiet.is_empty(), 
                "Quiet mode should not produce any output, but got: {}", stderr_quiet);
        
        // Test default mode
        let output_default = Command::new(&executable_path)
            .args([
                "-o", output_dir.to_str().unwrap(),
                "-n", "default_test",
                test_file_path.to_str().unwrap(),
            ])
            .output()
            .expect("Failed to execute llm_globber");
        
        assert!(output_default.status.success(), 
                "llm_globber failed in default mode");
        
        // Check if default mode doesn't show INFO or DEBUG messages
        let stderr_default = String::from_utf8_lossy(&output_default.stderr);
        assert!(!stderr_default.contains("INFO:") && !stderr_default.contains("DEBUG:"), 
                "Default mode should not show INFO or DEBUG messages, but got: {}", stderr_default);
    }
    
    #[test]
    fn test_basic_functionality() {
        // Create a temporary directory for test files
        let temp_dir = TempDir::new().unwrap();
        let test_dir = temp_dir.path();
        
        // Create two test files
        let test_file1 = test_dir.join("test1.c");
        let test_file2 = test_dir.join("test1.h");
        
        let mut file1 = File::create(&test_file1).unwrap();
        writeln!(file1, "This is a C file").unwrap();
        
        let mut file2 = File::create(&test_file2).unwrap();
        writeln!(file2, "This is a header file").unwrap();
        
        // Create output directory
        let output_dir = temp_dir.path().join("output");
        fs::create_dir(&output_dir).unwrap();
        
        // Get executable path
        let executable_path = get_executable_path();
        
        // Run llm_globber with the two files
        let output = Command::new(&executable_path)
            .args([
                "-o", output_dir.to_str().unwrap(),
                "-n", "basic_test",
                test_file1.to_str().unwrap(),
                test_file2.to_str().unwrap(),
            ])
            .output()
            .expect("Failed to execute llm_globber");
        
        assert!(output.status.success(), 
                "llm_globber failed: {}", 
                String::from_utf8_lossy(&output.stderr));
        
        // Find the generated output file
        let output_file = find_output_file(&output_dir, "basic_test_")
            .expect("No output file was generated");
        
        // Read the output file
        let content = fs::read_to_string(&output_file).unwrap();
        
        // Verify that both files are included
        assert!(content.contains("This is a C file"), "Output should contain C file content");
        assert!(content.contains("This is a header file"), "Output should contain header file content");
        
        // Verify file order (test1.c should come before test1.h)
        let c_pos = content.find("test1.c").unwrap_or(usize::MAX);
        let h_pos = content.find("test1.h").unwrap_or(usize::MAX);
        
        assert!(c_pos < h_pos, "test1.c should appear before test1.h in the output");
    }
}
