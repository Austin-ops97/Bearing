import Foundation
import Testing
@testable import Cailyn

struct AttentionEngineTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func immediateActionAlwaysRequiresAttention() {
        let action = CailynAction(title: "Critical check", priority: .immediate)
        #expect(AttentionEngine.requiresAttention(action, now: now))
    }

    @Test func completedActionNeverRequiresAttention() {
        let action = CailynAction(title: "Done", priority: .immediate, status: .complete)
        #expect(!AttentionEngine.requiresAttention(action, now: now))
    }

    @Test func waitingItemResurfacesAtFollowUpTime() {
        let action = CailynAction(
            title: "Confirmation",
            priority: .planned,
            status: .waiting,
            followUpAt: now.addingTimeInterval(-1),
            waitingSince: now.addingTimeInterval(-86_400)
        )
        #expect(AttentionEngine.requiresAttention(action, now: now))
    }

    @Test func futureWaitingItemStaysQuiet() {
        let action = CailynAction(
            title: "Confirmation",
            priority: .planned,
            status: .waiting,
            followUpAt: now.addingTimeInterval(3_600),
            waitingSince: now
        )
        #expect(!AttentionEngine.requiresAttention(action, now: now))
    }
}

