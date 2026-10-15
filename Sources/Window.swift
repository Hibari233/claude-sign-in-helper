import AppKit
import SwiftUI

/// A small fixed-size window with one warm canvas running under a transparent title bar.
/// Shared by the app and the preview renderer.
func makeMainWindow(model: HelperModel) -> NSWindow {
    let size = NSSize(width: HelperRootView.size.width, height: HelperRootView.size.height)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.title = "Claude Sign-In Helper"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.backgroundColor = Palette.canvasColor
    let host = NSHostingView(rootView: HelperRootView(model: model))
    host.sizingOptions = [] // The window keeps its fixed size; the content adapts to it.
    window.contentView = host
    window.setContentSize(size)
    return window
}
