<script lang="ts">
  let { title }: { title: string } = $props();
</script>

<div class="header"><span class="line"></span><span class="title">{title}</span><span class="line"></span></div>

<style>
  .header { display: flex; align-items: center; gap: 8px; margin: 12px 0 6px; }
  .line { flex: 1; height: 1px; background: var(--track); }
  .title { font-size: 10px; font-weight: 500; letter-spacing: 1px; text-transform: uppercase; color: var(--secondary); white-space: nowrap; }
</style>
