//! Local inference servers: llama.cpp in router mode and Ollama.

use std::collections::HashMap;
use std::time::Duration;

use serde::Deserialize;
use serde_json::json;

use crate::model::*;

pub fn client() -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(3))
        .build()
        .expect("http client")
}

async fn post(client: &reqwest::Client, url: String, body: serde_json::Value) -> Result<(), String> {
    let response = client
        .post(url)
        .timeout(Duration::from_secs(180))
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if response.status().is_success() {
        Ok(())
    } else {
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        Err(format!("HTTP {status}: {}", text.chars().take(300).collect::<String>()))
    }
}

// MARK: llama.cpp

/// llama-server in router mode (`--models-preset`). Per-model endpoints go through the router
/// with `?model=<id>`; `/metrics` needs `metrics = 1` in the preset.
pub struct LlamaCpp {
    pub base: String,
}

#[derive(Deserialize)]
struct ModelList {
    data: Vec<ModelEntry>,
}

#[derive(Deserialize)]
struct ModelEntry {
    id: String,
    status: Option<ModelStatus>,
}

#[derive(Deserialize)]
struct ModelStatus {
    value: String,
    #[serde(default)]
    args: Vec<String>,
}

#[derive(Deserialize)]
struct Slot {
    n_ctx: Option<u64>,
    is_processing: bool,
    id_task: Option<i64>,
    n_prompt_tokens: Option<u64>,
    next_token: Option<Vec<NextToken>>,
}

#[derive(Deserialize)]
struct NextToken {
    n_decoded: Option<u64>,
}

impl LlamaCpp {
    pub async fn snapshot(&self, client: &reqwest::Client) -> BackendSnapshot {
        let offline = BackendSnapshot { kind: BackendKind::LlamaCpp, online: false, models: vec![] };
        let Ok(response) = client.get(format!("{}/v1/models", self.base)).send().await else { return offline };
        let Ok(list) = response.json::<ModelList>().await else { return offline };

        let mut models = Vec::new();
        for entry in list.data {
            let status = entry.status.as_ref();
            let state = match status.map(|s| s.value.as_str()) {
                Some("loaded") => ModelState::Loaded,
                Some("loading") => ModelState::Loading,
                _ => ModelState::Unloaded,
            };
            let args = status.map(|s| s.args.as_slice()).unwrap_or_default();
            let mut info = ModelInfo::new(BackendKind::LlamaCpp, entry.id.clone(), state);
            info.path = argument(args, "--model").map(str::to_string);
            info.size_bytes = info.path.as_deref().and_then(|path| std::fs::metadata(path).ok()).map(|m| m.len());
            info.process_match = Some(ProcessMatch::FlagValue { exe: "llama-server", flag: "--alias", value: entry.id.clone() });
            if state == ModelState::Loaded {
                let mut stats = self.stats(client, &entry.id).await;
                if stats.context_size.is_none() {
                    stats.context_size = argument(args, "--ctx-size").and_then(|v| v.parse().ok());
                }
                info.stats = Some(stats);
            }
            models.push(info);
        }
        BackendSnapshot { kind: BackendKind::LlamaCpp, online: true, models }
    }

    async fn stats(&self, client: &reqwest::Client, model: &str) -> ModelStats {
        let mut stats = ModelStats::default();
        // The router autoloads a model on any request naming it; without autoload=false,
        // polling right after an eject loads the model straight back.
        let query = [("model", model), ("autoload", "false")];

        if let Ok(response) = client.get(format!("{}/metrics", self.base)).query(&query).send().await {
            if let Ok(text) = response.text().await {
                let metrics = parse_prometheus(&text);
                let get = |key: &str| metrics.get(key).copied();
                stats.prompt_tokens_total = get("llamacpp:prompt_tokens_total").unwrap_or(0.0);
                stats.predicted_tokens_total = get("llamacpp:tokens_predicted_total").unwrap_or(0.0);
                // The *_tokens_seconds gauges reset on every scrape, so average the cumulative counters.
                stats.prompt_tokens_per_second = ratio(stats.prompt_tokens_total, get("llamacpp:prompt_seconds_total"));
                stats.predicted_tokens_per_second = ratio(stats.predicted_tokens_total, get("llamacpp:tokens_predicted_seconds_total"));
                stats.requests_processing = get("llamacpp:requests_processing").unwrap_or(0.0) as u32;
            }
        }

        if let Ok(response) = client.get(format!("{}/slots", self.base)).query(&query).send().await {
            if let Ok(slots) = response.json::<Vec<Slot>>().await {
                stats.slots_total = slots.len() as u32;
                stats.slots_busy = slots.iter().filter(|s| s.is_processing).count() as u32;
                stats.context_size = slots.first().and_then(|s| s.n_ctx);
                // Busy slot first, otherwise the one that served the latest task.
                let current = slots.iter().find(|s| s.is_processing)
                    .or_else(|| slots.iter().filter(|s| s.id_task.is_some()).max_by_key(|s| s.id_task));
                // n_prompt_tokens grows as the slot decodes, so it already is the context in use.
                stats.context_used = current.and_then(|s| s.n_prompt_tokens);
                stats.in_flight_tokens = slots.iter().filter(|s| s.is_processing)
                    .filter_map(|s| s.next_token.as_ref()?.first()?.n_decoded)
                    .sum::<u64>() as f64;
            }
        }
        stats
    }

