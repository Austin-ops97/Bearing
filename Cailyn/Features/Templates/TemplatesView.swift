import SwiftData
import SwiftUI

struct TemplatesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CailynTemplate.title) private var templates: [CailynTemplate]
    @State private var showsNewTemplate = false
    @State private var selection = Set<UUID>()
    @State private var pendingDeletion = Set<UUID>()
    @State private var confirmsDeletion = false

    var body: some View {
        ZStack {
            PaperBackground()
            if templates.isEmpty {
                ContentUnavailableView {
                    Label("No Templates", systemImage: "rectangle.3.group")
                } description: {
                    Text("Build reusable forms and checklists for repeatable work.")
                } actions: {
                    Button("Build Template") { showsNewTemplate = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List(templates, selection: $selection) { template in
                    NavigationLink { TemplateDetailView(template: template) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(template.title).font(.headline)
                            Text("\(template.category) · \(template.fields.count) fields")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7)
                    }
                    .tag(template.id)
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("TEMPLATES")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !selection.isEmpty {
                    Button(role: .destructive) {
                        pendingDeletion = selection
                        confirmsDeletion = true
                    } label: { Label("Delete Selected", systemImage: "trash") }
                }
                EditButton()
                Button { showsNewTemplate = true } label: { Label("New Template", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showsNewTemplate) { NewTemplateView() }
        .confirmationDialog("Delete \(pendingDeletion.count) template\(pendingDeletion.count == 1 ? "" : "s")?", isPresented: $confirmsDeletion) {
            Button("Delete", role: .destructive, action: deletePending)
            Button("Cancel", role: .cancel) { pendingDeletion.removeAll() }
        } message: { Text("This permanently removes the selected template definitions.") }
    }

    private func deletePending() {
        templates.filter { pendingDeletion.contains($0.id) }.forEach(context.delete)
        try? context.save()
        selection.subtract(pendingDeletion)
        pendingDeletion.removeAll()
    }
}

private struct NewTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var category = "General"
    @State private var instructions = ""
    @State private var fieldLines = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    TextField("Name", text: $title)
                    TextField("Category", text: $category)
                    TextField("Purpose or instructions", text: $instructions, axis: .vertical).lineLimit(2...6)
                }
                Section {
                    TextEditor(text: $fieldLines).frame(minHeight: 180)
                } header: { Text("Fields") } footer: {
                    Text("Enter one field or checklist item per line. You can revise these later.")
                }
            }
            .navigationTitle("New Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func save() {
        let fields = fieldLines.split(whereSeparator: \.isNewline).map(String.init)
        context.insert(CailynTemplate(title: title.trimmingCharacters(in: .whitespacesAndNewlines), category: category, instructions: instructions, fields: fields))
        try? context.save()
        dismiss()
    }
}

struct TemplateDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var template: CailynTemplate

    var body: some View {
        Form {
            Section("Template") {
                TextField("Name", text: $template.title)
                TextField("Category", text: $template.category)
                TextField("Purpose or instructions", text: $template.instructions, axis: .vertical).lineLimit(2...8)
            }
            Section {
                TextEditor(text: $template.fieldLines).frame(minHeight: 220)
            } header: { Text("Fields") } footer: { Text("One field or checklist item per line.") }
        }
        .navigationTitle(template.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            template.modifiedAt = .now
            try? context.save()
        }
    }
}
