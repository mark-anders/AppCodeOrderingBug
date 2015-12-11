//
//  AppDelegate.swift
//  Lumberjack
//
//  Created by Mark Anders on 8/25/15.
//  Copyright © 2015 Mark Anders. All rights reserved.
//

import UIKit
import CocoaLumberjack
import LogKit

func testLogging() {
    log.debug("LogKit debug")
    log.info("LogKit info")
    log.notice("LogKit notice")
    log.warning("LogKit warning")
    log.error("LogKit error")
    log.critical("LogKit critical")
    DDLogDebug("CocoaLumberjack debug")
    DDLogInfo("CocoaLumberjack info")
    DDLogVerbose("CocoaLumberjack notice")
    DDLogWarn("CocoaLumberjack warning")
    DDLogError("CocoaLumberjack error")
}


let ddloglevel = DDLogLevel.Verbose

let log = LXLogger(endpoints: [
    
    LXConsoleEndpoint(
        synchronous: true,
        dateFormatter: LXDateFormatter.timeOnlyFormatter(),
        entryFormatter: LXEntryFormatter({ entry in
            return "\(entry.dateTime)[\(entry.fileName):\(entry.lineNumber)] " +
            "\(entry.level.uppercaseString)::\(entry.message)"
        })
    ),
    
    ])


func setupLoggers() {
    let asLogger = DDASLLogger.sharedInstance()
    asLogger.logFormatter = LogFormatter()
    DDLog.addLogger(asLogger)
    let ttyLogger = DDTTYLogger.sharedInstance()
    ttyLogger.logFormatter = LogFormatter()
    DDLog.addLogger(ttyLogger)
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // Override point for customization after application launch.
        setupLoggers()
        testLogging()
        return true
    }

    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}

