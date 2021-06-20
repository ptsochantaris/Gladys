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
