//! User settings, stored as JSON in the app config dir.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Widget {
    Icon,
    TokensPerSecond,
    Model,
    Ram,
    Gpu,
    Context,
    RamBar,
    Sparkline,
}

impl Widget {
    pub const ALL: [Widget; 8] = [
        Widget::Icon, Widget::TokensPerSecond, Widget::Model, Widget::Sparkline,
        Widget::Ram, Widget::RamBar, Widget::Gpu, Widget::Context,
    ];

    /// Drawn into the tray image; the rest are text (tray title on macOS/Linux, tooltip on Windows).
    pub fn is_graphic(self) -> bool {
        matches!(self, Widget::Icon | Widget::RamBar | Widget::Sparkline)
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WidgetSetting {
    pub widget: Widget,
    pub enabled: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TrayIcon {
    Llama,
    Chip,
    Bolt,
    Dot,
}

/// Appearance of the windows. The tray icon is unaffected: it follows the menu bar.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Theme {
    #[default]
    System,
    Light,
    Dark,
}

impl Theme {
    /// What to tell the OS window (title bar, scrollbars, native controls). None = follow the system.
    pub fn native(self) -> Option<tauri::Theme> {
        match self {
            Theme::System => None,
            Theme::Light => Some(tauri::Theme::Light),
            Theme::Dark => Some(tauri::Theme::Dark),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    pub theme: Theme,
    pub widgets: Vec<WidgetSetting>,
    pub icon: TrayIcon,
    pub colored: bool,
    /// Hide tokens/s while nothing is generating, so the tray stays quiet.
    pub tokens_only_while_generating: bool,
    pub hidden_sections: Vec<String>,
    pub refresh_interval: f64,
    pub llama_cpp_enabled: bool,
    pub llama_cpp_url: String,
    /// launchd label (macOS) or systemd --user unit (Linux) restarted by "Restart router".
    pub router_service: String,
    /// Path to the router's presets.ini; None = read it from the running llama-server's arguments.
    pub llama_cpp_presets: Option<String>,
    pub ollama_enabled: bool,
    pub ollama_url: String,
    /// None = follow the system.
    pub language: Option<String>,
}

impl Default for Settings {
    fn default() -> Self {
        let on = [Widget::Icon, Widget::TokensPerSecond, Widget::Model];
        Self {
            theme: Theme::System,
            widgets: Widget::ALL.iter().map(|&w| WidgetSetting { widget: w, enabled: on.contains(&w) }).collect(),
            icon: TrayIcon::Llama,
            colored: false,
            tokens_only_while_generating: true,
            hidden_sections: vec![],
            refresh_interval: 1.0,
            llama_cpp_enabled: true,
            llama_cpp_url: "http://127.0.0.1:8080".into(),
            router_service: if cfg!(target_os = "macos") { "com.local.llama-router".into() } else { "llama-router.service".into() },
            llama_cpp_presets: None,
            ollama_enabled: true,
            ollama_url: "http://127.0.0.1:11434".into(),
            language: None,
        }
    }
}

impl Settings {
    pub fn load(path: &PathBuf) -> Self {
        let mut settings: Settings = std::fs::read(path)
            .ok()
            .and_then(|data| serde_json::from_slice(&data).ok())
            .unwrap_or_default();
        // Widgets added in later versions show up at the end, disabled.
        for widget in Widget::ALL {
            if !settings.widgets.iter().any(|w| w.widget == widget) {
                settings.widgets.push(WidgetSetting { widget, enabled: false });
            }
        }
        settings.refresh_interval = settings.refresh_interval.clamp(0.5, 10.0);
        settings
    }

    pub fn save(&self, path: &PathBuf) -> Result<(), String> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        }
        std::fs::write(path, serde_json::to_vec_pretty(self).map_err(|e| e.to_string())?).map_err(|e| e.to_string())
    }

    pub fn enabled_widgets(&self) -> impl Iterator<Item = Widget> + '_ {
        self.widgets.iter().filter(|w| w.enabled).map(|w| w.widget)
    }
}
