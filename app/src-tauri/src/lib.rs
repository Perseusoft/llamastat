mod backends;
mod installer;
mod model;
mod monitor;
mod presets;
mod settings;
mod system;
pub mod tray;

use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, LogicalSize, Manager, State, WebviewUrl, WebviewWindow, WebviewWindowBuilder, WindowEvent};
use tauri_plugin_positioner::{Position, WindowExt};

use installer::{HfFile, HfRepo, InstallProgress, InstallSource, Installer, RouterPaths, RouterTarget};
use model::{BackendKind, ModelState, Snapshot};
use monitor::Monitor;
use settings::Settings;

const PANEL: &str = "panel";
const SETTINGS: &str = "settings";
const PANEL_WIDTH: f64 = 320.0;

struct AppState {
    monitor: Monitor,
    installer: Installer,
    settings: Mutex<Settings>,
    settings_path: PathBuf,
    tray: Mutex<Option<TrayIcon>>,
}

impl AppState {
    /// Settings override first, then the running router's `--models-preset`, then `~/models/presets.ini`.
    fn router_target(&self, app: &AppHandle) -> RouterTarget {
        let settings = self.settings.lock().unwrap().clone();
        let presets = settings.llama_cpp_presets.as_deref().map(str::trim).filter(|p| !p.is_empty()).map(PathBuf::from)
            .or_else(|| self.monitor.router_presets().map(PathBuf::from))
            .or_else(|| {
                let default = app.path().home_dir().ok()?.join("models").join("presets.ini");
                default.is_file().then_some(default)
            });
        let models_dir = presets.as_ref()
            .and_then(|p| std::fs::read_to_string(p).ok())
            .and_then(|text| presets::models_dir(&text));
        RouterTarget {
            llama_cpp_url: settings.llama_cpp_url.trim().trim_end_matches('/').to_string(),
            ollama_url: settings.ollama_url.trim().trim_end_matches('/').to_string(),
            presets,
            models_dir,
        }
    }
}

type Shared<'a> = State<'a, Arc<AppState>>;

// MARK: commands

#[tauri::command]
fn get_snapshot(state: Shared) -> Snapshot {
    state.monitor.snapshot()
}

#[tauri::command]
fn get_settings(state: Shared) -> Settings {
    state.settings.lock().unwrap().clone()
}

#[tauri::command]
fn set_settings(app: AppHandle, state: Shared, settings: Settings) -> Result<(), String> {
    settings.save(&state.settings_path)?;
    *state.settings.lock().unwrap() = settings.clone();
    update_tray(&state, &state.monitor.snapshot());
    rebuild_menu(&app, &state);
    apply_theme(&app, &settings);
    app.emit("settings", &settings).map_err(|e| e.to_string())
}

#[tauri::command]
async fn toggle_model(app: AppHandle, state: Shared<'_>, backend: BackendKind, name: String, load: bool) -> Result<(), String> {
    let settings = state.settings.lock().unwrap().clone();
    let state = Arc::clone(&state);
    // Show the spinner right away, then refresh once the backend answers.
    let snapshot = state.monitor.tick_pending_preview(&settings, backend, &name);
    let _ = app.emit("snapshot", &snapshot);
    state.monitor.toggle(&settings, backend, &name, load).await;
    let snapshot = state.monitor.tick(&settings).await;
    let _ = app.emit("snapshot", &snapshot);
    Ok(())
}

#[tauri::command]
fn restart_router(state: Shared) -> Result<(), String> {
    let service = state.settings.lock().unwrap().router_service.clone();
    let status = if cfg!(target_os = "macos") {
        std::process::Command::new("/bin/sh")
            .args(["-c", "launchctl kickstart -k \"gui/$(id -u)/$0\"", &service])
            .status()
    } else if cfg!(target_os = "linux") {
        std::process::Command::new("systemctl").args(["--user", "restart", &service]).status()
    } else {
        return Err("Restarting the router isn't supported on this OS yet".into());
    };
    match status {
        Ok(s) if s.success() => Ok(()),
        Ok(s) => Err(format!("{service}: exit {s}")),
        Err(e) => Err(e.to_string()),
    }
}

