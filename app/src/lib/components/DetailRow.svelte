<script lang="ts">
  let { label, value, color = null }: { label: string; value: string; color?: string | null } = $props();
</script>

<div class="row">
  {#if color}<span class="dot" style="background: {color}"></span>{/if}
  <span class="label">{label}:</span>
  <span class="value num">{value}</span>
</div>

<style>
  .row { display: flex; align-items: center; gap: 6px; font-size: 12px; line-height: 20px; }
  .dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .label { flex: 1; }
  .value { font-weight: 500; }
</style>
