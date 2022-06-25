import BackgroundTasks

extension CloudManager {
    static func scheduleSync() {
        PersistedOptions.extensionRequestedSync = true

        let syncTask = BGAppRefreshTaskRequest(identifier: syncSchedulingRequestId)
        syncTask.earliestBeginDate = nil
        do {
            try BGTaskScheduler.shared.submit(syncTask)
        } catch {
            log("Unable to submit task: \(error.localizedDescription)")
        }
    }
}
