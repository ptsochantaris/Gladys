//
//  ZIPFoundationFileAttributeTests.swift
//  ZIPFoundation
//
//  Copyright © 2017-2023 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import XCTest
@testable import ZIPFoundation

extension ZIPFoundationTests {

    func testFileAttributeHelperMethods() {
        let cdsBytes: [UInt8] = [0x50, 0x4b, 0x01, 0x02, 0x1e, 0x15, 0x14, 0x00,
                                 0x08, 0x08, 0x08, 0x00, 0xab, 0x85, 0x77, 0x47,
                                 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0xb0, 0x11, 0x00, 0x00, 0x00, 0x00]
        guard let cds = Entry.CentralDirectoryStructure(data: Data(cdsBytes),
                                                        additionalDataProvider: { count -> Data in
            guard let pathData = "/".data(using: .utf8) else {
                throw AdditionalDataError.encodingError
            }
            XCTAssert(count == pathData.count)
            return pathData
        }) else {
            XCTFail("Failed to read central directory structure."); return
        }
        let lfhBytes: [UInt8] = [0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x08, 0x08,
                                 0x08, 0x00, 0xab, 0x85, 0x77, 0x47, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        guard let lfh = Entry.LocalFileHeader(data: Data(lfhBytes),
                                              additionalDataProvider: { _ -> Data in return Data() })
        else {
            XCTFail("Failed to read local file header."); return
        }
        guard let entry = Entry(centralDirectoryStructure: cds, localFileHeader: lfh) else {
            XCTFail("Failed to create test entry."); return
        }
        let attributes = FileManager.attributes(from: entry)
        guard let permissions = attributes[.posixPermissions] as? UInt16 else {
            XCTFail("Failed to read file attributes."); return
        }
        XCTAssert(permissions == defaultDirectoryPermissions)
    }

    func testSymlinkPermissionsTransferErrorConditions() {
        let fileManager = FileManager()
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        do {
            try fileManager.setAttributes([:], ofItemAtURL: assetURL, traverseLink: false)
        } catch let error as Entry.EntryError {
            XCTAssert(error == Entry.EntryError.missingPermissionsAttributeError)
        } catch {
            XCTFail("Unexpected error while trying to transfer symlink attributes")
        }
        let permissions = NSNumber(value: Int16(0o753))
        let tempPath = NSTemporaryDirectory()
        var nonExistantURL = URL(fileURLWithPath: tempPath)
        nonExistantURL.appendPathComponent("invalid.path")
        do {
            try fileManager.setAttributes([.posixPermissions: permissions],
                                          ofItemAtURL: nonExistantURL, traverseLink: false)
        } catch let error as POSIXError {
            XCTAssert(error.code == .ENOENT)
        } catch {
            XCTFail("Unexpected error while trying to transfer symlink attributes")
        }
        do {
            try fileManager.setAttributes([.posixPermissions: permissions],
                                          ofItemAtURL: assetURL, traverseLink: false)
        } catch let error as Entry.EntryError {
            XCTAssert(error == Entry.EntryError.missingModificationDateAttributeError)
        } catch {
            XCTFail("Unexpected error while trying to transfer symlink attributes")
        }
        do {
            try fileManager.setAttributes([.posixPermissions: permissions, .modificationDate: Date()],
                                          ofItemAtURL: nonExistantURL, traverseLink: false)
        } catch let error as POSIXError {
            XCTAssert(error.code == .ENOENT)
        } catch {
            XCTFail("Unexpected error while trying to transfer symlink attributes")
        }
    }

    func testSymlinkModificationDateTransferErrorConditions() {
        let fileManager = FileManager()
        var assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let tempPath = NSTemporaryDirectory()
        var nonExistantURL = URL(fileURLWithPath: tempPath)
        nonExistantURL.appendPathComponent("invalid.path")
        do {
            try fileManager.setSymlinkModificationDate(Date(),
                                                       ofItemAtURL: nonExistantURL)
        } catch let error as POSIXError {
            XCTAssert(error.code == .ENOENT)
        } catch {
            XCTFail("Unexpected error while trying to transfer symlink attributes")
        }
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        do {
            var resourceValues = URLResourceValues()
            resourceValues.isUserImmutable = true
            try? assetURL.setResourceValues(resourceValues)
            defer {
                resourceValues.isUserImmutable = false
                try? assetURL.setResourceValues(resourceValues)
            }
            try fileManager.setSymlinkModificationDate(Date(),
                                                       ofItemAtURL: assetURL)
        } catch let error as POSIXError {
            XCTAssert(error.code == .EPERM)
        } catch {
            XCTFail("Unexpected error while trying to transfer symlink attributes")
        }
#endif
    }

    func testFilePermissionHelperMethods() {
        var permissions = FileManager.permissions(for: UInt32(777), osType: .unix, entryType: .file)
        XCTAssert(permissions == defaultFilePermissions)
        permissions = FileManager.permissions(for: UInt32(0), osType: .msdos, entryType: .file)
        XCTAssert(permissions == defaultFilePermissions)
        permissions = FileManager.permissions(for: UInt32(0), osType: .msdos, entryType: .directory)
        XCTAssert(permissions == defaultDirectoryPermissions)
    }

    func testFileModificationDateHelperMethods() {
        guard let nonFileURL = URL(string: "https://www.peakstep.com/") else {
            XCTFail("Failed to create file URL."); return
        }
        let nonExistantURL = URL(fileURLWithPath: "/nonexistant")
        do {
            _ = try FileManager.fileModificationDateTimeForItem(at: nonFileURL)
            _ = try FileManager.fileModificationDateTimeForItem(at: nonExistantURL)
        } catch let error as CocoaError {
            XCTAssert(error.code == CocoaError.fileReadNoSuchFile)
        } catch {
            XCTFail("Unexpected error while trying to retrieve file modification date")
        }
        let msDOSDate = Date(timeIntervalSince1970: TimeInterval(Int.min)).fileModificationDate
        XCTAssert(msDOSDate == 0)
        let msDOSTime = Date(timeIntervalSince1970: TimeInterval(Int.min)).fileModificationTime
        XCTAssert(msDOSTime == 0)
        let invalidEarlyMSDOSDate = Date(timeIntervalSince1970: 0).fileModificationDate
        XCTAssert(invalidEarlyMSDOSDate == 33)
        let invalidLateMSDOSDate = Date(timeIntervalSince1970: 4102444800).fileModificationDate
        XCTAssert(invalidLateMSDOSDate == 60961)
    }

    func testFileSizeHelperMethods() {
        let nonExistantURL = URL(fileURLWithPath: "/nonexistant")
        do {
            _ = try FileManager.fileSizeForItem(at: nonExistantURL)
        } catch let error as CocoaError {
            XCTAssert(error.code == CocoaError.fileReadNoSuchFile)
        } catch { XCTFail("Unexpected error while trying to retrieve file size") }
    }

    func testFileTypeHelperMethods() {
        let nonExistantURL = URL(fileURLWithPath: "/nonexistant")
        do {
            _ = try FileManager.typeForItem(at: nonExistantURL)
        } catch let error as CocoaError {
            XCTAssert(error.code == CocoaError.fileReadNoSuchFile)
        } catch {
            XCTFail("Unexpected error while trying to retrieve file type")
        }
        guard let nonFileURL = URL(string: "https://www.peakstep.com") else {
            XCTFail("Failed to create test URL."); return
        }
        do {
            _ = try FileManager.typeForItem(at: nonFileURL)
        } catch let error as CocoaError {
            XCTAssert(error.code == CocoaError.fileReadNoSuchFile)
        } catch {
            XCTFail("Unexpected error while trying to retrieve file type")
        }
    }

    func testFileModificationDate() {
        var testDateComponents = DateComponents()
        testDateComponents.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        testDateComponents.timeZone = TimeZone(identifier: "UTC")
        testDateComponents.year = 2000
        testDateComponents.month = 1
        testDateComponents.day = 1
        testDateComponents.hour = 12
        testDateComponents.minute = 30
        testDateComponents.second = 10
        guard let testDate = testDateComponents.date else {
            XCTFail("Failed to create test date/timestamp"); return
        }
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let fileManager = FileManager()
        let archive = self.archive(for: #function, mode: .create)
        do {
            try fileManager.setAttributes([.modificationDate: testDate], ofItemAtPath: assetURL.path)
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL)
            guard let entry = archive["\(assetURL.lastPathComponent)"] else {
                throw Archive.ArchiveError.unreadableArchive
            }
            guard let fileDate = entry.fileAttributes[.modificationDate] as? Date else {
                throw CocoaError(CocoaError.fileReadUnknown)
            }
            let currentTimeInterval = testDate.timeIntervalSinceReferenceDate
            let fileTimeInterval = fileDate.timeIntervalSinceReferenceDate
            // ZIP uses MSDOS timestamps, which provide very poor accuracy
            // https://blogs.msdn.microsoft.com/oldnewthing/20151030-00/?p=91881
            XCTAssertEqual(currentTimeInterval, fileTimeInterval, accuracy: 2.0)
        } catch { XCTFail("Failed to test last file modification date") }
    }

    func testPOSIXPermissions() {
        let permissions = NSNumber(value: Int16(0o753))
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let fileManager = FileManager()
        let archive = self.archive(for: #function, mode: .create)
        do {
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: assetURL.path)
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL)
            guard let entry = archive["\(assetURL.lastPathComponent)"] else {
                throw Archive.ArchiveError.unreadableArchive
            }
            guard let filePermissions = entry.fileAttributes[.posixPermissions] as? NSNumber else {
                throw CocoaError(CocoaError.fileReadUnknown)
            }
            XCTAssert(permissions.int16Value == filePermissions.int16Value)
        } catch { XCTFail("Failed to test POSIX permissions") }
    }
}
