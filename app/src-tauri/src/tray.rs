//! Tray item: graphic widgets are drawn into the icon image, text widgets go to the tray
//! title (macOS, Linux) or the tooltip (Windows, where the tray is a fixed-size square).

use tauri::image::Image;
use tiny_skia::{Color, FillRule, Paint, PathBuilder, Pixmap, Rect, Stroke, Transform};

use crate::model::Snapshot;
use crate::settings::{Settings, TrayIcon, Widget};

pub struct TrayContent {
    pub image: Image<'static>,
    /// macOS: render as a template image so the system tints it like other menu bar items.
    pub template: bool,
    pub title: String,
    pub tooltip: String,
}

const RED: (u8, u8, u8) = (255, 59, 48);
const BLUE: (u8, u8, u8) = (10, 132, 255);
const PURPLE: (u8, u8, u8) = (191, 90, 242);

pub fn render(snapshot: &Snapshot, settings: &Settings) -> TrayContent {
    let windows = cfg!(target_os = "windows");
    let macos = cfg!(target_os = "macos");
    let visible: Vec<Widget> = settings.enabled_widgets().filter(|w| is_shown(*w, snapshot, settings)).collect();

    let texts: Vec<String> = visible.iter().filter(|w| !w.is_graphic()).filter_map(|w| text(*w, snapshot)).collect();
    let mut graphics: Vec<Widget> = visible.iter().copied().filter(|w| w.is_graphic()).collect();
    if graphics.is_empty() && (texts.is_empty() || windows) {
        graphics.push(Widget::Icon);
    }
    if windows {
        // A Windows tray icon is one square: keep only the first graphic.
        graphics.truncate(1);
    }

    // Monochrome: black for the macOS template mask, white elsewhere (trays are usually dark).
    let mono = if macos { (0, 0, 0) } else { (255, 255, 255) };
    let colored = settings.colored;
    let height = if windows { 32 } else { 44 };
    let widths: Vec<u32> = graphics.iter().map(|w| match w {
        Widget::RamBar => if windows { 32 } else { 16 },
        Widget::Sparkline => if windows { 32 } else { 64 },
        _ => height,
    }).collect();
    let gap = 8;
    let width = widths.iter().sum::<u32>() + gap * (widths.len() as u32).saturating_sub(1);
    let mut pixmap = Pixmap::new(width.max(1), height).expect("pixmap");

    let mut x = 0.0;
    for (widget, w) in graphics.iter().zip(&widths) {
        let frame = Rect::from_xywh(x, 0.0, *w as f32, height as f32).unwrap();
        match widget {
            Widget::RamBar => {
                let fraction = snapshot.memory.used_fraction();
                let color = if !colored { mono } else if fraction > 0.85 { RED } else { PURPLE };
                draw_bar(&mut pixmap, frame, fraction, color);
            }
            Widget::Sparkline => {
                let values: Vec<f64> = snapshot.history.iter().rev().take(30).rev().map(|s| s.generation_rate).collect();
                draw_sparkline(&mut pixmap, frame, &values, if colored { BLUE } else { mono });
            }
            _ => draw_icon(&mut pixmap, frame, settings.icon, mono, snapshot.backends.iter().any(|b| b.online)),
        }
        x += *w as f32 + gap as f32;
    }

    let rgba = demultiply(&pixmap);
    let summary = texts.join("  ");
    TrayContent {
        image: Image::new_owned(rgba, pixmap.width(), pixmap.height()),
        template: macos && !colored,
        title: if windows { String::new() } else { summary.clone() },
        tooltip: if summary.is_empty() { "Llamastat".into() } else { format!("Llamastat · {summary}") },
    }
}

fn is_shown(widget: Widget, snapshot: &Snapshot, settings: &Settings) -> bool {
    let tokens_enabled = settings.enabled_widgets().any(|w| w == Widget::TokensPerSecond);
    match widget {
        Widget::TokensPerSecond => !settings.tokens_only_while_generating || snapshot.generating,
        // While generating, tokens/s replaces the model name to keep the item short.
        Widget::Model => !snapshot.active.is_empty() && !(settings.tokens_only_while_generating && snapshot.generating && tokens_enabled),
        Widget::Context => snapshot.context_fraction.is_some(),
        _ => true,
    }
}

