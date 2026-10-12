<script lang="ts">
  let { fraction, color }: { fraction: number; color: string } = $props();
</script>

<div class="bar"><span style="width: {Math.max(0, Math.min(fraction, 1)) * 100}%; background: {color}"></span></div>

<style>
  .bar { height: 5px; border-radius: 3px; background: var(--track); overflow: hidden; margin: 2px 0 4px; }
  span { display: block; height: 100%; border-radius: 3px; transition: width 0.4s ease-out; }
</style>
