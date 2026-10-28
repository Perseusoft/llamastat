import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

export type BackendKind = "llamaCpp" | "ollama";
export type ModelState = "loaded" | "loading" | "unloaded";

export interface ModelStats {
  promptTokensTotal: number;
  predictedTokensTotal: number;
  inFlightTokens: number;
  promptTokensPerSecond: number | null;
  predictedTokensPerSecond: number | null;
  requestsProcessing: number;
  contextSize: number | null;
  contextUsed: number | null;
  slotsTotal: number;
  slotsBusy: number;
  vramBytes: number | null;
  expiresAt: number | null;
}

export interface ModelInfo {
  id: string;
  backend: BackendKind;
  name: string;
  state: ModelState;
  sizeBytes: number | null;
  /// GGUF path for llama.cpp presets (what "Remove" deletes).
  path: string | null;
  stats: ModelStats | null;
}

export interface ActiveModel {
  info: ModelInfo;
  processRam: number | null;
  cpu: number | null;
  generationRate: number;
  promptRate: number;
  busy: boolean;
}

export interface Sample {
  time: number;
  generationRate: number;
  promptRate: number;
  gpu: number;
  memory: number;
  swap: number;
}

export interface Snapshot {
  backends: { kind: BackendKind; online: boolean; models: ModelInfo[] }[];
  active: ActiveModel[];
  memory: { total: number; used: number; swapUsed: number; swapTotal: number };
  gpu: { name: string; utilization: number; memoryUsed: number | null; memoryTotal: number | null } | null;
  history: Sample[];
  generationRate: number;
  generating: boolean;
  contextFraction: number | null;
  pending: string[];
  lastError: string | null;
  platform: "macos" | "windows" | "linux" | string;
}

export type Widget = "icon" | "tokensPerSecond" | "model" | "ram" | "gpu" | "context" | "ramBar" | "sparkline";
export type TrayIcon = "llama" | "chip" | "bolt" | "dot";
export type Section = "rings" | "warnings" | "history" | "models" | "memory" | "modelList";

export type Theme = "system" | "light" | "dark";

export interface Settings {
  theme: Theme;
  widgets: { widget: Widget; enabled: boolean }[];
  icon: TrayIcon;
  colored: boolean;
  tokensOnlyWhileGenerating: boolean;
  hiddenSections: Section[];
  refreshInterval: number;
  llamaCppEnabled: boolean;
  llamaCppUrl: string;
  routerService: string;
  /// Router presets.ini; null = read it from the running llama-server's arguments.
  llamaCppPresets: string | null;
  ollamaEnabled: boolean;
  ollamaUrl: string;
  language: string | null;
}

export interface InstallProgress {
  id: string;
  backend: BackendKind;
  name: string;
  /// downloading | pulling | removing | done | removed | cancelled | error
  status: string;
  completed: number;
  total: number | null;
  done: boolean;
  error: string | null;
}

export type InstallSource =
  | { kind: "ollama"; model: string }
  | { kind: "huggingFace"; repo: string; file: string; name: string | null };

export interface HfRepo { id: string; downloads: number; likes: number }
export interface HfFile { path: string; size: number | null }
export interface RouterPaths { presets: string | null; modelsDir: string | null }

export const backendLabel = (kind: BackendKind) => (kind === "llamaCpp" ? "llama.cpp" : "Ollama");

export const api = {
  snapshot: () => invoke<Snapshot>("get_snapshot"),
  settings: () => invoke<Settings>("get_settings"),
  saveSettings: (settings: Settings) => invoke("set_settings", { settings }),
  toggleModel: (model: ModelInfo) =>
    invoke("toggle_model", { backend: model.backend, name: model.name, load: model.state === "unloaded" }),
  restartRouter: () => invoke("restart_router"),
  openSettings: (page?: string) => invoke("open_settings", { page: page ?? null }),
  searchModels: (query: string) => invoke<HfRepo[]>("search_models", { query }),
  modelFiles: (repo: string) => invoke<HfFile[]>("model_files", { repo }),
  installModel: (source: InstallSource) => invoke("install_model", { source }),
  cancelInstall: (id: string) => invoke("cancel_install", { id }),
  removeModel: (model: ModelInfo) => invoke("remove_model", { backend: model.backend, name: model.name }),
  routerPaths: () => invoke<RouterPaths>("router_paths"),
  fitPanel: (height: number) => invoke("fit_panel", { height }),
  quit: () => invoke("quit"),
  onSnapshot: (fn: (s: Snapshot) => void) => listen<Snapshot>("snapshot", (e) => fn(e.payload)),
  onSettings: (fn: (s: Settings) => void) => listen<Settings>("settings", (e) => fn(e.payload)),
  onInstall: (fn: (p: InstallProgress) => void) => listen<InstallProgress>("install", (e) => fn(e.payload)),
  onOpenPage: (fn: (page: string) => void) => listen<string>("open-page", (e) => fn(e.payload)),
};
