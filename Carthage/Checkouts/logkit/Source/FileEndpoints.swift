// FileEndpoints.swift
//
// Copyright (c) 2015, Justin Pawela & The LogKit Project (http://www.logkit.info/)
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

import Foundation


/// The default file to use when logging: `log.txt`
private let defaultLogFileURL: NSURL? = LK_DEFAULT_LOG_DIRECTORY?.URLByAppendingPathComponent("log.txt", isDirectory: false)

/// A private UTC-based calendar used in date comparisons.
private let UTCCalendar: NSCalendar = {
//TODO: this is a cheap hack because .currentCalendar() compares dates based on local TZ
    let cal = NSCalendar.currentCalendar().copy() as! NSCalendar
    cal.timeZone = NSTimeZone(forSecondsFromGMT: 0)
    return cal
}()


private extension NSFileManager {

    /**
    Attempts to read a given file's metadata and convert it to an `LXFileProperties` instance.

    - parameter path: The path of the file to be examined.

    - throws: If the attributes of file cannot be read.

    - returns: An `LXFileProperties` instance if successful.
    */
    private func propertiesOfFileAtPath(path: String) throws -> LXFileProperties {
        let attributes = try NSFileManager.defaultManager().attributesOfItemAtPath(path)
        return LXFileProperties(
            size: (attributes[NSFileSize] as? NSNumber)?.unsignedLongLongValue,
            modified: (attributes[NSFileModificationDate] as? NSDate)?.timeIntervalSinceReferenceDate
        )
    }

}


/**
A collection of properties representing file metadata.

- parameter size: The size of the file in bytes.
- parameter modified: An `NSTimeInterval` representing the file's modification timestamp.
*/
private struct LXFileProperties {
    let size: UIntMax?
    let modified: NSTimeInterval?
}


//MARK: Log File Wrapper

/// A wrapper for a log file.
private class LXLogFile {

    private let lockQueue: dispatch_queue_t = dispatch_queue_create("logFile-Lock", DISPATCH_QUEUE_SERIAL)
    private let handle: NSFileHandle
    private let path: String
    private var privateByteCounter: UIntMax?
    private var privateModificationTracker: NSTimeInterval?

    /**
    Initialize a log file. May return `nil` if the file cannot be accessed.

    - parameter URL: The URL of the log file.
    - parameter shouldAppend: Indicates whether new data should be appended to existing data in the file, or if the file should
    be truncated when opened.
    */
    init?(URL: NSURL, shouldAppend: Bool) {
        guard NSFileManager.defaultManager().ensureFileAtURL(URL, withIntermediateDirectories: true),
        let path = URL.path, handle = NSFileHandle(forWritingAtPath: path) else {
            assertionFailure("Error opening log file at URL '\(URL.absoluteString)'; is URL valid?")
            self.path = ""
            self.handle = NSFileHandle.fileHandleWithNullDevice()
            self.handle.closeFile()
            return nil
        }
        self.path = path
        self.handle = handle
        if shouldAppend {
            self.privateByteCounter = UIntMax(self.handle.seekToEndOfFile())
        } else {
            self.handle.truncateFileAtOffset(0)
            self.privateByteCounter = 0
        }
        do {
            try self.privateModificationTracker = NSFileManager.defaultManager().propertiesOfFileAtPath(path).modified
        } catch {}
    }

    /// Clean up.
    deinit {
        dispatch_barrier_sync(self.lockQueue, {
            self.handle.synchronizeFile()
            self.handle.closeFile()
        })
    }

    /// The size of this log file in bytes.
    var sizeInBytes: UIntMax? {
        var size: UIntMax?
        dispatch_sync(self.lockQueue, { size = self.privateByteCounter })
        return size
    }

    /// The date when this log file was last modified.
    var modificationDate: NSDate? {
        var interval: NSTimeInterval?
        dispatch_sync(self.lockQueue, { interval = self.privateModificationTracker })
        return interval == nil ? nil : NSDate(timeIntervalSinceReferenceDate: interval!)
    }

//    private var properties: LXFileProperties? {
//        var props: LXFileProperties?
//        dispatch_sync(self.lockQueue, {
//            do { props = try NSFileManager.defaultManager().propertiesOfFileAtPath(self.path) } catch {}
//        })
//        return props
//    }

