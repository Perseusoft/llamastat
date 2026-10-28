//! Installs and removes models: Ollama through its API, llama.cpp by downloading a GGUF from
//! Hugging Face into the models folder and adding a preset. Progress goes out as `install` events.

use std::collections::HashMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures::StreamExt;
use serde::{Deserialize, Serialize};

use crate::backends::{self, LlamaCpp, Ollama};
use crate::model::BackendKind;
use crate::presets;

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InstallProgress {
    pub id: String,
    pub backend: BackendKind,
    pub name: String,
    /// `downloading`, `pulling`, `removing`, `done`, `error`, `cancelled`. `done` for llama.cpp
    /// means the preset changed and the router has to be restarted to see it.
    pub status: String,
    pub completed: u64,
    pub total: Option<u64>,
    pub done: bool,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum InstallSource {
    /// `ollama pull <model>`.
    Ollama { model: String },
    /// A `.gguf` from a Hugging Face repo, added to presets.ini as `[name]`.
    HuggingFace { repo: String, file: String, name: Option<String> },
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HfRepo {
    pub id: String,
    pub downloads: u64,
    pub likes: u64,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HfFile {
    pub path: String,
    pub size: Option<u64>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RouterPaths {
    pub presets: Option<String>,
    pub models_dir: Option<String>,
}

pub struct Installer {
    /// No overall timeout: a 20 GB download takes as long as it takes.
    client: reqwest::Client,
    cancels: Mutex<HashMap<String, Arc<AtomicBool>>>,
}

impl Installer {
    pub fn new() -> Self {
        let client = reqwest::Client::builder()
            .connect_timeout(Duration::from_secs(15))
            .user_agent(concat!("llamastat/", env!("CARGO_PKG_VERSION")))
            .build()
            .expect("http client");
        Self { client, cancels: Mutex::new(HashMap::new()) }
    }

    pub fn begin(&self, id: &str) -> Result<Arc<AtomicBool>, String> {
        let mut cancels = self.cancels.lock().unwrap();
        if cancels.contains_key(id) { return Err("already in progress".into()); }
        let flag = Arc::new(AtomicBool::new(false));
        cancels.insert(id.to_string(), Arc::clone(&flag));
        Ok(flag)
    }

    pub fn finish(&self, id: &str) {
        self.cancels.lock().unwrap().remove(id);
    }

    pub fn cancel(&self, id: &str) {
        if let Some(flag) = self.cancels.lock().unwrap().get(id) { flag.store(true, Ordering::Relaxed); }
    }

    // MARK: Hugging Face

    pub async fn search(&self, query: &str) -> Result<Vec<HfRepo>, String> {
        #[derive(Deserialize)]
        struct Item { id: String, #[serde(default)] downloads: u64, #[serde(default)] likes: u64 }
        let items: Vec<Item> = self.client
            .get("https://huggingface.co/api/models")
            .query(&[("search", query), ("filter", "gguf"), ("sort", "downloads"), ("direction", "-1"), ("limit", "25")])
            .timeout(Duration::from_secs(20))
            .send().await.map_err(|e| e.to_string())?
            .error_for_status().map_err(|e| e.to_string())?
            .json().await.map_err(|e| e.to_string())?;
        Ok(items.into_iter().map(|i| HfRepo { id: i.id, downloads: i.downloads, likes: i.likes }).collect())
    }

    /// `.gguf` files in the repo, sharded models excluded (they need every part).
    pub async fn files(&self, repo: &str) -> Result<Vec<HfFile>, String> {
        #[derive(Deserialize)]
        struct Entry { path: String, size: Option<u64>, #[serde(rename = "type")] kind: String }
        let entries: Vec<Entry> = self.client
            .get(format!("https://huggingface.co/api/models/{repo}/tree/main"))
            .query(&[("recursive", "true")])
            .timeout(Duration::from_secs(20))
            .send().await.map_err(|e| e.to_string())?
            .error_for_status().map_err(|e| e.to_string())?
            .json().await.map_err(|e| e.to_string())?;
        let mut files: Vec<HfFile> = entries.into_iter()
            .filter(|e| e.kind == "file" && e.path.to_lowercase().ends_with(".gguf") && !is_shard(&e.path))
            .map(|e| HfFile { path: e.path, size: e.size })
            .collect();
        files.sort_by_key(|f| f.size);
        Ok(files)
    }

    /// Streams `url` into `dest`, resuming a leftover `.part` when the server allows it.
    async fn download(&self, url: &str, dest: &Path, cancel: &AtomicBool, mut report: impl FnMut(u64, Option<u64>)) -> Result<(), String> {
        let part = dest.with_extension("gguf.part");
        let mut have = std::fs::metadata(&part).map(|m| m.len()).unwrap_or(0);
        let mut request = self.client.get(url);
        if have > 0 { request = request.header("Range", format!("bytes={have}-")); }
        let response = request.send().await.map_err(|e| e.to_string())?;
        let resuming = response.status() == reqwest::StatusCode::PARTIAL_CONTENT;
        if !response.status().is_success() { return Err(format!("HTTP {}", response.status())); }
        if !resuming { have = 0; }
        let total = response.content_length().map(|len| len + have);

        let mut file = std::fs::OpenOptions::new()
            .create(true).write(true).append(resuming).truncate(!resuming)
            .open(&part).map_err(|e| e.to_string())?;
        let mut stream = response.bytes_stream();
        let mut last_report = std::time::Instant::now();
        report(have, total);
        while let Some(chunk) = stream.next().await {
            if cancel.load(Ordering::Relaxed) { return Err("cancelled".into()); }
            let chunk = chunk.map_err(|e| e.to_string())?;
            file.write_all(&chunk).map_err(|e| e.to_string())?;
            have += chunk.len() as u64;
            if last_report.elapsed() >= Duration::from_millis(250) {
                report(have, total);
                last_report = std::time::Instant::now();
            }
        }
        file.flush().map_err(|e| e.to_string())?;
        drop(file);
        if let Some(total) = total {
            if have != total { return Err(format!("incomplete download: {have} of {total} bytes")); }
        }
        std::fs::rename(&part, dest).map_err(|e| e.to_string())?;
        report(have, total);
        Ok(())
    }

    // MARK: install / remove

    /// Runs one install to completion, calling `emit` with every progress update.
    pub async fn install(&self, source: InstallSource, router: RouterTarget, emit: impl Fn(InstallProgress)) {
        let (backend, name) = match &source {
            InstallSource::Ollama { model } => (BackendKind::Ollama, model.clone()),
            InstallSource::HuggingFace { file, name, .. } => (BackendKind::LlamaCpp, name.clone().unwrap_or_else(|| default_name(file))),
        };
        let id = format!("{}/{}", backend.label(), name);
        let progress = |status: &str, completed, total| InstallProgress {
            id: id.clone(), backend, name: name.clone(), status: status.into(), completed, total, done: false, error: None,
        };
        let cancel = match self.begin(&id) {
            Ok(flag) => flag,
            Err(e) => return emit(InstallProgress { done: true, error: Some(e), ..progress("error", 0, None) }),
        };

        let result = match &source {
            InstallSource::Ollama { model } => {
                emit(progress("pulling", 0, None));
                Ollama { base: router.ollama_url.clone() }
                    .pull(&self.client, model, &cancel, |done, total| emit(progress("pulling", done, total)))
                    .await
            }
            InstallSource::HuggingFace { repo, file, .. } => self.install_gguf(repo, file, &name, &router, &cancel, |done, total| emit(progress("downloading", done, total))).await,
        };

        self.finish(&id);
        emit(match result {
            Ok(()) => InstallProgress { done: true, ..progress("done", 0, None) },
            Err(e) if e == "cancelled" => InstallProgress { done: true, ..progress("cancelled", 0, None) },
            Err(e) => InstallProgress { done: true, error: Some(e), ..progress("error", 0, None) },
        });
    }

    async fn install_gguf(&self, repo: &str, file: &str, name: &str, router: &RouterTarget, cancel: &AtomicBool, report: impl FnMut(u64, Option<u64>)) -> Result<(), String> {
        let presets_path = router.presets.as_ref().ok_or("Can't find the router's presets.ini. Set it in Settings → Backends.")?;
        let text = std::fs::read_to_string(presets_path).unwrap_or_default();
        if presets::section_names(&text).iter().any(|s| s == name) {
            return Err(format!("A preset named \"{name}\" already exists"));
        }
        let dir = router.models_dir.clone()
            .or_else(|| presets::models_dir(&text))
            .or_else(|| presets_path.parent().map(Path::to_path_buf))
            .ok_or("Can't tell where models are stored")?;
        std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        let file_name = Path::new(file).file_name().ok_or("bad file name")?.to_string_lossy().into_owned();
        let dest = dir.join(&file_name);

        if !dest.exists() {
            let url = format!("https://huggingface.co/{repo}/resolve/main/{file}");
            self.download(&url, &dest, cancel, report).await?;
        }

        // Same keys as examples/llama-router/presets.example.ini.
        let path = dest.to_string_lossy().replace('\\', "/");
        let text = presets::add_section(&text, name, &[
            ("model", &path), ("ctx-size", "32768"), ("n-gpu-layers", "999"), ("jinja", "1"), ("metrics", "1"),
        ]);
        std::fs::write(presets_path, text).map_err(|e| e.to_string())
    }

    /// Deletes a model: Ollama through the API; llama.cpp drops the preset and the GGUF file.
    pub async fn remove(&self, backend: BackendKind, name: &str, path: Option<&str>, loaded: bool, router: &RouterTarget) -> Result<(), String> {
        match backend {
            BackendKind::Ollama => Ollama { base: router.ollama_url.clone() }.delete(&self.client, name).await,
            BackendKind::LlamaCpp => {
                let presets_path = router.presets.as_ref().ok_or("Can't find the router's presets.ini. Set it in Settings → Backends.")?;
                if loaded {
                    let _ = LlamaCpp { base: router.llama_cpp_url.clone() }.unload(&backends::client(), name).await;
                }
                let text = std::fs::read_to_string(presets_path).map_err(|e| e.to_string())?;
                let (text, preset_model) = presets::remove_section(&text, name);
                std::fs::write(presets_path, text).map_err(|e| e.to_string())?;
                if let Some(file) = path.map(str::to_string).or(preset_model) {
                    let file = PathBuf::from(file);
                    if file.is_file() { std::fs::remove_file(&file).map_err(|e| e.to_string())?; }
                    let _ = std::fs::remove_file(file.with_extension("gguf.part"));
                }
                Ok(())
            }
        }
    }
}

/// Where the router lives, resolved by the caller from settings and the running process.
#[derive(Clone, Debug)]
pub struct RouterTarget {
    pub llama_cpp_url: String,
    pub ollama_url: String,
    pub presets: Option<PathBuf>,
    pub models_dir: Option<PathBuf>,
}

/// `Qwen3-8B-Q4_K_M.gguf` → `Qwen3-8B-Q4_K_M`.
pub fn default_name(file: &str) -> String {
    let base = Path::new(file).file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_else(|| file.to_string());
    base.strip_suffix(".gguf").or_else(|| base.strip_suffix(".GGUF")).unwrap_or(&base).to_string()
}

/// `model-00001-of-00003.gguf`.
fn is_shard(path: &str) -> bool {
    let lower = path.to_lowercase();
    let Some(stem) = lower.strip_suffix(".gguf") else { return false };
    let Some((_, tail)) = stem.rsplit_once("-of-") else { return false };
    tail.chars().all(|c| c.is_ascii_digit()) && stem.len() > tail.len() + 10
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_and_shards() {
        assert_eq!(default_name("Qwen3-8B-Q4_K_M.gguf"), "Qwen3-8B-Q4_K_M");
        assert_eq!(default_name("sub/dir/model.GGUF"), "model");
        assert!(is_shard("Qwen3-235B-Q4_K_M-00001-of-00005.gguf"));
        assert!(!is_shard("Qwen3-8B-Q4_K_M.gguf"));
    }
}
