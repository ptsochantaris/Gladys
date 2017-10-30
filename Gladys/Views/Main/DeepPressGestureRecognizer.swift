import UIKit

class DeepPressGestureRecognizer: UIGestureRecognizer
{
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
		} else if pressed && (touch.force / touch.maximumPossibleForce) < threshold {
			state = .ended
			pressed = false
		}
	}
}

