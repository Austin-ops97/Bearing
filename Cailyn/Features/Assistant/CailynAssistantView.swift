import SwiftData
import SwiftUI

struct CailynAssistantView: View {
    @Query private var actions: [CailynAction]
    @Query(sort: \CailynCalendarEvent.startAt) private var events: [CailynCalendarEvent]
    @Query private var people: [CailynPerson]
    @Query private var assets: [CailynAsset]
    @Query(sort: \CailynLogEntry.timestamp, order: .reverse) private var logs: [CailynLogEntry]
    @Query(sort: \CailynTurnoverNote.approvedAt, order: .reverse) private var turnovers: [CailynTurnoverNote]
    @Query private var knowledge: [CailynKnowledgeItem]
    @Query private var knowledgeDocuments: [CailynKnowledgeDocument]
    @Query private var knowledgeChunks: [CailynKnowledgeChunk]
    @Query private var routines: [CailynRoutine]
    @StateObject private var model = CailynLocalModelManager.shared
    @StateObject private var microsoft = MicrosoftGraphService.shared
    @State private var question = ""
    @State private var answer: String?
    @State private var sources: [String] = []
    @State private var errorMessage: String?
    @State private var isAnswering = false
    @State private var comparison: LocalModelComparison?
    @State private var secondModelID = ""

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeading(title: "PRIVATE APP KNOWLEDGE", trailing: model.isLoaded ? "\(model.selectedModel.displayName.uppercased()) READY" : "ON-DEVICE MODEL")
                        Text("Ask about your actions, events, shifts, routines, people, assets, logs, turnovers, knowledge notes, uploaded documents, and connected work records.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Cailyn retrieves only relevant records for each question. Your app data stays on-device; an answer cites the records it used and says when evidence is missing.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .cailynSurface()

                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Ask a question about your records", text: $question, axis: .vertical)
                            .lineLimit(2...5)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task { await ask() }
                        } label: {
                            Label(isAnswering ? "Searching & answering…" : "Ask Cailyn", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAnswering || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.selectedModelIsDownloaded)
                        if model.downloadedModels.count >= 2 {
                            Picker("Compare with", selection: Binding(
                                get: {
                                    if model.downloadedModels.contains(where: { $0.rawValue == secondModelID && $0 != model.selectedModel }) {
                                        return secondModelID
                                    }
                                    return model.downloadedModels.first(where: { $0 != model.selectedModel })?.rawValue ?? ""
                                },
                                set: { secondModelID = $0 }
                            )) {
                                ForEach(model.downloadedModels.filter { $0 != model.selectedModel }) { option in
                                    Text(option.displayName).tag(option.rawValue)
                                }
                            }
                            Button {
                                let selectedSecondModel = secondModelID.isEmpty
                                    ? model.downloadedModels.first(where: { $0 != model.selectedModel })?.rawValue
                                    : secondModelID
                                Task { await ask(comparingWith: selectedSecondModel) }
                            } label: {
                                Label(isAnswering ? "Comparing models…" : "Compare Two Models", systemImage: "arrow.left.arrow.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(
                                isAnswering
                                    || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || !model.deviceSupportsModel
                                    || !model.selectedModelIsDownloaded
                            )
                            Text("Runs one model at a time and shows both answers side by side; it does not combine them into a verified answer.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if !model.selectedModelIsDownloaded {
                            Label("Choose and download an on-device model in Settings to use grounded Q&A.", systemImage: "arrow.down.circle")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .cailynSurface()

                    if let answer {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(title: "ANSWER")
                            Text(answer).font(.body).textSelection(.enabled)
                            if !sources.isEmpty {
                                Divider()
                                Text("SOURCES").font(.system(.caption, design: .monospaced, weight: .bold)).tracking(1.2)
                                ForEach(sources, id: \.self) {
                                    Text($0).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .cailynSurface()
                    }
                    if let comparison {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeading(title: "INDEPENDENT MODEL COMPARISON")
                            Text("These are separate model outputs, not a fact-check. Compare their claims against the cited records below.")
                                .font(.footnote).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(comparison.firstModelName.uppercased())
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                Text(comparison.firstAnswer).textSelection(.enabled)
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text(comparison.secondModelName.uppercased())
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                Text(comparison.secondAnswer).textSelection(.enabled)
                            }
                            if !sources.isEmpty {
                                Divider()
                                Text("SHARED SOURCE RECORDS").font(.system(.caption, design: .monospaced, weight: .bold)).tracking(1.2)
                                ForEach(sources, id: \.self) {
                                    Text($0).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .cailynSurface()
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(CailynTheme.urgent).cailynSurface()
                    }
                    NavigationLink { Microsoft365View() } label: {
                        Label("Connect Outlook & Teams (Microsoft 365)", systemImage: "envelope.badge")
                    }
                    .foregroundStyle(.primary)
                    .cailynSurface()
                }
                .padding(22)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("ASSISTANT")
    }

    @MainActor
    private func ask(comparingWith secondModelID: String? = nil) async {
        isAnswering = true
        answer = nil
        comparison = nil
        errorMessage = nil
        defer { isAnswering = false }
        do {
            let records = retrievedRecords(for: question)
            let evidenceBundle = makeEvidenceBundle(from: records)
            guard !evidenceBundle.records.isEmpty else {
                answer = CailynModelPrompts.infoNotInKnowledgeBase
                sources = []
                return
            }
            sources = evidenceBundle.records.map(\.label)
            if let secondModelID {
                comparison = try await model.compareAnswers(
                    question: question,
                    evidence: evidenceBundle.text,
                    sourceLabels: sources.map { "[\($0)]" },
                    secondModelID: secondModelID
                )
            } else {
                answer = try await model.answer(
                    question: question,
                    evidence: evidenceBundle.text,
                    sourceLabels: sources.map { "[\($0)]" }
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func retrievedRecords(for question: String) -> [EvidenceRecord] {
        var records: [EvidenceRecord] = []
        records += actions.map {
            EvidenceRecord(label: "Action \($0.title)", content: "Title: \($0.title); details: \($0.details); status: \($0.status.label); priority: \($0.priority.label); due: \($0.dueAt?.formatted() ?? "not set"); shift: \($0.dueAt.flatMap { ShiftSchedule.stored.shift(containing: $0)?.title } ?? "not assigned")")
        }
        records += events.map {
            EvidenceRecord(label: "Event \($0.title) · \($0.startAt.formatted(date: .abbreviated, time: .shortened))", content: "Title: \($0.title); starts: \($0.startAt.formatted()); ends: \($0.endAt.formatted()); location: \($0.location ?? "not set"); notes: \($0.notes); shift: \($0.shiftRaw ?? "not assigned")")
        }
        records += people.map {
            EvidenceRecord(label: "Person \($0.displayName)", content: "Name: \($0.displayName); role: \($0.role ?? "not set"); organization: \($0.organization ?? "not set"); notes: \($0.notes)")
        }
        records += assets.map {
            EvidenceRecord(label: "Asset \($0.name)", content: "Name: \($0.name); category: \($0.category); area: \($0.area); status: \($0.status.label); details: \($0.details)")
        }
        records += logs.map {
            EvidenceRecord(label: "Log \($0.timestamp.formatted(date: .abbreviated, time: .shortened))", content: "Text: \($0.text); type: \($0.kind.rawValue); shift: \($0.shiftRaw ?? "not assigned")")
        }
        records += turnovers.map {
            EvidenceRecord(label: "Turnover \($0.title) · \($0.approvedAt.formatted(date: .abbreviated, time: .shortened))", content: "Shift: \($0.shiftRaw ?? "not assigned"); overview: \($0.overview); unit status: \($0.unitStatus); events: \($0.events); abnormal conditions: \($0.abnormalConditions); completed work: \($0.completedWork); open actions: \($0.openActions); waiting on: \($0.waitingOn); upcoming work: \($0.upcomingWork); safety notes: \($0.safetyNotes); uncertainties: \($0.uncertainties)")
        }
        records += knowledge.map {
            EvidenceRecord(label: "Knowledge \($0.title)", content: "Title: \($0.title); source: \($0.source); body: \($0.body)")
        }
        let documentTitles = Dictionary(uniqueKeysWithValues: knowledgeDocuments.map { ($0.id, $0.title) })
        records += knowledgeChunks.compactMap { chunk in
            guard let title = documentTitles[chunk.documentID] else { return nil }
            return EvidenceRecord(
                label: "Document: \(title), page \(chunk.pageNumber), section \(chunk.chunkNumber)",
                content: chunk.content,
                indexedTerms: chunk.searchTerms
            )
        }
        records += routines.map {
            EvidenceRecord(label: "Routine \($0.title)", content: "Title: \($0.title); schedule: \($0.scheduleDescription); shift: \($0.shiftRaw ?? "all shifts"); enabled: \($0.isEnabled); items: \($0.items.sorted { $0.sortOrder < $1.sortOrder }.map(\.title).joined(separator: ", "))")
        }

        if microsoft.isConnected {
            records += microsoft.events.map {
                EvidenceRecord(label: "Outlook event \($0.subject ?? "Untitled") · \($0.start.dateTime)", content: "Subject: \($0.subject ?? "Untitled"); start: \($0.start.dateTime) (\($0.start.timeZone)); end: \($0.end.dateTime) (\($0.end.timeZone)); location: \($0.location?.displayName ?? "not set"); Teams join URL: \($0.onlineMeeting?.joinUrl ?? "not provided"); web link: \($0.webLink ?? "not provided")")
            }
            records += microsoft.messages.map {
                EvidenceRecord(label: "Outlook email \($0.subject ?? "Untitled") · \($0.from?.emailAddress.name ?? $0.from?.emailAddress.address ?? "Unknown sender")", content: "Subject: \($0.subject ?? "Untitled"); sender: \($0.from?.emailAddress.name ?? "Unknown") <\($0.from?.emailAddress.address ?? "")>; received: \($0.receivedDateTime?.formatted() ?? "unknown"); importance: \($0.importance ?? "normal"); Cailyn priority: \(microsoft.priorityScore(for: $0)); preview: \($0.bodyPreview ?? ""); link: \($0.webLink ?? "not provided")")
            }
        }

        let queryTokens = KnowledgeDocumentIndexer.searchTerms(for: question)
        return records
            .map { record in
                let searchableTerms = KnowledgeDocumentIndexer.searchTerms(for: record.label + " " + record.content)
                    .union(record.indexedTerms.split(separator: " ").map(String.init))
                return (record, searchableTerms.intersection(queryTokens).count)
            }
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 == $1.1 { return $0.0.label < $1.0.label }
                return $0.1 > $1.1
            }
            .prefix(20)
            .map(\.0)
    }

    private func makeEvidenceBundle(from records: [EvidenceRecord]) -> EvidenceBundle {
        var selectedRecords: [EvidenceRecord] = []
        var sections: [String] = []
        var remainingCharacters = 12_000

        for record in records {
            let sourceLine = "[\(record.label)]\n"
            let separator = sections.isEmpty ? "" : "\n\n"
            let availableContentLength = remainingCharacters - separator.count - sourceLine.count
            guard availableContentLength > 0 else { break }
            let content = String(record.content.prefix(availableContentLength))
            guard !content.isEmpty else { continue }
            let section = separator + sourceLine + content
            sections.append(section)
            selectedRecords.append(record)
            remainingCharacters -= section.count
        }
        return EvidenceBundle(records: selectedRecords, text: sections.joined())
    }

    private struct EvidenceRecord {
        let label: String
        let content: String
        var indexedTerms = ""
    }

    private struct EvidenceBundle {
        let records: [EvidenceRecord]
        let text: String
    }
}
