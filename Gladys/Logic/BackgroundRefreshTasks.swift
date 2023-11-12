import BackgroundTasks
import Foundation
import GladysCommon

enum BackgroundRefreshTasks {
    static let bgRefreshTaskIdentifier = "build.bru.gladys.refresh"

    static func ensureFutureRefreshIsScheduled() {
        let request = BGAppRefreshTaskRequest(identifier: bgRefreshTaskIdentifier)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log("Warning: Error when submitting a refresh task request to the system: \(error.localizedDescription)")
        }
    }
}
