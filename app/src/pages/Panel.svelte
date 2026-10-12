<script lang="ts">
  import { api, backendLabel } from "../lib/api";
  import AreaChart from "../lib/components/AreaChart.svelte";
  import Bars from "../lib/components/Bars.svelte";
  import DetailRow from "../lib/components/DetailRow.svelte";
  import ModelDetails from "../lib/components/ModelDetails.svelte";
  import ModelList from "../lib/components/ModelList.svelte";
  import Ring from "../lib/components/Ring.svelte";
  import SectionHeader from "../lib/components/SectionHeader.svelte";
  import UsageBar from "../lib/components/UsageBar.svelte";
  import * as f from "../lib/format";
  import { t } from "../lib/i18n";
  import { store } from "../lib/store.svelte";

  const RECENT = 120;
  let root: HTMLDivElement;
  const s = $derived(store.snapshot);
  const recent = $derived(s?.history.slice(-RECENT) ?? []);
  const peak = $derived(Math.max(1, ...recent.map((x) => x.generationRate)));
  const memFraction = $derived(s ? s.memory.used / Math.max(s.memory.total, 1) : 0);
  const swapFull = $derived(s ? s.memory.swapTotal > 0 && s.memory.swapUsed / s.memory.swapTotal > 0.8 : false);
  const multiBackend = $derived(s ? new Set(s.active.map((m) => m.info.backend)).size > 1 : false);

  // Size the window to the content so nothing is left over when sections disappear.
  $effect(() => {
    const observer = new ResizeObserver(() => api.fitPanel(Math.ceil(root.getBoundingClientRect().height)));
    observer.observe(root);
    return () => observer.disconnect();
  });
</script>

<div class="panel" bind:this={root}>
  {#if s}
    <div class="header">
      <strong>Llamastat</strong>
      <span class="backends">
        {#each s.backends as b}
          <span><i class:on={b.online}></i>{backendLabel(b.kind)}</span>
        {/each}
      </span>
    </div>

    {#if store.isVisible("rings")}
      <div class="rings">
        <Ring fraction={memFraction} color={memFraction > 0.85 ? "var(--warning)" : "var(--memory)"} label={f.percent(memFraction)} caption="RAM" size={58} />
        <Ring fraction={s.generationRate / peak} color="var(--generation)" label={s.generationRate.toFixed(0)} caption="tokens/s" size={84} width={8} />
        <Ring fraction={s.gpu?.utilization ?? 0} color="var(--gpu)" label={f.percent(s.gpu?.utilization)} caption="GPU" size={58} />
      </div>
    {/if}

    {#if store.isVisible("warnings")}
      {#if multiBackend}<div class="warning">⚠︎ {t("Models are loaded in more than one backend. Watch your RAM.")}</div>{/if}
      {#if swapFull}<div class="warning">⚠︎ {t("Swap almost full ({0}). The system will slow down.", f.gigabytes(s.memory.swapUsed))}</div>{/if}
      {#if s.lastError}<div class="warning">⚠︎ {s.lastError}</div>{/if}
    {/if}

    {#if store.isVisible("history")}
      <SectionHeader title={t("History")} />
      <div class="history">
        <AreaChart samples={recent} value={(x) => x.generationRate} color="var(--generation)" />
        <Bars values={recent.map((x) => x.gpu)} color="var(--gpu)" />
        <div class="legend">
          <span><i style="background: var(--generation)"></i>tokens/s</span>
          <span><i style="background: var(--gpu)"></i>GPU</span>
          <span class="muted">{t("last {0} s", RECENT)}</span>
        </div>
      </div>
    {/if}

    {#if store.isVisible("models")}
      {#each s.active as model (model.info.id)}
        <SectionHeader title={f.shortName(model.info.name)} />
        <ModelDetails {model} />
      {/each}
    {/if}

    {#if store.isVisible("memory")}
      <SectionHeader title={t("Memory")} />
      <DetailRow label={t("In use")} value="{f.gigabytes(s.memory.used)} / {f.gigabytes(s.memory.total)}" color="var(--memory)" />
      <UsageBar fraction={memFraction} color="var(--memory)" />
      <DetailRow label={t("Swap")} value={f.gigabytes(s.memory.swapUsed)} />
      {#if s.gpu?.memoryUsed}
        <DetailRow label="GPU" value={f.gigabytes(s.gpu.memoryUsed)} color="var(--gpu)" />
      {/if}
    {/if}

    {#if store.isVisible("modelList")}
      <SectionHeader title={t("Models")} />
      <ModelList />
    {/if}

    <div class="footer">
      <button class="link" onclick={() => api.restartRouter()}>{t("Restart router")}</button>
      <button class="link" title={t("Settings")} onclick={() => api.openSettings()}>⚙︎</button>
      <button class="link" onclick={() => api.quit()}>{t("Quit")}</button>
    </div>
  {/if}
</div>

<style>
  .panel {
    width: 320px;
    padding: 14px;
    background: var(--bg);
    border-radius: 12px;
    border: 0.5px solid var(--track);
  }
  .header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px; font-size: 14px; }
  .backends { display: flex; gap: 8px; font-size: 10px; color: var(--secondary); }
  .backends i { display: inline-block; width: 6px; height: 6px; border-radius: 50%; background: var(--track); margin-right: 4px; }
  .backends i.on { background: var(--green); }
  .rings { display: flex; align-items: center; justify-content: space-between; padding: 0 6px; }
  .warning { color: var(--warning); font-size: 11px; margin-top: 8px; }
  .history { background: var(--track); background: color-mix(in srgb, var(--track) 40%, transparent); border-radius: 8px; padding: 8px; display: flex; flex-direction: column; gap: 4px; }
  .legend { display: flex; gap: 10px; font-size: 10px; color: var(--secondary); }
  .legend i { display: inline-block; width: 6px; height: 6px; border-radius: 50%; margin-right: 4px; }
  .legend .muted { margin-left: auto; color: var(--tertiary); }
  .footer { display: flex; justify-content: space-between; margin-top: 12px; font-size: 11px; }
</style>
