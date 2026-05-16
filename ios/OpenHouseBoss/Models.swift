import Foundation

struct VisitorInput: Identifiable, Equatable {
    let id = UUID()
    var name: String = ""
    var email: String = ""
    var phone: String = ""
    // Captured by the iPad kiosk; not yet round-tripped to the backend's
    // CSV format (the diarization pipeline only consumes name + email +
    // phone). Held client-side for now so the agent can see them in the
    // Leads view; we'll surface them server-side once the analysis schema
    // can store structured guest answers.
    var hasAgent: HasAgent? = nil
    var marketingConsent: Bool = false
    var recordingConsent: Bool = false

    enum HasAgent: String, Codable, CaseIterable, Identifiable {
        case yes, no
        var id: String { rawValue }
        var label: String {
            switch self {
            case .yes: return "Yes"
            case .no:  return "Not yet"
            }
        }
    }
}

struct Session: Codable, Hashable, Identifiable {
    let id: String
    var status: String          // "processing" | "ready" | "error"
    var address: String?
    var createdAt: String?
    var completedAt: String?
    var error: String?
    var result: SessionResult?
    // Live-snapshot bookkeeping. `isLive=true` means the agent is still
    // recording and more updates are on the way; `lastSnapshotAt` is the
    // ISO timestamp of the most recent pipeline pass. Both default-nil so
    // older sessions cached on disk decode cleanly.
    var isLive: Bool?
    var lastSnapshotAt: String?
    // Homeowner identity for the Open House Report. Optional — captured at
    // session setup or set later from the Report tab via PATCH /homeowner.
    var homeownerEmail: String?
    var homeownerName: String?
    // Cached Open House Report. Nil until the agent taps Generate the first
    // time. Regenerable from the transcript + visitor analyses; the agent's
    // edits are preserved via PATCH /report and a separate report_meta blob.
    var report: SessionReport?
    var reportMeta: ReportMeta?

    enum CodingKeys: String, CodingKey {
        case id, status, address, error, result, report
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case isLive = "is_live"
        case lastSnapshotAt = "last_snapshot_at"
        case homeownerEmail = "homeowner_email"
        case homeownerName = "homeowner_name"
        case reportMeta = "report_meta"
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
    var visitors: [VisitorResult]
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

// Response from POST /sessions/{id}/abtest — three providers' diarized
// transcripts on the same audio, shown side-by-side in the iOS detail view
// to evaluate diarization quality. Per-provider errors come back inline so
// the UI can render partial results when (e.g.) Speechmatics times out but
// the others succeeded.
struct AbTestResponse: Codable, Hashable {
    let results: [AbTestProviderResult]
}

struct AbTestProviderResult: Codable, Hashable, Identifiable {
    let provider: String
    let elapsedS: Double
    let speakerCount: Int
    let utterances: [AbTestUtterance]
    let error: String?

    var id: String { provider }

    enum CodingKeys: String, CodingKey {
        case provider, utterances, error
        case elapsedS = "elapsed_s"
        case speakerCount = "speaker_count"
    }
}

struct AbTestUtterance: Codable, Hashable, Identifiable {
    let speaker: String
    let startMs: Int
    let text: String

    var id: String { "\(speaker):\(startMs)" }

    enum CodingKeys: String, CodingKey {
        case speaker, text
        case startMs = "start_ms"
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
    // CRM fields — backend defaults each to [] / nil so older sessions still
    // decode cleanly. iOS treats them as the lead's history feed.
    var notes: [LeadNote]?
    var tasks: [LeadTask]?
    var sentEmails: [SentEmail]?
    var scheduledEmail: ScheduledEmail?
    // Agent-edited follow-up draft. nil = use AnalysisResult.followUpDraft as-is.
    var draftOverride: DraftOverride?

    enum CodingKeys: String, CodingKey {
        case status, notes, tasks
        case sentAt = "sent_at"
        case snoozedUntil = "snoozed_until"
        case updatedAt = "updated_at"
        case sentEmails = "sent_emails"
        case scheduledEmail = "scheduled_email"
        case draftOverride = "draft_override"
    }

