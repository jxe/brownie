import SwiftUI

// MARK: - Speech Bubble Shape

struct SpeechBubbleShape: InsettableShape {
    var tailFraction: CGFloat = 1.0 / 6.0
    var tailWidth: CGFloat = 20
    var tailHeight: CGFloat = 10
    var cornerRadius: CGFloat = 18
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> SpeechBubbleShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let bodyBottom = r.maxY - tailHeight
        let tailCenterX = r.minX + r.width * tailFraction
        let halfTail = tailWidth / 2
        let cr = min(cornerRadius, r.width / 2, (r.height - tailHeight) / 2)

        var path = Path()

        // Start at top-left after corner
        path.move(to: CGPoint(x: r.minX + cr, y: r.minY))
        // Top edge
        path.addLine(to: CGPoint(x: r.maxX - cr, y: r.minY))
        // Top-right corner
        path.addArc(center: CGPoint(x: r.maxX - cr, y: r.minY + cr), radius: cr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        // Right edge
        path.addLine(to: CGPoint(x: r.maxX, y: bodyBottom - cr))
        // Bottom-right corner
        path.addArc(center: CGPoint(x: r.maxX - cr, y: bodyBottom - cr), radius: cr, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        // Bottom edge to tail
        path.addLine(to: CGPoint(x: tailCenterX + halfTail, y: bodyBottom))
        // Tail
        path.addLine(to: CGPoint(x: tailCenterX, y: r.maxY))
        path.addLine(to: CGPoint(x: tailCenterX - halfTail, y: bodyBottom))
        // Bottom edge to left
        path.addLine(to: CGPoint(x: r.minX + cr, y: bodyBottom))
        // Bottom-left corner
        path.addArc(center: CGPoint(x: r.minX + cr, y: bodyBottom - cr), radius: cr, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        // Left edge
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + cr))
        // Top-left corner
        path.addArc(center: CGPoint(x: r.minX + cr, y: r.minY + cr), radius: cr, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        path.closeSubpath()

        return path
    }
}

// MARK: - Split Halves for GlassEffectContainer

/// Left half of the speech bubble: left-rounded corners + tail at the bottom.
/// `tailFraction` is relative to the left half's own width.
struct SpeechBubbleLeftHalf: Shape {
    var tailFraction: CGFloat = 0.5
    var tailWidth: CGFloat = 20
    var tailHeight: CGFloat = 10
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let bodyBottom = rect.maxY - tailHeight
        // tailFraction is relative to the full bar, but this shape only covers the left half,
        // so we double it to map into our local coordinate space
        let localFraction = min(tailFraction * 2, 1.0)
        let tailCenterX = rect.minX + rect.width * localFraction
        let halfTail = tailWidth / 2
        let cr = min(cornerRadius, rect.width / 2, (rect.height - tailHeight) / 2)

        var path = Path()

        // Start at top-left after corner
        path.move(to: CGPoint(x: rect.minX + cr, y: rect.minY))
        // Top edge to right (flat, no corner on right side)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Right edge (straight, no corner)
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyBottom))
        // Bottom edge to tail
        path.addLine(to: CGPoint(x: min(tailCenterX + halfTail, rect.maxX), y: bodyBottom))
        // Tail
        path.addLine(to: CGPoint(x: tailCenterX, y: rect.maxY))
        path.addLine(to: CGPoint(x: max(tailCenterX - halfTail, rect.minX + cr), y: bodyBottom))
        // Bottom edge to left
        path.addLine(to: CGPoint(x: rect.minX + cr, y: bodyBottom))
        // Bottom-left corner
        path.addArc(center: CGPoint(x: rect.minX + cr, y: bodyBottom - cr), radius: cr, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        // Left edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cr))
        // Top-left corner
        path.addArc(center: CGPoint(x: rect.minX + cr, y: rect.minY + cr), radius: cr, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        path.closeSubpath()
        return path
    }
}

/// Right half of the speech bubble: right-rounded corners, flat left edge, flat bottom.
struct SpeechBubbleRightHalf: Shape {
    var tailHeight: CGFloat = 10
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let bodyBottom = rect.maxY - tailHeight
        let cr = min(cornerRadius, rect.width / 2, (rect.height - tailHeight) / 2)

        var path = Path()

        // Start at top-left (flat, no corner)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top edge to right corner
        path.addLine(to: CGPoint(x: rect.maxX - cr, y: rect.minY))
        // Top-right corner
        path.addArc(center: CGPoint(x: rect.maxX - cr, y: rect.minY + cr), radius: cr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyBottom - cr))
        // Bottom-right corner
        path.addArc(center: CGPoint(x: rect.maxX - cr, y: bodyBottom - cr), radius: cr, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        // Bottom edge (flat)
        path.addLine(to: CGPoint(x: rect.minX, y: bodyBottom))
        // Left edge (straight, no corner)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        path.closeSubpath()
        return path
    }
}

// MARK: - Speech Bubble Tail Only

/// Just the downward-pointing triangle, used as a separate overlay beneath the glass bar.
struct SpeechBubbleTail: Shape {
    var tailWidth: CGFloat = 20
    var tailHeight: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - tailWidth / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + tailWidth / 2, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Tab Bar Center X Reader

/// Environment key to pass a tab icon's center X position down to child views.
struct FeelingsTabCenterXKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var feelingsTabCenterX: CGFloat? {
        get { self[FeelingsTabCenterXKey.self] }
        set { self[FeelingsTabCenterXKey.self] = newValue }
    }
}

/// Finds the center X of a specific tab bar button by walking the UIKit view hierarchy.
struct TabBarCenterXReader: UIViewRepresentable {
    let tabIndex: Int
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            var root: UIView = uiView
            while let parent = root.superview { root = parent }
            Self.findTabButtons(in: root, tabIndex: tabIndex, onChange: onChange)
        }
    }

    private static func findTabButtons(in root: UIView, tabIndex: Int, onChange: (CGFloat) -> Void) {
        var buttons: [UIView] = []
        collectTabBarButtons(in: root, result: &buttons)
        let sorted = buttons.sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
        guard tabIndex < sorted.count else { return }
        let frame = sorted[tabIndex].convert(sorted[tabIndex].bounds, to: nil)
        onChange(frame.midX)
    }

    private static func collectTabBarButtons(in view: UIView, result: inout [UIView]) {
        let typeName = String(describing: type(of: view))
        if typeName.contains("TabBarButton") || typeName.contains("TabButton") {
            result.append(view)
            return
        }
        for subview in view.subviews {
            collectTabBarButtons(in: subview, result: &result)
        }
    }
}
