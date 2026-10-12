<script lang="ts">
  import type { Widget } from "../api";
  import { ICONS } from "../icons";
  import * as f from "../format";
  import { store } from "../store.svelte";


  const GRAPHIC = new Set<Widget>(["icon", "ramBar", "sparkline"]);
  const s = $derived(store.snapshot);
  const settings = $derived(store.settings);
  const windows = $derived(s?.platform === "windows");

  function shown(w: Widget) {
    if (!s || !settings) return false;
    const tokensOn = settings.widgets.some((x) => x.widget === "tokensPerSecond" && x.enabled);
    if (w === "tokensPerSecond") return !settings.tokensOnlyWhileGenerating || s.generating;
    if (w === "model") return s.active.length > 0 && !(settings.tokensOnlyWhileGenerating && s.generating && tokensOn);
    if (w === "context") return s.contextFraction != null;
    return true;
  }
  const widgets = $derived(settings?.widgets.filter((w) => w.enabled && shown(w.widget)).map((w) => w.widget) ?? []);
  // The tray draws graphics first, then the title text.
  const graphics = $derived(widgets.filter((w) => GRAPHIC.has(w)));
  const texts = $derived(widgets.filter((w) => !graphics.includes(w)));
  const spark = $derived((s?.history.slice(-30) ?? []).map((x) => x.generationRate));
  const sparkPeak = $derived(Math.max(1, ...spark));
  const color = (c: string) => (settings?.colored ? c : "currentColor");

  function text(w: Widget) {
    if (!s) return "";
    switch (w) {
      case "tokensPerSecond": return `${s.generationRate.toFixed(1)} t/s`;
      case "model": return s.active.map((m) => f.shortName(m.info.name)).join(" + ");
      case "ram": return `RAM ${f.percent(s.memory.used / s.memory.total)}`;
      case "gpu": return s.gpu ? `GPU ${f.percent(s.gpu.utilization)}` : "";
      case "context": return `ctx ${f.percent(s.contextFraction)}`;
      default: return "";
    }
  }
</script>

<div class="tray">
  {#each windows ? graphics.slice(0, 1) : graphics as w}
    {#if w === "icon" && settings}
      <svg viewBox="0 0 100 100" width="18" height="18"><path d={ICONS[settings.icon]} fill="currentColor" fill-rule="evenodd" /></svg>
    {:else if w === "ramBar" && s}
      <svg viewBox="0 0 8 18" width="8" height="18">
        <rect x="0.5" y="0.5" width="7" height="17" rx="1.5" fill="none" stroke={color("var(--memory)")} opacity="0.7" />
        <rect x="2" y={16 - 14 * (s.memory.used / s.memory.total)} width="4" height={14 * (s.memory.used / s.memory.total)} fill={color("var(--memory)")} />
      </svg>
    {:else if w === "sparkline"}
      <svg viewBox="0 0 32 16" width="34" height="16" preserveAspectRatio="none">
        <rect x="0.25" y="0.25" width="31.5" height="15.5" fill="none" stroke={color("var(--generation)")} stroke-width="0.5" opacity="0.6" />
        <path d={`M0,16 ${spark.map((v, i) => `L${(i / Math.max(spark.length - 1, 1)) * 32},${16 - 15 * (v / sparkPeak)}`).join(" ")} L32,16Z`}
          fill={color("var(--generation)")} fill-opacity="0.45" stroke={color("var(--generation)")} stroke-width="0.8" />
      </svg>
    {/if}
  {/each}
  {#if !windows}
    {#each texts as w}<span class="num">{text(w)}</span>{/each}
  {/if}
</div>

<style>
  .tray { display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; border-radius: 5px; background: var(--track); font-weight: 500; font-size: 12px; min-height: 26px; }
</style>
