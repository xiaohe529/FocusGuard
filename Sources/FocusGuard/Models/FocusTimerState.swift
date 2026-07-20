import Foundation

struct FocusTimerState: Codable {
    enum Kind: String, Codable { case focus, delayedBlock }
    var kind: Kind?
    var endTimestamp: Date?
    var emergencyUsesThisMonth: Int
    var lastResetMonth: String
    var delayedBlockPendingAuth: Bool?
    var delayedBlockRetryCount: Int?
}