fn text(widget: Widget, s: &Snapshot) -> Option<String> {
    let percent = |f: f64| format!("{:.0}%", f * 100.0);
    Some(match widget {
        Widget::TokensPerSecond => format!("{:.1} t/s", s.generation_rate),
        Widget::Model => s.active.iter().map(|m| short_name(&m.info.name)).collect::<Vec<_>>().join(" + "),
        Widget::Ram => format!("RAM {}", percent(s.memory.used_fraction())),
        Widget::Gpu => format!("GPU {}", percent(s.gpu.as_ref()?.utilization)),
        Widget::Context => format!("ctx {}", percent(s.context_fraction?)),
        _ => return None,
    })
}

pub fn short_name(name: &str) -> &str {
    name.split(':').next().unwrap_or(name)
}

fn paint(color: (u8, u8, u8), alpha: u8) -> Paint<'static> {
    let mut paint = Paint::default();
    paint.set_color(Color::from_rgba8(color.0, color.1, color.2, alpha));
    paint.anti_alias = true;
    paint
}

/// Stats-style vertical fill bar.
fn draw_bar(pixmap: &mut Pixmap, frame: Rect, fraction: f64, color: (u8, u8, u8)) {
    let (w, h) = (frame.width().min(16.0), frame.height() * 0.8);
    let x = frame.x() + (frame.width() - w) / 2.0;
    let y = (frame.height() - h) / 2.0;
    let outline = PathBuilder::from_rect(Rect::from_xywh(x + 1.0, y + 1.0, w - 2.0, h - 2.0).unwrap());
    pixmap.stroke_path(&outline, &paint(color, 160), &Stroke { width: 2.0, ..Default::default() }, Transform::identity(), None);
    let fill_h = ((h - 8.0) * fraction.clamp(0.0, 1.0) as f32).max(1.0);
    let fill = Rect::from_xywh(x + 4.0, y + h - 4.0 - fill_h, w - 8.0, fill_h).unwrap();
    pixmap.fill_rect(fill, &paint(color, 255), Transform::identity(), None);
}

fn draw_sparkline(pixmap: &mut Pixmap, frame: Rect, values: &[f64], color: (u8, u8, u8)) {
    let (x0, y0, w, h) = (frame.x() + 1.0, frame.height() * 0.15, frame.width() - 2.0, frame.height() * 0.7);
    let border = PathBuilder::from_rect(Rect::from_xywh(x0, y0, w, h).unwrap());
    pixmap.stroke_path(&border, &paint(color, 110), &Stroke { width: 1.0, ..Default::default() }, Transform::identity(), None);
    if values.len() < 2 {
        return;
    }
    let peak = values.iter().cloned().fold(1.0, f64::max);
    let step = w / (values.len() - 1) as f32;
    let point = |i: usize, v: f64| (x0 + i as f32 * step, y0 + h - (h - 2.0) * (v / peak) as f32);
    let mut area = PathBuilder::new();
    area.move_to(x0, y0 + h);
    for (i, v) in values.iter().enumerate() {
        let (x, y) = point(i, *v);
        area.line_to(x, y);
    }
    area.line_to(x0 + w, y0 + h);
    area.close();
    if let Some(path) = area.finish() {
        pixmap.fill_path(&path, &paint(color, 120), FillRule::Winding, Transform::identity(), None);
        pixmap.stroke_path(&path, &paint(color, 255), &Stroke { width: 1.5, ..Default::default() }, Transform::identity(), None);
    }
}

/// Icons are drawn in a 100×100 box and scaled into the frame.
fn draw_icon(pixmap: &mut Pixmap, frame: Rect, icon: TrayIcon, color: (u8, u8, u8), online: bool) {
    let size = frame.height() * 0.8;
    let scale = size / 100.0;
    let transform = Transform::from_row(scale, 0.0, 0.0, scale, frame.x() + (frame.width() - size) / 2.0, frame.y() + (frame.height() - size) / 2.0);
    let fill = paint(color, if online { 255 } else { 110 });
    let path = match icon {
        TrayIcon::Llama => polygon(LLAMA),
        TrayIcon::Bolt => polygon(&[(58.0, 2.0), (16.0, 58.0), (46.0, 58.0), (38.0, 98.0), (84.0, 38.0), (54.0, 38.0)]),
        TrayIcon::Dot => PathBuilder::from_circle(50.0, 50.0, 30.0),
        TrayIcon::Chip => {
            let mut pb = PathBuilder::new();
            pb.push_rect(Rect::from_xywh(20.0, 20.0, 60.0, 60.0).unwrap());
            pb.push_rect(Rect::from_xywh(34.0, 34.0, 32.0, 32.0).unwrap());
            for i in 0..3 {
                let o = 30.0 + i as f32 * 17.0;
                pb.push_rect(Rect::from_xywh(o, 6.0, 6.0, 14.0).unwrap());
                pb.push_rect(Rect::from_xywh(o, 80.0, 6.0, 14.0).unwrap());
                pb.push_rect(Rect::from_xywh(6.0, o, 14.0, 6.0).unwrap());
                pb.push_rect(Rect::from_xywh(80.0, o, 14.0, 6.0).unwrap());
            }
            pb.finish()
        }
    };
    if let Some(path) = path {
        // EvenOdd so the chip's inner square is a hole.
        pixmap.fill_path(&path, &fill, FillRule::EvenOdd, transform, None);
    }
}

