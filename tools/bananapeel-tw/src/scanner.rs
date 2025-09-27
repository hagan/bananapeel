use crate::hashing::{hash_blake3, hash_sha256};
use crate::record::{FileRecord, Report, now_rfc3339};
use anyhow::{Result, Context};
use ignore::WalkBuilder;
use rayon::prelude::*;
use serde_json::json;
use std::fs::{self, Metadata};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

fn to_record(path: &Path, md: &Metadata, want_sha256: bool) -> Result<FileRecord> {
    let file_type = if md.is_file() {
        "file"
    } else if md.is_dir() {
        "dir"
    } else if md.file_type().is_symlink() {
        "symlink"
    } else {
        "special"
    }.to_string();

    let mut rec = FileRecord {
        path: path.to_string_lossy().to_string(),
        file_type: file_type.clone(),
        size: md.size(),
        mode: md.mode(),
        uid: md.uid(),
        gid: md.gid(),
        mtime: md.mtime(),
        inode: Some(md.ino()),
        blake3: None,
        sha256: None,
    };

    if file_type == "file" {
        // Safe hashing with fallbacks
        if let Ok(h) = hash_blake3(&rec.path) { rec.blake3 = Some(h); }
        if want_sha256 {
            if let Ok(h) = hash_sha256(&rec.path) { rec.sha256 = Some(h); }
        }
    }
    Ok(rec)
}

pub fn init_baseline(root: &str, out: &str, exclude: &[String]) -> Result<()> {
    let mut walker = WalkBuilder::new(root);
    for ex in exclude { walker.add_ignore(ex); }
    // Do not follow symlinks by default
    walker.follow_links(false);

    let entries: Vec<PathBuf> = walker.build()
        .filter_map(|r| r.ok())
        .map(|d| d.into_path())
        .filter(|p| p.exists())
        .collect();

    let want_sha256 = false; // toggle via CLI in future
    let records: Vec<_> = entries.par_iter().filter_map(|p| {
        fs::symlink_metadata(p).ok().and_then(|md| to_record(p, &md, want_sha256).ok())
    }).collect();

    // Write JSONL
    let mut w = std::io::BufWriter::new(fs::File::create(out)?);
    for rec in records {
        serde_json::to_writer(&mut w, &rec)?;
        use std::io::Write; writeln!(&mut w)?;
    }
    Ok(())
}

pub fn check_against_baseline(root: &str, baseline: &str, out: &str, exclude: &[String]) -> Result<()> {
    // Load baseline into map
    let mut map = std::collections::HashMap::new();
    let f = fs::File::open(baseline).with_context(|| format!("open baseline: {}", baseline))?;
    let reader = std::io::BufReader::new(f);
    for line in reader.lines() {
        let line = line?;
        if line.trim().is_empty() { continue; }
        let rec: FileRecord = serde_json::from_str(&line)?;
        map.insert(rec.path.clone(), rec);
    }

    // Walk current filesystem
    let mut walker = WalkBuilder::new(root);
    for ex in exclude { walker.add_ignore(ex); }
    walker.follow_links(false);
    let entries: Vec<PathBuf> = walker.build().filter_map(|r| r.ok()).map(|d| d.into_path()).collect();

    let want_sha256 = false;
    let mut added = Vec::new();
    let mut modified = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let mut errors = Vec::new();

    entries.par_iter().for_each(|p| {
        if let Ok(md) = fs::symlink_metadata(p) {
            if let Ok(rec) = to_record(p, &md, want_sha256) {
                seen.insert(rec.path.clone());
                if let Some(old) = map.get(&rec.path) {
                    if rec.file_type == "file" {
                        if rec.blake3 != old.blake3 || rec.size != old.size || rec.mode != old.mode || rec.mtime != old.mtime {
                            modified.push(rec.path.clone());
                        }
                    } else if rec.file_type != old.file_type || rec.mode != old.mode {
                        modified.push(rec.path.clone());
                    }
                } else {
                    added.push(rec.path.clone());
                }
            } else {
                errors.push(format!("record error: {}", p.display()));
            }
        } else {
            errors.push(format!("stat error: {}", p.display()));
        }
    });

    // Removed = in baseline but not seen now
    let removed: Vec<String> = map.keys().filter(|k| !seen.contains(*k)).cloned().collect();

    // Build report
    let host = hostname::get().unwrap_or_default().to_string_lossy().to_string();
    let report = Report {
        ts: now_rfc3339(),
        host,
        added,
        removed,
        modified,
        errors,
    };
    let json = serde_json::to_string_pretty(&report)?;
    fs::write(out, json)?;

    // Exit code parity idea (to be handled by caller): 0 OK, 1 attention
    println!("{}", serde_json::to_string(&json!({"status":"OK"}))?);
    Ok(())
}

pub fn print_report(path: &str) -> Result<()> {
    let s = fs::read_to_string(path)?;
    let report: Report = serde_json::from_str(&s)?;
    println!("Report @ {} on {}", report.ts, report.host);
    println!("  Added: {}", report.added.len());
    println!("  Removed: {}", report.removed.len());
    println!("  Modified: {}", report.modified.len());
    if !report.errors.is_empty() {
        println!("  Errors: {}", report.errors.len());
    }
    Ok(())
}

