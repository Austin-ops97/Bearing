import CryptoKit
import Foundation
import PDFKit

struct IndexedKnowledgeDocument: Sendable {
    let title: String
    let fileName: String
    let pageCount: Int
    let contentHash: String
    let chunks: [IndexedKnowledgeChunk]
}

struct IndexedKnowledgeChunk: Sendable {
    let pageNumber: Int
    let chunkNumber: Int
    let content: String
    let searchTerms: String
}

enum KnowledgeDocumentIndexer {
    static let maximumFileBytes = 50_000_000
    static let maximumExtractedCharacters = 5_000_000
    private static let chunkCharacterLimit = 900
    private static let overlapCharacterCount = 120

    static func index(url: URL) throws -> IndexedKnowledgeDocument {
        let data = try Data(contentsOf: url)
        guard data.count <= maximumFileBytes else { throw KnowledgeDocumentError.fileTooLarge }

        let pageTexts: [String]
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(data: data) else {
                throw KnowledgeDocumentError.cannotReadDocument
            }
            pageTexts = (0..<document.pageCount).map { index in
                document.page(at: index)?.string ?? ""
            }
        case "txt", "text", "md", "markdown", "csv":
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16)
            else { throw KnowledgeDocumentError.unsupportedOrUnreadableFormat }
            pageTexts = [text]
        case "rtf", "docx", "html":
            do {
                let attributed = try NSAttributedString(
                    url: url,
                    options: [:],
                    documentAttributes: nil
                )
                pageTexts = [attributed.string]
            } catch {
                throw KnowledgeDocumentError.unsupportedOrUnreadableFormat
            }
        default:
            throw KnowledgeDocumentError.unsupportedOrUnreadableFormat
        }

        let extractedCharacterCount = pageTexts.reduce(0) { $0 + $1.count }
        guard extractedCharacterCount <= maximumExtractedCharacters else {
            throw KnowledgeDocumentError.documentTooLong
        }
        let chunks = pageTexts.enumerated().flatMap { pageIndex, text in
            makeChunks(from: text, pageNumber: pageIndex + 1)
        }
        guard !chunks.isEmpty else { throw KnowledgeDocumentError.noExtractableText }

        return IndexedKnowledgeDocument(
            title: url.deletingPathExtension().lastPathComponent,
            fileName: url.lastPathComponent,
            pageCount: pageTexts.count,
            contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            chunks: chunks
        )
    }

    static func makeChunks(from text: String, pageNumber: Int) -> [IndexedKnowledgeChunk] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }

        var chunks: [IndexedKnowledgeChunk] = []
        var start = 0
        while start < characters.count {
            var end = min(start + chunkCharacterLimit, characters.count)
            if end < characters.count,
               let paragraphBreak = (start + chunkCharacterLimit * 3 / 4..<end)
                .last(where: { characters[$0].isWhitespace }) {
                end = paragraphBreak + 1
            }

            let content = String(characters[start..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                chunks.append(IndexedKnowledgeChunk(
                    pageNumber: pageNumber,
                    chunkNumber: chunks.count + 1,
                    content: content,
                    searchTerms: searchTerms(for: content).sorted().joined(separator: " ")
                ))
            }
            guard end < characters.count else { break }
            start = max(start + 1, end - overlapCharacterCount)
        }
        return chunks
    }

    static func searchTerms(for text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from",
            "how", "i", "in", "is", "it", "of", "on", "or", "that", "the", "this",
            "to", "was", "what", "when", "where", "which", "who", "why", "with"
        ]
        return Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 1 && !stopWords.contains($0) }
        )
    }
}

enum KnowledgeDocumentError: LocalizedError {
    case fileTooLarge
    case documentTooLong
    case cannotReadDocument
    case unsupportedOrUnreadableFormat
    case noExtractableText

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "This file is over the 50 MB import limit."
        case .documentTooLong:
            "This document contains too much text to index safely."
        case .cannotReadDocument:
            "Cailyn could not open this PDF."
        case .unsupportedOrUnreadableFormat:
            "This file format is unsupported or its text could not be extracted. Try PDF, DOCX, RTF, HTML, TXT, Markdown, or CSV."
        case .noExtractableText:
            "No selectable text was found. Scanned-image PDFs need OCR before they can be searched."
        }
    }
}
