import Foundation

// Not an active lease. The original deadline never changes while interrupted.
// A matching end is merely permission to ask Dart to recheck current authority.
struct InterruptionContinuation {
    let sessionId: String
    let microphone: Bool
    let deadline: TimeInterval
    private(set) var ended = false

    mutating func end(shouldResume: Bool, now: TimeInterval) -> Bool {
        guard !ended, shouldResume, now < deadline else { return false }
        ended = true
        return true
    }

    func permits(sessionId: String, microphone: Bool, now: TimeInterval) -> Bool {
        ended && self.sessionId == sessionId && now < deadline &&
            (!microphone || self.microphone)
    }
}
