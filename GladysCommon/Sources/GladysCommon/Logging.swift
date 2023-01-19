#if DEBUG
    import os.log
    public func log(_ line: @autoclosure () -> String) {
        os_log("%{public}@", line())
    }
#else
    public func log(_: @autoclosure () -> String) {}
#endif
