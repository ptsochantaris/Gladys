#if !os(visionOS)
    import UIKit

    final class GladysPopoverBackgroundView: UIPopoverBackgroundView {
        override static func contentViewInsets() -> UIEdgeInsets {
            .zero
        }

        private let arrowRectangle = Arrow(frame: CGRect(x: 0, y: 0, width: 44, height: 12))

        override static func arrowBase() -> CGFloat {
            44
        }

        override static func arrowHeight() -> CGFloat {
            12
        }

        override static var wantsDefaultContentAppearance: Bool {
            true
        }

        private var _arrowDirection: UIPopoverArrowDirection = .unknown
        override var arrowDirection: UIPopoverArrowDirection {
            get {
                _arrowDirection
            }
            set {
                _arrowDirection = newValue
                setNeedsLayout()
            }
        }

        private var _arrowOffset: CGFloat = 0
        override var arrowOffset: CGFloat {
            get {
                _arrowOffset
            }
            set {
                _arrowOffset = newValue
                setNeedsLayout()
            }
        }

        private class Arrow: UIView {
            override init(frame: CGRect) {
                super.init(frame: frame)
                isOpaque = false
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override func draw(_ rect: CGRect) {
                super.draw(rect)

                tintColor.setFill()

                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: rect.height))
                path.addLine(to: CGPoint(x: rect.width, y: rect.height))
                path.addLine(to: CGPoint(x: rect.width * 0.5, y: 0))
                path.addLine(to: CGPoint(x: 0, y: rect.height))
                path.fill()
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)

            addSubview(arrowRectangle)
        }

        private var darkMode: Bool {
            traitCollection.userInterfaceStyle == .dark
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private var needGradient = true

        override func layoutSubviews() {
            super.layoutSubviews()

            layer.shadowColor = UIColor.black.withAlphaComponent(darkMode ? 0.8 : 0.3).cgColor
            layer.shadowPath = UIBezierPath(rect: arrowRectangle.bounds.insetBy(dx: 100, dy: 100)).cgPath

            let arrowHeight = GladysPopoverBackgroundView.arrowHeight()
            var backgroundFrame = frame
            let arrowCenter: CGPoint
            let arrowTransformInRadians: CGFloat

            switch arrowDirection {
            case .up:
                backgroundFrame.origin.y += arrowHeight
                backgroundFrame.size.height -= arrowHeight
                arrowTransformInRadians = 0
                arrowCenter = CGPoint(x: backgroundFrame.size.width * 0.5 + arrowOffset, y: arrowHeight * 0.5)
            case .down:
                backgroundFrame.size.height -= arrowHeight
                arrowTransformInRadians = CGFloat.pi
                arrowCenter = CGPoint(x: backgroundFrame.size.width * 0.5 + arrowOffset, y: backgroundFrame.size.height + arrowHeight * 0.5)
            case .left:
                backgroundFrame.origin.x += arrowHeight
                backgroundFrame.size.width -= arrowHeight
                arrowTransformInRadians = CGFloat.pi * 1.5
                arrowCenter = CGPoint(x: arrowHeight * 0.5, y: backgroundFrame.size.height * 0.5 + arrowOffset)
            case .right:
                backgroundFrame.size.width -= arrowHeight
                arrowTransformInRadians = CGFloat.pi * 0.5
                arrowCenter = CGPoint(x: backgroundFrame.size.width + arrowHeight * 0.5, y: backgroundFrame.size.height * 0.5 + arrowOffset)
            case .any, .unknown:
                return // doesn't apply here
            default:
                return
            }

            if arrowRectangle.center.y < 44 {
                arrowRectangle.tintColor = darkMode ? UIColor(white: 0.175, alpha: 1) : UIColor.white
            } else {
                arrowRectangle.tintColor = UIColor.g_colorPaper
            }
            arrowRectangle.center = arrowCenter
            arrowRectangle.transform = CGAffineTransform(rotationAngle: arrowTransformInRadians)

            if needGradient {
                needGradient = false

                let gradientLayer = CAGradientLayer()
                gradientLayer.type = .radial
                gradientLayer.colors = [UIColor.black.withAlphaComponent(0.3).cgColor, UIColor.clear.cgColor]
                gradientLayer.locations = [0, 1]
                gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
                gradientLayer.endPoint = CGPoint(x: 1, y: 1)
                gradientLayer.frame = bounds.insetBy(dx: -1024, dy: -1024)
                gradientLayer.opacity = 0.0
                layer.insertSublayer(gradientLayer, at: 0)

                Task {
                    try? await Task.sleep(for: .seconds(0.1))
                    UIView.animate {
                        gradientLayer.opacity = 1.0
                    }
                }
            }
        }
    }
#endif
