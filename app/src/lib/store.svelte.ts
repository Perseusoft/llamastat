import { api, type Settings, type Snapshot } from "./api";

/// Live snapshot + settings shared by every view in a window.
class Store {
  snapshot = $state<Snapshot | null>(null);
  settings = $state<Settings | null>(null);

  async start() {
    this.snapshot = await api.snapshot();
    this.settings = await api.settings();
    await api.onSnapshot((s) => (this.snapshot = s));
    await api.onSettings((s) => (this.settings = s));
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
