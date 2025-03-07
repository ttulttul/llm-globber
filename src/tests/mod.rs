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

    #[test]
    fn test_name_pattern_filtering() {
        // Create a temporary directory for test files
        let temp_dir = TempDir::new().unwrap();
        let test_dir = temp_dir.path();
        
        // Create test files
        let files = create_test_files(test_dir);
        
        // Create output directory
        let output_dir = temp_dir.path().join("output");
        fs::create_dir(&output_dir).unwrap();
        
        // Run llm_globber with name pattern filter
        let output = Command::new(env!("CARGO_BIN_EXE_llm_globber"))
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
        let entries = fs::read_dir(&output_dir).unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| {
                e.file_name().to_string_lossy().starts_with("name_pattern_test_")
            })
            .collect::<Vec<_>>();
        
        assert!(!entries.is_empty(), "No output file was generated");
        
        // Read the output file
        let output_file = entries[0].path();
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
}
