//! Edits the router's `presets.ini` (one `[section]` per model, `key = value` lines).
//! Only the section being added or removed is touched; everything else is kept byte for byte.

use std::path::{Path, PathBuf};

fn header(line: &str) -> Option<&str> {
    let line = line.trim();
    line.strip_prefix('[').and_then(|l| l.strip_suffix(']')).map(str::trim)
}

fn is_comment(line: &str) -> bool {
    let line = line.trim_start();
    line.starts_with(';') || line.starts_with('#')
}

pub fn section_names(text: &str) -> Vec<String> {
    text.lines().filter(|l| !is_comment(l)).filter_map(header).map(str::to_string).collect()
}

/// Value of `key` inside `[name]`.
pub fn section_value(text: &str, name: &str, key: &str) -> Option<String> {
    let mut inside = false;
    for line in text.lines() {
        if is_comment(line) { continue; }
        if let Some(h) = header(line) {
            inside = h == name;
            continue;
        }
        if inside {
            if let Some((k, v)) = line.split_once('=') {
                if k.trim() == key { return Some(v.trim().to_string()); }
            }
        }
    }
    None
}

/// Appends `[name]` with the given entries, separated from what's before by a blank line.
pub fn add_section(text: &str, name: &str, entries: &[(&str, &str)]) -> String {
    let mut out = text.to_string();
    if !out.is_empty() && !out.ends_with('\n') { out.push('\n'); }
    if !out.is_empty() && !out.ends_with("\n\n") { out.push('\n'); }
    out.push_str(&format!("[{name}]\n"));
    for (k, v) in entries { out.push_str(&format!("{k} = {v}\n")); }
    out
}

/// Removes `[name]` and its lines, up to the blank line that separates it from whatever
/// follows (so a commented-out section after it survives). Returns the new text and the
/// section's `model` value, so the caller can delete the file.
pub fn remove_section(text: &str, name: &str) -> (String, Option<String>) {
    let model = section_value(text, name, "model");
    let mut out = String::with_capacity(text.len());
    let mut skipping = false;
    for line in text.split_inclusive('\n') {
        let trimmed = line.trim_end_matches(['\n', '\r']);
        if !is_comment(trimmed) {
            if let Some(h) = header(trimmed) {
                skipping = h == name;
                if skipping { continue; }
            }
        }
        if skipping {
            if trimmed.trim().is_empty() { skipping = false; }
            continue;
        }
        out.push_str(line);
    }
    // A removed section can leave two separators back to back; collapse them.
    while out.contains("\n\n\n") { out = out.replace("\n\n\n", "\n\n"); }
    (out, model)
}

/// Folder of the first `model = …` entry: where new downloads go.
pub fn models_dir(text: &str) -> Option<PathBuf> {
    let mut inside = false;
    for line in text.lines() {
        if is_comment(line) { continue; }
        if header(line).is_some() { inside = true; continue; }
        if inside {
            if let Some((k, v)) = line.split_once('=') {
                if k.trim() == "model" {
                    return Path::new(v.trim()).parent().map(Path::to_path_buf);
                }
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    const INI: &str = "; presets\n\n[Qwen3-8B]\nmodel = /m/Qwen3-8B-Q4_K_M.gguf\nctx-size = 32768\nmetrics = 1\n\n; [old]\n; model = /m/old.gguf\n\n[gpt-oss-20b]\nmodel = /m/gpt-oss-20b.gguf\n";

    #[test]
    fn reads_sections() {
        assert_eq!(section_names(INI), ["Qwen3-8B", "gpt-oss-20b"]);
        assert_eq!(section_value(INI, "gpt-oss-20b", "model").as_deref(), Some("/m/gpt-oss-20b.gguf"));
        assert_eq!(section_value(INI, "Qwen3-8B", "ctx-size").as_deref(), Some("32768"));
        assert_eq!(models_dir(INI), Some(PathBuf::from("/m")));
    }

    #[test]
    fn adds_and_removes() {
        let added = add_section(INI, "New", &[("model", "/m/new.gguf"), ("metrics", "1")]);
        assert!(added.ends_with("[gpt-oss-20b]\nmodel = /m/gpt-oss-20b.gguf\n\n[New]\nmodel = /m/new.gguf\nmetrics = 1\n"));
        assert_eq!(section_names(&added), ["Qwen3-8B", "gpt-oss-20b", "New"]);

        let (removed, model) = remove_section(&added, "Qwen3-8B");
        assert_eq!(model.as_deref(), Some("/m/Qwen3-8B-Q4_K_M.gguf"));
        assert_eq!(section_names(&removed), ["gpt-oss-20b", "New"]);
        assert!(removed.starts_with("; presets\n\n; [old]\n"), "{removed}");
        assert!(!removed.contains("ctx-size"));

        let (same, none) = remove_section(INI, "missing");
        assert_eq!(same, INI);
        assert_eq!(none, None);
    }

    #[test]
    fn add_to_empty_file() {
        assert_eq!(add_section("", "A", &[("model", "/m/a.gguf")]), "[A]\nmodel = /m/a.gguf\n");
    }
}
