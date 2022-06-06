//
//  Logging.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 09/02/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

#if DEBUG
    import os.log
    func log(_ line: @autoclosure () -> String) {
        os_log("%{public}@", line())
    }
#else
    func log(_: @autoclosure () -> String) {}
#endif
