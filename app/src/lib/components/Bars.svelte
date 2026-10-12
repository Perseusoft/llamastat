<script lang="ts">
  let { values, color, height = 24 }: { values: number[]; color: string; height?: number } = $props();
</script>

<div class="bars" style="height: {height}px">
  {#each values as v}<span style="height: {Math.max(0, Math.min(v, 1)) * 100}%; background: {color}"></span>{/each}
</div>

<style>
  .bars { display: flex; align-items: flex-end; gap: 1px; padding-right: 36px; }
  span { flex: 1; min-width: 1px; border-radius: 1px; opacity: 0.85; }
</style>
