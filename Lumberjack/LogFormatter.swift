//
//  LogFormatter.swift
//  DataModel
//
//  Created by Mark Anders on 8/20/15.
//  Copyright © 2015 P1vot LLC. All rights reserved.
//


import Foundation
import CocoaLumberjack.DDDispatchQueueLogFormatter

class LogFormatter: DDDispatchQueueLogFormatter {
    let df: NSDateFormatter
    
    override init() {
        df = NSDateFormatter()
        df.formatterBehavior = .Behavior10_4
        df.dateFormat = "HH:mm:ss.SSS"
        
        super.init()
    }
    
    override func formatLogMessage(logMessage: DDLogMessage!) -> String {
        let dateAndTime = df.stringFromDate(logMessage.timestamp)
        
        var logLevel: String
        var useLog = true
        var formattedLog = ""
        let logFlag:DDLogFlag  = logMessage.flag
        if logFlag.contains(.Verbose) {
            logLevel = "VERBOSE:"
        } else if logFlag.contains(.Debug) {
            logLevel = "DEBUG:"
        } else if logFlag.contains(.Info) {
            logLevel = "INFO:"
        } else if logFlag.contains(.Warning) {
            logLevel = "WARNING:"
        } else if logFlag.contains(.Error) {
            logLevel = "ERROR:"
        } else {
            logLevel = "OFF:"
            useLog = false;
        }
        if(useLog){
            let path = NSURL.fileURLWithPath(logMessage.file)
            let filename = path.lastPathComponent!
            formattedLog = "\(dateAndTime) [\(filename):\(logMessage.line)] \(logLevel):\(logMessage.message)"
        }
        
        return formattedLog;
    }
}