import Foundation

struct VisitorInput: Identifiable, Equatable {
    let id = UUID()
    var name: String = ""
    var email: String = ""
    var phone: String = ""
}

struct Session: Codable, Hashable, Identifiable {
    let id: String
    var status: String       // "processing" | "ready" | "error"
    var error: String?
    var result: SessionResult?

    enum CodingKeys: String, CodingKey { case id, status, error, result }
}

struct SessionResult: Codable, Hashable {
    let agentSpeaker: String
    let unmatchedSpeakers: [String]
    let visitors: [VisitorResult]
    let fullTranscript: String

    enum CodingKeys: String, CodingKey {
        case visitors
        case agentSpeaker = "agent_speaker"
        case unmatchedSpeakers = "unmatched_speakers"
        case fullTranscript = "full_transcript"
    }
}

struct VisitorResult: Codable, Hashable, Identifiable {
    let visitor: VisitorInfo
    let analysis: AnalysisResult
    var id: String { visitor.name + ":" + (visitor.speaker ?? "") }
}

struct VisitorInfo: Codable, Hashable {
    let name: String
    let email: String
    let phone: String
    let speaker: String?
}

struct AnalysisResult: Codable, Hashable {
    let summary: String
    let tag: String           // "Buyer" | "Seller" | "Browser"
    let tagReason: String
    let score: Int            // 0..100
    let signals: [String]
    let followUpDraft: String
    let wordsSpoken: Int

    enum CodingKeys: String, CodingKey {
        case summary, tag, score, signals
        case tagReason = "tag_reason"
        case followUpDraft = "follow_up_draft"
        case wordsSpoken = "words_spoken"
    }
}

// UI helpers — the design uses lowercase tag tokens for the TagPill kinds.
extension AnalysisResult {
    var tagToken: String { tag.lowercased() }   // "buyer" / "seller" / "browser"
}

extension VisitorResult {
    var displayName: String { visitor.name }
    var displayInitials: String {
        visitor.name
            .split(separator: " ")
            .compactMap { $0.first.map(String.init) }
            .prefix(2)
            .joined()
    }
}