#[tauri::command]
fn open_settings(app: AppHandle, page: Option<String>) {
    show_settings(&app, page.as_deref());
}

// MARK: model management

#[tauri::command]
async fn search_models(state: Shared<'_>, query: String) -> Result<Vec<HfRepo>, String> {
    state.installer.search(query.trim()).await
}

#[tauri::command]
async fn model_files(state: Shared<'_>, repo: String) -> Result<Vec<HfFile>, String> {
    state.installer.files(repo.trim()).await
}

/// Starts an install in the background; progress arrives as `install` events.
#[tauri::command]
fn install_model(app: AppHandle, state: Shared, source: InstallSource) {
    let router = state.router_target(&app);
    let state = Arc::clone(&state);
    tauri::async_runtime::spawn(async move {
        let handle = app.clone();
        state.installer.install(source, router, move |p: InstallProgress| { let _ = handle.emit("install", &p); }).await;
        let settings = state.settings.lock().unwrap().clone();
        let snapshot = state.monitor.tick(&settings).await;
        let _ = app.emit("snapshot", &snapshot);
    });
}

#[tauri::command]
fn cancel_install(state: Shared, id: String) {
    state.installer.cancel(&id);
}

#[tauri::command]
async fn remove_model(app: AppHandle, state: Shared<'_>, backend: BackendKind, name: String) -> Result<(), String> {
    let router = state.router_target(&app);
    let id = format!("{}/{}", backend.label(), name);
    let progress = |status: &str, error: Option<String>| InstallProgress {
        id: id.clone(), backend, name: name.clone(), status: status.into(), completed: 0, total: None, done: status != "removing", error,
    };
    let _ = app.emit("install", progress("removing", None));
    let (path, loaded) = state.monitor.snapshot().backends.iter()
        .flat_map(|b| b.models.iter())
        .find(|m| m.backend == backend && m.name == name)
        .map(|m| (m.path.clone(), m.state != ModelState::Unloaded))
        .unwrap_or((None, false));
    let result = state.installer.remove(backend, &name, path.as_deref(), loaded, &router).await;
    let _ = app.emit("install", match &result {
        Ok(()) => progress("removed", None),
        Err(e) => progress("error", Some(e.clone())),
    });
    let settings = state.settings.lock().unwrap().clone();
    let snapshot = state.monitor.tick(&settings).await;
    let _ = app.emit("snapshot", &snapshot);
    result
}

#[tauri::command]
fn router_paths(app: AppHandle, state: Shared) -> RouterPaths {
    let target = state.router_target(&app);
    RouterPaths {
        presets: target.presets.map(|p| p.to_string_lossy().into_owned()),
        models_dir: target.models_dir.map(|p| p.to_string_lossy().into_owned()),
    }
}

/// The panel measures its content and asks for exactly that height (no leftover space).
#[tauri::command]
fn fit_panel(window: WebviewWindow, height: f64) -> Result<(), String> {
    window.set_size(LogicalSize::new(PANEL_WIDTH, height.clamp(120.0, 1400.0))).map_err(|e| e.to_string())?;
    if window.is_visible().unwrap_or(false) {
        position_panel(&window);
    }
    Ok(())
}

#[tauri::command]
fn quit(app: AppHandle) {
    app.exit(0);
}

// MARK: windows

/// The web UI switches its own colors from the settings; this keeps the native parts in step.
fn apply_theme(app: &AppHandle, settings: &Settings) {
    for name in [PANEL, SETTINGS] {
        if let Some(window) = app.get_webview_window(name) {
            let _ = window.set_theme(settings.theme.native());
        }
    }
}

