#if DEBUG
    import os.log
    func log(_ line: @autoclosure () -> String) {
        os_log("%{public}@", line())
    }
#else
    func log(_: @autoclosure () -> String) {}
#endif
