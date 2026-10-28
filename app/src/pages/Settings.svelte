<script lang="ts">
  import { getVersion } from "@tauri-apps/api/app";
  import { disable, enable, isEnabled } from "@tauri-apps/plugin-autostart";
  import { api, backendLabel, type Section, type Settings, type TrayIcon, type Widget } from "../lib/api";
  import AreaChart from "../lib/components/AreaChart.svelte";
  import ModelDetails from "../lib/components/ModelDetails.svelte";
  import ModelManager from "../lib/components/ModelManager.svelte";
  import Ring from "../lib/components/Ring.svelte";
  import TrayPreview from "../lib/components/TrayPreview.svelte";
  import { ICONS } from "../lib/icons";
  import * as f from "../lib/format";
  import { languages, t } from "../lib/i18n";
  import { store } from "../lib/store.svelte";

  type Page = "dashboard" | "tray" | "panel" | "models" | "backends" | "general";
  const PAGES: Page[] = ["dashboard", "tray", "panel", "models", "backends", "general"];
  const asPage = (p: string | undefined) => PAGES.find((x) => x === p);
  // The Rust side opens index.html#settings/<page>, or sends "open-page" if the window already exists.
  let page = $state<Page>(asPage(location.hash.split("/")[1]) ?? "dashboard");
  api.onOpenPage((p) => { const next = asPage(p); if (next) page = next; });
  let launchAtLogin = $state(false);
  let dragging = $state<number | null>(null);

  let version = $state("");
  isEnabled().then((v) => (launchAtLogin = v)).catch(() => {});
  getVersion().then((v) => (version = v)).catch(() => {});

  const s = $derived(store.snapshot);
  const settings = $derived(store.settings);
  const isMac = $derived(s?.platform === "macos");

  const pages = $derived<{ id: Page; title: string; icon: string }[]>([
    { id: "dashboard", title: t("Dashboard"), icon: "▦" },
    { id: "tray", title: isMac ? t("Menu bar") : t("Tray"), icon: "▭" },
    { id: "panel", title: t("Panel"), icon: "▤" },
    { id: "models", title: t("Models"), icon: "▣" },
    { id: "backends", title: t("Backends"), icon: "⛁" },
    { id: "general", title: t("General"), icon: "⚙︎" },
  ]);

  const widgetTitles: Record<Widget, string> = {
    icon: "Icon", tokensPerSecond: "Tokens per second", model: "Loaded model", ram: "RAM %",
    gpu: "GPU %", context: "Context used %", ramBar: "RAM bar", sparkline: "Tokens/s graph",
  };
  const iconTitles: Record<TrayIcon, string> = { llama: "Llama", chip: "Chip", bolt: "Bolt", dot: "Dot" };
  const sections: Record<Section, string> = {
    rings: "Gauges", warnings: "Warnings", history: "History", models: "Loaded model details", memory: "Memory", modelList: "Models",
  };

  const set = (change: (x: Settings) => void) => store.update(change);
  const memFraction = $derived(s ? s.memory.used / Math.max(s.memory.total, 1) : 0);

  function drop(target: number) {
    if (dragging == null || dragging === target) return;
    const from = dragging;
    set((x) => {
      const [moved] = x.widgets.splice(from, 1);
      x.widgets.splice(target, 0, moved);
    });
    dragging = null;
  }

  async function toggleLogin(on: boolean) {
    try {
      if (on) await enable(); else await disable();
    } finally {
      launchAtLogin = await isEnabled();
    }
  }

  function resetTray() {
    set((x) => {
      const on = ["icon", "tokensPerSecond", "model"];
      const order: Widget[] = ["icon", "tokensPerSecond", "model", "sparkline", "ram", "ramBar", "gpu", "context"];
      x.widgets = order.map((widget) => ({ widget, enabled: on.includes(widget) }));
      x.icon = "llama";
      x.colored = false;
      x.tokensOnlyWhileGenerating = true;
    });
  }
</script>

