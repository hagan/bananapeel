use anyhow::Result;
use std::fs::File;
use std::io::{Read, BufReader};

pub fn hash_blake3(path: &str) -> Result<String> {
    let f = File::open(path)?;
    let mut reader = BufReader::new(f);
    let mut hasher = blake3::Hasher::new();
    let mut buf = vec![0u8; 1024 * 1024];
    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 { break; }
        hasher.update(&buf[..n]);
    }
    Ok(hasher.finalize().to_hex().to_string())
}

pub fn hash_sha256(path: &str) -> Result<String> {
    use sha2::{Digest, Sha256};
    let f = File::open(path)?;
    let mut reader = BufReader::new(f);
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1024 * 1024];
    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 { break; }
        hasher.update(&buf[..n]);
    }
    Ok(hex::encode(hasher.finalize()))
}

