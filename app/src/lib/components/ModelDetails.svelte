<script lang="ts">
  import { backendLabel, type ActiveModel } from "../api";
  import * as f from "../format";
  import { t } from "../i18n";
  import DetailRow from "./DetailRow.svelte";
  import UsageBar from "./UsageBar.svelte";

  let { model }: { model: ActiveModel } = $props();
  const stats = $derived(model.info.stats);
</script>

<DetailRow label={t("Status")} value={model.busy ? t("generating") : t("idle")} color={model.busy ? "var(--green)" : "var(--track)"} />
<DetailRow label="Backend" value={backendLabel(model.info.backend)} />
{#if stats?.contextSize}
  <DetailRow label={t("Context")} value="{f.count(stats.contextUsed ?? 0)} / {f.context(stats.contextSize)}" color="var(--prompt)" />
  <UsageBar fraction={(stats.contextUsed ?? 0) / stats.contextSize} color="var(--prompt)" />
{/if}
{#if stats && stats.slotsTotal > 0}
  <DetailRow label={t("Busy slots")} value="{stats.slotsBusy} / {stats.slotsTotal}" />
{/if}
{#if stats && model.info.backend === "llamaCpp"}
  <DetailRow label={t("Generation (avg)")} value={f.rate(stats.predictedTokensPerSecond)} color="var(--generation)" />
  <DetailRow label={t("Prompt (avg)")} value={f.rate(stats.promptTokensPerSecond)} color="var(--prompt)" />
  <DetailRow label={t("Generated tokens")} value={f.count(stats.predictedTokensTotal + stats.inFlightTokens)} />
  <DetailRow label={t("Prompt tokens")} value={f.count(stats.promptTokensTotal)} />
{/if}
{#if stats?.vramBytes}
  <DetailRow label="VRAM" value={f.bytes(stats.vramBytes)} color="var(--gpu)" />
{/if}
{#if model.processRam}
  <DetailRow label={t("Process RAM")} value={f.gigabytes(model.processRam)} color="var(--memory)" />
{/if}
{#if model.cpu != null}
  <DetailRow label="CPU" value={f.percent(model.cpu)} />
{/if}
{#if stats?.expiresAt}
  <DetailRow label={t("Unloads")} value={new Date(stats.expiresAt * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })} />
{/if}
