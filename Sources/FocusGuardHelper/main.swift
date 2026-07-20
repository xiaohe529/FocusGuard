import Foundation
import FocusGuardHelperShared

let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
let delegate = HelperServiceDelegate()
listener.delegate = delegate
listener.resume()

RunLoop.main.run()