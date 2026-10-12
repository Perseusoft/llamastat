import AppKit
import SwiftUI

/// MenuBarExtra's window grows with its content but never shrinks back (e.g. after ejecting a
/// model the panel keeps the old height). This measures the content and resizes the window,
/// keeping its top edge pinned under the menu bar.
struct FitWindowToContent: ViewModifier {
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(WindowReader(window: $window))
            .background(GeometryReader { geo in
                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
            })
            .onPreferenceChange(ContentHeightKey.self) { height in
                resize(to: height)
            }
    }

    private func resize(to height: CGFloat) {
        guard let window, height > 0 else { return }
        let target = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: window.contentLayoutRect.width, height: height)).height
        guard abs(window.frame.height - target) > 0.5 else { return }
        var frame = window.frame
        frame.origin.y += frame.height - target
        frame.size.height = target
        window.setFrame(frame, display: true)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if window !== view.window {
            DispatchQueue.main.async { window = view.window }
        }
    }
}

extension View {
    func fitWindowToContent() -> some View { modifier(FitWindowToContent()) }
}
