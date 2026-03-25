//! Bloom filter for fast negative lookups on trigram sets.
//!
//! Each file gets a compact bloom filter (~2 KB) that summarises which
//! trigrams it contains.  A query trigram set can be tested against the
//! filter in constant time — if any trigram is *definitely absent* the
//! file is eliminated without touching the posting lists.

const BITS_PER_FILTER: usize = 16_384; // 2 KB = 16 384 bits
const HASH_COUNT: usize = 3;

/// Compact bloom filter storing trigram membership for a single file.
#[derive(Clone)]
pub struct BloomFilter {
    bits: Vec<u64>,
}

impl BloomFilter {
    /// Create a new empty bloom filter.
    pub fn new() -> Self {
        // 16384 / 64 = 256 u64 words
        BloomFilter {
            bits: vec![0u64; BITS_PER_FILTER / 64],
        }
    }

    /// Insert a trigram hash into the filter.
    pub fn insert(&mut self, trigram: u32) {
        for seed in 0..HASH_COUNT as u32 {
            let bit = hash_to_bit(trigram, seed);
            let word = bit / 64;
            let offset = bit % 64;
            self.bits[word] |= 1u64 << offset;
        }
    }

    /// Test whether a trigram *may* be present. False positives are
    /// possible (~1 % at 500 trigrams); false negatives are impossible.
    pub fn may_contain(&self, trigram: u32) -> bool {
        for seed in 0..HASH_COUNT as u32 {
            let bit = hash_to_bit(trigram, seed);
            let word = bit / 64;
            let offset = bit % 64;
            if self.bits[word] & (1u64 << offset) == 0 {
                return false;
            }
        }
        true
    }

    /// Test whether *all* trigrams in the set may be present.
    /// Returns false as soon as one is definitely absent.
    pub fn may_contain_all(&self, trigrams: &[u32]) -> bool {
        trigrams.iter().all(|&t| self.may_contain(t))
    }

    /// Serialise to raw bytes (2 KB).
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(self.bits.len() * 8);
        for word in &self.bits {
            out.extend_from_slice(&word.to_le_bytes());
        }
        out
    }

    /// Deserialise from raw bytes.
    pub fn from_bytes(data: &[u8]) -> Option<Self> {
        if data.len() != BITS_PER_FILTER / 8 {
            return None;
        }
        let bits: Vec<u64> = data
            .chunks_exact(8)
            .map(|chunk| u64::from_le_bytes(chunk.try_into().unwrap()))
            .collect();
        Some(BloomFilter { bits })
    }

    /// Approximate number of bits set (for diagnostics).
    pub fn popcount(&self) -> u32 {
        self.bits.iter().map(|w| w.count_ones()).sum()
    }
}

/// Map (trigram, seed) → bit position in [0, BITS_PER_FILTER).
/// Uses a simple multiplicative hash with different seeds.
fn hash_to_bit(trigram: u32, seed: u32) -> usize {
    let h = trigram.wrapping_mul(2654435761u32.wrapping_add(seed.wrapping_mul(0x9E3779B9)));
    (h as usize) % BITS_PER_FILTER
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn insert_and_query() {
        let mut bf = BloomFilter::new();
        let tg = trigram_hash(b"abc");
        bf.insert(tg);
        assert!(bf.may_contain(tg));
    }

    #[test]
    fn false_negative_impossible() {
        let mut bf = BloomFilter::new();
        let trigrams: Vec<u32> = (0..500u32).map(|i| i * 7 + 3).collect();
        for &t in &trigrams {
            bf.insert(t);
        }
        for &t in &trigrams {
            assert!(bf.may_contain(t), "false negative for {}", t);
        }
    }

    #[test]
    fn serialization_roundtrip() {
        let mut bf = BloomFilter::new();
        bf.insert(42);
        bf.insert(999);
        let bytes = bf.to_bytes();
        let bf2 = BloomFilter::from_bytes(&bytes).unwrap();
        assert!(bf2.may_contain(42));
        assert!(bf2.may_contain(999));
    }

    fn trigram_hash(bytes: &[u8; 3]) -> u32 {
        (bytes[0] as u32) << 16 | (bytes[1] as u32) << 8 | bytes[2] as u32
    }
}
