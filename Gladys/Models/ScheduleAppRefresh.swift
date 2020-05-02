//
//  ScheduleAppRefresh.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 02/05/2020.
//  Copyright © 2020 Paul Tsochantaris. All rights reserved.
//

import BackgroundTasks

func scheduleAppRefresh() {
    do {
        let request = BGAppRefreshTaskRequest(identifier: syncSchedulingRequestId)
        request.earliestBeginDate = nil
        try BGTaskScheduler.shared.submit(request)
        log("Scheduled main app sync")
    } catch {
        log("Could not schedule main app sync: \(error.localizedDescription)")
    }
}
