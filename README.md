<p align="center">
  <img src="docs/icon.png" width="112" alt="Llamastat icon">
</p>

<h1 align="center">Llamastat</h1>

<p align="center">
  <b>See what your local LLMs are doing, right from the menu bar.</b><br>
  Live tokens/s, context window, RAM, GPU and swap for <a href="https://github.com/ggml-org/llama.cpp">llama.cpp</a> and <a href="https://ollama.com">Ollama</a>,
  plus one-click load / eject. For macOS, Windows and Linux.
</p>

<p align="center">
  <a href="https://llamastat.perseusoft.tech"><b>⬇ Download</b></a> ·
  <a href="#install">Install</a> ·
  <a href="#set-up-a-backend">Set up a backend</a> ·
  <a href="#build-from-source">Build</a> ·
  <a href="README.es.md">Español</a>
</p>

<p align="center">
  <img src="docs/panel.png" width="320" alt="Llamastat panel">
  &nbsp;&nbsp;
  <img src="docs/dashboard.png" width="480" alt="Llamastat dashboard">
</p>

---

## Why

Running models locally is great until your machine starts crawling and you don't know why.
Llamastat keeps the important numbers one glance away:

- **Is it generating, and how fast?** Live tokens/s, average generation and prompt speed, tokens served.
- **How full is the context?** Used vs. size of the context window.
- **Will it fit in memory?** RAM of the model process, system RAM, swap and GPU memory, with a warning when swap is
  almost full or when two backends have models loaded at the same time (the classic "why is everything frozen").
- **Free memory without a terminal.** Load and eject models from the panel.

## Features

