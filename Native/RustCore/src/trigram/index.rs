//! Core trigram inverted index.
//!
//! For every indexed file we extract the set of unique trigrams (3-char
//! subsequences) and record them in a global inverted index mapping
//! each trigram hash to the list of file IDs that contain it.
//!
//! A search query extracts its own trigrams and intersects the posting
//! lists to produce a small candidate set of files that *might* contain
//! the query string.  A verification pass then confirms actual matches.

use super::bloom::BloomFilter;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

/// Numeric file identifier (dense, assigned during build).
pub type FileId = u32;

/// An indexed file entry.
#[derive(Clone, Serialize, Deserialize)]
pub struct IndexedFileEntry {
    pub file_id: FileId,
    pub path: String,
    pub content_hash: u64,
}

/// The trigram inverted index.
pub struct TrigramIndex {
    /// trigram_hash → sorted list of file_ids.
    pub posting_lists: HashMap<u32, Vec<FileId>>,
    /// Per-file bloom filter for fast rejection.
    pub bloom_filters: HashMap<FileId, BloomFilter>,
    /// File metadata.
    pub files: Vec<IndexedFileEntry>,
    /// Path → file_id lookup.
    pub path_to_id: HashMap<String, FileId>,
}

impl TrigramIndex {
    /// Build the index from a set of files.
    pub fn build(files: &[(String, String, u64)]) -> Self {
        let mut posting_lists: HashMap<u32, Vec<FileId>> = HashMap::new();
        let mut bloom_filters: HashMap<FileId, BloomFilter> = HashMap::new();
        let mut file_entries: Vec<IndexedFileEntry> = Vec::with_capacity(files.len());
        let mut path_to_id: HashMap<String, FileId> = HashMap::new();

        for (file_id, (path, content, content_hash)) in files.iter().enumerate() {
            let fid = file_id as FileId;
            file_entries.push(IndexedFileEntry {
                file_id: fid,
                path: path.clone(),
                content_hash: *content_hash,
            });
            path_to_id.insert(path.clone(), fid);

            let trigrams = extract_trigrams(content);
            let mut bloom = BloomFilter::new();

            for tg in &trigrams {
                bloom.insert(*tg);
                posting_lists.entry(*tg).or_default().push(fid);
            }

            bloom_filters.insert(fid, bloom);
        }

        // Sort posting lists for efficient intersection.
        for list in posting_lists.values_mut() {
            list.sort_unstable();
            list.dedup();
        }

        TrigramIndex {
            posting_lists,
            bloom_filters,
            files: file_entries,
            path_to_id,
        }
    }

    /// Find candidate file IDs that may contain the query string.
    /// Uses trigram intersection + bloom filter pre-check.
    pub fn query_candidates(&self, pattern: &str) -> Vec<FileId> {
        let trigrams = extract_trigrams_from_pattern(pattern);
        if trigrams.is_empty() {
            // Pattern too short for trigram filtering — return all files.
            return self.files.iter().map(|f| f.file_id).collect();
        }

        // Get posting lists for each trigram, sorted by length (shortest first).
        let mut lists: Vec<&[FileId]> = trigrams
            .iter()
            .filter_map(|tg| self.posting_lists.get(tg).map(|v| v.as_slice()))
            .collect();

        if lists.is_empty() {
            return vec![];
        }

        lists.sort_by_key(|l| l.len());

        // Intersect posting lists progressively.
        let mut candidates: HashSet<FileId> = lists[0].iter().copied().collect();
        for list in &lists[1..] {
            let set: HashSet<FileId> = list.iter().copied().collect();
            candidates = candidates.intersection(&set).copied().collect();
            if candidates.is_empty() {
                return vec![];
            }
        }

        // Bloom filter verification pass.
        let trigram_vec: Vec<u32> = trigrams.into_iter().collect();
        candidates
            .into_iter()
            .filter(|fid| {
                self.bloom_filters
                    .get(fid)
                    .map_or(true, |bf| bf.may_contain_all(&trigram_vec))
            })
            .collect()
    }

