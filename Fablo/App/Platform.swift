import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor

extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor

extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}

// iOS-only SwiftUI APIs, mapped to their Mac equivalents (or no-ops) so shared views compile unchanged.

extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
}

enum NavigationBarTitleDisplayMode { case automatic, inline, large }

enum KeyboardType { case `default`, URL }

enum TextInputAutocapitalization { case never, words, sentences, characters }

extension View {
    func navigationBarTitleDisplayMode(_ mode: NavigationBarTitleDisplayMode) -> some View { self }
    func keyboardType(_ type: KeyboardType) -> some View { self }
    func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View { self }
}
#endif

#if os(macOS)
/// Hides the window's close / minimize / zoom buttons; ⌘W, ⌘M and the Window menu still work.
/// AppKit re-shows them on some layout passes, so they are hidden again whenever it does.
struct HiddenWindowButtons: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) { Probe.hide(in: view.window) }

    private final class Probe: NSView {
        private var observation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            Self.hide(in: window)
            observation = window?.standardWindowButton(.closeButton)?.observe(\.isHidden) { button, _ in
                if !button.isHidden { DispatchQueue.main.async { Self.hide(in: button.window) } }
            }
        }

        static func hide(in window: NSWindow?) {
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window?.standardWindowButton(type)?.isHidden = true
            }
        }
    }
}

/// Mac sheets can't be swiped away; this gives them a close button that also answers Esc.
private struct MacDismissButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            Button("关闭", systemImage: "xmark.circle.fill") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(12)
        }
    }
}
#endif

#if os(macOS)
extension View {
    /// The in-content top bars that replace the Mac window toolbar: round glass icon buttons,
    /// inset to line up with the content below, on a frosted paper background that content scrolls under.
    func macTopBarStyle(inset: CGFloat) -> some View {
        labelStyle(.iconOnly)
            .buttonStyle(MacGlassIconButtonStyle())
            .padding(.vertical, 10)
            .padding(.horizontal, inset)
            .background {
                Rectangle()
                    .fill(Theme.paper.opacity(0.85))
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
            }
    }
}

/// A neutral glass circle; `.glass` would take on the black accent tint.
struct MacGlassIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(width: 36, height: 36)
            .glassEffect(.regular.interactive(), in: .circle)
            .contentShape(.circle)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
    }
}
#endif

extension View {
    func macDismissButton() -> some View {
        #if os(macOS)
        modifier(MacDismissButton())
        #else
        self
        #endif
    }

    /// Mac sheets size to their content; give form-like sheets a comfortable size there.
    func macSheetFrame(width: CGFloat = 460, height: CGFloat = 620) -> some View {
        #if os(macOS)
        frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
        #else
        self
        #endif
    }
}