    pub async fn load(&self, client: &reqwest::Client, model: &str) -> Result<(), String> {
        post(client, format!("{}/models/load", self.base), json!({ "model": model })).await
    }

    pub async fn unload(&self, client: &reqwest::Client, model: &str) -> Result<(), String> {
        post(client, format!("{}/models/unload", self.base), json!({ "model": model })).await
    }
}

fn argument<'a>(args: &'a [String], flag: &str) -> Option<&'a str> {
    let i = args.iter().position(|a| a == flag)?;
    args.get(i + 1).map(String::as_str)
}

fn ratio(tokens: f64, seconds: Option<f64>) -> Option<f64> {
    seconds.filter(|s| *s > 0.0).map(|s| tokens / s)
}

/// Parses `name value` lines; labels are dropped (llama.cpp doesn't use them).
pub fn parse_prometheus(text: &str) -> HashMap<String, f64> {
    text.lines()
        .filter(|line| !line.starts_with('#'))
        .filter_map(|line| {
            let mut parts = line.split_whitespace();
            let name = parts.next()?.split('{').next()?.to_string();
            let value = parts.next()?.parse().ok()?;
            Some((name, value))
        })
        .collect()
}

// MARK: Ollama

/// Ollama's native API. No live token counters, so stats are what `/api/ps` reports.
pub struct Ollama {
    pub base: String,
}

#[derive(Deserialize)]
struct Tags {
    models: Vec<Tag>,
}

#[derive(Deserialize)]
struct Tag {
    name: String,
    size: Option<u64>,
}

#[derive(Deserialize)]
struct Running {
    models: Vec<RunningModel>,
}

#[derive(Deserialize)]
struct RunningModel {
    name: String,
    size_vram: Option<u64>,
    context_length: Option<u64>,
    expires_at: Option<String>,
}

impl Ollama {
    pub async fn snapshot(&self, client: &reqwest::Client) -> BackendSnapshot {
        let offline = BackendSnapshot { kind: BackendKind::Ollama, online: false, models: vec![] };
        let Ok(response) = client.get(format!("{}/api/tags", self.base)).send().await else { return offline };
        let Ok(tags) = response.json::<Tags>().await else { return offline };

        let mut running: HashMap<String, RunningModel> = HashMap::new();
        if let Ok(response) = client.get(format!("{}/api/ps", self.base)).send().await {
            if let Ok(ps) = response.json::<Running>().await {
                running = ps.models.into_iter().map(|m| (m.name.clone(), m)).collect();
            }
        }

        let models = tags.models.into_iter().map(|tag| {
            let live = running.get(&tag.name);
            let state = if live.is_some() { ModelState::Loaded } else { ModelState::Unloaded };
            let mut info = ModelInfo::new(BackendKind::Ollama, tag.name.clone(), state);
            info.size_bytes = tag.size;
            if let Some(live) = live {
                // Runners get the blob path, not the model name; good enough with one model loaded.
                info.process_match = Some(ProcessMatch::ArgContains { exe: "llama-server", needle: "models/blobs" });
                info.stats = Some(ModelStats {
                    context_size: live.context_length,
                    vram_bytes: live.size_vram,
                    expires_at: live.expires_at.as_deref().and_then(parse_rfc3339),
                    ..Default::default()
                });
            }
            info
        }).collect();
        BackendSnapshot { kind: BackendKind::Ollama, online: true, models }
    }

    pub async fn load(&self, client: &reqwest::Client, model: &str) -> Result<(), String> {
        post(client, format!("{}/api/generate", self.base), json!({ "model": model, "keep_alive": "15m" })).await
    }

    pub async fn unload(&self, client: &reqwest::Client, model: &str) -> Result<(), String> {
        post(client, format!("{}/api/generate", self.base), json!({ "model": model, "keep_alive": 0 })).await
    }

