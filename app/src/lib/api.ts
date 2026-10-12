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

export interface Settings {
  widgets: { widget: Widget; enabled: boolean }[];
  icon: TrayIcon;
  colored: boolean;
  tokensOnlyWhileGenerating: boolean;
  hiddenSections: Section[];
  refreshInterval: number;
  llamaCppEnabled: boolean;
  llamaCppUrl: string;
  routerService: string;
  ollamaEnabled: boolean;
  ollamaUrl: string;
  language: string | null;
}

export const backendLabel = (kind: BackendKind) => (kind === "llamaCpp" ? "llama.cpp" : "Ollama");

export const api = {
  snapshot: () => invoke<Snapshot>("get_snapshot"),
  settings: () => invoke<Settings>("get_settings"),
  saveSettings: (settings: Settings) => invoke("set_settings", { settings }),
  toggleModel: (model: ModelInfo) =>
    invoke("toggle_model", { backend: model.backend, name: model.name, load: model.state === "unloaded" }),
  restartRouter: () => invoke("restart_router"),
  openSettings: () => invoke("open_settings"),
  fitPanel: (height: number) => invoke("fit_panel", { height }),
  quit: () => invoke("quit"),
  onSnapshot: (fn: (s: Snapshot) => void) => listen<Snapshot>("snapshot", (e) => fn(e.payload)),
  onSettings: (fn: (s: Settings) => void) => listen<Settings>("settings", (e) => fn(e.payload)),
};