    /// Write data to this log file.
    func writeData(data: NSData) {
        dispatch_async(self.lockQueue, {
            self.handle.writeData(data)
            self.privateByteCounter = (self.privateByteCounter ?? 0) + UIntMax(data.length)
            self.privateModificationTracker = CFAbsoluteTimeGetCurrent()
        })
    }

    /// Empty this log file. Future writes will start from the the beginning of the file.
    func reset() {
        dispatch_sync(self.lockQueue, {
            self.handle.synchronizeFile()
            self.handle.truncateFileAtOffset(0)
            self.privateByteCounter = 0
            self.privateModificationTracker = CFAbsoluteTimeGetCurrent()
        })
    }

}


//MARK: Rotating File Endpoint

/**
An Endpoint that writes Log Entries to a set of numbered files. Once a file has reached its maximum file size, the Endpoint
automatically rotates to the next file in the set.
*/
public class LXRotatingFileEndpoint: LXEndpoint {
    /// The minimum Priority Level a Log Entry must meet to be accepted by this Endpoint.
    public var minimumPriorityLevel: LXPriorityLevel
    /// The formatter used by this Endpoint to serialize a Log Entry’s `dateTime` property to a string.
    public var dateFormatter: LXDateFormatter
    /// The formatter used by this Endpoint to serialize each Log Entry to a string.
    public var entryFormatter: LXEntryFormatter
    /// This Endpoint requires a newline character appended to each serialized Log Entry string.
    public let requiresNewlines: Bool = true

    /// The URL of the directory of the log files.
    private let directoryURL: NSURL
    /// The base file name of the log files.
    private let baseFileName: String
    /// The maximum allowed file size in bytes.
    private let maxFileSizeBytes: UIntMax
    /// The number of files to include in the rotating set.
    private let numberOfFiles: UInt
    /// The index of the current file from the rotating set.
    private lazy var currentIndex: UInt = {
        let startingFile: (index: UInt, modified: NSTimeInterval) = Array(1...self.numberOfFiles).reduce((1, 0), combine: {
            if let path = self.URLForIndex($1).path {
                do {
                    let props = try NSFileManager.defaultManager().propertiesOfFileAtPath(path)
                    if let modified = props.modified where modified > $0.1 {
                        return (index: $1, modified: modified)
                    }
                } catch {}
            }
            return $0
        })
        return startingFile.index
    }()
    /// The file currently being written to.
    private lazy var currentFile: LXLogFile? = {
        guard let file = LXLogFile(URL: self.currentURL, shouldAppend: true) else {
            assertionFailure("Could not open the log file at URL '\(self.currentURL.absoluteString)'")
            return nil
        }
        return file
    }()

    /**
    Initialize a rotating file endpoint. If the specified file cannot be opened, or if the index-prepended URL evaluates to `nil`,
    the initializer may fail.

    - parameter baseURL: (optional) The URL used to build the rotating file set’s file URLs. Each file's index number will be
    prepended to the last path component of this URL. Defaults to `Application Support/{bundleID}/logs/{number}_log.txt`.
    - parameter numberOfFiles: (optional) The number of files to be used in the rotation. Defaults to `5`.
    - parameter maxFileSizeKiB: (optional) The maximum file size of each file in the rotation, specified in kilobytes. Defaults
    to `1024`.
    - parameter minimumPriorityLevel: (optional) The minimum Priority Level a Log Entry must meet to be accepted by this Endpoint.
    Defaults to `.All`.
    - parameter dateFormatter: (optional) The formatter used by this Endpoint to serialize a Log Entry’s `dateTime` property to a
    string. Defaults to `.standardFormatter()`.
    - parameter entryFormatter: (optional) The formatter used by this Endpoint to serialize each Log Entry to a string. Defaults
    to `.standardFormatter()`.
    */
    public init?(
        baseURL: NSURL? = defaultLogFileURL,
        numberOfFiles: UInt = 5,
        maxFileSizeKiB: UInt = 1024,
        minimumPriorityLevel: LXPriorityLevel = .All,
        dateFormatter: LXDateFormatter = LXDateFormatter.standardFormatter(),
        entryFormatter: LXEntryFormatter = LXEntryFormatter.standardFormatter()
    ) {
        self.dateFormatter = dateFormatter
        self.entryFormatter = entryFormatter
        self.maxFileSizeBytes = UIntMax(maxFileSizeKiB) * 1024
        self.numberOfFiles = numberOfFiles
        //TODO: check file or directory to predict if file is accessible
        guard let dirURL = baseURL?.URLByDeletingLastPathComponent, filename = baseURL?.lastPathComponent else {
            assertionFailure("The log file URL '\(baseURL?.absoluteString ?? String())' is invalid")
            self.minimumPriorityLevel = .None
            self.directoryURL = NSURL(string: "")!
            self.baseFileName = ""
            return nil
        }
        self.minimumPriorityLevel = minimumPriorityLevel
        self.directoryURL = dirURL
        self.baseFileName = filename
    }

