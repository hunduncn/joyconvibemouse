import AppKit
import Foundation

// Match both identity and location: never quit an unrelated checkout or app.
let paths = Set(CommandLine.arguments.dropFirst().map {
    URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
})
let apps = NSRunningApplication.runningApplications(
    withBundleIdentifier: "com.aqxp.JoyConVibeRemote"
).filter {
    guard let url = $0.bundleURL else { return false }
    return paths.contains(url.resolvingSymlinksInPath().path)
}
for app in apps where !app.isTerminated {
    _ = app.terminate()
}
let deadline = Date().addingTimeInterval(8)
while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
if apps.contains(where: { !$0.isTerminated }) {
    fputs("Please quit Joy-Con Vibe Remote and retry. The installed app has not been replaced.\n", stderr)
    exit(1)
}
