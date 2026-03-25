//! Binary persistence for the trigram index.
//!
//! Layout:
//!   [Header: 32 bytes]
//!     magic (4 bytes): "TRGM"
//!     version (4 bytes): 1
//!     file_count (4 bytes)
//!     trigram_count (4 bytes)
//!     files_offset (8 bytes)
//!     postings_offset (8 bytes)
//!   [File entries: variable]
//!   [Posting lists: variable]
//!   [Bloom filters: file_count * 2048 bytes]

use super::bloom::BloomFilter;
use super::index::{FileId, IndexedFileEntry, TrigramIndex};
use std::collections::HashMap;
use std::io::{self, Write};
use std::path::Path;

const MAGIC: &[u8; 4] = b"TRGM";
const VERSION: u32 = 1;
const HEADER_SIZE: usize = 32;
const BLOOM_SIZE: usize = 2048; // 16384 bits = 2048 bytes

/// Persist the trigram index to a binary file.
pub fn save(index: &TrigramIndex, path: &Path) -> io::Result<()> {
    let mut buf: Vec<u8> = Vec::new();

    // Placeholder header — we'll fill offsets later.
    buf.extend_from_slice(&[0u8; HEADER_SIZE]);

    // File entries section.
    let files_offset = buf.len() as u64;
    for entry in &index.files {
        let path_bytes = entry.path.as_bytes();
        buf.extend_from_slice(&(path_bytes.len() as u32).to_le_bytes());
        buf.extend_from_slice(path_bytes);
        buf.extend_from_slice(&entry.content_hash.to_le_bytes());
    }

    // Posting lists section.
    let postings_offset = buf.len() as u64;
    // Write: [trigram_count: u32] then for each: [trigram: u32][list_len: u32][file_ids...]
    let trigram_count = index.posting_lists.len() as u32;
    buf.extend_from_slice(&trigram_count.to_le_bytes());
    for (&trigram, list) in &index.posting_lists {
        buf.extend_from_slice(&trigram.to_le_bytes());
        buf.extend_from_slice(&(list.len() as u32).to_le_bytes());
        for &fid in list {
            buf.extend_from_slice(&fid.to_le_bytes());
        }
    }

    // Bloom filters section (fixed size per file).
    for i in 0..index.files.len() {
        let fid = i as FileId;
        if let Some(bf) = index.bloom_filters.get(&fid) {
            let bytes = bf.to_bytes();
            assert_eq!(bytes.len(), BLOOM_SIZE);
            buf.extend_from_slice(&bytes);
        } else {
            buf.extend_from_slice(&[0u8; BLOOM_SIZE]);
        }
    }

    // Fill header.
    let file_count = index.files.len() as u32;
    buf[0..4].copy_from_slice(MAGIC);
    buf[4..8].copy_from_slice(&VERSION.to_le_bytes());
    buf[8..12].copy_from_slice(&file_count.to_le_bytes());
    buf[12..16].copy_from_slice(&trigram_count.to_le_bytes());
    buf[16..24].copy_from_slice(&files_offset.to_le_bytes());
    buf[24..32].copy_from_slice(&postings_offset.to_le_bytes());

    let mut file = std::fs::File::create(path)?;
    file.write_all(&buf)?;
    file.flush()?;
    Ok(())
}

/// Load the trigram index from a binary file.
pub fn load(path: &Path) -> io::Result<TrigramIndex> {
    let data = std::fs::read(path)?;
    if data.len() < HEADER_SIZE {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "file too small"));
    }

    // Verify header.
    if &data[0..4] != MAGIC {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "bad magic"));
    }
    let version = u32::from_le_bytes(data[4..8].try_into().unwrap());
    if version != VERSION {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("unsupported version {}", version),
        ));
    }

    let file_count = u32::from_le_bytes(data[8..12].try_into().unwrap()) as usize;
    let _trigram_count = u32::from_le_bytes(data[12..16].try_into().unwrap());
    let files_offset = u64::from_le_bytes(data[16..24].try_into().unwrap()) as usize;
    let postings_offset = u64::from_le_bytes(data[24..32].try_into().unwrap()) as usize;

    // Read file entries.
    let mut cursor = files_offset;
    let mut files = Vec::with_capacity(file_count);
    let mut path_to_id = HashMap::new();
    for i in 0..file_count {
        let path_len = read_u32(&data, &mut cursor) as usize;
        let path_str = String::from_utf8_lossy(&data[cursor..cursor + path_len]).to_string();
        cursor += path_len;
        let content_hash = read_u64(&data, &mut cursor);
        let fid = i as FileId;
        path_to_id.insert(path_str.clone(), fid);
        files.push(IndexedFileEntry {
            file_id: fid,
            path: path_str,
            content_hash,
        });
    }

    // Read posting lists.
    cursor = postings_offset;
    let trigram_count = read_u32(&data, &mut cursor) as usize;
    let mut posting_lists = HashMap::with_capacity(trigram_count);
    for _ in 0..trigram_count {
        let trigram = read_u32(&data, &mut cursor);
        let list_len = read_u32(&data, &mut cursor) as usize;
        let mut list = Vec::with_capacity(list_len);
        for _ in 0..list_len {
            list.push(read_u32(&data, &mut cursor));
        }
        posting_lists.insert(trigram, list);
    }

    // Read bloom filters.
    let bloom_start = cursor;
    let mut bloom_filters = HashMap::with_capacity(file_count);
    for i in 0..file_count {
        let offset = bloom_start + i * BLOOM_SIZE;
        if offset + BLOOM_SIZE <= data.len() {
            if let Some(bf) = BloomFilter::from_bytes(&data[offset..offset + BLOOM_SIZE]) {
                bloom_filters.insert(i as FileId, bf);
            }
        }
    }

    Ok(TrigramIndex {
        posting_lists,
        bloom_filters,
        files,
        path_to_id,
    })
}

fn read_u32(data: &[u8], cursor: &mut usize) -> u32 {
    let val = u32::from_le_bytes(data[*cursor..*cursor + 4].try_into().unwrap());
    *cursor += 4;
    val
}

fn read_u64(data: &[u8], cursor: &mut usize) -> u64 {
    let val = u64::from_le_bytes(data[*cursor..*cursor + 8].try_into().unwrap());
    *cursor += 8;
    val
}
