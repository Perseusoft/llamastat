// Browser-only preview (`npm run dev` without Tauri): fakes the IPC with a recorded snapshot
// so the UI can be developed and screenshotted in a normal browser.
import { emit } from "@tauri-apps/api/event";
import { mockIPC } from "@tauri-apps/api/mocks";
import type { Settings, Snapshot } from "../lib/api";
import recorded from "./snapshot.json";

const settings: Settings = {
  widgets: (["icon", "tokensPerSecond", "model", "sparkline", "ram", "ramBar", "gpu", "context"] as const).map((widget, i) => ({ widget, enabled: i < 4 })),
  icon: "llama",
  colored: true,
  tokensOnlyWhileGenerating: false,
  hiddenSections: [],
  refreshInterval: 1,
  llamaCppEnabled: true,
  llamaCppUrl: "http://127.0.0.1:8080",
  routerService: "com.local.llama-router",
  llamaCppPresets: null,
  ollamaEnabled: true,
  ollamaUrl: "http://127.0.0.1:11434",
  language: new URLSearchParams(location.search).get("lang"),
};

/// Synthesize 5 minutes of history around the recorded values.
function fakeSnapshot(): Snapshot {
  const base = recorded as unknown as Snapshot;
  const now = Date.now();
  const history = Array.from({ length: 300 }, (_, i) => {
    const generating = i > 200 && i < 285;
    return {
      time: now - (299 - i) * 1000,
      generationRate: generating ? 24 + Math.sin(i / 3) * 1.5 : 0,
      promptRate: 0,
      gpu: generating ? 0.95 : 0.03 + Math.random() * 0.05,
      memory: 0.86 + Math.sin(i / 40) * 0.02,
      swap: base.memory.swapUsed,
    };
  });
  return { ...base, history, generationRate: history.at(-1)!.generationRate, generating: true };
}

/// Fake Hugging Face answers and a download that advances over a few seconds.
const repos = [
  { id: "unsloth/Qwen3-8B-GGUF", downloads: 671881, likes: 412 },
  { id: "Qwen/Qwen3-8B-GGUF", downloads: 402113, likes: 388 },
  { id: "bartowski/Qwen_Qwen3-8B-GGUF", downloads: 155020, likes: 97 },
];
const files = ["Q4_K_M", "Q5_K_M", "Q6_K", "Q8_0"].map((q, i) => ({ path: `Qwen3-8B-${q}.gguf`, size: 4.9e9 + i * 1.2e9 }));
function fakeInstall(source: { kind: string; model?: string; file?: string; name?: string | null }) {
  const backend = source.kind === "ollama" ? "ollama" : "llamaCpp";
  const name = source.kind === "ollama" ? source.model! : source.name || source.file!.replace(/\.gguf$/, "");
  const id = `${backend === "ollama" ? "Ollama" : "llama.cpp"}/${name}`;
  const total = 4.9e9;
  let completed = 0;
  const timer = setInterval(() => {
    completed = Math.min(total, completed + total / 40);
    const done = completed >= total;
    emit("install", { id, backend, name, status: done ? "done" : backend === "ollama" ? "pulling" : "downloading", completed, total, done, error: null });
    if (done) clearInterval(timer);
  }, 250);
}

export function installMock() {
  mockIPC((cmd, args) => {
    switch (cmd) {
      case "get_snapshot": return fakeSnapshot();
      case "get_settings": return settings;
      case "set_settings": Object.assign(settings, (args as { settings: Settings }).settings); emit("settings", settings); return;
      case "search_models": return repos;
      case "model_files": return files;
      case "install_model": fakeInstall((args as { source: { kind: string } }).source); return;
      case "remove_model": {
        const a = args as { backend: string; name: string };
        const id = `${a.backend === "ollama" ? "Ollama" : "llama.cpp"}/${a.name}`;
        emit("install", { id, backend: a.backend, name: a.name, status: "removed", completed: 0, total: null, done: true, error: null });
        return;
      }
      case "router_paths": return { presets: "/Users/me/models/presets.ini", modelsDir: "/Users/me/models" };
      default: return null;
    }
  }, { shouldMockEvents: true });
  // `?install=1` starts a fake download right away, to look at the progress UI.
  if (new URLSearchParams(location.search).get("install")) {
    setTimeout(() => fakeInstall({ kind: "huggingFace", file: "Qwen3-8B-Q5_K_M.gguf", name: null }), 500);
  }
}
