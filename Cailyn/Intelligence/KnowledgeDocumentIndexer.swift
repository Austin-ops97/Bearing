import CryptoKit
import Foundation
import NaturalLanguage
import PDFKit
import Vision

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
    let embeddingData: Data?
}

enum KnowledgeDocumentIndexer {
    static let maximumFileBytes = 50_000_000
    static let maximumExtractedCharacters = 5_000_000
    private static let maximumOCRPageCount = 200
    private static let chunkCharacterLimit = 900
    private static let minimumPreferredBoundaryOffset = 550
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
            if document.pageCount > maximumOCRPageCount,
               (0..<document.pageCount).contains(where: {
                   document.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
               }) {
                throw KnowledgeDocumentError.tooManyScannedPages
            }
            pageTexts = try (0..<document.pageCount).map { index in
                guard let page = document.page(at: index) else {
                    throw KnowledgeDocumentError.cannotReadDocument
                }
                let extracted = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return extracted.isEmpty ? try recognizeText(on: page) : extracted
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
            let limit = min(start + chunkCharacterLimit, characters.count)
            let end = preferredChunkEnd(in: characters, start: start, limit: limit)

            let content = String(characters[start..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                chunks.append(IndexedKnowledgeChunk(
                    pageNumber: pageNumber,
                    chunkNumber: chunks.count + 1,
                    content: content,
                    searchTerms: tokens(for: content).joined(separator: " "),
                    embeddingData: sentenceEmbeddingData(for: content)
                ))
            }
            guard end < characters.count else { break }
            start = max(start + 1, end - overlapCharacterCount)
        }
        return chunks
    }

    private static func recognizeText(on page: PDFPage) throws -> String {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return "" }
        let scale = min(1, 2_048 / max(bounds.width, bounds.height))
        let thumbnail = page.thumbnail(
            of: CGSize(width: bounds.width * scale, height: bounds.height * scale),
            for: .mediaBox
        )
        guard let image = thumbnail.cgImage else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? ""
    }

    private static func preferredChunkEnd(in characters: [Character], start: Int, limit: Int) -> Int {
        guard limit < characters.count else { return limit }
        let earliest = min(start + minimumPreferredBoundaryOffset, limit)
        let candidates = earliest..<limit
        if let paragraph = candidates.last(where: {
            characters[$0].isNewline && $0 > start && characters[$0 - 1].isNewline
        }) {
            return paragraph
        }
        if let sentence = candidates.last(where: {
            characters[$0].isWhitespace && $0 > start && ".!?".contains(characters[$0 - 1])
        }) {
            return sentence
        }
        if let whitespace = candidates.last(where: { characters[$0].isWhitespace }) {
            return whitespace
        }
        return limit
    }

    static func tokens(for text: String) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from",
            "how", "i", "in", "is", "it", "of", "on", "or", "that", "the", "this",
            "to", "was", "what", "when", "where", "which", "who", "why", "with"
        ]
        return text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 && !stopWords.contains($0) }
    }

    static func searchTerms(for text: String) -> Set<String> {
        Set(tokens(for: text))
    }

    static func hybridScores(
        query: String,
        documentTokens: [[String]],
        embeddingData: [Data?]
    ) -> [Double] {
        precondition(documentTokens.count == embeddingData.count)
        let queryTerms = Set(tokens(for: query))
        guard !documentTokens.isEmpty else { return [] }
        let averageLength = max(1, Double(documentTokens.reduce(0) { $0 + $1.count }) / Double(documentTokens.count))
        let documentFrequencies = queryTerms.reduce(into: [String: Int]()) { frequencies, term in
            frequencies[term] = documentTokens.reduce(into: 0) { count, terms in
                if terms.contains(term) { count += 1 }
            }
        }
        let k1 = 1.5
        let b = 0.75
        let lexicalScores = documentTokens.map { terms in
            let counts = terms.reduce(into: [String: Int]()) { result, term in
                result[term, default: 0] += 1
            }
            return queryTerms.reduce(0) { score, term in
                let frequency = Double(counts[term, default: 0])
                guard frequency > 0 else { return score }
                let documentsWithTerm = Double(documentFrequencies[term, default: 0])
                let inverseDocumentFrequency = log(
                    1 + (Double(documentTokens.count) - documentsWithTerm + 0.5) / (documentsWithTerm + 0.5)
                )
                let lengthNormalization = k1 * (1 - b + b * Double(terms.count) / averageLength)
                return score + inverseDocumentFrequency * (frequency * (k1 + 1)) / (frequency + lengthNormalization)
            }
        }
        let lexicalRanks = rankedIndices(lexicalScores, minimumScore: 0.000_001)
        var combinedScores = lexicalScores.indices.map { index in
            lexicalRanks[index].map { 1 / Double(60 + $0) } ?? 0
        }

        if let queryVector = sentenceVector(for: query) {
            let semanticScores = embeddingData.map { data in
                guard let vector = decodeVector(data), vector.count == queryVector.count else { return -1.0 }
                return cosineSimilarity(queryVector, vector)
            }
            let semanticRanks = rankedIndices(semanticScores, minimumScore: 0.2)
            for index in combinedScores.indices {
                if let rank = semanticRanks[index] {
                    combinedScores[index] += 1 / Double(60 + rank)
                }
            }
        }
        return combinedScores
    }

    static func sentenceEmbeddingData(for text: String) -> Data? {
        guard let vector = sentenceVector(for: text) else { return nil }
        let values = vector.map(Float.init)
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func sentenceVector(for text: String) -> [Double]? {
        NLEmbedding.sentenceEmbedding(for: .english)?.vector(for: text)
    }

    private static func decodeVector(_ data: Data?) -> [Double]? {
        guard let data, data.count.isMultiple(of: MemoryLayout<Float>.size) else { return nil }
        return data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self)).map(Double.init)
        }
    }

    private static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        let dot = zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
        let leftMagnitude = sqrt(lhs.reduce(0) { $0 + $1 * $1 })
        let rightMagnitude = sqrt(rhs.reduce(0) { $0 + $1 * $1 })
        guard leftMagnitude > 0, rightMagnitude > 0 else { return -1 }
        return dot / (leftMagnitude * rightMagnitude)
    }

    private static func rankedIndices(_ scores: [Double], minimumScore: Double) -> [Int: Int] {
        let indices = scores.indices
            .filter { scores[$0] >= minimumScore }
            .sorted {
                if scores[$0] == scores[$1] { return $0 < $1 }
                return scores[$0] > scores[$1]
            }
        return Dictionary(uniqueKeysWithValues: indices.enumerated().map { ($0.element, $0.offset + 1) })
    }
}

enum KnowledgeDocumentError: LocalizedError {
    case fileTooLarge
    case documentTooLong
    case cannotReadDocument
    case tooManyScannedPages
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
        case .tooManyScannedPages:
            "This PDF has more than 200 pages and includes scanned pages. Split it into smaller files before importing."
        case .unsupportedOrUnreadableFormat:
            "This file format is unsupported or its text could not be extracted. Try PDF, DOCX, RTF, HTML, TXT, Markdown, or CSV."
        case .noExtractableText:
            "No readable text was found, including after on-device OCR."
        }
    }
}