<div class="window">
  <nav>
    {#each pages as p}
      <button class:active={page === p.id} onclick={() => (page = p.id)}><span>{p.icon}</span>{p.title}</button>
    {/each}
  </nav>

  <main>
    <h1>{pages.find((p) => p.id === page)?.title}</h1>
    {#if s && settings}
      {#if page === "dashboard"}
        <section class="card">
          <div class="memory">
            <Ring fraction={memFraction} color={memFraction > 0.85 ? "var(--warning)" : "var(--memory)"} label={f.percent(memFraction)} caption="RAM" size={84} width={8} />
            <div class="grow">
              <div class="split"><span>{t("Used: {0}", f.gigabytes(s.memory.used))}</span><span>{t("Total: {0}", f.gigabytes(s.memory.total))}</span></div>
              <div class="stack"><span style="width: {memFraction * 100}%"></span></div>
              <div class="legend">
                <span><i style="background: var(--memory)"></i>{t("In use")}: <b>{f.gigabytes(s.memory.used)}</b></span>
                <span><i style="background: var(--track)"></i>{t("Free")}: <b>{f.gigabytes(s.memory.total - s.memory.used)}</b></span>
              </div>
            </div>
          </div>
          <AreaChart samples={s.history} value={(x) => x.memory * 100} color="var(--memory)" max={100} height={90} axis unit="%" />
        </section>
        <section class="card">
          <h2>{t("Tokens per second")}</h2>
          <AreaChart samples={s.history} value={(x) => x.generationRate} color="var(--generation)" height={140} axis />
        </section>
        <div class="columns">
          <section class="card">
            <h2>GPU {s.gpu ? `· ${s.gpu.name}` : ""}</h2>
            {#if s.gpu}
              <div class="mini">
                <Ring fraction={s.gpu.utilization} color="var(--gpu)" label={f.percent(s.gpu.utilization)} size={70} />
                <div class="grow"><AreaChart samples={s.history} value={(x) => x.gpu * 100} color="var(--gpu)" max={100} height={80} unit="%" /></div>
              </div>
            {:else}
              <p class="hint">{t("No GPU stats on this system")}</p>
            {/if}
          </section>
          <section class="card">
            <h2>{t("Swap")}</h2>
            <div class="mini">
              <Ring fraction={s.memory.swapTotal ? s.memory.swapUsed / s.memory.swapTotal : 0} color="var(--prompt)" label={f.gigabytes(s.memory.swapUsed)} size={70} />
              <div class="grow"><AreaChart samples={s.history} value={(x) => x.swap / 1024 ** 3} color="var(--prompt)" height={80} /></div>
            </div>
          </section>
        </div>
        {#each s.active as model (model.info.id)}
          <section class="card"><h2>{model.info.name}</h2><ModelDetails {model} /></section>
        {/each}

      {:else if page === "tray"}
        <section class="card">
          <h2>{t("Preview")}</h2>
          <div class="center"><TrayPreview /></div>
        </section>
        <section class="card">
          <h2>{t("Icon")}</h2>
          <div class="icons">
            {#each Object.keys(ICONS) as icon}
              <button class:selected={settings.icon === icon} title={t(iconTitles[icon as TrayIcon])}
                onclick={() => set((x) => (x.icon = icon as TrayIcon))}>
                <svg viewBox="0 0 100 100" width="20" height="20"><path d={ICONS[icon as TrayIcon]} fill="currentColor" fill-rule="evenodd" /></svg>
              </button>
            {/each}
          </div>
        </section>
        <section class="card">
          <h2>{t("Widgets")}</h2>
          <p class="hint">{t("Turn widgets on and drag them to change the order.")} {t("Graphics are drawn in the icon; text appears next to it (in the tooltip on Windows).")}</p>
          <ul class="widgets">
            {#each settings.widgets as item, i (item.widget)}
              <li draggable="true" class:dragging={dragging === i}
                ondragstart={() => (dragging = i)} ondragover={(e) => e.preventDefault()} ondrop={() => drop(i)} ondragend={() => (dragging = null)}>
                <span class="grip">≡</span>
                <span class="grow">{t(widgetTitles[item.widget])}</span>
                <input type="checkbox" class="switch" checked={item.enabled} onchange={(e) => set((x) => (x.widgets[i].enabled = e.currentTarget.checked))} />
              </li>
            {/each}
          </ul>
        </section>
        <section class="card">
          <h2>{t("Options")}</h2>
          <label class="check"><input type="checkbox" checked={settings.colored} onchange={(e) => set((x) => (x.colored = e.currentTarget.checked))} />{t("Colored (otherwise follows the menu bar color)")}</label>
          <label class="check"><input type="checkbox" checked={settings.tokensOnlyWhileGenerating} onchange={(e) => set((x) => (x.tokensOnlyWhileGenerating = e.currentTarget.checked))} />{t("Show tokens/s only while generating")}</label>
          <div><button onclick={resetTray}>{t("Restore defaults")}</button></div>
        </section>

      {:else if page === "panel"}
        <section class="card">
          <h2>{t("Sections shown in the panel")}</h2>
          {#each Object.entries(sections) as [id, title]}
            <label class="check">
              <input type="checkbox" checked={!settings.hiddenSections.includes(id as Section)}
                onchange={(e) => set((x) => {
                  x.hiddenSections = x.hiddenSections.filter((h) => h !== id);
                  if (!e.currentTarget.checked) x.hiddenSections.push(id as Section);
                })} />
              {t(title)}
            </label>
          {/each}
        </section>

      {:else if page === "models"}
        <ModelManager />

      {:else if page === "backends"}
        {#each [{ kind: "llamaCpp", enabled: "llamaCppEnabled", url: "llamaCppUrl" }, { kind: "ollama", enabled: "ollamaEnabled", url: "ollamaUrl" }] as const as b}
          {@const online = s.backends.find((x) => x.kind === b.kind)?.online ?? false}
          <section class="card">
            <div class="split">
              <h2>{backendLabel(b.kind)} <i class="status" class:on={online}></i><small>{online ? t("Online") : t("Offline")}</small></h2>
              <input type="checkbox" class="switch" checked={settings[b.enabled]} onchange={(e) => set((x) => (x[b.enabled] = e.currentTarget.checked))} />
            </div>
            <label class="field">URL <input type="text" value={settings[b.url]} onchange={(e) => set((x) => (x[b.url] = e.currentTarget.value))} /></label>
            {#if b.kind === "llamaCpp"}
              {#if s.platform !== "windows"}
                <label class="field">{t("Router service")} <input type="text" value={settings.routerService} onchange={(e) => set((x) => (x.routerService = e.currentTarget.value))} /></label>
                <p class="hint">{t("launchd label (macOS) or systemd --user unit (Linux).")}</p>
              {/if}
              <label class="field">{t("Presets file")} <input type="text" placeholder="presets.ini" value={settings.llamaCppPresets ?? ""} onchange={(e) => set((x) => (x.llamaCppPresets = e.currentTarget.value.trim() || null))} /></label>
              <p class="hint">{t("Leave empty to read it from the running llama-server (--models-preset). Installing and removing models edits this file.")}</p>
              <p class="hint">{t("Router mode (llama-server --models-preset). Add metrics = 1 to each preset for token stats.")}</p>
            {:else}
              <p class="hint">{t("Ollama doesn't expose token counters; only memory, context and expiry are shown.")}</p>
            {/if}
          </section>
        {/each}

      {:else if page === "general"}
        <section class="card">
          <label class="field">{t("Appearance")}
            <select value={settings.theme} onchange={(e) => set((x) => (x.theme = e.currentTarget.value as Settings["theme"]))}>
              <option value="system">{t("System")}</option>
              <option value="light">{t("Light")}</option>
              <option value="dark">{t("Dark")}</option>
            </select>
          </label>
          <label class="field">{t("Language")}
            <select value={settings.language ?? ""} onchange={(e) => set((x) => (x.language = e.currentTarget.value || null))}>
              {#each languages as l}<option value={l.code ?? ""}>{l.code ? l.name : t(l.name)}</option>{/each}
            </select>
          </label>
          <label class="field">{t("Update every")}
            <select value={settings.refreshInterval} onchange={(e) => set((x) => (x.refreshInterval = Number(e.currentTarget.value)))}>
              {#each [1, 2, 5] as v}<option value={v}>{v} s</option>{/each}
            </select>
          </label>
          <label class="check"><input type="checkbox" checked={launchAtLogin} onchange={(e) => toggleLogin(e.currentTarget.checked)} />{t("Open at login")}</label>
        </section>
        <section class="card split"><span>Llamastat {version} · {s.platform}</span></section>
      {/if}
    {/if}
  </main>
</div>

<style>
  .window { display: flex; height: 100vh; }
  nav { width: 180px; padding: 12px 8px; background: color-mix(in srgb, var(--track) 50%, var(--bg)); display: flex; flex-direction: column; gap: 2px; }
  nav button { display: flex; gap: 10px; align-items: center; text-align: left; border: none; background: none; padding: 6px 10px; border-radius: 6px; }
  nav button span { width: 16px; text-align: center; }
  nav button.active { background: var(--accent); color: white; }
  main { flex: 1; overflow-y: auto; padding: 16px 20px 24px; }
  h1 { font-size: 15px; margin: 0 0 14px; }
  h2 { font-size: 13px; margin: 0 0 10px; display: flex; align-items: center; gap: 6px; }
  h2 small { font-weight: 400; color: var(--secondary); font-size: 11px; }
  .card { background: var(--card); border: 0.5px solid var(--track); border-radius: 10px; padding: 14px; margin-bottom: 14px; }
  .columns { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
  .memory, .mini { display: flex; align-items: center; gap: 18px; margin-bottom: 10px; }
  .grow { flex: 1; min-width: 0; }
  .split { display: flex; justify-content: space-between; align-items: center; }
  .stack { height: 10px; border-radius: 5px; background: var(--track); overflow: hidden; margin: 8px 0; }
  .stack span { display: block; height: 100%; background: var(--memory); }
  .legend { display: flex; gap: 14px; font-size: 11px; }
  .legend i { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 4px; }
  .hint { font-size: 11px; color: var(--secondary); margin: 4px 0 8px; }
  .center { display: flex; justify-content: center; }
  .icons { display: flex; gap: 10px; }
  .icons button { width: 44px; height: 34px; display: grid; place-items: center; }
  .icons button.selected { border-color: var(--accent); background: color-mix(in srgb, var(--accent) 20%, var(--card)); }
  .widgets { list-style: none; margin: 0; padding: 0; }
  .widgets li { display: flex; align-items: center; gap: 10px; padding: 6px 4px; border-bottom: 0.5px solid var(--track); cursor: grab; }
  .widgets li.dragging { opacity: 0.4; }
  .grip { color: var(--tertiary); }
  .check { display: flex; align-items: center; gap: 8px; margin: 6px 0; }
  .field { display: flex; align-items: center; gap: 10px; margin: 6px 0; }
  .field input, .field select { flex: 1; }
  .status { display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: var(--track); }
  .status.on { background: var(--green); }
</style>
