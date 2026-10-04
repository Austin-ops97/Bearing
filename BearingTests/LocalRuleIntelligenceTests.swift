import Foundation
import Testing
@testable import Bearing

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
}
