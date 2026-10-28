//! Data shared between the monitor, the tray and the web UI (serialized as camelCase JSON).

use serde::Serialize;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BackendKind {
    LlamaCpp,
    Ollama,
}

impl BackendKind {
    pub fn label(self) -> &'static str {
        match self {
            BackendKind::LlamaCpp => "llama.cpp",
            BackendKind::Ollama => "Ollama",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ModelState {
    Loaded,
    Loading,
    Unloaded,
}

/// How to find the OS process serving a model: executable name plus an argv needle.
#[derive(Clone, Debug)]
pub enum ProcessMatch {
    /// `--flag value` appears in argv (llama.cpp: `--alias <model>`).
    FlagValue { exe: &'static str, flag: &'static str, value: String },
    /// Some argument contains the substring (Ollama runners get the blob path).
    ArgContains { exe: &'static str, needle: &'static str },
}

/// Live counters for a loaded model. Totals are cumulative since the model loaded.
#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelStats {
    pub prompt_tokens_total: f64,
    pub predicted_tokens_total: f64,
    /// Tokens decoded by requests still running (llama.cpp only counts a request in /metrics once it ends).
    pub in_flight_tokens: f64,
    pub prompt_tokens_per_second: Option<f64>,
    pub predicted_tokens_per_second: Option<f64>,
    pub requests_processing: u32,
    pub context_size: Option<u64>,
    pub context_used: Option<u64>,
    pub slots_total: u32,
    pub slots_busy: u32,
    pub vram_bytes: Option<u64>,
    /// Unix seconds when Ollama unloads the model.
    pub expires_at: Option<i64>,
}

impl ModelStats {
    pub fn generated_tokens(&self) -> f64 {
        self.predicted_tokens_total + self.in_flight_tokens
    }
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelInfo {
    pub id: String,
    pub backend: BackendKind,
    pub name: String,
    pub state: ModelState,
    pub size_bytes: Option<u64>,
    /// GGUF path for llama.cpp presets (what "Remove" deletes); Ollama manages its own blobs.
    pub path: Option<String>,
    pub stats: Option<ModelStats>,
    #[serde(skip)]
    pub process_match: Option<ProcessMatch>,
}

impl ModelInfo {
    pub fn new(backend: BackendKind, name: String, state: ModelState) -> Self {
        Self {
            id: format!("{}/{}", backend.label(), name),
            backend,
            name,
            state,
            size_bytes: None,
            path: None,
            stats: None,
            process_match: None,
        }
    }
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackendSnapshot {
    pub kind: BackendKind,
    pub online: bool,
    pub models: Vec<ModelInfo>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActiveModel {
    pub info: ModelInfo,
    pub process_ram: Option<u64>,
    /// Fraction of one core (1.0 = 100%).
    pub cpu: Option<f64>,
    pub generation_rate: f64,
    pub prompt_rate: f64,
    pub busy: bool,
}

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MemorySnapshot {
    pub total: u64,
    pub used: u64,
    pub swap_used: u64,
    pub swap_total: u64,
}

impl MemorySnapshot {
    pub fn used_fraction(&self) -> f64 {
        if self.total == 0 { 0.0 } else { self.used as f64 / self.total as f64 }
    }
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GpuSnapshot {
    pub name: String,
    /// 0..1
    pub utilization: f64,
    pub memory_used: Option<u64>,
    pub memory_total: Option<u64>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Sample {
    /// Unix milliseconds.
    pub time: i64,
    pub generation_rate: f64,
    pub prompt_rate: f64,
    pub gpu: f64,
    pub memory: f64,
    pub swap: u64,
}

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub backends: Vec<BackendSnapshot>,
    pub active: Vec<ActiveModel>,
    pub memory: MemorySnapshot,
    pub gpu: Option<GpuSnapshot>,
    pub history: Vec<Sample>,
    pub generation_rate: f64,
    pub generating: bool,
    pub context_fraction: Option<f64>,
    pub pending: Vec<String>,
    pub last_error: Option<String>,
    pub platform: &'static str,
}
