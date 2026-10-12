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

export function installMock() {
  mockIPC((cmd, args) => {
    switch (cmd) {
      case "get_snapshot": return fakeSnapshot();
      case "get_settings": return settings;
      case "set_settings": Object.assign(settings, (args as { settings: Settings }).settings); emit("settings", settings); return;
      default: return null;
    }
  }, { shouldMockEvents: true });
}
