//! Trigram-based instant grep index.
//!
//! Provides sub-millisecond candidate filtering for code search queries
//! by maintaining an inverted index of 3-character subsequences (trigrams).
//! Inspired by Cursor's approach: trigram candidate filtering + bloom filters
//! + memory-mapped posting lists.

pub mod bloom;
pub mod ffi;
pub mod index;
pub mod persistence;
pub mod search;