fn position_panel(window: &WebviewWindow) {
    // Linux trays don't report their position, and Windows' taskbar is usually at the bottom.
    let position = if cfg!(target_os = "macos") {
        Position::TrayBottomCenter
    } else if cfg!(target_os = "windows") {
        Position::TrayCenter
    } else {
        Position::TopRight
    };
    if window.move_window_constrained(position).is_err() {
        let _ = window.move_window(Position::TopRight);
    }
}

fn toggle_panel(app: &AppHandle) {
    let Some(window) = app.get_webview_window(PANEL) else { return };
    if window.is_visible().unwrap_or(false) {
        let _ = window.hide();
    } else {
        position_panel(&window);
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn create_panel(app: &AppHandle, theme: Option<tauri::Theme>) -> tauri::Result<()> {
    let window = WebviewWindowBuilder::new(app, PANEL, WebviewUrl::App("index.html#panel".into()))
        .title("Llamastat")
        .theme(theme)
        .inner_size(PANEL_WIDTH, 560.0)
        .decorations(false)
        .transparent(true)
        .resizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .shadow(true)
        .visible(false)
        .build()?;
    let handle = window.clone();
    window.on_window_event(move |event| {
        if let WindowEvent::Focused(false) = event {
            let _ = handle.hide();
        }
    });
    Ok(())
}

/// `page` is a Settings tab ("models", "backends"…): a new window opens on it, an existing one switches.
fn show_settings(app: &AppHandle, page: Option<&str>) {
    let theme = app.try_state::<Arc<AppState>>().map(|s| s.settings.lock().unwrap().theme.native()).unwrap_or(None);
    if let Some(panel) = app.get_webview_window(PANEL) {
        let _ = panel.hide();
    }
    if let Some(window) = app.get_webview_window(SETTINGS) {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
        if let Some(page) = page {
            let _ = app.emit("open-page", page);
        }
        return;
    }
    let url = match page {
        Some(page) if page.chars().all(|c| c.is_ascii_alphanumeric()) => format!("index.html#settings/{page}"),
        _ => "index.html#settings".to_string(),
    };
    let _ = WebviewWindowBuilder::new(app, SETTINGS, WebviewUrl::App(url.into()))
        .title("Llamastat")
        .theme(theme)
        .inner_size(860.0, 620.0)
        .min_inner_size(720.0, 480.0)
        .center()
        .focused(true)
        .build();
}

// MARK: tray

/// Tray menu labels. English is the fallback; keep the language list in sync with `lib/i18n.ts`.
fn tr(state: &AppState, key: &str) -> &'static str {
    let lang = state.settings.lock().unwrap().language.clone()
        .or_else(sys_locale::get_locale)
        .unwrap_or_default()
        .to_lowercase();
    let lang = lang.get(..2).unwrap_or("en");
    let (panel, settings, quit) = match lang {
        "es" => ("Abrir panel", "Ajustes…", "Salir"),
        "pt" => ("Abrir painel", "Configurações…", "Sair"),
        "fr" => ("Ouvrir le panneau", "Réglages…", "Quitter"),
        "de" => ("Panel öffnen", "Einstellungen…", "Beenden"),
        "it" => ("Apri il pannello", "Impostazioni…", "Esci"),
        "zh" => ("打开面板", "设置…", "退出"),
        "ja" => ("パネルを開く", "設定…", "終了"),
        _ => ("Open panel", "Settings…", "Quit"),
    };
    match key {
        "panel" => panel,
        "settings" => settings,
        "quit" => quit,
        _ => "",
    }
}

fn build_menu(app: &AppHandle, state: &AppState) -> tauri::Result<Menu<tauri::Wry>> {
    Menu::with_items(app, &[
        &MenuItem::with_id(app, "panel", tr(state, "panel"), true, None::<&str>)?,
        &MenuItem::with_id(app, "settings", tr(state, "settings"), true, None::<&str>)?,
        &PredefinedMenuItem::separator(app)?,
        &MenuItem::with_id(app, "quit", tr(state, "quit"), true, None::<&str>)?,
    ])
}

fn rebuild_menu(app: &AppHandle, state: &AppState) {
    if let (Some(tray), Ok(menu)) = (state.tray.lock().unwrap().as_ref(), build_menu(app, state)) {
        let _ = tray.set_menu(Some(menu));
    }
}

fn create_tray(app: &AppHandle, state: &Arc<AppState>) -> tauri::Result<()> {
    let content = tray::render(&state.monitor.snapshot(), &state.settings.lock().unwrap());
    let tray = TrayIconBuilder::with_id("main")
        .icon(content.image)
        .icon_as_template(content.template)
        .tooltip("Llamastat")
        .menu(&build_menu(app, state)?)
        // Left click opens the panel (macOS/Windows); the menu stays on right click.
        // Linux trays (AppIndicator) only support the menu.
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "panel" => toggle_panel(app),
            "settings" => show_settings(app, None),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            tauri_plugin_positioner::on_tray_event(tray.app_handle(), &event);
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                toggle_panel(tray.app_handle());
            }
        })
        .build(app)?;
    *state.tray.lock().unwrap() = Some(tray);
    Ok(())
}

