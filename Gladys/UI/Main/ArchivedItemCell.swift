import GladysCommon
import GladysUI
import GladysUIKit
import UIKit

#if canImport(PencilKit)
    import PencilKit
#endif

final class ArchivedItemCell: CommonItemCell {
    var wideCell: Bool {
        get {
            style == .wide
        }
        set {
            style = newValue ? .wide : .square
        }
    }

    private func cancelSelected() {
        if let archivedDropItem, archivedDropItem.status.shouldDisplayLoading {
            Model.delete(items: [archivedDropItem])
        }
    }

    #if canImport(PencilKit)
        override func setup() {
            super.setup()
            let pencil = UIIndirectScribbleInteraction(delegate: self)
            addInteraction(pencil)
        }

        private var notesTextView: UITextView?
    #endif
}

#if canImport(PencilKit)
    extension ArchivedItemCell: UIIndirectScribbleInteractionDelegate {
        nonisolated func indirectScribbleInteraction(_: UIInteraction, shouldDelayFocusForElement _: String) -> Bool {
            false
        }

        nonisolated func indirectScribbleInteraction(_: UIInteraction, willBeginWritingInElement _: String) {}

        nonisolated func indirectScribbleInteraction(_: UIInteraction, didFinishWritingInElement _: String) {
            onlyOnMainThread {
                if let item = archivedDropItem, let text = notesTextView?.text?.trimmingCharacters(in: .whitespacesAndNewlines), text.isPopulated, item.note != text {
                    item.note = text
                    item.markUpdated()
                    Task {
                        await Model.save()
                    }
                }

                if let n = notesTextView {
                    notesTextView = nil
                    UIView.animate(withDuration: 0.15, animations: {
                        n.alpha = 0
                    }, completion: { _ in
                        n.removeFromSuperview()
                    })
                }
            }
        }

        nonisolated func indirectScribbleInteraction(_: UIInteraction, focusElementIfNeeded _: String, referencePoint _: CGPoint, completion: @escaping ((UIResponder & UITextInput)?) -> Void) {
            onlyOnMainThread {
                if let n = notesTextView {
                    completion(n)
                    return
                }

                let f = UITextView()
                f.contentInset = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
                f.backgroundColor = UIColor.g_colorTint
                f.tintColor = UIColor.g_colorTint
                f.textColor = .white
                f.font = UIFont.preferredFont(forTextStyle: .headline)
                f.isEditable = false
                f.isSelectable = false
                f.clipsToBounds = true
                f.layer.cornerRadius = 10
                f.layer.borderWidth = pixelSize
                f.layer.borderColor = UIColor.opaqueSeparator.cgColor
                f.autocorrectionType = .no
                f.alpha = 0
                cover(with: f)
                notesTextView = f
                UIView.animate(withDuration: 0.15, animations: {
                    f.alpha = 1
                }, completion: { _ in
                    completion(f)
                })
            }
        }

        nonisolated func indirectScribbleInteraction(_: UIInteraction, requestElementsIn _: CGRect, completion: @escaping ([String]) -> Void) {
            onlyOnMainThread {
                if archivedDropItem?.isLocked == true {
                    completion([])
                } else {
                    completion(["NotesIdentifier"])
                }
            }
        }

        nonisolated func indirectScribbleInteraction(_: UIInteraction, frameForElement _: String) -> CGRect {
            onlyOnMainThread {
                bounds
            }
        }

        nonisolated func indirectScribbleInteraction(_: UIInteraction, isElementFocused _: String) -> Bool {
            onlyOnMainThread {
                notesTextView != nil
            }
        }
    }
#endif
