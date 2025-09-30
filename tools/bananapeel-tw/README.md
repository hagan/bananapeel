# bananapeel-tw (Prototype)

A high-performance, parallel filesystem integrity scanner written in Rust. Produces JSON outputs compatible with the Bananapeel manager.

Status: Prototype scaffold (commands and core structs defined; implementation deliberately minimal).

## Goals
- Fast scanning with parallel hashing (BLAKE3 primary; optional SHA-256)
- Simple policy (include/exclude globs) with ignore file support
- Stable JSON outputs + exit code parity (0/1/2)
- Safe defaults (no symlink following, skip special files)

## CLI (planned)
```
bananapeel-tw init   --root / --out baseline.jsonl --exclude '*/tmp/*'
bananapeel-tw check  --root / --baseline baseline.jsonl --out report.json
bananapeel-tw print  --report report.json
```

## Build
```
cd tools/bananapeel-tw
cargo build --release
```

## Notes
- This crate is not yet wired into the system wrapper; it is a standalone prototype.
- JSON schemas will be documented in the project documentation.