    /// `ollama pull`: streams NDJSON progress lines (one `total`/`completed` pair per layer).
    /// `client` must have no overall timeout. Progress is the sum over the layers seen so far.
    pub async fn pull(&self, client: &reqwest::Client, model: &str, cancel: &std::sync::atomic::AtomicBool,
                      mut report: impl FnMut(u64, Option<u64>)) -> Result<(), String> {
        use futures::StreamExt;
        #[derive(Deserialize)]
        struct Line { status: Option<String>, error: Option<String>, digest: Option<String>, total: Option<u64>, completed: Option<u64> }

        let response = client.post(format!("{}/api/pull", self.base))
            .json(&json!({ "model": model, "stream": true }))
            .send().await.map_err(|e| e.to_string())?;
        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            return Err(format!("HTTP {status}: {}", text.chars().take(300).collect::<String>()));
        }
        let mut layers: HashMap<String, (u64, u64)> = HashMap::new();
        let mut buffer = String::new();
        let mut stream = response.bytes_stream();
        while let Some(chunk) = stream.next().await {
            if cancel.load(std::sync::atomic::Ordering::Relaxed) { return Err("cancelled".into()); }
            buffer.push_str(&String::from_utf8_lossy(&chunk.map_err(|e| e.to_string())?));
            while let Some(end) = buffer.find('\n') {
                let line = buffer[..end].trim().to_string();
                buffer.drain(..=end);
                if line.is_empty() { continue; }
                let Ok(parsed) = serde_json::from_str::<Line>(&line) else { continue };
                if let Some(error) = parsed.error { return Err(error); }
                if let (Some(digest), Some(total)) = (parsed.digest, parsed.total) {
                    layers.insert(digest, (parsed.completed.unwrap_or(0), total));
                    let done: u64 = layers.values().map(|(c, _)| c).sum();
                    let total: u64 = layers.values().map(|(_, t)| t).sum();
                    report(done, Some(total));
                }
                if parsed.status.as_deref() == Some("success") { return Ok(()); }
            }
        }
        Err("the pull ended without a success status".into())
    }

    pub async fn delete(&self, client: &reqwest::Client, model: &str) -> Result<(), String> {
        let response = client.delete(format!("{}/api/delete", self.base))
            .timeout(Duration::from_secs(60))
            .json(&json!({ "model": model }))
            .send().await.map_err(|e| e.to_string())?;
        if response.status().is_success() { return Ok(()); }
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        Err(format!("HTTP {status}: {}", text.chars().take(300).collect::<String>()))
    }
}

/// Minimal RFC 3339 → unix seconds (Ollama: `2026-10-12T17:45:01.123456789-06:00`).
fn parse_rfc3339(s: &str) -> Option<i64> {
    let (date, rest) = s.split_once('T')?;
    let mut d = date.split('-').map(|p| p.parse::<i64>());
    let (y, m, day) = (d.next()?.ok()?, d.next()?.ok()?, d.next()?.ok()?);
    let time_end = rest.find(|c: char| c == 'Z' || c == '+' || c == '-').unwrap_or(rest.len());
    let mut t = rest[..time_end].split(':');
    let (h, min) = (t.next()?.parse::<i64>().ok()?, t.next()?.parse::<i64>().ok()?);
    let sec = t.next()?.split('.').next()?.parse::<i64>().ok()?;
    let offset = match &rest[time_end..] {
        "" | "Z" => 0,
        tz => {
            let sign = if tz.starts_with('-') { -1 } else { 1 };
            let mut parts = tz[1..].split(':');
            let oh = parts.next()?.parse::<i64>().ok()?;
            let om = parts.next().unwrap_or("0").parse::<i64>().ok()?;
            sign * (oh * 3600 + om * 60)
        }
    };
    // Days from civil (Howard Hinnant).
    let (y, m) = if m <= 2 { (y - 1, m + 9) } else { (y, m - 3) };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * m + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    Some(days * 86400 + h * 3600 + min * 60 + sec - offset)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prometheus() {
        let m = parse_prometheus("# HELP x\nllamacpp:prompt_tokens_total 14\nllamacpp:n_decode_total 17\n");
        assert_eq!(m["llamacpp:prompt_tokens_total"], 14.0);
        assert_eq!(m.len(), 2);
    }

    #[test]
    fn rfc3339() {
        assert_eq!(parse_rfc3339("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(parse_rfc3339("2026-10-12T17:45:01.123456789-06:00"), Some(1791848701));
    }
}
