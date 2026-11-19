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
