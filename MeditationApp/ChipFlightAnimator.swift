import SwiftUI
import UIKit

// MARK: - Preference Key for destination frames

struct ChipDestinationPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Flight Animator

@MainActor
final class ChipFlightAnimator: NSObject, CAAnimationDelegate {
    static let shared = ChipFlightAnimator()

    private var completions: [String: () -> Void] = [:]
    private var flyingViews: [String: UIView] = [:]

    nonisolated func animationDidStop(_ anim: CAAnimation, finished: Bool) {
        guard let emotionId = anim.value(forKey: "emotionId") as? String else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handleAnimationComplete(emotionId: emotionId)
        }
    }

    private func handleAnimationComplete(emotionId: String) {
        flyingViews[emotionId]?.removeFromSuperview()
        flyingViews.removeValue(forKey: emotionId)
        let completion = completions.removeValue(forKey: emotionId)
        completion?()
    }

    func fly(
        emotionId: String,
        chipView: some View,
        from sourceFrame: CGRect,
        to destFrame: CGRect,
        completion: @escaping () -> Void
    ) {
        // Respect reduce motion
        if UIAccessibility.isReduceMotionEnabled {
            completion()
            return
        }

        guard let window = Self.keyWindow else {
            completion()
            return
        }

        // Render the chip to an image
        let renderer = ImageRenderer(content: chipView)
        renderer.scale = UIScreen.main.scale
        guard let image = renderer.uiImage else {
            completion()
            return
        }

        // Create the flying view
        let flyingView = UIImageView(image: image)
        flyingView.frame = sourceFrame
        flyingView.layer.cornerRadius = 10
        flyingView.layer.masksToBounds = true
        flyingView.layer.shadowColor = UIColor.black.cgColor
        flyingView.layer.shadowOpacity = 0.2
        flyingView.layer.shadowOffset = CGSize(width: 0, height: 4)
        flyingView.layer.shadowRadius = 8
        flyingView.layer.masksToBounds = false
        window.addSubview(flyingView)

        flyingViews[emotionId] = flyingView
        completions[emotionId] = completion

        // Build bezier flight path
        let sourceCenter = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let destCenter = CGPoint(x: destFrame.midX, y: destFrame.midY)

        let dx = destCenter.x - sourceCenter.x
        let dy = destCenter.y - sourceCenter.y
        let arcHeight: CGFloat = min(abs(dy) * 0.5, 150) + 60

        let cp1 = CGPoint(
            x: sourceCenter.x + dx * 0.25,
            y: sourceCenter.y - arcHeight
        )
        let cp2 = CGPoint(
            x: sourceCenter.x + dx * 0.75,
            y: destCenter.y - arcHeight * 0.5
        )

        let path = UIBezierPath()
        path.move(to: sourceCenter)
        path.addCurve(to: destCenter, controlPoint1: cp1, controlPoint2: cp2)

        // Position animation along the bezier path
        let positionAnim = CAKeyframeAnimation(keyPath: "position")
        positionAnim.path = path.cgPath
        positionAnim.calculationMode = .paced

        // Size animation from source to destination
        let boundsAnim = CABasicAnimation(keyPath: "bounds.size")
        boundsAnim.fromValue = NSValue(cgSize: sourceFrame.size)
        boundsAnim.toValue = NSValue(cgSize: destFrame.size)

        // Slight scale bounce at the end via a subtle opacity pulse
        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.values = [1.0, 1.0, 0.95, 1.0]
        opacityAnim.keyTimes = [0.0, 0.7, 0.85, 1.0]

        // Group all animations
        let group = CAAnimationGroup()
        group.animations = [positionAnim, boundsAnim, opacityAnim]
        group.duration = 0.5
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        group.delegate = self
        group.setValue(emotionId, forKey: "emotionId")

        // Set final position before animating so it doesn't snap back
        flyingView.layer.position = destCenter
        flyingView.layer.bounds.size = destFrame.size

        flyingView.layer.add(group, forKey: "flight_\(emotionId)")
    }

    // MARK: - Helpers

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
