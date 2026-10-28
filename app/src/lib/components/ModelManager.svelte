<script lang="ts">
  import { api, backendLabel, type BackendKind, type HfFile, type HfRepo, type ModelInfo, type RouterPaths } from "../api";
  import * as f from "../format";
  import { t } from "../i18n";
  import { store } from "../store.svelte";

  const s = $derived(store.snapshot);
  const models = $derived(s?.backends.flatMap((b) => b.models) ?? []);
  const jobs = $derived(Object.values(store.installs));
  const canRestart = $derived(s?.platform !== "windows");
  /// A llama.cpp install or removal changed presets.ini; the router only re-reads it on restart.
  const needsRestart = $derived(jobs.some((j) => j.backend === "llamaCpp" && (j.status === "done" || j.status === "removed")));

  let confirming = $state<string | null>(null);
  let backend = $state<BackendKind>("llamaCpp");
  let paths = $state<RouterPaths | null>(null);
  api.routerPaths().then((p) => (paths = p)).catch(() => {});

  // Hugging Face flow: search → repo → file → name.
  let query = $state("");
  let searching = $state(false);
  let results = $state<HfRepo[] | null>(null);
  let repo = $state<HfRepo | null>(null);
  let files = $state<HfFile[] | null>(null);
  let file = $state<HfFile | null>(null);
  let presetName = $state("");
  let error = $state("");

  // Ollama flow: just a name.
  let ollamaName = $state("");

  async function search() {
    if (!query.trim()) return;
    searching = true; error = ""; repo = null; files = null; file = null;
    try { results = await api.searchModels(query); } catch (e) { error = String(e); results = []; } finally { searching = false; }
  }

  async function pick(r: HfRepo) {
    repo = r; files = null; file = null; error = "";
    try { files = await api.modelFiles(r.id); } catch (e) { error = String(e); files = []; }
  }

  function choose(x: HfFile) {
    file = x;
    presetName = x.path.split("/").pop()!.replace(/\.gguf$/i, "");
  }

  async function download() {
    if (!repo || !file) return;
    await api.installModel({ kind: "huggingFace", repo: repo.id, file: file.path, name: presetName.trim() || null });
    file = null;
  }

  async function pull() {
    const model = ollamaName.trim();
    if (!model) return;
    await api.installModel({ kind: "ollama", model });
    ollamaName = "";
  }

  async function remove(model: ModelInfo) {
    confirming = null;
    try { await api.removeModel(model); } catch { /* the error arrives as an install event */ }
  }

  const statusLabel = (status: string) =>
    ({ downloading: t("Downloading"), pulling: t("Pulling"), removing: t("Removing"), done: t("Installed"), removed: t("Removed"), cancelled: t("Cancelled"), error: t("Error") })[status] ?? status;
</script>

