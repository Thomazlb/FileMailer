import AppKit
import SwiftUI

enum MailAppearance {
    static let glassPreference = "darkLiquidGlass"
    static let blurPreference = "glassBackgroundBlur"
    static let defaultBlur = 0.4
}

struct MailBackdrop<Outline: Shape>: View {
    var outline: Outline
    @AppStorage(MailAppearance.glassPreference) private var glassEnabled = true
    @AppStorage(MailAppearance.blurPreference) private var blur = MailAppearance.defaultBlur
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var nativeGlass: some View {
        // Clip the glass to the window without drawing a second highlight around its edge.
        Color.clear.glassEffect(.clear, in: Rectangle()).padding(-16)
    }

    var body: some View {
        ZStack {
            if glassEnabled && !reduceTransparency {
                Color(white: 0.065).opacity(0.30)
                #if FILEMAILER_ADJUSTABLE_BLUR
                if WindowBlur.isAvailable {
                    WindowBlur(radius: Int32((min(max(blur, 0), 1) * 64).rounded()))
                } else {
                    nativeGlass
                }
                #else
                nativeGlass
                #endif
            } else {
                Color.black
            }
        }
        .clipShape(outline)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if FILEMAILER_ADJUSTABLE_BLUR
// Only the direct distribution uses WindowServer's adjustable blur.
struct WindowBlur: NSViewRepresentable {
    let radius: Int32

    private typealias Connection = @convention(c) () -> Int32
    private typealias SetRadius = @convention(c) (Int32, UInt32, Int32) -> Int32

    private static let process = dlopen(nil, RTLD_LAZY)
    private static let connection = dlsym(process, "CGSMainConnectionID").map {
        unsafeBitCast($0, to: Connection.self)
    }
    private static let setRadius = dlsym(process, "CGSSetWindowBackgroundBlurRadius").map {
        unsafeBitCast($0, to: SetRadius.self)
    }

    static var isAvailable: Bool { connection != nil && setRadius != nil }

    func makeNSView(context: Context) -> Attachment { Attachment() }

    func updateNSView(_ view: Attachment, context: Context) {
        view.radius = radius
    }

    final class Attachment: NSView {
        private var originalShadow: Bool?

        var radius: Int32 = 0 {
            didSet {
                if radius != oldValue { apply(radius) }
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if window !== newWindow {
                apply(0)
                if let originalShadow { window?.hasShadow = originalShadow }
                originalShadow = nil
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // A transparent window casts its own shadow through the unblurred background.
            originalShadow = window?.hasShadow
            window?.hasShadow = false
            apply(radius)
        }

        private func apply(_ radius: Int32) {
            guard let number = window?.windowNumber, number > 0,
                  let connection = WindowBlur.connection, let setRadius = WindowBlur.setRadius else { return }
            _ = setRadius(connection(), UInt32(number), radius)
        }
    }
}
#endif

extension View {
    func mailWindowBackground() -> some View {
        background {
            MailBackdrop(outline: Rectangle()).ignoresSafeArea()
        }
    }
}