| | |
|---|---|
| **Tray / menu bar item** | Pick what to show and in which order: icon, tokens/s, loaded model, RAM %, GPU %, context %, RAM bar, tokens/s graph. Monochrome or colored. |
| **Panel** | Gauges for RAM, tokens/s and GPU, 2-minute history, details for each loaded model, memory, model list with **Load / Eject**. Choose which sections appear. |
| **Dashboard** | 5-minute charts for RAM, tokens/s, GPU and swap. |
| **Backends** | llama.cpp router mode (full stats) and Ollama (memory, context, keep-alive). Configurable URLs. |
| **GPU** | Apple Silicon (IOKit), NVIDIA (NVML) on Windows/Linux, AMD on Linux (sysfs). |
| **Languages** | English (default), Spanish, Portuguese, French, German, Italian, Chinese and Japanese; follows the system or pick one in Settings. |
| **Small** | Rust core + the system webview ([Tauri](https://tauri.app)). No Electron. |

## Install

Download the installer for your system from **[llamastat.perseusoft.tech](https://llamastat.perseusoft.tech)** (or the [latest GitHub release](https://github.com/Perseusoft/llamastat/releases/latest)):

| System | Architectures | File |
|---|---|---|
| **macOS** 11+ | Apple Silicon & Intel (universal) | `Llamastat_<version>_universal.dmg` |
| **Windows** 10/11 | x64 | `Llamastat_<version>_x64-setup.exe` or `.msi` |
| | ARM64 | `Llamastat_<version>_arm64-setup.exe` |
| **Linux** | x64 | `.AppImage`, `.deb` (Debian/Ubuntu), `.rpm` (Fedora/openSUSE) |
| | ARM64 | `.AppImage`, `.deb`, `.rpm` |

<details>
<summary><b>macOS</b></summary>

1. Open the `.dmg` and drag **Llamastat** to **Applications**.
2. Until releases are notarized, macOS says the app "can't be verified". Right-click the app → **Open** → **Open**,
   or run `xattr -dr com.apple.quarantine /Applications/Llamastat.app` once.
3. Llamastat lives in the menu bar (no Dock icon). Click it for the panel; ⚙︎ opens Settings.
</details>

<details>
<summary><b>Windows</b></summary>

1. Run the `-setup.exe` (or the `.msi`). If SmartScreen appears: **More info** → **Run anyway**.
2. Llamastat sits in the notification area. If you don't see it, click **^** and drag it to the taskbar.
3. Left click opens the panel, right click shows the menu. Windows tray icons are a single square, so text widgets
   (tokens/s, model…) show up in the tooltip.

Needs WebView2, which ships with Windows 10 (21H2+) and 11; the installer adds it if it's missing.
</details>

<details>
<summary><b>Linux</b></summary>

```bash
# Debian / Ubuntu
sudo apt install ./Llamastat_<version>_amd64.deb      # or _arm64.deb
# Fedora / openSUSE
sudo dnf install ./Llamastat-<version>-1.x86_64.rpm   # or .aarch64.rpm
# Any distro
chmod +x Llamastat_<version>_amd64.AppImage && ./Llamastat_<version>_amd64.AppImage
```

Needs a system tray with **AppIndicator** support. KDE, Cinnamon, XFCE and Ubuntu's GNOME work out of the box;
on vanilla GNOME install the [AppIndicator extension](https://extensions.gnome.org/extension/615/appindicator-support/).
Linux trays only do menus, so open the panel from the tray menu (**Open panel**).
</details>

## Set up a backend

Llamastat reads from servers you already run; it doesn't run models itself.

### llama.cpp (recommended, full stats)

Run `llama-server` in **router mode** (one server that loads models on demand), with `metrics = 1` in each preset:

```ini
; ~/models/presets.ini
[Qwen3-8B]
model = /home/you/models/Qwen3-8B-Q4_K_M.gguf
ctx-size = 32768
n-gpu-layers = 999
jinja = 1
metrics = 1
```

```bash
llama-server --models-preset ~/models/presets.ini --models-max 1 --host 127.0.0.1 --port 8080
```

[`examples/llama-router`](examples/llama-router) has scripts that install it as a service:

| OS | Install llama.cpp | Run the router at login |
|---|---|---|
| macOS | `brew install llama.cpp` | `examples/llama-router/macos/install.sh` (LaunchAgent) |
| Linux | [build or download](https://github.com/ggml-org/llama.cpp#quick-start) | `examples/llama-router/linux/install.sh` (systemd `--user`) |
| Windows | `winget install llama.cpp` | `examples/llama-router/windows/start-router.ps1` |

The router speaks the OpenAI API (`http://localhost:8080/v1`) and the Anthropic Messages API (`/v1/messages`),
so the same server works with most tools.

### Ollama

Nothing to configure: Llamastat finds it at `http://127.0.0.1:11434`. Ollama doesn't expose token counters,
so you get memory, context and keep-alive, but no tokens/s.

> **Tip:** don't keep big models loaded in two backends at once. On 16–32 GB machines that's how you end up deep in
> swap; Llamastat warns you when it happens.

## Requirements

| | macOS | Windows | Linux |
|---|---|---|---|
| OS | 11 Big Sur or later | 10 (1803+) / 11 | glibc 2.35+ (Ubuntu 22.04, Debian 12, Fedora 36…) |
| Runtime | — | WebView2 | WebKitGTK 4.1, AppIndicator |
| GPU stats | Apple Silicon | NVIDIA (driver) | NVIDIA (driver), AMD (amdgpu) |

## Build from source

You need [Rust](https://rustup.rs) (stable), [Node.js](https://nodejs.org) 20+ and the
[Tauri prerequisites](https://tauri.app/start/prerequisites/) for your OS.

```bash
git clone https://github.com/Perseusoft/llamastat.git
cd llamastat/app
npm install
npm run tauri dev      # run with hot reload
npm run tauri build    # installers in src-tauri/target/release/bundle/
```

While developing:

- `npm run dev`, then open http://localhost:1420/#panel (or `#settings`) to work on the UI in a browser with recorded
  data (`?lang=es` for Spanish).
- `src-tauri/target/debug/llamastat --print-snapshot` prints what the backends report, as JSON.

### Project layout

```
app/
  src/                 Svelte UI: pages/Panel.svelte, pages/Settings.svelte, lib/components
  src-tauri/src/
    backends.rs        llama.cpp router + Ollama clients
    monitor.rs         polling, rates, history
    system.rs          memory, processes, GPU (IOKit / NVML / sysfs)
    tray.rs            tray image (tiny-skia) and title
    settings.rs        settings.json
    lib.rs             windows, tray, commands
examples/llama-router  router presets + service scripts per OS
.github/workflows      CI and release builds
```

GitHub Actions builds releases for macOS (universal), Windows x64/ARM64 and Linux x64/ARM64; see
[docs/RELEASE.md](docs/RELEASE.md).

## Roadmap

- GPU stats for Intel/AMD on Windows
- Time to first token and per-request history
- More backends (LM Studio, vLLM, MLX)
- Signed and notarized builds, auto-update

## Contributing

Issues and PRs are welcome. Please run `npm run check` (in `app/`) and `cargo test` (in `app/src-tauri/`) first.

---

<p align="center">Made by <a href="https://github.com/Perseusoft">Perseusoft</a></p>
