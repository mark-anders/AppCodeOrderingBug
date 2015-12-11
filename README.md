# AppCode, CocoaLumberjack, LogKit Ordering Bug
This iOS XCode Swift project illustrates an issue where log messages
get out of order when run under AppCode.

This repo has all of the files checked in - including Pods and Carthage build
outputs, so you should be able to just build and run in either XCode (7.1 used)
or AppCode (3.3.2 used)

What the app does is, on startup, outputs the various log level messages for LogKit, followed
by ones for CocoaLumberjack.

*(Note: I ran into this because I'm switching from CocoaLumberjack to LogKit, which looks
great, and has an easy to use synchronous option, which I like for debugging.)*

The basic code looks like:

```Swift
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
```
When run under XCode the output in the console should have the correct order like this:
```
14:36:47.505[AppDelegate.swift:14] DEBUG::LogKit debug
14:36:47.512[AppDelegate.swift:15] INFO::LogKit info
14:36:47.512[AppDelegate.swift:16] NOTICE::LogKit notice
14:36:47.513[AppDelegate.swift:17] WARNING::LogKit warning
14:36:47.513[AppDelegate.swift:18] ERROR::LogKit error
14:36:47.513[AppDelegate.swift:19] CRITICAL::LogKit critical
07:36:47.513 [AppDelegate.swift:20] DEBUG::CocoaLumberjack debug
07:36:47.513 [AppDelegate.swift:21] INFO::CocoaLumberjack info
07:36:47.513 [AppDelegate.swift:22] VERBOSE::CocoaLumberjack notice
07:36:47.513 [AppDelegate.swift:23] WARNING::CocoaLumberjack warning
07:36:47.513 [AppDelegate.swift:24] ERROR::CocoaLumberjack error
```

Under AppCode, the output can get jumbled, such as this:

```
Simulator session started with process 91960
07:32:28.924 [AppDelegate.swift:20] DEBUG::CocoaLumberjack debug
14:32:28.917[AppDelegate.swift:14] DEBUG::LogKit debug
07:32:28.924 [AppDelegate.swift:21] INFO::CocoaLumberjack info
14:32:28.924[AppDelegate.swift:15] INFO::LogKit info
07:32:28.924 [AppDelegate.swift:22] VERBOSE::CocoaLumberjack notice
14:32:28.924[AppDelegate.swift:16] NOTICE::LogKit notice
07:32:28.924 [AppDelegate.swift:23] WARNING::CocoaLumberjack warning
14:32:28.924[AppDelegate.swift:17] WARNING::LogKit warning
07:32:28.924 [AppDelegate.swift:24] ERROR::CocoaLumberjack error
14:32:28.924[AppDelegate.swift:18] ERROR::LogKit error
14:32:28.924[AppDelegate.swift:19] CRITICAL::LogKit critical

```
Hopefully, this will help in tracking down the bug.