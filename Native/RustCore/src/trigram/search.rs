//! Query execution: trigram candidate filtering + content verification.
//!
//! The flow is:
//! 1. Extract trigrams from the search pattern
//! 2. Intersect posting lists to get candidate file IDs
//! 3. Apply bloom filter pre-check
//! 4. For each candidate, verify with actual content matching (regex)
//! 5. Collect matches with file path, line number, and snippet

use super::index::TrigramIndex;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A single grep match result.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GrepMatch {
    pub file_path: String,
    pub line: u32,
    pub column: u32,
    pub snippet: String,
}

/// Result of a trigram-accelerated grep search.
#[derive(Debug, Serialize, Deserialize)]
pub struct GrepResult {
    pub matches: Vec<GrepMatch>,
    pub candidates_checked: u32,
    pub total_files: u32,
    pub elapsed_us: u64,
}

/// Run a grep search using the trigram index for candidate filtering.
///
/// `file_contents` maps file_id → content string (loaded on demand).
pub fn grep(
    index: &TrigramIndex,
    pattern: &str,
    file_contents: &HashMap<u32, String>,
    max_results: usize,
    case_sensitive: bool,
) -> GrepResult {
    let start = std::time::Instant::now();

    // Build regex for verification.
    let regex = if case_sensitive {
        Regex::new(pattern)
    } else {
        Regex::new(&format!("(?i){}", regex::escape(pattern)))
    };

    let regex = match regex {
        Ok(r) => r,
        Err(_) => {
            // If pattern is not valid regex, escape it.
            match Regex::new(&regex::escape(pattern)) {
                Ok(r) => r,
                Err(_) => {
                    return GrepResult {
                        matches: vec![],
                        candidates_checked: 0,
                        total_files: index.file_count() as u32,
                        elapsed_us: start.elapsed().as_micros() as u64,
                    };
                }
            }
        }
    };

    // Get candidate files via trigram filtering.
    let candidates = index.query_candidates(pattern);
    let mut matches = Vec::new();
    let mut candidates_checked = 0u32;

    for fid in &candidates {
        candidates_checked += 1;
        let content = match file_contents.get(fid) {
            Some(c) => c,
            None => continue,
        };

        // Verify with actual regex matching.
        for (line_idx, line) in content.lines().enumerate() {
            if let Some(m) = regex.find(line) {
                matches.push(GrepMatch {
                    file_path: index.files[*fid as usize].path.clone(),
                    line: (line_idx + 1) as u32,
                    column: (m.start() + 1) as u32,
                    snippet: line.to_string(),
                });

                if matches.len() >= max_results {
                    return GrepResult {
                        matches,
                        candidates_checked,
                        total_files: index.file_count() as u32,
                        elapsed_us: start.elapsed().as_micros() as u64,
                    };
                }
            }
        }
    }

    GrepResult {
        matches,
        candidates_checked,
        total_files: index.file_count() as u32,
        elapsed_us: start.elapsed().as_micros() as u64,
    }
}

/// Estimate how many files will be candidates for a given pattern.
/// Useful for deciding whether to use trigram index or raw grep.
pub fn estimate_candidates(index: &TrigramIndex, pattern: &str) -> usize {
    index.query_candidates(pattern).len()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn grep_finds_matches() {
        let files = vec![
            (
                "a.swift".to_string(),
                "func handleSearch() {\n    // search logic\n}".to_string(),
                1u64,
            ),
            (
                "b.swift".to_string(),
                "func processData() {\n    // data logic\n}".to_string(),
                2u64,
            ),
        ];
        let index = TrigramIndex::build(&files);

        let mut contents = HashMap::new();
        for (i, (_, content, _)) in files.iter().enumerate() {
            contents.insert(i as u32, content.clone());
        }

        let result = grep(&index, "search", &contents, 100, false);
        assert!(!result.matches.is_empty());
        assert!(result.matches.iter().any(|m| m.file_path == "a.swift"));
    }

    #[test]
    fn grep_respects_max_results() {
        let files = vec![(
            "a.rs".to_string(),
            "aaa\naaa\naaa\naaa\naaa".to_string(),
            1u64,
        )];
        let index = TrigramIndex::build(&files);
        let mut contents = HashMap::new();
        contents.insert(0u32, files[0].1.clone());

        let result = grep(&index, "aaa", &contents, 2, false);
        assert!(result.matches.len() <= 2);
    }
}
