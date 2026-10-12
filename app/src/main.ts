import { mount } from "svelte";
import "./app.css";
import { store } from "./lib/store.svelte";
import Panel from "./pages/Panel.svelte";
import Settings from "./pages/Settings.svelte";

// One bundle, two windows: the Rust side opens index.html#panel or index.html#settings.
if (import.meta.env.DEV && !("__TAURI_INTERNALS__" in window)) {
  (await import("./dev/mock")).installMock();
}

const isSettings = location.hash.startsWith("#settings");
document.body.classList.toggle("settings", isSettings);
await store.start();
mount(isSettings ? Settings : Panel, { target: document.getElementById("app")! });