    /// The index of the next file in the rotation.
    private var nextIndex: UInt { return self.currentIndex + 1 > self.numberOfFiles ? 1 : self.currentIndex + 1 }
    /// The URL of the currently selected file.
    private var currentURL: NSURL { return self.URLForIndex(self.currentIndex) }
    /// The URL of the next file in the rotation.
    private var nextURL: NSURL { return self.URLForIndex(self.nextIndex) }

    /// The URL for the file at a given index.
    private func URLForIndex(index: UInt) -> NSURL {
        return self.directoryURL.URLByAppendingPathComponent(self.fileNameForIndex(index), isDirectory: false)
    }

    /// The name for the file at a given index.
    private func fileNameForIndex(index: UInt) -> String {
        let format = "%0\(Int(floor(log10(Double(self.numberOfFiles)) + 1.0)))d"
        return "\(String(format: format, index))_\(self.baseFileName)"
    }

    /// Writes a serialized Log Entry string to the currently selected file.
    public func write(string: String) {
        if let data = string.dataUsingEncoding(NSUTF8StringEncoding) {
            //TODO: might pass test but file fills before write
            if let nextFile = self.rotateToFileBeforeWritingDataWithLength(data.length) {
                self.currentFile = nextFile
                self.currentIndex = self.nextIndex
            }
            self.currentFile?.writeData(data)
        } else {
            assertionFailure("Failure to create data from entry string")
        }
    }

    /// Clears the currently selected file and begins writing again at its beginning.
    public func resetCurrentFile() {
        self.currentFile?.reset()
    }

    /**
    This method provides an opportunity to determine whether a new log file should be selected before writing the next Log Entry.

    - parameter length: The length of the data (number of bytes) that will be written next.

    - returns: A new log file to write this data to, or `nil` if the endpoint should continue using the existing file.
    */
    private func rotateToFileBeforeWritingDataWithLength(length: Int) -> LXLogFile? {
        switch self.currentFile?.sizeInBytes {
        case .Some(let size) where size + UIntMax(length) > self.maxFileSizeBytes:  // Won't fit in current file
            fallthrough
        case .None:                                                                 // Can't determine size of current file
            return LXLogFile(URL: self.nextURL, shouldAppend: false)
        case .Some:                                                                 // Will fit in current file
            return nil
        }
    }

}


//MARK: File Endpoint

/// An Endpoint that writes Log Entries to a specified file.
public class LXFileEndpoint: LXRotatingFileEndpoint {

