import AppKit
import SwiftUI

enum MailAppearance {
    static let glassPreference = "darkLiquidGlass"
    static let blurPreference = "glassBackgroundBlur"
    static let defaultBlur = 0.5
}

struct MailBackdrop<Outline: Shape>: View {
    var outline: Outline
    @AppStorage(MailAppearance.glassPreference) private var glassEnabled = true
    @AppStorage(MailAppearance.blurPreference) private var blur = MailAppearance.defaultBlur
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if glassEnabled && !reduceTransparency {
                WindowGlass(blur: blur)
                    .padding(-1)
                Color(white: 0.065).opacity(0.30)
            } else {
                Color.black
            }
        }
        .clipShape(outline)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WindowGlass: NSViewRepresentable {
    var blur: Double

    func makeNSView(context: Context) -> NSGlassEffectView {
        #if FILEMAILER_ADJUSTABLE_BLUR
        let glass = AdjustableGlass()
        #else
        let glass = NSGlassEffectView()
        #endif
        glass.style = .clear
        glass.cornerRadius = 18
        return glass
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        #if FILEMAILER_ADJUSTABLE_BLUR
        let strength = min(max(blur, 0), 1)
        // Give subtle blur more travel near the start of the slider.
        (view as? AdjustableGlass)?.radius = strength * strength * 18
        #endif
    }
}

#if FILEMAILER_ADJUSTABLE_BLUR
// Only the direct download adjusts the native glass compositor.
private final class AdjustableGlass: NSGlassEffectView {
    var radius: Double = 0 {
        didSet { if radius != oldValue { tuneGlass() } }
    }

    override func layout() {
        super.layout()
        tuneGlass()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // AppKit installs its backdrop after attaching and laying out the view.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.tuneGlass() }
    }

    private func tuneGlass() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateBackdrop(in: layer)
        CATransaction.commit()
    }

    private func updateBackdrop(in layer: CALayer) {
        for case let filter as NSObject in layer.filters ?? [] {
            guard filter.responds(to: NSSelectorFromString("inputKeys")),
                  let keys = filter.value(forKey: "inputKeys") as? [String],
                  keys.contains("inputBlurOpacity0"),
                  let name = filter.value(forKey: "name") as? String else { continue }
            // Keep the optical edge active at zero blur. Only the radius follows the slider.
            var inputs = ["inputBlurRadius": radius, "inputRefractionOpacity": 1.0]
            for key in keys where key.hasPrefix("inputBlurOpacity") { inputs[key] = 1 }
            for (key, value) in inputs where keys.contains(key) {
                guard (filter.value(forKey: key) as? NSNumber)?.doubleValue != value else { continue }
                layer.setValue(value, forKeyPath: "filters.\(name).\(key)")
            }
            return
        }
        layer.sublayers?.forEach { updateBackdrop(in: $0) }
    }
}
#endif

extension View {
    func mailWindowBackground() -> some View {
        background {
            MailBackdrop(outline: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .ignoresSafeArea()
        }
    }
}
