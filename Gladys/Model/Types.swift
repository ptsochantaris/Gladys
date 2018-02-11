
import Foundation

#if MAINAPP
let kGladysDetailViewingActivity = "build.bru.Gladys.item.view"
let kGladysDetailViewingActivityItemUuid = "kGladysDetailViewingActivityItemUuid"
#endif

func log(_ line: @autoclosure ()->String) {
	#if DEBUG
		print(line())
	#endif
}

enum ArchivedDropItemDisplayType: Int {
	case fit, fill, center, circle
}

protocol LoadCompletionDelegate: class {
	func loadCompleted(sender: AnyObject)
}

extension Error {
	var finalDescription: String {
		let err = self as NSError
		return (err.userInfo[NSUnderlyingErrorKey] as? NSError)?.finalDescription ?? err.localizedDescription
	}
}
