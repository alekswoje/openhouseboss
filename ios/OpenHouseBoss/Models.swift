import Foundation

struct VisitorInput: Identifiable, Equatable {
    let id = UUID()
    var name: String = ""
    var email: String = ""
    var phone: String = ""
}

struct Session: Codable, Hashable, Identifiable {
    let id: String
    var status: String          // "processing" | "ready" | "error"
    var address: String?
    var createdAt: String?
    var completedAt: String?
    var error: String?
    var result: SessionResult?

    enum CodingKeys: String, CodingKey {
        case id, status, address, error, result
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}

// Compact row returned by GET /sessions. No transcript, no analysis — those
// are fetched lazily when the user opens a session.
struct SessionSummary: Codable, Hashable, Identifiable {
    let id: String
    let status: String
    let address: String?
    let createdAt: String
    let completedAt: String?
    let visitorCount: Int

    enum CodingKeys: String, CodingKey {
        case id, status, address
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case visitorCount = "visitor_count"
    }
}

struct SessionResult: Codable, Hashable {
    let agentSpeaker: String
    let unmatchedSpeakers: [String]
    let visitors: [VisitorResult]
    let fullTranscript: String
    var scriptCoverage: ScriptCoverage?

    enum CodingKeys: String, CodingKey {
        case visitors
        case agentSpeaker = "agent_speaker"
        case unmatchedSpeakers = "unmatched_speakers"
        case fullTranscript = "full_transcript"
        case scriptCoverage = "script_coverage"
    }
}

// MARK: – Script + script coverage

// A preset (or eventually uploaded) script attached to a session. The
// Setup screen lets the agent pick one before recording, and the backend
// grades the agent's transcript against it.
struct ScriptSummary: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let description: String
    let stepCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case stepCount = "step_count"
    }
}

struct StepCoverage: Codable, Hashable, Identifiable {
    let stepId: String
    let status: String          // "hit" | "partial" | "missed"
    let evidence: String        // verbatim quote from agent transcript or ""
    let suggestion: String

    var id: String { stepId }

    enum CodingKeys: String, CodingKey {
        case status, evidence, suggestion
        case stepId = "step_id"
    }
}

struct ScriptCoverage: Codable, Hashable {
    let scriptId: String
    let scriptName: String
    let overallSummary: String?
    let score: Int?
    let steps: [StepCoverage]?
    let error: String?          // present when coverage grading failed

    enum CodingKeys: String, CodingKey {
        case score, steps, error
        case scriptId = "script_id"
        case scriptName = "script_name"
        case overallSummary = "overall_summary"
    }
}

// We also expose step labels client-side so Summary can show readable
// names instead of bare step_id strings. Mirrors the backend's preset list.
struct ScriptStepInfo: Hashable, Identifiable {
    let id: String
    let section: String
    let label: String
    let quote: String
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

extension SessionSummary {
    // Best-effort date for sorting/display. Ignored if backend returns
    // something unexpected.
    var createdDate: Date? {
        ISO8601DateFormatter.fractionalSeconds.date(from: createdAt)
    }
    var displayTitle: String {
        if let a = address, !a.isEmpty { return a }
        return "Session " + String(id.prefix(8))
    }
}

private extension ISO8601DateFormatter {
    static let fractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
