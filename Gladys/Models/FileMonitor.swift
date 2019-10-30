import Foundation

// Tweaked from https://blog.beecomedigital.com/2015/06/27/developing-a-filesystemwatcher-for-os-x-by-using-fsevents-with-swift-2/

final class FileMonitor {

    private var streamRef: FSEventStreamRef!
    private var callback: (String, FSEventStreamEventFlags) -> Void

    init(pathsToWatch: [String], callback: @escaping (String, FSEventStreamEventFlags) -> Void) {
        self.callback = callback
        
        let startEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        var context = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        streamRef = FSEventStreamCreate(kCFAllocatorDefault, eventCallback, &context, pathsToWatch as CFArray, startEventId, 0, flags)
         
        FSEventStreamScheduleWithRunLoop(streamRef, CFRunLoopGetMain(), RunLoop.Mode.default.rawValue as CFString)
        FSEventStreamStart(streamRef)
    }
     
    deinit {
        FSEventStreamStop(streamRef)
        FSEventStreamInvalidate(streamRef)
        FSEventStreamRelease(streamRef)
    }
 
    private let eventCallback: FSEventStreamCallback = { (stream: ConstFSEventStreamRef, contextInfo: UnsafeMutableRawPointer?, numEvents: Int, eventPaths: UnsafeMutableRawPointer, eventFlags: UnsafePointer<FSEventStreamEventFlags>, eventIds: UnsafePointer<FSEventStreamEventId>) in
        guard let contextInfo = contextInfo else { return }
        let monitor = Unmanaged<FileMonitor>.fromOpaque(contextInfo).takeUnretainedValue()
        let paths = Unmanaged<NSArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
         
        for index in 0 ..< numEvents {
            monitor.callback(paths[index], eventFlags[index])
        }
    }
}
