<script lang="ts">
  let { fraction, color, label, caption = "", size = 64, width = 6 }: {
    fraction: number; color: string; label: string; caption?: string; size?: number; width?: number;
  } = $props();
  const r = $derived((size - width) / 2);
  const circumference = $derived(2 * Math.PI * r);
  const dash = $derived(circumference * Math.min(Math.max(fraction, 0.002), 1));
</script>

<div class="ring">
  <svg width={size} height={size} viewBox="0 0 {size} {size}">
    <circle cx={size / 2} cy={size / 2} {r} fill="none" stroke="var(--track)" stroke-width={width} />
    <circle cx={size / 2} cy={size / 2} {r} fill="none" stroke={color} stroke-width={width} stroke-linecap="round"
      stroke-dasharray="{dash} {circumference}" transform="rotate(-90 {size / 2} {size / 2})" class="arc" />
    <text x="50%" y="50%" dominant-baseline="central" text-anchor="middle" class="num" font-size={size * 0.2}>{label}</text>
  </svg>
  {#if caption}<div class="caption">{caption}</div>{/if}
</div>

<style>
  .ring { display: flex; flex-direction: column; align-items: center; gap: 2px; }
  .arc { transition: stroke-dasharray 0.4s ease-out; }
  text { fill: var(--text); font-weight: 500; }
  .caption { font-size: 10px; color: var(--secondary); }
</style>
