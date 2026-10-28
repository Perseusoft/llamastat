import { api, type InstallProgress, type Settings, type Snapshot } from "./api";

/// Live snapshot + settings shared by every view in a window.
class Store {
  snapshot = $state<Snapshot | null>(null);
  settings = $state<Settings | null>(null);
  /// Installs and removals in flight (or just finished), by model id.
  installs = $state<Record<string, InstallProgress>>({});

  async start() {
    this.snapshot = await api.snapshot();
    this.settings = await api.settings();
    await api.onSnapshot((s) => (this.snapshot = s));
    await api.onSettings((s) => (this.settings = s));
    await api.onInstall((p) => (this.installs = { ...this.installs, [p.id]: p }));
  }

  dismissInstall(id: string) {
    const { [id]: _, ...rest } = this.installs;
    this.installs = rest;
  }

  /// Apply a change locally and persist it (the Rust side re-renders the tray).
  async update(change: (s: Settings) => void) {
    if (!this.settings) return;
    const next: Settings = JSON.parse(JSON.stringify(this.settings));
    change(next);
    this.settings = next;
    await api.saveSettings(next);
  }

  isVisible(section: Settings["hiddenSections"][number]) {
    return !this.settings?.hiddenSections.includes(section);
  }
}

export const store = new Store();
