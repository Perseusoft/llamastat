// Prevents an extra console window on Windows in release.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // `llamastat --write-icon out.png`: render the 1024px app icon source for `tauri icon`.
    let args: Vec<String> = std::env::args().collect();
    if let Some(i) = args.iter().position(|a| a == "--write-icon") {
        std::fs::write(&args[i + 1], llamastat_lib::tray::app_icon_png()).expect("write icon");
        return;
    }
    if args.iter().any(|a| a == "--print-snapshot") {
        llamastat_lib::print_snapshot(None);
        return;
    }
    llamastat_lib::run()
}