fn polygon(points: &[(f32, f32)]) -> Option<tiny_skia::Path> {
    let mut pb = PathBuilder::new();
    pb.move_to(points[0].0, points[0].1);
    for (x, y) in &points[1..] {
        pb.line_to(*x, *y);
    }
    pb.close();
    pb.finish()
}

/// Side-view llama silhouette, facing left.
const LLAMA: &[(f32, f32)] = &[
    (6.0, 26.0), (10.0, 20.0), (16.0, 16.0), (18.0, 3.0), (22.0, 12.0), (25.0, 2.0), (28.0, 14.0),
    (30.0, 24.0), (31.0, 46.0), (38.0, 50.0), (76.0, 48.0), (86.0, 52.0), (93.0, 58.0), (88.0, 62.0),
    (86.0, 72.0), (86.0, 97.0), (80.0, 97.0), (79.0, 76.0), (74.0, 76.0), (73.0, 97.0), (67.0, 97.0),
    (66.0, 74.0), (46.0, 74.0), (45.0, 97.0), (39.0, 97.0), (38.0, 76.0), (34.0, 76.0), (33.0, 97.0),
    (27.0, 97.0), (25.0, 66.0), (21.0, 56.0), (19.0, 34.0), (12.0, 32.0), (6.0, 30.0),
];

/// tiny-skia stores premultiplied alpha; Tauri images are straight RGBA.
fn demultiply(pixmap: &Pixmap) -> Vec<u8> {
    pixmap.pixels().iter().flat_map(|p| {
        let c = p.demultiply();
        [c.red(), c.green(), c.blue(), c.alpha()]
    }).collect()
}

/// App icon source (1024×1024) for `tauri icon`: white llama on a blue rounded square.
pub fn app_icon_png() -> Vec<u8> {
    let mut pixmap = Pixmap::new(1024, 1024).unwrap();
    let mut bg = PathBuilder::new();
    let (r, s) = (220.0, 1024.0 - 2.0 * 64.0);
    // Rounded square via quadratic corners.
    bg.move_to(64.0 + r, 64.0);
    bg.line_to(64.0 + s - r, 64.0);
    bg.quad_to(64.0 + s, 64.0, 64.0 + s, 64.0 + r);
    bg.line_to(64.0 + s, 64.0 + s - r);
    bg.quad_to(64.0 + s, 64.0 + s, 64.0 + s - r, 64.0 + s);
    bg.line_to(64.0 + r, 64.0 + s);
    bg.quad_to(64.0, 64.0 + s, 64.0, 64.0 + s - r);
    bg.line_to(64.0, 64.0 + r);
    bg.quad_to(64.0, 64.0, 64.0 + r, 64.0);
    bg.close();
    let mut shader = Paint::default();
    shader.anti_alias = true;
    shader.shader = tiny_skia::LinearGradient::new(
        tiny_skia::Point::from_xy(0.0, 64.0),
        tiny_skia::Point::from_xy(0.0, 960.0),
        vec![
            tiny_skia::GradientStop::new(0.0, Color::from_rgba8(64, 156, 255, 255)),
            tiny_skia::GradientStop::new(1.0, Color::from_rgba8(88, 86, 214, 255)),
        ],
        tiny_skia::SpreadMode::Pad,
        Transform::identity(),
    ).unwrap();
    pixmap.fill_path(&bg.finish().unwrap(), &shader, FillRule::Winding, Transform::identity(), None);
    draw_icon(&mut pixmap, Rect::from_xywh(112.0, 112.0, 800.0, 800.0).unwrap(), TrayIcon::Llama, (255, 255, 255), true);
    pixmap.encode_png().unwrap()
}