fn update_tray(state: &AppState, snapshot: &Snapshot) {
    let settings = state.settings.lock().unwrap().clone();
    let content = tray::render(snapshot, &settings);
    if let Some(tray) = state.tray.lock().unwrap().as_ref() {
        let _ = tray.set_icon(Some(content.image));
        let _ = tray.set_icon_as_template(content.template);
        let _ = tray.set_title(Some(content.title));
        let _ = tray.set_tooltip(Some(content.tooltip));
    }
}

// MARK: entry point

/// `llamastat --print-snapshot`: sample twice (rates need two points) and print the JSON.
/// Uses the saved settings; handy to debug backends without the UI.
pub fn print_snapshot(settings_path: Option<PathBuf>) {
    let settings = settings_path.map(|p| Settings::load(&p)).unwrap_or_default();
    let monitor = Monitor::new();
    let snapshot = tauri::async_runtime::block_on(async {
        monitor.tick(&settings).await;
        tokio::time::sleep(Duration::from_secs(1)).await;
        monitor.tick(&settings).await
    });
    println!("{}", serde_json::to_string_pretty(&snapshot).unwrap());
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| show_settings(app, None)))
        .plugin(tauri_plugin_positioner::init())
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, None))
        .invoke_handler(tauri::generate_handler![
            get_snapshot, get_settings, set_settings, toggle_model, restart_router, open_settings, fit_panel, quit,
            search_models, model_files, install_model, cancel_install, remove_model, router_paths,
        ])
        .setup(|app| {
            // Menu bar / tray app: no Dock icon.
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let settings_path = app.path().app_config_dir()?.join("settings.json");
            let state = Arc::new(AppState {
                monitor: Monitor::new(),
                installer: Installer::new(),
                settings: Mutex::new(Settings::load(&settings_path)),
                settings_path,
                tray: Mutex::new(None),
            });
            app.manage(Arc::clone(&state));
            create_tray(app.handle(), &state)?;
            let theme = state.settings.lock().unwrap().theme.native();
            create_panel(app.handle(), theme)?;
            if std::env::args().any(|a| a == "--open-settings") {
                show_settings(app.handle(), None);
            }

            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                loop {
                    let settings = state.settings.lock().unwrap().clone();
                    let snapshot = state.monitor.tick(&settings).await;
                    update_tray(&state, &snapshot);
                    let _ = handle.emit("snapshot", &snapshot);
                    tokio::time::sleep(Duration::from_secs_f64(settings.refresh_interval)).await;
                }
            });
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building Llamastat")
        // Closing the settings window must not quit a tray app.
        .run(|_, event| {
            if let tauri::RunEvent::ExitRequested { api, code: None, .. } = event {
                api.prevent_exit();
            }
        });
}
