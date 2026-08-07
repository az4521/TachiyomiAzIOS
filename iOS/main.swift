import UIKit

// OpenJDK Mobile initializes its statically linked VM before UIKit takes over
// the process main thread. Starting it lazily from an already-running SwiftUI
// action can abort inside HotSpot before Swift has an error to catch.
JVMSourceRuntime.prepareBeforeUIApplicationMain()

UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    nil,
    NSStringFromClass(AppDelegate.self)
)
