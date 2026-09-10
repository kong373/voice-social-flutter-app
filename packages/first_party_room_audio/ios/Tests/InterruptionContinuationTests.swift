import Foundation

@main
enum InterruptionContinuationTests {
    static func main() {
        let id = "12345678-1234-4234-8234-123456789abc"
        var ticket = InterruptionContinuation(sessionId: id, microphone: true, deadline: 45)
        precondition(!ticket.permits(sessionId: id, microphone: true, now: 1))
        precondition(!ticket.end(shouldResume: false, now: 2))
        precondition(ticket.end(shouldResume: true, now: 3))
        precondition(ticket.permits(sessionId: id, microphone: true, now: 4))
        precondition(ticket.permits(sessionId: id, microphone: false, now: 4))
        precondition(!ticket.end(shouldResume: true, now: 5))
        precondition(!ticket.permits(sessionId: "other", microphone: true, now: 4))
        precondition(!ticket.permits(sessionId: id, microphone: true, now: 45))
        precondition(ticket.deadline == 45)
        var expired = InterruptionContinuation(sessionId: id, microphone: true, deadline: 45)
        precondition(!expired.end(shouldResume: true, now: 45))
        precondition(!expired.permits(sessionId: id, microphone: true, now: 46))
        var playback = InterruptionContinuation(sessionId: id, microphone: false, deadline: 45)
        precondition(playback.end(shouldResume: true, now: 3))
        precondition(playback.permits(sessionId: id, microphone: false, now: 4))
        precondition(!playback.permits(sessionId: id, microphone: true, now: 4))
        print("InterruptionContinuation: 14 assertions PASS")
    }
}