    static let defaultDrafted = LeadState(
        status: .drafted, sentAt: nil, snoozedUntil: nil, updatedAt: nil,
        notes: [], tasks: [], sentEmails: [], scheduledEmail: nil,
        draftOverride: nil
    )
}

struct DraftOverride: Codable, Hashable {
    var subject: String?
    var body: String
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case subject, body
        case updatedAt = "updated_at"
    }
}

// MARK: – Follow-up templates

// Offers / campaigns the agent has authored. Free-form `name` doubles
// as the @reference token in AI prompts — autocomplete on the client
// makes spaces and punctuation unambiguous to type. `enabled` is the
// agent-facing toggle for whether AI calls should consider this offer.
struct Offer: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var body: String           // marketing copy the AI weaves into emails
    var enabled: Bool
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, body, enabled
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Older payloads pre-date `enabled` and won't decode cleanly with
    // a non-optional Bool. Custom init treats a missing key as true so
    // legacy offers behave like they always have.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        body = try c.decode(String.self, forKey: .body)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    init(id: String, name: String, body: String, enabled: Bool = true,
         createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.name = name
        self.body = body
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct OffersEnvelope: Codable, Hashable {
    var offers: [Offer]
}

struct FollowupTemplate: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var subject: String
    var body: String
    var matchHints: String
    var enabled: Bool
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, subject, body, enabled
        case matchHints = "match_hints"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        body = try c.decode(String.self, forKey: .body)
        matchHints = try c.decodeIfPresent(String.self, forKey: .matchHints) ?? ""
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    init(id: String, name: String, subject: String, body: String,
         matchHints: String, enabled: Bool = true,
         createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.name = name
        self.subject = subject
        self.body = body
        self.matchHints = matchHints
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct TemplatesEnvelope: Codable, Hashable {
    var templates: [FollowupTemplate]
    var forceTemplates: Bool

    enum CodingKeys: String, CodingKey {
        case templates
        case forceTemplates = "force_templates"
    }
}

struct LeadNote: Codable, Hashable, Identifiable {
    let id: String
    var body: String
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct LeadTask: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var dueAt: String?
    var done: Bool
    let createdAt: String?
    var doneAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, done
        case dueAt = "due_at"
        case createdAt = "created_at"
        case doneAt = "done_at"
    }
}

struct SentEmail: Codable, Hashable, Identifiable {
    let id: String
    let to: String
    let subject: String
    let body: String
    let sentAt: String?
    let messageId: String?
    let scheduled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, to, subject, body, scheduled
        case sentAt = "sent_at"
        case messageId = "message_id"
    }
}

struct ScheduledEmail: Codable, Hashable {
    let sendAt: String?
    let to: String?
    let subject: String?
    let body: String?
    let queuedAt: String?
    let error: String?
    let failedAt: String?

    enum CodingKeys: String, CodingKey {
        case to, subject, body, error
        case sendAt = "send_at"
        case queuedAt = "queued_at"
        case failedAt = "failed_at"
    }

    var sendDate: Date? {
        guard let s = sendAt else { return nil }
        return ISO8601DateFormatter.fractionalSeconds.date(from: s)
            ?? ISO8601DateFormatter().date(from: s)
    }
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

// MARK: – Open House Report
//
// Homeowner-facing report generated from a session. The agent reviews
// (and optionally edits), then emails to the seller. Backend: see
// pipeline/report.py for generation + HTML rendering.

struct ReportThemeQuote: Codable, Hashable, Identifiable {
    var quote: String
    var attribution: String = ""

    var id: String { quote }
}

struct ReportTheme: Codable, Hashable, Identifiable {
    var title: String
    var frequency: Int
    var summary: String
    var quotes: [ReportThemeQuote] = []

    var id: String { title }
}

struct ReportStandoutVisitor: Codable, Hashable, Identifiable {
    var label: String
    var score: Int
    var summary: String
    var followUpStatus: String

    var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label, score, summary
        case followUpStatus = "follow_up_status"
    }
}

struct SessionReport: Codable, Hashable {
    var headline: String
    var tldr: [String]
    var trafficSummary: String
    var highlights: [ReportTheme]
    var concerns: [ReportTheme]
    var priceSignal: String
    var standoutVisitors: [ReportStandoutVisitor]
    var agentTake: String
    var nextSteps: [String]

    // Metadata stamped by backend at generation time. Editable but rarely
    // touched by the agent — these are facts derived from the session.
    var address: String = ""
    var dateLabel: String = ""
    var durationMinutes: Int = 0
    var visitorCount: Int = 0
    var groupCountEstimate: Int = 0
    var agentName: String = ""
    var generatedAt: String = ""

    enum CodingKeys: String, CodingKey {
        case headline, tldr, highlights, concerns, address
        case trafficSummary = "traffic_summary"
        case priceSignal = "price_signal"
        case standoutVisitors = "standout_visitors"
        case agentTake = "agent_take"
        case nextSteps = "next_steps"
        case dateLabel = "date_label"
        case durationMinutes = "duration_minutes"
        case visitorCount = "visitor_count"
        case groupCountEstimate = "group_count_estimate"
        case agentName = "agent_name"
        case generatedAt = "generated_at"
    }
}

struct ReportMeta: Codable, Hashable {
    var generatedAt: String?
    var updatedAt: String?
    var edited: Bool = false
    var sentAt: String?
    var sentTo: String?
    var sentMessageId: String?

    enum CodingKeys: String, CodingKey {
        case edited
        case generatedAt = "generated_at"
        case updatedAt = "updated_at"
        case sentAt = "sent_at"
        case sentTo = "sent_to"
        case sentMessageId = "sent_message_id"
    }
}
