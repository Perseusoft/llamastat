//! Polls the backends and the system, computes rates and keeps the history.

use std::collections::{HashMap, HashSet};
use std::sync::Mutex;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use crate::backends::{self, LlamaCpp, Ollama};
use crate::model::*;
use crate::settings::Settings;
use crate::system::SystemStats;

/// Samples kept for the dashboard (5 min at 1 s); the panel shows the last 120.
pub const HISTORY_LENGTH: usize = 300;

struct Previous {
    at: Instant,
    generated: f64,
    prompt: f64,
}

pub struct Monitor {
    client: reqwest::Client,
    sys: Mutex<SystemStats>,
    previous: Mutex<HashMap<String, Previous>>,
    snapshot: Mutex<Snapshot>,
    pending: Mutex<HashSet<String>>,
    last_error: Mutex<Option<String>>,
}

impl Monitor {
    pub fn new() -> Self {
        Self {
            client: backends::client(),
            sys: Mutex::new(SystemStats::new()),
            previous: Mutex::new(HashMap::new()),
            snapshot: Mutex::new(Snapshot { platform: std::env::consts::OS, ..Default::default() }),
            pending: Mutex::new(HashSet::new()),
            last_error: Mutex::new(None),
        }
    }

    pub fn snapshot(&self) -> Snapshot {
        self.snapshot.lock().unwrap().clone()
    }

    pub async fn tick(&self, settings: &Settings) -> Snapshot {
        let llama = settings.llama_cpp_enabled.then(|| LlamaCpp { base: trim(&settings.llama_cpp_url) });
        let ollama = settings.ollama_enabled.then(|| Ollama { base: trim(&settings.ollama_url) });
        let (llama, ollama) = futures::join!(
            async { match &llama { Some(b) => Some(b.snapshot(&self.client).await), None => None } },
            async { match &ollama { Some(b) => Some(b.snapshot(&self.client).await), None => None } },
        );
        let backends: Vec<BackendSnapshot> = [llama, ollama].into_iter().flatten().collect();

        let now = Instant::now();
        let (memory, gpu, active) = {
            let mut sys = self.sys.lock().unwrap();
            let memory = sys.memory();
            let gpu = sys.gpu();
            sys.refresh_processes();

            let mut previous = self.previous.lock().unwrap();
            let mut next = HashMap::new();
            let active: Vec<ActiveModel> = backends.iter()
                .flat_map(|b| b.models.iter())
                .filter(|m| m.state == ModelState::Loaded)
                .map(|info| {
                    let stats = info.stats.clone().unwrap_or_default();
                    let process = info.process_match.as_ref().and_then(|m| sys.find(m));
                    let (mut generation_rate, mut prompt_rate) = (0.0, 0.0);
                    if let Some(last) = previous.get(&info.id) {
                        let dt = now.duration_since(last.at).as_secs_f64();
                        if dt > 0.0 {
                            // Counters reset when a model reloads; ignore negative deltas.
                            generation_rate = (stats.generated_tokens() - last.generated).max(0.0) / dt;
                            prompt_rate = (stats.prompt_tokens_total - last.prompt).max(0.0) / dt;
                        }
                    }
                    next.insert(info.id.clone(), Previous { at: now, generated: stats.generated_tokens(), prompt: stats.prompt_tokens_total });
                    ActiveModel {
                        busy: stats.requests_processing > 0 || stats.slots_busy > 0,
                        info: info.clone(),
                        process_ram: process.as_ref().map(|p| p.ram),
                        cpu: process.as_ref().map(|p| p.cpu),
                        generation_rate,
                        prompt_rate,
                    }
                })
                .collect();
            *previous = next;
            (memory, gpu, active)
        };

        let generation_rate: f64 = active.iter().map(|m| m.generation_rate).sum();
        let context_fraction = active.iter().find(|m| m.busy).or(active.first()).and_then(|m| {
            let stats = m.info.stats.as_ref()?;
            let size = stats.context_size.filter(|s| *s > 0)?;
            Some(stats.context_used.unwrap_or(0) as f64 / size as f64)
        });

        let mut snapshot = self.snapshot.lock().unwrap();
        snapshot.history.push(Sample {
            time: SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0),
            generation_rate,
            prompt_rate: active.iter().map(|m| m.prompt_rate).sum(),
            gpu: gpu.as_ref().map(|g| g.utilization).unwrap_or(0.0),
            memory: memory.used_fraction(),
            swap: memory.swap_used,
        });
        let overflow = snapshot.history.len().saturating_sub(HISTORY_LENGTH);
        snapshot.history.drain(..overflow);

        snapshot.generating = active.iter().any(|m| m.busy);
        snapshot.backends = backends;
        snapshot.active = active;
        snapshot.memory = memory;
        snapshot.gpu = gpu;
        snapshot.generation_rate = generation_rate;
        snapshot.context_fraction = context_fraction;
        snapshot.pending = self.pending.lock().unwrap().iter().cloned().collect();
        snapshot.last_error = self.last_error.lock().unwrap().clone();
        snapshot.clone()
    }

    /// Current snapshot with `id` marked pending, so the UI shows a spinner immediately.
    pub fn tick_pending_preview(&self, _settings: &Settings, backend: BackendKind, name: &str) -> Snapshot {
        let id = format!("{}/{}", backend.label(), name);
        self.pending.lock().unwrap().insert(id);
        let mut snapshot = self.snapshot.lock().unwrap();
        snapshot.pending = self.pending.lock().unwrap().iter().cloned().collect();
        snapshot.clone()
    }

    pub async fn toggle(&self, settings: &Settings, backend: BackendKind, name: &str, load: bool) {
        let id = format!("{}/{}", backend.label(), name);
        self.pending.lock().unwrap().insert(id.clone());
        let result = match backend {
            BackendKind::LlamaCpp => {
                let b = LlamaCpp { base: trim(&settings.llama_cpp_url) };
                if load { b.load(&self.client, name).await } else { b.unload(&self.client, name).await }
            }
            BackendKind::Ollama => {
                let b = Ollama { base: trim(&settings.ollama_url) };
                if load { b.load(&self.client, name).await } else { b.unload(&self.client, name).await }
            }
        };
        *self.last_error.lock().unwrap() = result.err().map(|e| format!("{name}: {e}"));
        self.pending.lock().unwrap().remove(&id);
    }
}

fn trim(url: &str) -> String {
    url.trim().trim_end_matches('/').to_string()
}
