<script lang="ts">
  import { api, backendLabel } from "../api";
  import * as f from "../format";
  import { t } from "../i18n";
  import { store } from "../store.svelte";

  const models = $derived(store.snapshot?.backends.flatMap((b) => b.models) ?? []);
  const anyOnline = $derived(store.snapshot?.backends.some((b) => b.online) ?? false);
</script>

{#if models.length === 0}
  <div class="empty">{anyOnline ? t("No models") : t("No backend is responding")}</div>
{/if}
{#each models as model (model.id)}
  {@const busy = store.snapshot?.pending.includes(model.id) || model.state === "loading"}
  <div class="model">
    <span class="dot {model.state}"></span>
    <div class="name">
      <div>{model.name}</div>
      <div class="meta">{backendLabel(model.backend)} · {f.bytes(model.sizeBytes)}</div>
    </div>
    {#if busy}
      <span class="spinner"></span>
    {:else}
      <button onclick={() => api.toggleModel(model)}
        title={model.state === "unloaded" ? t("Load the model into memory") : t("Free the memory used by the model")}>
        {model.state === "unloaded" ? `▶ ${t("Load")}` : `⏏ ${t("Eject")}`}
      </button>
    {/if}
  </div>
{/each}

<style>
  .model { display: flex; align-items: center; gap: 6px; margin: 4px 0; }
  .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--track); flex-shrink: 0; }
  .dot.loaded { background: var(--green); }
  .dot.loading { background: #ffd60a; }
  .name { flex: 1; min-width: 0; font-size: 12px; }
  .name div:first-child { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .meta { font-size: 10px; color: var(--secondary); }
  button { font-size: 11px; padding: 2px 8px; white-space: nowrap; }
  .empty { font-size: 11px; color: var(--secondary); }
  .spinner { width: 14px; height: 14px; border: 2px solid var(--track); border-top-color: var(--secondary); border-radius: 50%; animation: spin 0.8s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
