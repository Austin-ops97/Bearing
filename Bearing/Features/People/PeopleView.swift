import SwiftData
import SwiftUI

struct PeopleView: View {
    @Query(sort: \BearingPerson.displayName) private var people: [BearingPerson]

    var body: some View {
        ZStack {
            PaperBackground()
            List(people) { person in
                NavigationLink { PersonDetailView(person: person) } label: {
                    HStack(spacing: 14) {
                        Monogram(name: person.displayName)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(person.displayName).font(.headline)
                            Text([person.role, person.organization].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        let open = person.actions.filter { $0.status != .complete }.count
                        if open > 0 { Text("\(open)").font(.system(.caption, design: .monospaced, weight: .bold)).foregroundStyle(BearingTheme.olive) }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("PEOPLE")
    }
}

private struct Monogram: View {
    let name: String
    private var initials: String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() }
    var body: some View {
        Text(initials)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .frame(width: 38, height: 38)
            .background(BearingTheme.oliveSoft.opacity(0.7), in: Circle())
            .foregroundStyle(BearingTheme.graphite)
            .accessibilityHidden(true)
    }
}

private struct PersonDetailView: View {
    let person: BearingPerson
    private var openItems: [BearingAction] { person.actions.filter { $0.status != .complete && $0.status != .waiting } }
    private var waiting: [BearingAction] { person.actions.filter { $0.status == .waiting } }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(person.displayName).font(.system(.largeTitle, design: .serif, weight: .semibold))
                        Text([person.role, person.organization].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                    }
                    PersonActionSection(title: "OPEN ITEMS", actions: openItems, empty: "Nothing owed to this person.")
                    PersonActionSection(title: "WAITING ON", actions: waiting, empty: "Nothing currently waiting.")
                    if let email = person.email {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(title: "CONTACT")
                            Link(destination: URL(string: "mailto:\(email)")!) { Label(email, systemImage: "envelope") }
                        }
                    }
                }
                .padding(22).frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("PERSON")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PersonActionSection: View {
    let title: String
    let actions: [BearingAction]
    let empty: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: title)
            if actions.isEmpty { Text(empty).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 14) }
            ForEach(actions) { ActionSummaryRow(action: $0) }
        }
    }
}

