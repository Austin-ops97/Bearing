import Foundation
import Testing
@testable import Cailyn

struct LocalRuleIntelligenceTests {
    @Test func extractsKnownPersonAndAssetWithoutNetwork() async {
        let service = LocalRuleIntelligenceService()
        let proposal = await service.proposeAction(
            from: "Check with Mike Wednesday about Yankee 3's charger.",
            people: ["Mike Thompson"],
            assets: ["Yankee 3"],
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(proposal.personName == "Mike Thompson")
        #expect(proposal.assetName == "Yankee 3")
        #expect(proposal.dueAt != nil)
        #expect(proposal.status == .waiting)
    }

    @Test func voiceStyleCaptureProducesReviewableElevenAMReminder() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 8))!

        let proposal = await LocalRuleIntelligenceService().proposeAction(
            from: "Today around 11 o'clock, we need to make sure we email JP about the work flow we are working on.",
            people: [],
            assets: [],
            now: now
        )

        #expect(proposal.title == "Email JP about the workflow we are working on")
        #expect(proposal.personName == "JP")
        #expect(proposal.alertKind == .reminder)
        #expect(proposal.dueAt.map { calendar.component(.hour, from: $0) } == 11)
        #expect(proposal.interpretationNotes.contains(where: { $0.contains("approximate") }))
    }

    @Test func turnoverCleanupPreservesNegationNumbersAndCreatesActions() async {
        let source = "Um, Unit 2 is running at 48 megawatts. The battery charger did not return to service. We need to email JP tomorrow at 9 AM. Waiting on maintenance for the valve."
        let draft = await LocalRuleIntelligenceService().organizeTurnover(from: source, people: [], now: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(draft.unitStatus.contains("48 megawatts"))
        #expect(draft.completedWork.contains("did not return") || draft.unitStatus.contains("did not return") || draft.abnormalConditions.contains("did not return"))
        #expect(draft.waitingOn.contains("maintenance"))
        #expect(draft.actionCandidates.count == 1)
        #expect(draft.rawTranscript.contains("did not"))
    }

    @Test func modelNormalizationMustPreserveNumbersAndNegation() {
        #expect(HybridIntelligenceService.isSafeNormalization(
            "Email JP at 11 AM; Unit 2 did not return to service.",
            of: "At 11 AM, email JP because Unit 2 did not return to service."
        ))
        #expect(!HybridIntelligenceService.isSafeNormalization(
            "Email JP at 1 PM; Unit 2 returned to service.",
            of: "At 11 AM, email JP because Unit 2 did not return to service."
        ))
    }

    @Test func deterministicOnlyHybridMatchesAuthoritativeParser() async {
        let source = "Tomorrow at 9 AM, call Mike about Yankee 3."
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expected = await LocalRuleIntelligenceService().proposeAction(
            from: source,
            people: ["Mike Thompson"],
            assets: ["Yankee 3"],
            now: now
        )
        let actual = await HybridIntelligenceService(preference: .deterministicOnly).proposeAction(
            from: source,
            people: ["Mike Thompson"],
            assets: ["Yankee 3"],
            now: now
        )
        #expect(actual == expected)
    }
}