    /// Add or update a single file in the index.
    pub fn update_file(&mut self, path: &str, content: &str, content_hash: u64) {
        // Remove old entry if exists.
        if let Some(&old_fid) = self.path_to_id.get(path) {
            self.remove_file_from_postings(old_fid);
            self.bloom_filters.remove(&old_fid);
        }

        let fid = self.path_to_id.get(path).copied().unwrap_or_else(|| {
            let new_id = self.files.len() as FileId;
            self.files.push(IndexedFileEntry {
                file_id: new_id,
                path: path.to_string(),
                content_hash,
            });
            self.path_to_id.insert(path.to_string(), new_id);
            new_id
        });

        // Update content hash.
        if let Some(entry) = self.files.get_mut(fid as usize) {
            entry.content_hash = content_hash;
        }

        let trigrams = extract_trigrams(content);
        let mut bloom = BloomFilter::new();
        for tg in &trigrams {
            bloom.insert(*tg);
            let list = self.posting_lists.entry(*tg).or_default();
            if !list.contains(&fid) {
                list.push(fid);
            }
        }
        self.bloom_filters.insert(fid, bloom);
    }

    /// Remove a file from posting lists (leaves the file entry for ID stability).
    fn remove_file_from_postings(&mut self, fid: FileId) {
        for list in self.posting_lists.values_mut() {
            list.retain(|&id| id != fid);
        }
    }

    /// Number of indexed files.
    pub fn file_count(&self) -> usize {
        self.files.len()
    }

    /// Number of unique trigrams.
    pub fn trigram_count(&self) -> usize {
        self.posting_lists.len()
    }
}

// ---------------------------------------------------------------------------
// Trigram extraction
// ---------------------------------------------------------------------------

/// Hash a 3-byte trigram into a u32.
pub fn trigram_hash(a: u8, b: u8, c: u8) -> u32 {
    (a as u32) << 16 | (b as u32) << 8 | c as u32
}

/// Extract unique trigram hashes from text content.
pub fn extract_trigrams(text: &str) -> HashSet<u32> {
    let bytes = text.as_bytes();
    let mut set = HashSet::new();
    if bytes.len() < 3 {
        return set;
    }
    for window in bytes.windows(3) {
        // Skip trigrams that span newlines (they add noise).
        if window.contains(&b'\n') || window.contains(&b'\r') {
            continue;
        }
        set.insert(trigram_hash(window[0], window[1], window[2]));
    }
    set
}

/// Extract trigrams from a search pattern (case-insensitive).
pub fn extract_trigrams_from_pattern(pattern: &str) -> HashSet<u32> {
    let lower = pattern.to_lowercase();
    let bytes = lower.as_bytes();
    let mut set = HashSet::new();
    if bytes.len() < 3 {
        return set;
    }
    for window in bytes.windows(3) {
        if window.contains(&b'\n') {
            continue;
        }
        set.insert(trigram_hash(window[0], window[1], window[2]));
    }
    set
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basic_build_and_query() {
        let files = vec![
            (
                "a.swift".to_string(),
                "func handleSearch() { }".to_string(),
                1u64,
            ),
            (
                "b.swift".to_string(),
                "func processData() { }".to_string(),
                2u64,
            ),
            (
                "c.swift".to_string(),
                "class SearchEngine { }".to_string(),
                3u64,
            ),
        ];
        let index = TrigramIndex::build(&files);
        assert_eq!(index.file_count(), 3);

        let candidates = index.query_candidates("Search");
        // Should find files a.swift and c.swift (both contain "Search").
        assert!(candidates.len() >= 2);
    }

    #[test]
    fn no_false_negatives() {
        let files = vec![(
            "test.rs".to_string(),
            "fn hello_world() { println!(\"hello\") }".to_string(),
            1u64,
        )];
        let index = TrigramIndex::build(&files);
        let candidates = index.query_candidates("hello_world");
        assert!(
            !candidates.is_empty(),
            "Must find the file containing the pattern"
        );
    }

    #[test]
    fn short_pattern_returns_all() {
        let files = vec![
            ("a.rs".to_string(), "abc".to_string(), 1u64),
            ("b.rs".to_string(), "def".to_string(), 2u64),
        ];
        let index = TrigramIndex::build(&files);
        // Pattern "ab" is only 2 chars → too short for trigram filtering.
        let candidates = index.query_candidates("ab");
        assert_eq!(candidates.len(), 2);
    }

    #[test]
    fn incremental_update() {
        let files = vec![("a.rs".to_string(), "old content here".to_string(), 1u64)];
        let mut index = TrigramIndex::build(&files);
        assert!(
            !index.query_candidates("new_function").is_empty() == false
                || index.query_candidates("new_function").is_empty()
        );

        index.update_file("a.rs", "fn new_function() { }", 2);
        let candidates = index.query_candidates("new_function");
        assert!(!candidates.is_empty());
    }
}
