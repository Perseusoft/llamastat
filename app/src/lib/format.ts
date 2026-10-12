const GB = 1024 ** 3;

export const gigabytes = (bytes: number | null | undefined) => (bytes == null ? "—" : `${(bytes / GB).toFixed(1)} GB`);

export const bytes = (value: number | null | undefined) => {
  if (value == null) return "—";
  if (value >= GB) return `${(value / GB).toFixed(2)} GB`;
  return `${(value / 1024 ** 2).toFixed(0)} MB`;
};

export const rate = (value: number | null | undefined) =>
  value == null || value <= 0 ? "—" : value >= 100 ? `${value.toFixed(0)} t/s` : `${value.toFixed(1)} t/s`;

export const percent = (fraction: number | null | undefined) => (fraction == null ? "—" : `${Math.round(fraction * 100)}%`);

export const count = (value: number) =>
  value >= 1e6 ? `${(value / 1e6).toFixed(1)}M` : value >= 1e4 ? `${(value / 1e3).toFixed(0)}k` : value >= 1e3 ? `${(value / 1e3).toFixed(1)}k` : `${Math.round(value)}`;

/// Context sizes are powers of two: 32768 reads as "32k", not "33k".
export const context = (tokens: number) => (tokens >= 1024 && tokens % 1024 === 0 ? `${tokens / 1024}k` : count(tokens));

export const shortName = (name: string) => name.split(":")[0];
