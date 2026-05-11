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
    // "recorded" (default) for audio-captured sessions, "manual" for leads
    // the agent typed in. Sessions tab hides "manual"; Leads inbox shows
    // everything. Decoded with a default so old session payloads (cached
    // on disk before this field existed) still parse cleanly.
    var kind: String = "recorded"

    enum CodingKeys: String, CodingKey {
        case id, status, address, kind
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case visitorCount = "visitor_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decode(String.self, forKey: .status)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
        visitorCount = try c.decode(Int.self, forKey: .visitorCount)
        kind = (try c.decodeIfPresent(String.self, forKey: .kind)) ?? "recorded"
    }
}

struct SessionResult: Codable, Hashable {
    let agentSpeaker: String
    let unmatchedSpeakers: [String]
    let visitors: [VisitorResult]
    let fullTranscript: String
    var utterances: [Utterance]?
    var scriptCoverage: ScriptCoverage?

    enum CodingKeys: String, CodingKey {
        case visitors, utterances
        case agentSpeaker = "agent_speaker"
        case unmatchedSpeakers = "unmatched_speakers"
        case fullTranscript = "full_transcript"
        case scriptCoverage = "script_coverage"
    }
}

// One diarized turn — surfaced in the Summary "What you said" section so
// the agent can see their own lines with the visitor they were addressing.
struct Utterance: Codable, Hashable, Identifiable {
    let speaker: String
    let text: String
    let startMs: Int
    let endMs: Int

    var id: String { "\(speaker):\(startMs)" }

    enum CodingKeys: String, CodingKey {
        case speaker, text
        case startMs = "start_ms"
        case endMs = "end_ms"
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
    var isPreset: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case stepCount = "step_count"
        case isPreset = "is_preset"
    }
}

// Step shape the iOS editor produces when creating a custom script.
struct ScriptStepDraft: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var label: String = ""
    var quote: String = ""
    var intent: String = ""
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

// MARK: – Listings

// A property the agent is hosting an open house at. Persisted on-device in
// UserDefaults — no backend yet. The list shows on the new-session screen
// where the agent taps a card to immediately start recording for that home.
struct Listing: Codable, Hashable, Identifiable {
    var id: String                // UUID string
    var address: String           // "1936 17th Ave NE"
    var neighborhood: String      // "Issaquah Highlands"
    var price: Int                // dollars; 0 = unset
    var beds: Int
    var baths: Double
    var sqft: Int
    var photoData: Data?          // optional inline photo (small JPEG)

    var displayPrice: String {
        guard price > 0 else { return "" }
        if price >= 1_000_000 {
            let m = Double(price) / 1_000_000
            return String(format: "$%.2fM", m).replacingOccurrences(of: ".00M", with: "M")
        }
        return "$\(price.formatted())"
    }

    var displaySpecs: String {
        let bathLabel = baths.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(baths))"
            : String(format: "%.1f", baths)
        return "\(beds) Beds · \(bathLabel) Baths · \(sqft.formatted()) SF"
    }
}

struct VisitorResult: Codable, Hashable, Identifiable {
    let visitor: VisitorInfo
    let analysis: AnalysisResult
    var leadState: LeadState?
    var id: String { visitor.name + ":" + (visitor.speaker ?? "") }

    enum CodingKeys: String, CodingKey {
        case visitor, analysis
        case leadState = "lead_state"
    }
}

// Where a captured lead sits in the agent's follow-up workflow. The backend
// is the source of truth — iOS does optimistic updates and PATCHes on change.
struct LeadState: Codable, Hashable {
    enum Status: String, Codable, Hashable, CaseIterable {
        case drafted, sent, replied, archived
    }

    var status: Status
    var sentAt: String?
    var snoozedUntil: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case sentAt = "sent_at"
        case snoozedUntil = "snoozed_until"
        case updatedAt = "updated_at"
    }

    static let defaultDrafted = LeadState(status: .drafted, sentAt: nil, snoozedUntil: nil, updatedAt: nil)
}

extension LeadState {
    // Decoded as Date if present + parseable; otherwise nil so callers can
    // treat "unsnoozed" and "garbage backend value" the same way.
    var snoozedUntilDate: Date? {
        guard let s = snoozedUntil else { return nil }
        return ISO8601DateFormatter.fractionalSeconds.date(from: s)
            ?? ISO8601DateFormatter().date(from: s)
    }
    var isSnoozedNow: Bool {
        guard let d = snoozedUntilDate else { return false }
        return d > Date()
    }
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

extension ISO8601DateFormatter {
    // Shared parser/formatter that accepts the millisecond-precision strings
    // the backend emits. Used by SessionSummary.createdDate and the
    // LeadState snooze helpers — keep it module-internal so any file that
    // talks to backend timestamps can reuse it.
    static let fractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
