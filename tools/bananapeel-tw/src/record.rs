use serde::{Serialize, Deserialize};
use time::OffsetDateTime;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FileRecord {
    pub path: String,
    pub file_type: String, // file, dir, symlink, special
    pub size: u64,
    pub mode: u32,
    pub uid: u32,
    pub gid: u32,
    pub mtime: i64,
    pub inode: Option<u64>,
    pub blake3: Option<String>,
    pub sha256: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Report {
    pub ts: String,
    pub host: String,
    pub added: Vec<String>,
    pub removed: Vec<String>,
    pub modified: Vec<String>,
    pub errors: Vec<String>,
}

pub fn now_rfc3339() -> String {
    OffsetDateTime::now_utc().format(&time::format_description::well_known::Rfc3339).unwrap_or_else(|_| "1970-01-01T00:00:00Z".to_string())
}

