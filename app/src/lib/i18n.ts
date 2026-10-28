import { store } from "./store.svelte";
import de from "./locales/de.json";
import es from "./locales/es.json";
import fr from "./locales/fr.json";
import it from "./locales/it.json";
import ja from "./locales/ja.json";
import pt from "./locales/pt.json";
import zh from "./locales/zh.json";

/// English is the source language: keys are the English text, `{0}` placeholders are filled from args.
/// Each locale lives in `locales/<code>.json` with the same keys (`npm run check:i18n` enforces it).
/// To add a language: create the JSON file, register it below, and add the tray menu strings in
/// `src-tauri/src/lib.rs` (`tr`).
const dictionaries: Record<string, Record<string, string>> = { de, es, fr, it, ja, pt, zh };

export const languages: { code: string | null; name: string }[] = [
  { code: null, name: "System" },
  { code: "en", name: "English" },
  { code: "es", name: "Español" },
  { code: "pt", name: "Português" },
  { code: "fr", name: "Français" },
  { code: "de", name: "Deutsch" },
  { code: "it", name: "Italiano" },
  { code: "zh", name: "中文" },
  { code: "ja", name: "日本語" },
];

/// Two-letter code of the active language; falls back to English for anything without a dictionary.
export function currentLanguage(): string {
  const code = (store.settings?.language ?? navigator.language ?? "en").slice(0, 2).toLowerCase();
  return code === "en" || code in dictionaries ? code : "en";
}

export function t(key: string, ...args: (string | number)[]): string {
  const text = dictionaries[currentLanguage()]?.[key] ?? key;
  return args.reduce<string>((s, arg, i) => s.replace(`{${i}}`, String(arg)), text);
}
