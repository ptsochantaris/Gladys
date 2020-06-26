import UIKit

final class CenteredPinchGestureRecognizer: UIPinchGestureRecognizer {
    var startPoint: CGPoint?
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let view = view {
            startPoint = location(in: view)
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let start = startPoint, let view = view {
            let newPoint = location(in: view)
            let distance = sqrt(pow(newPoint.x - start.x, 2) + pow(newPoint.y - start.y, 2))
            if distance > 44 && velocity < 1 {
                state = .failed
                return
            }
        }
        super.touchesMoved(touches, with: event)
    }
}

final class DeepPressGestureRecognizer: UIGestureRecognizer {
	private let threshold: CGFloat
	private var pressed = false

	required init(target: AnyObject?, action: Selector, threshold: CGFloat) {
		self.threshold = threshold
		super.init(target: target, action: action)
	}

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
		if let touch = touches.first {
			handleTouch(touch: touch)
		}
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
		if let touch = touches.first {
			handleTouch(touch: touch)
		}
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesEnded(touches, with: event)
		state = pressed ? .ended : .failed
		pressed = false
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
		state = pressed ? .ended : .failed
		pressed = false
	}

	private func handleTouch(touch: UITouch) {
		guard touch.force != 0 && touch.maximumPossibleForce != 0 else {
			return
		}

		if !pressed && (touch.force / touch.maximumPossibleForce) >= threshold {
			state = .began
			pressed = true
			UIImpactFeedbackGenerator(style: .light).impactOccurred()

		} else if pressed && (touch.force / touch.maximumPossibleForce) < threshold {
			state = .ended
			pressed = false
		}
	}
}
