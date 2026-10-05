import SwiftData
import SwiftUI

struct PeopleView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CailynPerson.displayName) private var people: [CailynPerson]
    @State private var selection = Set<UUID>()
    @State private var pendingDeletion = Set<UUID>()
    @State private var showsDeleteConfirmation = false
    @State private var showsNewPerson = false

    var body: some View {
        ZStack {
            PaperBackground()
            if people.isEmpty {
                ContentUnavailableView {
                    Label("No People", systemImage: "person.2")
                } description: {
                    Text("Add people to connect owners and follow-ups to your work.")
                } actions: {
                    Button("Add Person") { showsNewPerson = true }.buttonStyle(.borderedProminent)
                }
            } else { List(people, selection: $selection) { person in
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
                        if open > 0 { Text("\(open)").font(.system(.caption, design: .monospaced, weight: .bold)).foregroundStyle(CailynTheme.champagne) }
                    }
                    .padding(.vertical, 6)
                }
                .tag(person.id)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("PEOPLE")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !selection.isEmpty {
                    Button(role: .destructive) {
                        pendingDeletion = selection
                        showsDeleteConfirmation = true
                    } label: { Label("Delete Selected", systemImage: "trash") }
                }
                EditButton()
                Button { showsNewPerson = true } label: { Label("Add Person", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showsNewPerson) { NewPersonView() }
        .confirmationDialog(
            "Delete \(pendingDeletion.count) person\(pendingDeletion.count == 1 ? "" : "s")?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deletePending)
            Button("Cancel", role: .cancel) { pendingDeletion.removeAll() }
        } message: {
            Text("Their actions remain in Cailyn, but will no longer be linked to them.")
        }
    }

    private func deletePending() {
        people.filter { pendingDeletion.contains($0.id) }.forEach(context.delete)
        try? context.save()
        selection.subtract(pendingDeletion)
        pendingDeletion.removeAll()
    }
}

private struct NewPersonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var role = ""
    @State private var organization = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $name)
                    TextField("Role", text: $role)
                    TextField("Organization", text: $organization)
                }
                Section("Contact") {
                    TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                    TextField("Phone", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                }
                Section("Notes") { TextEditor(text: $notes).frame(minHeight: 120) }
            }
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func save() {
        context.insert(CailynPerson(
            displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.nilIfBlank,
            phone: phone.nilIfBlank,
            organization: organization.nilIfBlank,
            role: role.nilIfBlank,
            notes: notes
        ))
        try? context.save()
        dismiss()
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct Monogram: View {
    let name: String
    private var initials: String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() }
    var body: some View {
        Text(initials)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .frame(width: 38, height: 38)
            .background(CailynTheme.champagneMuted.opacity(0.7), in: Circle())
            .foregroundStyle(CailynTheme.graphite)
            .accessibilityHidden(true)
    }
}

struct PersonDetailView: View {
    let person: CailynPerson
    private var openItems: [CailynAction] { person.actions.filter { $0.status != .complete && $0.status != .waiting } }
    private var waiting: [CailynAction] { person.actions.filter { $0.status == .waiting } }

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
    let actions: [CailynAction]
    let empty: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: title)
            if actions.isEmpty { Text(empty).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 14) }
            ForEach(actions) { ActionSummaryRow(action: $0) }
        }
    }
}
