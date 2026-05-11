import Foundation
import Security

enum APIError: Error, LocalizedError {
    case http(Int, String)
    case unexpected(String)
    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .unexpected(let m): return m
        }
    }
}

// MARK: – Keychain helper

// Minimal Keychain wrapper for storing per-integration API keys (FUB today,
// kvCORE later). Generic-password class, this-device only, biometrics-free
// — the agent unlocks the phone normally and the app can read the key.
enum Keychain {
    enum Error: Swift.Error { case osError(OSStatus) }

    static func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "OpenHouseBoss",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { throw Error.osError(status) }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "OpenHouseBoss",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "OpenHouseBoss",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: – Follow Up Boss credential

// API key lives in Keychain so a lost phone doesn't expose the agent's
// entire contact database. The key authenticates via HTTP Basic with the
// key as username + empty password (FUB convention).
enum FUBCredential {
    static let keychainAccount = "fub_api_key"

    static var apiKey: String? { Keychain.get(keychainAccount) }
    static var isConnected: Bool { apiKey != nil }

    static func save(_ key: String) throws {
        try Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: keychainAccount)
    }

    static func clear() {
        Keychain.remove(keychainAccount)
    }
}

actor APIClient {
    static let shared = APIClient()

    // Snappy timeouts so a missing/unreachable backend surfaces as an error
    // card in seconds, not a frozen UI for the URLSession default minute.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 120
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    // iOS-only path: upload audio, let the backend synthesize visitors from
    // diarized speakers. Returns the freshly-created session (status=processing).
    // `speakersExpected` is forwarded to AssemblyAI as a diarization hint.
    // `scriptId` attaches a preset script for post-session coverage grading.
    func createSession(audioURL: URL, address: String? = nil, speakersExpected: Int? = nil, scriptId: String? = nil) async throws -> Session {
        try await createSession(audioURL: audioURL, address: address, visitorsCSV: nil, speakersExpected: speakersExpected, scriptId: scriptId)
    }

    // Kiosk path: upload audio plus a sign-in CSV so the backend can match
    // named visitors to speakers.
    func createSession(audioURL: URL, address: String?, visitors: [VisitorInput], speakersExpected: Int? = nil, scriptId: String? = nil) async throws -> Session {
        let csv = (["name,email,phone,signed_in_at"]
            + visitors.map { "\($0.name),\($0.email),\($0.phone)," }).joined(separator: "\n")
        return try await createSession(audioURL: audioURL, address: address, visitorsCSV: Data(csv.utf8), speakersExpected: speakersExpected, scriptId: scriptId)
    }

    private func createSession(audioURL: URL, address: String?, visitorsCSV: Data?, speakersExpected: Int?, scriptId: String?) async throws -> Session {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("sessions"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        if let a = address?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
            body.appendField(boundary: boundary, name: "address", value: a)
        }
        if let n = speakersExpected, n > 0 {
            body.appendField(boundary: boundary, name: "speakers_expected", value: String(n))
        }
        if let sid = scriptId, !sid.isEmpty {
            body.appendField(boundary: boundary, name: "script_id", value: sid)
        }
        if let csv = visitorsCSV {
            body.appendForm(boundary: boundary, name: "visitors", filename: "visitors.csv",
                            contentType: "text/csv", data: csv)
        }
        let audioData = try Data(contentsOf: audioURL)
        body.appendForm(boundary: boundary, name: "audio", filename: "recording.m4a",
                        contentType: "audio/m4a", data: audioData)
        body.append("--\(boundary)--\r\n")

        let (data, response) = try await self.session.upload(for: req, from: body)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    // GET /scripts — presets + user-created.
    func listScripts() async throws -> [ScriptSummary] {
        let url = Config.backendURL.appendingPathComponent("scripts")
        let (data, response) = try await self.session.data(from: url)
        try validate(response: response, data: data)
        struct Wrapper: Codable { let scripts: [ScriptSummary] }
        return try JSONDecoder().decode(Wrapper.self, from: data).scripts
    }

    // POST /scripts — create a new user script with steps.
    func createScript(name: String, description: String, steps: [ScriptStepDraft]) async throws -> ScriptSummary {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("scripts"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let stepDicts = steps.map { s -> [String: String] in
            ["label": s.label, "quote": s.quote, "intent": s.intent]
        }
        let body: [String: Any] = [
            "name": name, "description": description, "steps": stepDicts,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        struct CreatedScript: Codable {
            let id: String, name: String, description: String
            let steps: [Step]
            struct Step: Codable { let id, label: String }
        }
        let created = try JSONDecoder().decode(CreatedScript.self, from: data)
        return ScriptSummary(
            id: created.id, name: created.name, description: created.description,
            stepCount: created.steps.count, isPreset: false
        )
    }

    func deleteScript(id: String) async throws {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("scripts/\(id)"))
        req.httpMethod = "DELETE"
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
    }

    // POST /leads — adds a manual lead with no audio. The backend creates
    // a kind="manual" session so the lead flows into the inbox like any
    // recorded visitor. Returns the new session so callers can route into
    // it (e.g. to immediately open the follow-up draft for editing).
    func createManualLead(
        name: String,
        email: String,
        phone: String,
        tag: String,
        address: String?
    ) async throws -> Session {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("leads"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "name": name,
            "email": email,
            "phone": phone,
            "tag": tag,
        ]
        if let a = address, !a.isEmpty { body["address"] = a }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    // GET /sessions — compact list for the home screen.
    func listSessions() async throws -> [SessionSummary] {
        let url = Config.backendURL.appendingPathComponent("sessions")
        let (data, response) = try await self.session.data(from: url)
        try validate(response: response, data: data)
        struct Wrapper: Codable { let sessions: [SessionSummary] }
        return try JSONDecoder().decode(Wrapper.self, from: data).sessions
    }

    // Flip lead_state for a single visitor in a session. The backend keys on
    // (name, speaker) — same composite id iOS uses in VisitorResult.id — so
    // the lookup survives reanalyze runs that regenerate visitor entries.
    // Pass snoozedUntil = .some(nil) to explicitly clear an existing snooze;
    // pass .none to leave it untouched.
    func updateLeadState(
        sessionId: String,
        visitorName: String,
        visitorSpeaker: String?,
        status: LeadState.Status,
        snoozedUntil: String?? = .none
    ) async throws -> LeadState {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("sessions/\(sessionId)/visitors/state"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "name": visitorName,
            "speaker": visitorSpeaker ?? "",
            "status": status.rawValue,
        ]
        if case .some(let val) = snoozedUntil {
            body["snoozed_until"] = val as Any? ?? NSNull()
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LeadState.self, from: data)
    }

    func getSession(id: String) async throws -> Session {
        let url = Config.backendURL.appendingPathComponent("sessions/\(id)")
        let (data, response) = try await self.session.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    // Re-run the analysis pipeline on a session's saved audio with a new
    // speakers_expected hint. Used by the Summary "Re-analyze" control.
    // Returns once the backend has *queued* the work; caller should poll.
    func reprocessSession(id: String, speakersExpected: Int?) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("sessions/\(id)/reprocess"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        if let n = speakersExpected, n > 0 {
            body.appendField(boundary: boundary, name: "speakers_expected", value: String(n))
        }
        body.append("--\(boundary)--\r\n")

        let (data, response) = try await self.session.upload(for: req, from: body)
        try validate(response: response, data: data)
    }

    func pollUntilDone(id: String) async throws -> Session {
        while true {
            let s = try await getSession(id: id)
            if s.status == "ready" || s.status == "error" { return s }
            try await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: – Follow Up Boss

    private static let fubBase = URL(string: "https://api.followupboss.com/v1")!

    private func fubRequest(_ path: String, method: String, body: [String: Any]? = nil, apiKey: String) throws -> URLRequest {
        var req = URLRequest(url: Self.fubBase.appendingPathComponent(path))
        req.httpMethod = method
        // FUB auth: HTTP Basic with the API key as username, empty password.
        let creds = "\(apiKey):"
        let token = Data(creds.utf8).base64EncodedString()
        req.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("OpenHouseBoss", forHTTPHeaderField: "X-System")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    // GET /identity — used by the Connect FUB sheet to validate the key the
    // agent just pasted before saving it to Keychain. Returns the connected
    // account's display name (best-effort) so we can show "Connected as ..."
    func fubTestKey(_ key: String) async throws -> String {
        let req = try fubRequest("identity", method: "GET", apiKey: key)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let name = (json?["name"] as? String)
            ?? (json?["email"] as? String)
            ?? "FUB account"
        return name
    }

    // Pushes a captured lead into FUB. Creates/upserts the person (FUB
    // de-dupes by email server-side), attaches a note with the AI summary +
    // transcript address, and creates a follow-up task due on the snooze
    // date (or +3 days if no snooze set). Idempotent across re-pushes
    // because FUB's POST /people merges on email.
    struct FUBPushResult {
        let personId: Int
        let alreadyExisted: Bool
    }

    func fubPushLead(
        visitor: VisitorResult,
        sessionAddress: String?,
        snoozedUntil: Date?
    ) async throws -> FUBPushResult {
        guard let key = FUBCredential.apiKey else {
            throw APIError.unexpected("Follow Up Boss isn't connected.")
        }

        let v = visitor.visitor
        let a = visitor.analysis
        let nameParts = v.name.split(separator: " ", maxSplits: 1).map(String.init)
        let firstName = nameParts.first ?? v.name
        let lastName  = nameParts.count > 1 ? nameParts[1] : ""

        var emails: [[String: String]] = []
        if !v.email.isEmpty { emails.append(["value": v.email, "type": "home"]) }
        var phones: [[String: String]] = []
        if !v.phone.isEmpty { phones.append(["value": v.phone, "type": "mobile"]) }

        var tags: [String] = [a.tag]
        if let addr = sessionAddress, !addr.isEmpty { tags.append(addr) }

        let personBody: [String: Any] = [
            "firstName": firstName,
            "lastName": lastName,
            "emails": emails,
            "phones": phones,
            "source": "OpenHouseBoss",
            "tags": tags,
            "stage": "Lead",
        ]
        let personReq = try fubRequest("people", method: "POST", body: personBody, apiKey: key)
        let (personData, personResp) = try await self.session.data(for: personReq)
        try validate(response: personResp, data: personData)
        let personJSON = (try? JSONSerialization.jsonObject(with: personData)) as? [String: Any]
        guard let personId = personJSON?["id"] as? Int else {
            throw APIError.unexpected("FUB /people response missing id: \(String(data: personData, encoding: .utf8) ?? "")")
        }
        let alreadyExisted = (personJSON?["created"] as? Bool) == false

        // Note — what the agent learned about this person on the open house
        // floor. Posted best-effort: a note failure shouldn't roll back the
        // person create, that's already useful on its own.
        let noteSubject = sessionAddress.map { "Open house · \($0)" } ?? "Open house notes"
        let noteBody = [
            "Tag: \(a.tag) (score \(a.score))",
            a.signals.isEmpty ? nil : "Signals: \(a.signals.joined(separator: " · "))",
            "",
            a.summary,
            "",
            a.tagReason,
        ].compactMap { $0 }.joined(separator: "\n")
        let noteReqBody: [String: Any] = [
            "personId": personId,
            "subject": noteSubject,
            "body": noteBody,
        ]
        let noteReq = try fubRequest("notes", method: "POST", body: noteReqBody, apiKey: key)
        let (noteData, noteResp) = try await self.session.data(for: noteReq)
        // Don't throw on note failure — log and move on.
        if let http = noteResp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            Log.warn("FUB /notes failed: \(http.statusCode) \(String(data: noteData, encoding: .utf8) ?? "")")
        }

        // Task — a reminder to circle back, due on the snooze date or +3
        // days from now. Format dueDate as YYYY-MM-DD per FUB's API.
        let due = snoozedUntil ?? Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let taskBody: [String: Any] = [
            "personId": personId,
            "name": "Follow up — \(v.name)",
            "dueDate": dateFmt.string(from: due),
        ]
        let taskReq = try fubRequest("tasks", method: "POST", body: taskBody, apiKey: key)
        let (taskData, taskResp) = try await self.session.data(for: taskReq)
        if let http = taskResp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            Log.warn("FUB /tasks failed: \(http.statusCode) \(String(data: taskData, encoding: .utf8) ?? "")")
        }

        return FUBPushResult(personId: personId, alreadyExisted: alreadyExisted)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.unexpected("No HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}

private extension Data {
    mutating func append(_ s: String) { append(Data(s.utf8)) }

    mutating func appendForm(boundary: String, name: String, filename: String, contentType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        append("\r\n")
    }

    mutating func appendField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(value)
        append("\r\n")
    }
}
