import AppKit

typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

/// Saves the window as a PNG with what the window server composited, glass included. `CGWindowListCreateImage` is
/// obsoleted in the SDK but still in the system library; it needs no screen-recording permission for the app's own windows.
/// `withChildren`: the screen region of the window instead of the window alone, so a sheet or a popover on it is in the picture.
func savePNG(window: NSWindow, to path: String, withChildren: Bool) -> Bool {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return false }
    let capture = unsafeBitCast(sym, to: CaptureFn.self)
    let image: CGImage?
    if withChildren {
        let screenHeight = NSScreen.screens[0].frame.height
        let f = window.frame.insetBy(dx: -30, dy: -30)
        let region = CGRect(x: f.minX, y: screenHeight - f.maxY, width: f.width, height: f.height)
        image = capture(region, 1 << 0, 0, 1 << 4)?.takeRetainedValue()   // on screen only, nominal resolution
    } else {
        image = capture(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 4))?.takeRetainedValue()   // the window, no shadow framing
    }
    guard let image, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
    return (try? data.write(to: URL(fileURLWithPath: path))) != nil
}
