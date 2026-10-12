<script lang="ts">
  import type { Sample } from "../api";

  let { samples, value, color, max, height = 64, axis = false, unit = "" }: {
    samples: Sample[]; value: (s: Sample) => number; color: string; max?: number; height?: number; axis?: boolean; unit?: string;
  } = $props();

  const W = 1000; // viewBox width; the SVG stretches to its container
  const values = $derived(samples.map(value));
  const peak = $derived(max ?? Math.max(10, ...values) * 1.1);
  const points = $derived(values.map((v, i) => [values.length > 1 ? (i / (values.length - 1)) * W : 0, height - (v / peak) * height] as const));
  const line = $derived(points.map(([x, y], i) => `${i ? "L" : "M"}${x.toFixed(1)},${y.toFixed(1)}`).join(""));
  const area = $derived(points.length ? `${line}L${W},${height}L0,${height}Z` : "");
  const ticks = $derived([0, 0.5, 1].map((f) => ({ y: height - f * height, label: Math.round(peak * f) })));
  const times = $derived(axis && samples.length > 1
    ? [0, 0.5, 1].map((f) => new Date(samples[Math.round(f * (samples.length - 1))].time).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" }))
    : []);
  const id = `g${Math.random().toString(36).slice(2)}`;
</script>

<div class="chart" class:axis>
  <svg viewBox="0 0 {W} {height}" preserveAspectRatio="none" style="height: {height}px">
    <defs>
      <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color={color} stop-opacity="0.45" />
        <stop offset="1" stop-color={color} stop-opacity="0.08" />
      </linearGradient>
    </defs>
    {#each ticks as tick}
      <line x1="0" x2={W} y1={tick.y} y2={tick.y} stroke="var(--track)" stroke-width="1" vector-effect="non-scaling-stroke" />
    {/each}
    <path d={area} fill="url(#{id})" />
    <path d={line} fill="none" stroke={color} stroke-width="1.5" vector-effect="non-scaling-stroke" />
  </svg>
  <div class="yaxis num">
    {#each ticks as tick}<span style="top: {tick.y}px">{tick.label}{unit}</span>{/each}
  </div>
  {#if axis}
    <div class="xaxis num">{#each times as time}<span>{time}</span>{/each}</div>
  {/if}
</div>

<style>
  .chart { position: relative; padding-right: 36px; }
  svg { width: 100%; display: block; overflow: visible; }
  .yaxis { position: absolute; right: 0; top: 0; width: 32px; height: 100%; font-size: 9px; color: var(--secondary); }
  .axis .yaxis { height: calc(100% - 16px); }
  .yaxis span { position: absolute; transform: translateY(-50%); }
  .xaxis { display: flex; justify-content: space-between; font-size: 9px; color: var(--secondary); margin-top: 4px; }
</style>
