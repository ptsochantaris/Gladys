import Foundation

extension Data {
    var isPlist: Bool {
        count > 5
            && self[0 ..< 6].elementsEqual([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74])
    }

    var isZip: Bool {
        count > 3
            && self[0 ..< 2].elementsEqual([0x50, 0x4B])
            && (self[2 ..< 4].elementsEqual([3, 4])
                || self[2 ..< 4].elementsEqual([5, 6])
                || self[2 ..< 4].elementsEqual([7, 8])
            )
    }

    static func forceMemoryMapped(contentsOf url: URL) -> Data? {
        guard let cPath = url.absoluteURL.path.cString(using: .utf8) else {
            log("Warning, could not resolve \(url.absoluteURL.path)")
            return nil
        }

        var st = stat()
        if stat(cPath, &st) != 0 {
            log("Warning, could not size \(url.absoluteURL.path)")
            return nil
        }
        let count = Int(st.st_size)

        let fd = open(cPath, O_RDONLY)
        if fd < 0 {
            log("Warning, could not open \(url.absoluteURL.path)")
            return nil
        }

        defer {
            if close(fd) != 0 {
                log("Warning, error when closing \(url.absoluteURL.path)")
            }
        }

        guard let mappedBuffer = mmap(nil, count, PROT_READ, MAP_PRIVATE | MAP_FILE, fd, 0) else {
            log("Warning, could not memory map \(url.absoluteURL.path)")
            return nil
        }

        return Data(bytesNoCopy: mappedBuffer, count: count, deallocator: .unmap)
    }
}
