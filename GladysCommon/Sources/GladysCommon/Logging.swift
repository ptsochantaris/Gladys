#if DEBUG
    import os.log

    public nonisolated func log(_ line: String) {
        os_log("%{public}@", line)
    }
#else
    public nonisolated func log(_: @autoclosure () -> String) {}
#endif