{#if jobs.length}
  <section class="card">
    {#each jobs as job (job.id)}
      <div class="job">
        <div class="split">
          <span><b>{job.name}</b> <small>{backendLabel(job.backend)} · {statusLabel(job.status)}{job.total && !job.done ? ` · ${f.bytes(job.completed)} / ${f.bytes(job.total)}` : ""}</small></span>
          {#if job.done}
            <button class="link" onclick={() => store.dismissInstall(job.id)}>✕</button>
          {:else if job.status !== "removing"}
            <button onclick={() => api.cancelInstall(job.id)}>{t("Cancel")}</button>
          {/if}
        </div>
        {#if !job.done}
          <div class="bar" class:indeterminate={!job.total}><span style="width: {job.total ? (job.completed / job.total) * 100 : 30}%"></span></div>
        {/if}
        {#if job.error}<p class="error">{job.error}</p>{/if}
      </div>
    {/each}
    {#if needsRestart}
      <div class="restart">
        <span>{t("The router only reads presets.ini when it starts. Restart it to apply the change.")}</span>
        {#if canRestart}<button onclick={() => api.restartRouter()}>{t("Restart router")}</button>{/if}
      </div>
    {/if}
  </section>
{/if}

<section class="card">
  <h2>{t("Installed")}</h2>
  {#if models.length === 0}
    <p class="hint">{s?.backends.some((b) => b.online) ? t("No models") : t("No backend is responding")}</p>
  {/if}
  {#each models as model (model.id)}
    {@const busy = store.installs[model.id] && !store.installs[model.id].done}
    <div class="row">
      <span class="dot {model.state}"></span>
      <div class="grow">
        <div class="name" title={model.path ?? ""}>{model.name}</div>
        <small>{backendLabel(model.backend)} · {f.bytes(model.sizeBytes)}{model.path ? ` · ${model.path}` : ""}</small>
      </div>
      {#if confirming === model.id}
        <span class="confirm">
          {model.backend === "llamaCpp" ? t("Remove {0}? The file is deleted from disk.", model.name) : t("Remove {0}?", model.name)}
          <button class="danger" onclick={() => remove(model)}>{t("Yes, remove")}</button>
          <button onclick={() => (confirming = null)}>{t("Cancel")}</button>
        </span>
      {:else}
        <button disabled={busy} onclick={() => (confirming = model.id)}>{t("Remove")}</button>
      {/if}
    </div>
  {/each}
</section>

<section class="card">
  <h2>{t("Install a model")}</h2>
  <div class="tabs">
    <button class:selected={backend === "llamaCpp"} onclick={() => (backend = "llamaCpp")}>llama.cpp</button>
    <button class:selected={backend === "ollama"} onclick={() => (backend = "ollama")}>Ollama</button>
  </div>
  <p class="hint">{t("Ollama pulls from its library; llama.cpp downloads a GGUF from Hugging Face into your models folder.")}</p>

  {#if backend === "llamaCpp"}
    <form class="field" onsubmit={(e) => { e.preventDefault(); search(); }}>
      <input type="text" placeholder={t("Search Hugging Face (GGUF)")} bind:value={query} />
      <button type="submit" disabled={searching || !query.trim()}>{t("Search")}</button>
    </form>
    {#if paths?.modelsDir}<p class="hint">{t("Models folder: {0}", paths.modelsDir)}</p>{/if}
    {#if !paths?.presets}<p class="error">{t("Can't find the router's presets.ini. Set it in Settings → Backends.")}</p>{/if}

    {#if results}
      <div class="columns">
        <ul class="list">
          {#if results.length === 0}<li class="hint">{t("No results")}</li>{/if}
          {#each results as r (r.id)}
            <li><button class="item" class:selected={repo?.id === r.id} onclick={() => pick(r)}>
              <span class="name">{r.id}</span><small>{t("{0} downloads", f.count(r.downloads))}</small>
            </button></li>
          {/each}
        </ul>
        <ul class="list">
          {#if repo && !files}<li class="hint">…</li>{/if}
          {#if files?.length === 0}<li class="hint">{t("No results")}</li>{/if}
          {#each files ?? [] as x (x.path)}
            <li><button class="item" class:selected={file?.path === x.path} onclick={() => choose(x)}>
              <span class="name">{x.path}</span><small>{f.bytes(x.size)}</small>
            </button></li>
          {/each}
        </ul>
      </div>
    {/if}

    {#if file}
      <form class="field" onsubmit={(e) => { e.preventDefault(); download(); }}>
        <label>{t("Preset name")}</label>
        <input type="text" bind:value={presetName} />
        <button type="submit" class="primary" disabled={!presetName.trim() || !paths?.presets}>{t("Download")} · {f.bytes(file.size)}</button>
      </form>
    {/if}
  {:else}
    <form class="field" onsubmit={(e) => { e.preventDefault(); pull(); }}>
      <input type="text" placeholder={t("Model name (e.g. llama3.2:3b)")} bind:value={ollamaName} />
      <button type="submit" class="primary" disabled={!ollamaName.trim()}>{t("Pull")}</button>
    </form>
  {/if}
  {#if error}<p class="error">{error}</p>{/if}
</section>

<style>
  .card { background: var(--card); border: 0.5px solid var(--track); border-radius: 10px; padding: 14px; margin-bottom: 14px; }
  h2 { font-size: 13px; margin: 0 0 10px; }
  small { color: var(--secondary); font-size: 11px; }
  .hint { font-size: 11px; color: var(--secondary); margin: 4px 0 8px; }
  .error { font-size: 11px; color: var(--warning); margin: 6px 0 0; }
  .split { display: flex; justify-content: space-between; align-items: center; gap: 10px; }
  .grow { flex: 1; min-width: 0; }
  .row { display: flex; align-items: center; gap: 10px; padding: 7px 0; border-bottom: 0.5px solid var(--track); }
  .row:last-child { border-bottom: none; }
  .row .name, .row small { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; display: block; }
  .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--track); flex-shrink: 0; }
  .dot.loaded { background: var(--green); }
  .dot.loading { background: #ffd60a; }
  .confirm { display: flex; align-items: center; gap: 8px; font-size: 11px; color: var(--warning); }
  .danger { border-color: var(--warning); color: var(--warning); }
  .primary { background: var(--accent); color: white; border-color: var(--accent); }
  .job { padding: 6px 0; }
  .job + .job { border-top: 0.5px solid var(--track); }
  .bar { height: 6px; border-radius: 3px; background: var(--track); overflow: hidden; margin-top: 6px; }
  .bar span { display: block; height: 100%; background: var(--accent); transition: width 0.25s; }
  .bar.indeterminate span { animation: slide 1.2s ease-in-out infinite; }
  @keyframes slide { 0% { margin-left: 0; } 50% { margin-left: 70%; } 100% { margin-left: 0; } }
  .restart { display: flex; justify-content: space-between; align-items: center; gap: 10px; margin-top: 10px; padding-top: 10px; border-top: 0.5px solid var(--track); font-size: 12px; }
  .tabs { display: flex; gap: 6px; margin-bottom: 6px; }
  .tabs button.selected { border-color: var(--accent); background: color-mix(in srgb, var(--accent) 20%, var(--card)); }
  .field { display: flex; align-items: center; gap: 10px; margin: 8px 0; }
  .field input { flex: 1; }
  .columns { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 8px; }
  .list { list-style: none; margin: 0; padding: 0; max-height: 220px; overflow-y: auto; border: 0.5px solid var(--track); border-radius: 8px; }
  .list li.hint { padding: 8px 10px; }
  .item { width: 100%; text-align: left; border: none; border-radius: 0; background: none; padding: 6px 10px; display: flex; flex-direction: column; gap: 1px; }
  .item .name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .item:hover { background: color-mix(in srgb, var(--track) 50%, transparent); filter: none; }
  .item.selected { background: color-mix(in srgb, var(--accent) 18%, var(--card)); }
</style>