    /**
    Initialize a File Endpoint. If the specified file cannot be opened, or if the URL evaluates to `nil`, the initializer may
    fail.

    - parameter fileURL: (optional) The URL of the log file. Defaults to `Application Support/{bundleID}/logs/log.txt`.
    - parameter shouldAppend: (optional) Indicates whether the Endpoint should continue appending Log Entries to the end of the
    file, or clear it and start at the beginning. Defaults to `true`.
    - parameter minimumPriorityLevel: (optional) The minimum Priority Level a Log Entry must meet to be accepted by this Endpoint.
    Defaults to `.All`.
    - parameter dateFormatter: (optional) The formatter used by this Endpoint to serialize a Log Entry’s `dateTime` property to a
    string. Defaults to `.standardFormatter()`.
    - parameter entryFormatter: (optional) The formatter used by this Endpoint to serialize each Log Entry to a string. Defaults
    to `.standardFormatter()`.
    */
    public init?(
        fileURL: NSURL? = defaultLogFileURL,
        shouldAppend: Bool = true,
        minimumPriorityLevel: LXPriorityLevel = .All,
        dateFormatter: LXDateFormatter = LXDateFormatter.standardFormatter(),
        entryFormatter: LXEntryFormatter = LXEntryFormatter.standardFormatter()
    ) {
        super.init(
            baseURL: fileURL,
            numberOfFiles: 1,
            maxFileSizeKiB: 0,
            minimumPriorityLevel: minimumPriorityLevel,
            dateFormatter: dateFormatter,
            entryFormatter: entryFormatter
        )
    }

    /// This endpoint always uses `baseFileName` as its file name.
    private override func fileNameForIndex(index: UInt) -> String {
        return self.baseFileName
    }

    /// This endpoint will never rotate files.
    private override func rotateToFileBeforeWritingDataWithLength(length: Int) -> LXLogFile? {
        return nil
    }

}


//MARK: Dated File Endpoint

/**
An Endpoint that writes Log Enties to a dated file. A datestamp will be prepended to the file's name. The file rotates
automatically at midnight UTC.
*/
public class LXDatedFileEndpoint: LXRotatingFileEndpoint {

    /// The formatter used for datestamp preparation.
    private let nameFormatter = LXDateFormatter.dateOnlyFormatter()

    /**
    Initialize a Dated File Endpoint. If the specified file cannot be opened, or if the datestamp-prepended URL evaluates to
    `nil`, the initializer may fail.

    - parameter baseURL: (optional) The URL used to build the date files’ URLs. Today's date will be prepended to the last path
    component of this URL. Defaults to `Application Support/{bundleID}/logs/{datestamp}_log.txt`.
    - parameter minimumPriorityLevel: (optional) The minimum Priority Level a Log Entry must meet to be accepted by this Endpoint.
    Defaults to `.All`.
    - parameter dateFormatter: (optional) The formatter used by this Endpoint to serialize a Log Entry’s `dateTime` property to a
    string. Defaults to `.standardFormatter()`.
    - parameter entryFormatter: (optional) The formatter used by this Endpoint to serialize each Log Entry to a string. Defaults
    to `.standardFormatter()`.
    */
    public init?(
        baseURL: NSURL? = defaultLogFileURL,
        minimumPriorityLevel: LXPriorityLevel = .All,
        dateFormatter: LXDateFormatter = LXDateFormatter.standardFormatter(),
        entryFormatter: LXEntryFormatter = LXEntryFormatter.standardFormatter()
    ) {
        super.init(
            baseURL: baseURL,
            numberOfFiles: 1,
            maxFileSizeKiB: 0,
            minimumPriorityLevel: minimumPriorityLevel,
            dateFormatter: dateFormatter,
            entryFormatter: entryFormatter
        )
    }

    /// The name for the file with today's date.
    private override func fileNameForIndex(index: UInt) -> String {
        return "\(self.nameFormatter.stringFromDate(NSDate()))_\(self.baseFileName)"
    }

    /// Returns `nil` if the current file still corresponds to today's date, or a new log file if the date has changed.
    private override func rotateToFileBeforeWritingDataWithLength(length: Int) -> LXLogFile? {
        switch self.currentFile?.modificationDate {
        case .Some(let modificationDate) where !UTCCalendar.isDateSameAsToday(modificationDate):    // Wrong date
            fallthrough
        case .None:                                                                                 // Can't determine the date
            return LXLogFile(URL: self.nextURL, shouldAppend: false)
        case .Some:                                                                                 // Correct date
            return nil
        }
    }

}
