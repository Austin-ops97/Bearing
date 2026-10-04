import Foundation
import Testing
@testable import Bearing

struct PlanningEngineTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func workloadIncludesActionsEventsAndPreparation() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let action = BearingAction(
            title: "Rounds",
            priority: .today,
            dueAt: day,
            estimatedDurationMinutes: 30,
            timing: .flexible
        )
        let event = BearingCalendarEvent(
            title: "Meeting",
            startAt: day,
            endAt: day.addingTimeInterval(60 * 60),
            preparationMinutes: 20,
            transitionMinutes: 10
        )

        let summary = PlanningEngine.summary(
            actions: [action],
            events: [event],
            on: day,
            availableMinutes: 8 * 60,
            calendar: calendar
        )

        #expect(summary.actionCount == 1)
        #expect(summary.eventCount == 1)
        #expect(summary.estimatedWorkMinutes == 120)
        #expect(summary.isFeasible)
    }

    @Test func planReportsOverCapacityRatherThanHidingIt() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let action = BearingAction(title: "Long task", priority: .today, dueAt: day, estimatedDurationMinutes: 540)
        let summary = PlanningEngine.summary(actions: [action], events: [], on: day, availableMinutes: 480, calendar: calendar)

        #expect(!summary.isFeasible)
        #expect(summary.overCapacityMinutes == 60)
        #expect(PlanningEngine.intensity(for: summary) == .overloaded)
    }
}
