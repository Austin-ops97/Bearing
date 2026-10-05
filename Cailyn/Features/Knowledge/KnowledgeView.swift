import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum KnowledgeSheet: Identifiable {
    case newNote
    case newFolder(UUID?)
    case renameFolder(UUID)

    var id: String {
        switch self {
        case .newNote: "new-note"
        case .newFolder(let parentID): "new-folder-\(parentID?.uuidString ?? "root")"
        case .renameFolder(let folderID): "rename-folder-\(folderID.uuidString)"
        }
    }
}

struct KnowledgeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CailynKnowledgeItem.modifiedAt, order: .reverse) private var items: [CailynKnowledgeItem]
    @Query(sort: \CailynKnowledgeDocument.importedAt, order: .reverse) private var documents: [CailynKnowledgeDocument]
    @Query(sort: \CailynKnowledgeFolder.name) private var folders: [CailynKnowledgeFolder]
    let folderID: UUID?
    let folderTitle: String

    init(folderID: UUID? = nil, folderTitle: String = "KNOWLEDGE") {
        self.folderID = folderID
        self.folderTitle = folderTitle
    }

    @State private var showsImporter = false
    @State private var activeSheet: KnowledgeSheet?
    @State private var selection = Set<UUID>()
    @State private var pendingDeletion = Set<UUID>()
    @State private var confirmsDeletion = false
    @State private var documentToDelete: CailynKnowledgeDocument?
    @State private var folderToDelete: CailynKnowledgeFolder?
    @State private var isImporting = false
    @State private var importError: String?

    private var visibleFolders: [CailynKnowledgeFolder] {
        folders.filter { $0.parentID == folderID }
    }

    private var visibleDocuments: [CailynKnowledgeDocument] {
        documents.filter { $0.folderID == folderID }
    }

    private var visibleNotes: [CailynKnowledgeItem] {
        folderID == nil ? items : []
    }

    var body: some View {
        ZStack {
            PaperBackground()
            if visibleFolders.isEmpty && visibleDocuments.isEmpty && visibleNotes.isEmpty {
                ContentUnavailableView {
                    Label(folderID == nil ? "No Knowledge Yet" : "Empty Folder", systemImage: "books.vertical")
                } description: {
                    Text("Create a folder, add a note, or import documents for Cailyn to index and search.")
                } actions: {
                    Button("Import Documents") { showsImporter = true }.buttonStyle(.borderedProminent)
                    Button("New Folder") { activeSheet = .newFolder(folderID) }.buttonStyle(.bordered)
                    Button("Add Knowledge Note") { activeSheet = .newNote }.buttonStyle(.bordered)
                }
            } else {
                List(selection: $selection) {
                    if !visibleFolders.isEmpty {
                        Section("Folders") {
                            ForEach(visibleFolders) { folder in
                                NavigationLink(destination: KnowledgeView(folderID: folder.id, folderTitle: folder.name)) {
                                    KnowledgeFolderRow(folder: folder, folders: folders)
                                }
                                .contextMenu {
                                    Button {
                                        activeSheet = .renameFolder(folder.id)
                                    } label: {
                                        Label("Rename Folder", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        folderToDelete = folder
                                    } label: {
                                        Label("Delete Folder", systemImage: "folder.badge.minus")
                                    }
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    if !visibleDocuments.isEmpty {
                        Section("Documents") {
                            ForEach(visibleDocuments) { document in
                                NavigationLink(destination: KnowledgeDocumentDetailView(document: document)) {
                                    KnowledgeDocumentRow(document: document)
                                }
                                .swipeActions {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        documentToDelete = document
                                    }
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    if !visibleNotes.isEmpty {
                        Section("Knowledge Notes") {
                            ForEach(visibleNotes) { item in
                                NavigationLink(destination: KnowledgeDetailView(item: item)) {
                                    KnowledgeNoteRow(item: item)
                                }
                                .tag(item.id)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            if isImporting {
                ProgressView("Extracting and indexing documents…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle(folderTitle)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !selection.isEmpty {
                    Button(role: .destructive) {
                        pendingDeletion = selection
                        confirmsDeletion = true
                    } label: { Label("Delete Selected", systemImage: "trash") }
                }
                EditButton()
                Menu {
                    Button("New Folder", systemImage: "folder.badge.plus") { activeSheet = .newFolder(folderID) }
                    Button("Import Documents", systemImage: "doc.badge.plus") { showsImporter = true }
                    Button("Add Knowledge Note", systemImage: "square.and.pencil") { activeSheet = .newNote }
                } label: {
                    Label("Add to Knowledge", systemImage: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { destination in
            switch destination {
            case .newNote:
                NewKnowledgeView()
            case .newFolder(let parentID):
                NewKnowledgeFolderView(parentID: parentID)
            case .renameFolder(let folderID):
                if let folder = folders.first(where: { $0.id == folderID }) {
                    RenameKnowledgeFolderView(folder: folder)
                }
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: supportedDocumentTypes,
            allowsMultipleSelection: true,
            onCompletion: importDocuments
        )
        .confirmationDialog("Delete \(pendingDeletion.count) knowledge item\(pendingDeletion.count == 1 ? "" : "s")?", isPresented: $confirmsDeletion) {
            Button("Delete", role: .destructive, action: deletePending)
            Button("Cancel", role: .cancel) { pendingDeletion.removeAll() }
        }
        .confirmationDialog(
            "Delete \(documentToDelete?.title ?? "document")?",
            isPresented: Binding(
                get: { documentToDelete != nil },
                set: { if !$0 { documentToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Indexed Content", role: .destructive, action: deleteDocument)
            Button("Cancel", role: .cancel) { documentToDelete = nil }
        } message: {
            Text("This removes the extracted text and search index from Cailyn.")
        }
        .confirmationDialog(
            "Delete \(folderToDelete?.name ?? "folder")?",
            isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive, action: deleteFolder)
            Button("Cancel", role: .cancel) { folderToDelete = nil }
        } message: {
            Text("Documents and subfolders will be moved to this folder’s parent. No document content will be deleted.")
        }
        .alert("Knowledge Import", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var supportedDocumentTypes: [UTType] {
        let standardTypes: [UTType] = [.pdf, .plainText, .rtf, .html]
        let extraTypes: [UTType] = ["md", "markdown", "csv", "docx"].compactMap { extensionName in
            UTType(filenameExtension: extensionName)
        }
        return standardTypes + extraTypes
    }

    private func importDocuments(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            Task { await indexDocuments(urls) }
        }
    }

    @MainActor
    private func indexDocuments(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        var importedCount = 0
        var failures: [String] = []

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                failures.append("\(url.lastPathComponent): Cailyn could not access this file.")
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let indexed = try await Task.detached(priority: .userInitiated) {
                    try KnowledgeDocumentIndexer.index(url: url)
                }.value
                guard !documents.contains(where: { $0.contentHash == indexed.contentHash }) else {
                    failures.append("\(url.lastPathComponent): already in the knowledge base.")
                    continue
                }

                let document = CailynKnowledgeDocument(
                    title: indexed.title,
                    fileName: indexed.fileName,
                    folderID: folderID,
                    pageCount: indexed.pageCount,
                    chunkCount: indexed.chunks.count,
                    contentHash: indexed.contentHash
                )
                context.insert(document)
                for chunk in indexed.chunks {
                    context.insert(CailynKnowledgeChunk(
                        documentID: document.id,
                        pageNumber: chunk.pageNumber,
                        chunkNumber: chunk.chunkNumber,
                        content: chunk.content,
                        searchTerms: chunk.searchTerms
                    ))
                }
                try context.save()
                importedCount += 1
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            importError = ([importedCount > 0 ? "Imported \(importedCount) document(s)." : nil]
                .compactMap { $0 } + failures).joined(separator: "\n")
        }
    }

    private func deletePending() {
        do {
            items.filter { pendingDeletion.contains($0.id) }.forEach(context.delete)
            try context.save()
            selection.subtract(pendingDeletion)
            pendingDeletion.removeAll()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func deleteDocument() {
        guard let document = documentToDelete else { return }
        do {
            let chunks = try context.fetch(FetchDescriptor<CailynKnowledgeChunk>())
                .filter { $0.documentID == document.id }
            chunks.forEach(context.delete)
            context.delete(document)
            try context.save()
        } catch {
            importError = error.localizedDescription
        }
        documentToDelete = nil
    }

    private func deleteFolder() {
        guard let folder = folderToDelete else { return }
        let childFolders = folders.filter { $0.parentID == folder.id }
        let childDocuments = documents.filter { $0.folderID == folder.id }
        do {
            childFolders.forEach { $0.parentID = folder.parentID }
            childDocuments.forEach { $0.folderID = folder.parentID }
            context.delete(folder)
            try context.save()
        } catch {
            context.insert(folder)
            childFolders.forEach { $0.parentID = folder.id }
            childDocuments.forEach { $0.folderID = folder.id }
            importError = error.localizedDescription
        }
        folderToDelete = nil
    }
}

private struct NewKnowledgeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var bodyText = ""
    @State private var source = "Cailyn Note"
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Source or reference", text: $source)
                TextEditor(text: $bodyText).frame(minHeight: 260)
            }
            .navigationTitle("Add Knowledge")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Could Not Save Knowledge", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func save() {
        let item = CailynKnowledgeItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: bodyText,
            source: source
        )
        context.insert(item)
        do {
            try context.save()
            dismiss()
        } catch {
            context.delete(item)
            saveError = error.localizedDescription
        }
    }
}

struct KnowledgeDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var item: CailynKnowledgeItem

    var body: some View {
        Form {
            Section("Reference") {
                TextField("Title", text: $item.title)
                TextField("Source", text: $item.source)
            }
            Section("Content") { TextEditor(text: $item.body).frame(minHeight: 260) }
            Section {
                ShareLink(item: item.shareText) {
                    Label("Add to Apple Notes or Share", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Apple does not provide apps direct write access to Notes. The share sheet is the supported Apple workflow; choose Notes to create a copy there.")
            }
        }

        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            item.modifiedAt = .now
            try? context.save()
        }
    }
}

private struct NewKnowledgeFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let parentID: UUID?
    @State private var name = ""
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder name", text: $name)
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Could Not Create Folder", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func create() {
        let folder = CailynKnowledgeFolder(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            parentID: parentID
        )
        context.insert(folder)
        do {
            try context.save()
            dismiss()
        } catch {
            context.delete(folder)
            saveError = error.localizedDescription
        }
    }
}

private struct RenameKnowledgeFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var folder: CailynKnowledgeFolder
    @State private var name: String
    @State private var saveError: String?

    init(folder: CailynKnowledgeFolder) {
        self.folder = folder
        _name = State(initialValue: folder.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder name", text: $name)
            }
            .navigationTitle("Rename Folder")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Could Not Rename Folder", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let previousName = folder.name
        folder.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        folder.modifiedAt = .now
        do {
            try context.save()
            dismiss()
        } catch {
            folder.name = previousName
            saveError = error.localizedDescription
        }
    }
}

struct KnowledgeDocumentDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var chunks: [CailynKnowledgeChunk]
    @Query(sort: \CailynKnowledgeFolder.name) private var folders: [CailynKnowledgeFolder]
    @Bindable var document: CailynKnowledgeDocument
    @State private var saveError: String?

    private var documentChunks: [CailynKnowledgeChunk] {
        chunks
            .filter { $0.documentID == document.id }
            .sorted {
                ($0.pageNumber, $0.chunkNumber) < ($1.pageNumber, $1.chunkNumber)
            }
    }

    var body: some View {
        List {
            Section("Source") {
                LabeledContent("File", value: document.fileName)
                LabeledContent("Indexed", value: document.importedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Indexed Sections", value: "\(document.chunkCount)")
                Picker("Folder", selection: $document.folderID) {
                    Text("Knowledge").tag(Optional<UUID>.none)
                    ForEach(folders) { folder in
                        Text(folderPath(for: folder)).tag(Optional(folder.id))
                    }
                }
                .onChange(of: document.folderID) { oldValue, _ in
                    do {
                        try context.save()
                    } catch {
                        document.folderID = oldValue
                        saveError = error.localizedDescription
                    }
                }
            }
            ForEach(documentChunks) { chunk in
                Section("Page \(chunk.pageNumber) · Section \(chunk.chunkNumber)") {
                    Text(chunk.content)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Could Not Save Folder", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func folderPath(for folder: CailynKnowledgeFolder) -> String {
        KnowledgeFolderPath.path(for: folder, folders: folders)
    }
}

private struct KnowledgeFolderRow: View {
    let folder: CailynKnowledgeFolder
    let folders: [CailynKnowledgeFolder]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(CailynTheme.champagne)
                .frame(width: 34, height: 34)
                .background(CailynTheme.champagne.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name).font(.headline)
                Text("FOLDER · \(KnowledgeFolderPath.path(for: folder, folders: folders))")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct KnowledgeDocumentRow: View {
    let document: CailynKnowledgeDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundStyle(CailynTheme.champagneGlow)
                .frame(width: 34, height: 34)
                .background(CailynTheme.champagneGlow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title).font(.headline)
                Text(document.fileName).font(.caption).foregroundStyle(.secondary)
                Text("\(document.pageCount) pages · \(document.chunkCount) indexed sections")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(CailynTheme.champagne)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct KnowledgeNoteRow: View {
    let item: CailynKnowledgeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title).font(.headline)
            Text(item.body)
                .lineLimit(2)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(item.source.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(CailynTheme.champagne)
        }
        .padding(.vertical, 7)
    }
}

private enum KnowledgeFolderPath {
    static func path(for folder: CailynKnowledgeFolder, folders: [CailynKnowledgeFolder]) -> String {
        var names = [folder.name]
        var parentID = folder.parentID
        while let id = parentID, let parent = folders.first(where: { $0.id == id }) {
            names.insert(parent.name, at: 0)
            parentID = parent.parentID
        }
        return names.joined(separator: " / ")
    }
}
