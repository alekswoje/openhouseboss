import AuthenticationServices
import Foundation
import Observation
import Security
import UIKit

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

    // Attaches the saved Authorization: Bearer header so every backend call
    // is automatically scoped to the signed-in user. Keep request mutation
    // in one place so individual call sites don't forget.
    private func authorize(_ req: inout URLRequest) {
        if let token = Keychain.get(AuthStore.tokenKey) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    // Cold-start-tolerant POST for IDEMPOTENT ops (refine draft, AI agent
    // ask, etc.) that are safe to retry. Same retry strategy as
    // coldStartGET but works with a pre-built URLRequest (since POST
    // bodies are set by the caller). Retries on URLError transients AND
    // on HTTP 502/503/504 — those usually mean Render's edge couldn't
    // talk to the origin (cold start mid-flight), which a quick retry
    // typically clears.
    //
    // DO NOT use this for non-idempotent ops like send_email — they
    // would silently double-send. Use the single-shot path for those
    // and surface failures to the user.
    // Backend runs on Render's paid plan (no cold starts), so the dyno is
    // always warm. We still retry on transient 502/503/504 because
    // Cloudflare can briefly fail to reach the origin, but per-attempt
    // timeouts are tight: Haiku rewrites finish in 1-3s on a warm worker,
    // so anything past ~20s means something's really wrong and a retry
    // is overdue. Worst case total: 20 + 1 + 8 + 1 + 8 ≈ 38s, not minutes.
    private func coldStartPOST(
        request original: URLRequest,
        firstTimeout: TimeInterval = 20,
        retryTimeout: TimeInterval = 8,
        maxAttempts: Int = 3
    ) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            var req = original
            req.timeoutInterval = attempt == 0 ? firstTimeout : retryTimeout
            do {
                let (data, response) = try await self.session.data(for: req)
                if let http = response as? HTTPURLResponse,
                   [502, 503, 504].contains(http.statusCode) {
                    // Render / Cloudflare edge failed to reach a healthy
                    // worker. Treat as transient and retry.
                    lastError = APIError.http(http.statusCode,
                                              String(data: data, encoding: .utf8) ?? "")
                    if attempt < maxAttempts - 1 {
                        // Short backoff — the worker should be hot now.
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        continue
                    }
                    return (data, response)
                }
                return (data, response)
            } catch let urlErr as URLError {
                switch urlErr.code {
                case .timedOut,
                     .cannotConnectToHost,
                     .networkConnectionLost,
                     .dnsLookupFailed,
                     .notConnectedToInternet:
                    lastError = urlErr
                    if attempt < maxAttempts - 1 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        continue
                    }
                    throw urlErr
                default:
                    throw urlErr
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    // Resilient GET — short timeout per attempt + retry on transient
    // network errors so a single dropped packet doesn't show as an empty
    // Home/Leads screen. Backend is on Render's paid plan (always warm),
    // so we don't need huge timeouts. Authoritative server errors
    // (4xx/5xx) are NOT retried — they're forwarded via `validate`.
    private func coldStartGET(
        path: String,
        timeout: TimeInterval = 15,
        maxAttempts: Int = 3
    ) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            var req = URLRequest(url: Config.backendURL.appendingPathComponent(path))
            req.timeoutInterval = timeout
            authorize(&req)
            do {
                return try await self.session.data(for: req)
            } catch let urlErr as URLError {
                // Retry only on the errors that look like "backend is asleep
                // or the network just hiccuped" — not on auth/host config
                // failures the user can't fix by waiting.
                switch urlErr.code {
                case .timedOut,
                     .cannotConnectToHost,
                     .networkConnectionLost,
                     .dnsLookupFailed,
                     .notConnectedToInternet:
                    lastError = urlErr
                    if attempt < maxAttempts - 1 {
                        // 1s, then 2s. Short enough that the user doesn't
                        // wait forever; long enough that Render's wake-up
                        // typically completes by the second/third try.
                        let delay = UInt64((attempt + 1) * 1_000_000_000)
                        try? await Task.sleep(nanoseconds: delay)
                        continue
                    }
                    throw urlErr
                default:
                    throw urlErr
                }
            } catch {
                throw error
            }
        }
        // Unreachable, but the compiler can't tell.
        throw lastError ?? URLError(.unknown)
    }

    // Fire-and-forget ping that pre-touches the backend during the splash.
    // The dyno is always warm (paid plan), but a fresh deploy still has to
    // import Python modules on the first hit; doing that during the splash
    // means the user's first real action is fast. Cheap insurance — runs
    // detached, errors ignored.
    func warmup() async {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("healthz"))
        req.timeoutInterval = 10
        _ = try? await self.session.data(for: req)
    }

    // GET /auth/me — used to (a) verify a Keychain token on launch and (b)
    // pull the user's name/email/picture/profile for the profile screen.
    // Cold-start tolerant: this is one of the first calls after launch, so
    // it eats most of Render's free-tier wake-up cost.
    func fetchMe() async throws -> AuthUser {
        let (data, response) = try await coldStartGET(path: "auth/me")
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AuthUser.self, from: data)
    }

    // MARK: – Agent profile (brokerage / license / phone / title / tagline / headshot)

    func getProfile() async throws -> AgentProfile {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("me/profile"))
        req.timeoutInterval = 10
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AgentProfile.self, from: data)
    }

    func updateProfile(
        brokerage: String? = nil,
        licenseNumber: String? = nil,
        phone: String? = nil,
        title: String? = nil,
        tagline: String? = nil
    ) async throws -> AgentProfile {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("me/profile"))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        authorize(&req)
        var payload: [String: String] = [:]
        if let brokerage     { payload["brokerage"]      = brokerage }
        if let licenseNumber { payload["license_number"] = licenseNumber }
        if let phone         { payload["phone"]          = phone }
        if let title         { payload["title"]          = title }
        if let tagline       { payload["tagline"]        = tagline }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AgentProfile.self, from: data)
    }

    // Upload the headshot as raw image data — backend writes it to disk and
    // updates the profile's headshot_url. Caller passes UIImage's JPEG
    // representation (default quality 0.85 = a reasonable email-friendly
    // ~50-200KB for a square crop).
    func uploadHeadshot(data: Data, contentType: String = "image/jpeg") async throws -> AgentProfile {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("me/profile/headshot"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        authorize(&req)
        var body = Data()
        body.appendForm(boundary: boundary, name: "file", filename: "headshot.jpg",
                        contentType: contentType, data: data)
        body.append("--\(boundary)--\r\n")
        let (respData, response) = try await uploadWithRetry(req, body: body)
        try validate(response: response, data: respData)
        return try JSONDecoder().decode(AgentProfile.self, from: respData)
    }

    func deleteHeadshot() async throws -> AgentProfile {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("me/profile/headshot"))
        req.httpMethod = "DELETE"
        req.timeoutInterval = 10
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AgentProfile.self, from: data)
    }

    // Authenticated URL for the agent's own headshot — what the iOS
    // profile editor displays. We return the URL request (not the URL)
    // so callers can hand it to AsyncImage / URLSession with the JWT
    // attached. Cache-buster comes from AgentProfile.headshotUrl.
    func headshotRequest(relativePath: String) -> URLRequest {
        var req = URLRequest(url: Config.backendURL
            .appendingPathComponent(relativePath.trimmingCharacters(in: .init(charactersIn: "/"))))
        authorize(&req)
        return req
    }

    // Authenticated GET for a session's recorded audio. Used by
    // SessionStore.continueRecording when local chunks are gone — we pull
    // the backend's authoritative recording and seed chunk_000.m4a so the
    // resumed snapshot still includes the prior session's audio.
    func audioFetchRequest(sessionId: String) -> URLRequest {
        var req = URLRequest(url: Config.backendURL
            .appendingPathComponent("sessions/\(sessionId)/audio"))
        req.timeoutInterval = 60
        authorize(&req)
        return req
    }

    // iOS-only path: upload audio, let the backend synthesize visitors from
    // diarized speakers. Returns the freshly-created session (status=processing).
    // `speakersExpected` is forwarded to AssemblyAI as a diarization hint.
    // `scriptId` attaches a preset script for post-session coverage grading.
    // `name` is the agent's nickname for the session (optional).
    func createSession(audioURL: URL, address: String? = nil, name: String? = nil, speakersExpected: Int? = nil, scriptId: String? = nil) async throws -> Session {
        try await createSession(audioURL: audioURL, address: address, name: name, visitorsCSV: nil, speakersExpected: speakersExpected, scriptId: scriptId)
    }

    // Kiosk path: upload audio plus a sign-in CSV so the backend can match
    // named visitors to speakers.
    func createSession(audioURL: URL, address: String?, name: String? = nil, visitors: [VisitorInput], speakersExpected: Int? = nil, scriptId: String? = nil) async throws -> Session {
        let csv = (["name,email,phone,signed_in_at"]
            + visitors.map { "\($0.name),\($0.email),\($0.phone)," }).joined(separator: "\n")
        return try await createSession(audioURL: audioURL, address: address, name: name, visitorsCSV: Data(csv.utf8), speakersExpected: speakersExpected, scriptId: scriptId)
    }

    private func createSession(audioURL: URL, address: String?, name: String?, visitorsCSV: Data?, speakersExpected: Int?, scriptId: String?) async throws -> Session {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("sessions"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // Uploads ride a long-lived connection — bump the per-request idle
        // timeout from the default 8s. Whole upload still bounded by the
        // session's resource timeout (120s).
        req.timeoutInterval = 60
        authorize(&req)

        var body = Data()
        if let a = address?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
            body.appendField(boundary: boundary, name: "address", value: a)
        }
        if let nm = name?.trimmingCharacters(in: .whitespacesAndNewlines), !nm.isEmpty {
            body.appendField(boundary: boundary, name: "name", value: nm)
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

        let (data, response) = try await uploadWithRetry(req, body: body)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    // Wraps URLSession.upload with the same transient-error retry policy as
    // coldStartPOST. iPhones routinely drop URLError.networkConnectionLost
    // (-1005) when the radio handsoff between towers / WiFi-to-cell, even on
    // a "fine" connection. One retry recovers transparently; without it the
    // agent has to redo the whole recording.
    //
    // Duplicate-session risk: if the first attempt completed server-side but
    // the response was lost, we'll create a second session. The orphan stays
    // in "processing" until it errors out, but the user only ever sees the
    // one we got a response for. That's a much better failure mode than
    // forcing them to start over.
    private func uploadWithRetry(
        _ original: URLRequest,
        body: Data,
        maxAttempts: Int = 3
    ) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await self.session.upload(for: original, from: body)
            } catch let urlErr as URLError {
                switch urlErr.code {
                case .networkConnectionLost,
                     .timedOut,
                     .cannotConnectToHost,
                     .dnsLookupFailed,
                     .notConnectedToInternet:
                    lastError = urlErr
                    if attempt < maxAttempts - 1 {
                        let delay = UInt64((attempt + 1) * 1_000_000_000)
                        try? await Task.sleep(nanoseconds: delay)
                        continue
                    }
                    throw urlErr
                default:
                    throw urlErr
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    // Mid-session snapshot upload. Sends the entire concatenated audio so
    // far so the backend's diarization stays globally consistent across
    // snapshots. `analysisDepth = .light` skips per-visitor Claude calls
    // (the expensive part) and only re-transcribes + re-grades coverage;
    // `.full` re-runs the whole pipeline (used by the final end-of-session
    // upload). Returns the queued session ({id, status}) — caller should
    // poll /sessions/{id} for the updated `is_live` + `last_snapshot_at`
    // and the refreshed result.
    enum AnalysisDepth: String {
        case light, full
    }
    func uploadSnapshot(
        sessionId: String,
        audioURL: URL,
        depth: AnalysisDepth = .light,
        speakersExpected: Int? = nil
    ) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: Config.backendURL.appendingPathComponent(
            "sessions/\(sessionId)/snapshot"
        ))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        authorize(&req)

        var body = Data()
        body.appendField(boundary: boundary, name: "analysis_depth", value: depth.rawValue)
        if let n = speakersExpected, n > 0 {
            body.appendField(boundary: boundary, name: "speakers_expected", value: String(n))
        }
        let audioData = try Data(contentsOf: audioURL)
        body.appendForm(boundary: boundary, name: "audio", filename: "snapshot.m4a",
                        contentType: "audio/m4a", data: audioData)
        body.append("--\(boundary)--\r\n")

        let (data, response) = try await uploadWithRetry(req, body: body)
        try validate(response: response, data: data)
    }

    // GET /scripts — presets + user-created.
    func listScripts() async throws -> [ScriptSummary] {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("scripts"))
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        struct Wrapper: Codable { let scripts: [ScriptSummary] }
        return try JSONDecoder().decode(Wrapper.self, from: data).scripts
    }

    // POST /scripts — create a new user script with steps.
    func createScript(name: String, description: String, steps: [ScriptStepDraft]) async throws -> ScriptSummary {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("scripts"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&req)
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
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
    }

    // PATCH /scripts/{id} — overwrite a user script. Same body shape as
    // createScript. Presets are not editable; returns the updated record.
    func updateScript(id: String, name: String, description: String, steps: [ScriptStepDraft]) async throws -> ScriptSummary {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("scripts/\(id)"))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&req)
        let stepDicts = steps.map { s -> [String: String] in
            ["label": s.label, "quote": s.quote, "intent": s.intent]
        }
        let body: [String: Any] = [
            "name": name, "description": description, "steps": stepDicts,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        struct UpdatedScript: Codable {
            let id: String, name: String, description: String
            let steps: [Step]
            struct Step: Codable { let id, label: String }
        }
        let updated = try JSONDecoder().decode(UpdatedScript.self, from: data)
        return ScriptSummary(
            id: updated.id, name: updated.name, description: updated.description,
            stepCount: updated.steps.count, isPreset: false
        )
    }

    // GET /scripts/{id} — full script with all step bodies, used by the
    // iPad script editor to populate the form when editing existing scripts.
    struct ScriptDetailDTO: Codable {
        let id: String
        let name: String
        let description: String
        let steps: [Step]
        struct Step: Codable {
            let id: String
            let label: String
            let quote: String?
            let intent: String?
            let section: String?
        }
    }
    func getScript(id: String) async throws -> ScriptDetailDTO {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("scripts/\(id)"))
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ScriptDetailDTO.self, from: data)
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
        authorize(&req)
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
    // Cold-start tolerant: this fires from the Home/Leads `.task {}` on
    // launch and the 8s default would lose to a sleeping Render service.
    func listSessions() async throws -> [SessionSummary] {
        let (data, response) = try await coldStartGET(path: "sessions")
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
        authorize(&req)

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
        // Leads inbox fans out one of these per session in parallel on
        // launch, so a single drop would leave a row missing. Retry with
        // a short timeout — backend is always warm so each call lands in
        // a couple seconds.
        let (data, response) = try await coldStartGET(
            path: "sessions/\(id)", timeout: 15, maxAttempts: 3
        )
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    // Update a session's agent-set nickname. Empty string clears it back
    // to nil so the display falls through to address. Used by the inline
    // rename control on SummaryView and the End-Session name prompt.
    func renameSession(id: String, name: String) async throws {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("sessions/\(id)"))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        authorize(&req)
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
    }

    // Permanently delete a session and all its on-disk artifacts. The
    // confirmation dialog is in the UI — by the time we get here, the user
    // has already approved the destructive action.
    func deleteSession(id: String) async throws {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("sessions/\(id)"))
        req.httpMethod = "DELETE"
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
    }

    // Remove a single visitor (lead) from a session by their position in
    // the result.visitors array. The session itself stays around so the
    // recording + transcript remain available for other leads.
    func deleteVisitor(sessionId: String, visitorIndex: Int) async throws {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent(
            "sessions/\(sessionId)/visitors/\(visitorIndex)"))
        req.httpMethod = "DELETE"
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
    }

    // MARK: – MLS Grid (address autocomplete on the New-Listing form)

    // What the backend's autocomplete dropdown serves up. All optional
    // because demo records often arrive with bedrooms/baths/sqft missing
    // — the UI just hides whichever stat is nil.
    struct MLSSuggestion: Codable, Hashable, Identifiable {
        let listing_id: String
        let address: String?
        let city: String?
        let state: String?
        let postal_code: String?
        let list_price: Int?
        let bedrooms: Int?
        let bathrooms_total: Double?
        let living_area: Int?
        let standard_status: String?
        let photos_count: Int?
        var id: String { listing_id }
    }

    struct MLSProperty: Codable {
        let listing_id: String
        let address: String?
        let city: String?
        let state: String?
        let postal_code: String?
        let county: String?
        let subdivision: String?
        let list_price: Int?
        let bedrooms: Int?
        let bathrooms_total: Double?
        let living_area: Int?
        let lot_size_sqft: Double?
        let year_built: Int?
        let latitude: Double?
        let longitude: Double?
        let photos_count: Int?
        let public_remarks: String?
        let list_agent_name: String?
        let list_office_name: String?
        let standard_status: String?
    }

    // Type-ahead lookup on the New-Listing screen. Returns up to `limit`
    // active-residential suggestions from the locally-replicated MLS feed.
    // Caller debounces; backend FTS is fast enough that 150ms is comfortable.
    func mlsAutocomplete(query: String, limit: Int = 10) async throws -> [MLSSuggestion] {
        var comps = URLComponents(url: Config.backendURL.appendingPathComponent("mls/autocomplete"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 10
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        struct Wrapper: Codable { let suggestions: [MLSSuggestion] }
        return try JSONDecoder().decode(Wrapper.self, from: data).suggestions
    }

    // Full normalized property record for an agent-selected suggestion.
    func mlsProperty(listingId: String) async throws -> MLSProperty {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("mls/property/\(listingId)"))
        req.timeoutInterval = 10
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(MLSProperty.self, from: data)
    }

    // MARK: – Contact verification (kiosk form)

    struct ContactCheck: Codable {
        let valid: Bool
        let reason: String?
        let formatted: String?
        let e164: String?
    }

    struct ContactVerifyResult: Codable {
        let email: ContactCheck?
        let phone: ContactCheck?
    }

    func verifyContact(email: String? = nil, phone: String? = nil) async throws -> ContactVerifyResult {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("verify/contact"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [:]
        if let email { body["email"] = email }
        if let phone { body["phone"] = phone }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ContactVerifyResult.self, from: data)
    }

    // MARK: – Gmail send (separate from sign-in OAuth)

    struct GmailStatus: Codable {
        let connected: Bool
        let email: String?
        // Optional Send-as alias the agent has set. When present, the
        // backend stamps it on the From: header of every outgoing
        // follow-up (Gmail will silently fall back if the alias isn't
        // verified inside Gmail Settings → Accounts → Send mail as).
        let sendFrom: String?

        enum CodingKeys: String, CodingKey {
            case connected, email
            case sendFrom = "send_from"
        }
    }

    func gmailStatus() async throws -> GmailStatus {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("auth/gmail/status"))
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(GmailStatus.self, from: data)
    }

    func disconnectGmail() async throws {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("auth/gmail/disconnect"))
        req.httpMethod = "POST"
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
    }

    /// Save (or clear with address=nil) the Send-as alias for the
    /// signed-in agent. Backend echoes back the full Gmail status.
    func setGmailSendFrom(address: String?) async throws -> GmailStatus {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("auth/gmail/send_from"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&req)
        let body: [String: Any] = ["address": (address ?? "") as Any]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(GmailStatus.self, from: data)
    }

    struct SendEmailResult: Codable {
        let sent: Bool
        let messageId: String?
        let leadState: LeadState?

        enum CodingKeys: String, CodingKey {
            case sent
            case messageId = "message_id"
            case leadState = "lead_state"
        }
    }

    enum SendEmailError: Error, LocalizedError {
        case gmailNotConnected
        case noRecipient
        case generic(String)

        var errorDescription: String? {
            switch self {
            case .gmailNotConnected: return "Connect Gmail to send."
            case .noRecipient:       return "No email on file for this lead."
            case .generic(let s):    return s
            }
        }
    }

    func sendVisitorEmail(
        sessionId: String,
        visitorName: String,
        visitorSpeaker: String?,
        to: String? = nil,
        subject: String? = nil,
        body: String? = nil
    ) async throws -> SendEmailResult {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent(
            "sessions/\(sessionId)/visitors/send_email"
        ))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Gmail send is synchronous on the backend (with its own 20s
        // timeout talking to Google) and Render's paid dyno is always
        // warm, so 30s is plenty: ~1s to hit the worker, up to 20s for
        // Google, a few seconds to write state and respond.
        req.timeoutInterval = 30
        authorize(&req)

        var payload: [String: Any] = [
            "name": visitorName,
            "speaker": visitorSpeaker ?? "",
        ]
        if let to { payload["to"] = to }
        if let subject { payload["subject"] = subject }
        if let body { payload["body"] = body }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await self.session.data(for: req)
        // Distinguish "Gmail not connected" (400 with specific message) from
        // generic failures so the UI can prompt to connect rather than
        // surface a scary error.
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 400 {
                let txt = String(data: data, encoding: .utf8) ?? ""
                if txt.contains("Gmail not connected") {
                    throw SendEmailError.gmailNotConnected
                }
                if txt.contains("No recipient email") {
                    throw SendEmailError.noRecipient
                }
            }
            if !(200..<300).contains(http.statusCode) {
                throw SendEmailError.generic(String(data: data, encoding: .utf8) ?? "Send failed")
            }
        }
        return try JSONDecoder().decode(SendEmailResult.self, from: data)
    }

    // MARK: – Open House Report

    struct ReportEnvelope: Codable {
        let report: SessionReport
        let reportMeta: ReportMeta?

        enum CodingKeys: String, CodingKey {
            case report
            case reportMeta = "report_meta"
        }
    }

    struct ReportSendResult: Codable {
        let sent: Bool
        let to: String
        let messageId: String?
        let reportMeta: ReportMeta?

        enum CodingKeys: String, CodingKey {
            case sent, to
            case messageId = "message_id"
            case reportMeta = "report_meta"
        }
    }

    // Returns nil when the backend reports "report not generated yet" (404).
    // Other errors propagate so the UI can surface them.
    func getReport(sessionId: String) async throws -> ReportEnvelope? {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent(
            "sessions/\(sessionId)/report"
        ))
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return nil
        }
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ReportEnvelope.self, from: data)
    }

    // Triggers a Claude call (~10-30s). Overwrites any cached report,
    // including agent edits — the iOS client warns before calling this
    // when a report already exists.
    func generateReport(sessionId: String) async throws -> ReportEnvelope {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent(
            "sessions/\(sessionId)/report"
        ))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Claude generation is the slow path here. Give it room — Sonnet
        // typically lands in 10-20s for a normal-size open house.
        req.timeoutInterval = 60
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ReportEnvelope.self, from: data)
    }

    // Saves the agent's edits — full report payload, not a diff. Sets
    // `edited: true` on report_meta.
    func updateReport(sessionId: String, report: SessionReport) async throws -> ReportEnvelope {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent(
            "sessions/\(sessionId)/report"
        ))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        authorize(&req)
        req.httpBody = try JSONEncoder().encode(report)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ReportEnvelope.self, from: data)
    }

    // Send the report to the homeowner via the agent's connected Gmail.
    // `to` defaults to session.homeownerEmail server-side when nil.
    func sendReport(
        sessionId: String,
        to: String? = nil,
        subject: String? = nil,
        greeting: String? = nil
    ) async throws -> ReportSendResult {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent(
            "sessions/\(sessionId)/report/send"
        ))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        authorize(&req)
        var payload: [String: Any] = [:]
        if let to { payload["to"] = to }
        if let subject { payload["subject"] = subject }
        if let greeting { payload["greeting"] = greeting }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await self.session.data(for: req)
        // Reuse the visitor-send error mapping — same Gmail backend, same
        // failure modes (not connected, no recipient, generic).
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 400 {
                let txt = String(data: data, encoding: .utf8) ?? ""
                if txt.contains("Gmail not connected") {
                    throw SendEmailError.gmailNotConnected
                }
                if txt.contains("No recipient email") {
                    throw SendEmailError.noRecipient
                }
            }
            if !(200..<300).contains(http.statusCode) {
                throw SendEmailError.generic(String(data: data, encoding: .utf8) ?? "Send failed")
            }
        }
        return try JSONDecoder().decode(ReportSendResult.self, from: data)
    }

    // URL to the rendered HTML report. iOS loads this in a WKWebView for
    // the PDF export flow (WKWebView → UIPrintPageRenderer → PDF data).
    // Includes the JWT as a header — we pass an authenticated URLRequest
    // to the webview rather than the bare URL.
    func reportHtmlRequest(sessionId: String) -> URLRequest {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent(
            "sessions/\(sessionId)/report.html"
        ))
        authorize(&req)
        return req
    }

    // Update the homeowner's email/name on a session. Pass empty string to
    // clear a field; pass nil to leave it untouched.
    func setHomeowner(
        sessionId: String,
        email: String?,
        name: String?
    ) async throws {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent(
            "sessions/\(sessionId)/homeowner"
        ))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        authorize(&req)
        var payload: [String: Any] = [:]
        if let email { payload["homeowner_email"] = email }
        if let name { payload["homeowner_name"] = name }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
    }

    // MARK: – Lead CRM (notes, tasks, history, schedule)

    struct LeadStateEnvelope: Codable {
        let leadState: LeadState
        enum CodingKeys: String, CodingKey { case leadState = "lead_state" }
    }

    private func crmRequest(_ path: String, method: String, body: [String: Any]? = nil) throws -> URLRequest {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&req)
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    func addNote(sessionId: String, visitorName: String, visitorSpeaker: String?, body: String) async throws -> LeadState {
        let req = try crmRequest("sessions/\(sessionId)/visitors/notes", method: "POST", body: [
            "name": visitorName,
            "speaker": visitorSpeaker ?? "",
            "body": body,
        ])
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LeadStateEnvelope.self, from: data).leadState
    }

    func updateNote(sessionId: String, noteId: String, visitorName: String, visitorSpeaker: String?, body: String) async throws -> LeadState {
        let req = try crmRequest("sessions/\(sessionId)/visitors/notes/\(noteId)", method: "PATCH", body: [
            "name": visitorName,
            "speaker": visitorSpeaker ?? "",
            "body": body,
        ])
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LeadStateEnvelope.self, from: data).leadState
    }

    func deleteNote(sessionId: String, noteId: String, visitorName: String, visitorSpeaker: String?) async throws -> LeadState {
        var comps = URLComponents(url: Config.backendURL.appendingPathComponent(
            "sessions/\(sessionId)/visitors/notes/\(noteId)"
        ), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "name", value: visitorName),
            URLQueryItem(name: "speaker", value: visitorSpeaker ?? ""),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LeadStateEnvelope.self, from: data).leadState
    }

    func addTask(sessionId: String, visitorName: String, visitorSpeaker: String?, title: String, dueAt: String? = nil) async throws -> LeadState {
        var body: [String: Any] = [
            "name": visitorName,
            "speaker": visitorSpeaker ?? "",
            "title": title,
        ]
        if let dueAt { body["due_at"] = dueAt }
        let req = try crmRequest("sessions/\(sessionId)/visitors/tasks", method: "POST", body: body)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LeadStateEnvelope.self, from: data).leadState
    }

    func updateTask(sessionId: String, taskId: String, visitorName: String, visitorSpeaker: String?, done: Bool? = nil, title: String? = nil, dueAt: String?? = .none) async throws -> LeadState {
        var body: [String: Any] = [
            "name": visitorName,
            "speaker": visitorSpeaker ?? "",
        ]
        if let done { body["done"] = done }
        if let title { body["title"] = title }
        if case .some(let val) = dueAt { body["due_at"] = val as Any? ?? NSNull() }
        let req = try crmRequest("sessions/\(sessionId)/visitors/tasks/\(taskId)", method: "PATCH", body: body)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LeadStateEnvelope.self, from: data).leadState
    }

    func deleteTask(sessionId: String, taskId: String, visitorName: String, visitorSpeaker: String?) async throws -> LeadState {
        var comps = URLComponents(url: Config.backendURL.appendingPathComponent(
            "sessions/\(sessionId)/visitors/tasks/\(taskId)"
        ), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "name", value: visitorName),
            URLQueryItem(name: "speaker", value: visitorSpeaker ?? ""),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LeadStateEnvelope.self, from: data).leadState
    }

    func scheduleEmail(sessionId: String, visitorName: String, visitorSpeaker: String?, sendAt: Date, subject: String? = nil, bodyText: String? = nil, to: String? = nil) async throws -> LeadState {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var body: [String: Any] = [
            "name": visitorName,
            "speaker": visitorSpeaker ?? "",
            "send_at": iso.string(from: sendAt),
        ]
        if let to { body["to"] = to }
        if let subject { body["subject"] = subject }
        if let bodyText { body["body"] = bodyText }
        let req = try crmRequest("sessions/\(sessionId)/visitors/schedule_email", method: "POST", body: body)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LeadStateEnvelope.self, from: data).leadState
    }

    // MARK: – Leads AI agent

    // The agent's reply to a free-text question or send-instruction. It's
    // either an `answer` (text we just display) or a `plan` the agent can
    // review and confirm to fire bulk sends from.
    struct LeadsAgentRecipient: Codable, Identifiable, Hashable {
        let sessionId: String
        let name: String
        let speaker: String?
        let email: String
        let address: String?
        let body: String
        var id: String { "\(sessionId):\(name):\(speaker ?? "")" }
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case name, speaker, email, address, body
        }
    }
    struct LeadsAgentSkipped: Codable, Hashable {
        let name: String
        let reason: String
    }
    struct LeadsAgentReply: Codable, Hashable {
        let kind: String        // "answer" | "plan"
        let text: String?
        let summary: String?
        let action: String?
        let subject: String?
        let recipients: [LeadsAgentRecipient]?
        let skipped: [LeadsAgentSkipped]?
    }
    struct LeadsAgentExecuteResult: Codable, Hashable {
        let sent: Int
        let failed: [LeadsAgentSkipped]
    }

    func askLeadsAgent(message: String) async throws -> LeadsAgentReply {
        let req = try crmRequest(
            "me/leads/agent", method: "POST", body: ["message": message]
        )
        // Asking the agent is read-only — safe to retry on transient 502s.
        let (data, response) = try await coldStartPOST(request: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LeadsAgentReply.self, from: data)
    }

    func executeLeadsAgentPlan(
        subject: String,
        recipients: [LeadsAgentRecipient]
    ) async throws -> LeadsAgentExecuteResult {
        let payload: [String: Any] = [
            "plan": [
                "action": "send_email",
                "subject": subject,
                "recipients": recipients.map { [
                    "session_id": $0.sessionId,
                    "name": $0.name,
                    "speaker": $0.speaker ?? "",
                    "email": $0.email,
                    "address": $0.address ?? "",
                    "body": $0.body,
                ] },
            ]
        ]
        var req = try crmRequest("me/leads/agent/execute", method: "POST", body: payload)
        // N gmail sends in series — give it real headroom.
        req.timeoutInterval = 180
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LeadsAgentExecuteResult.self, from: data)
    }

    // Ask Claude to rewrite the current follow-up draft per the agent's
    // instruction ("too long", "add a CTA about the 1pm Saturday open
    // house", etc.). Returns just the new body text — caller drops it
    // back into the editor for review/save. Pass `baseBody` to refine
    // an in-progress edit instead of the saved override.
    func refineDraft(
        sessionId: String,
        visitorName: String,
        visitorSpeaker: String?,
        instruction: String,
        baseBody: String? = nil
    ) async throws -> String {
        var payload: [String: Any] = [
            "name": visitorName,
            "speaker": visitorSpeaker ?? "",
            "instruction": instruction,
        ]
        if let baseBody { payload["base_body"] = baseBody }
        let req = try crmRequest(
            "sessions/\(sessionId)/visitors/draft/refine", method: "POST", body: payload
        )
        // Refine is idempotent — safe to auto-retry on 502/timeout. The
        // first call usually wakes a cold Render dyno; the retry lands
        // on a hot worker and succeeds.
        let (data, response) = try await coldStartPOST(request: req)
        try validate(response: response, data: data)
        struct Wrapper: Codable { let body: String }
        return try JSONDecoder().decode(Wrapper.self, from: data).body
    }

    // Edit a lead's contact info (display name + email + phone). Backend
    // matches by the OLD (name, speaker); speaker stays stable so notes,
    // tasks, schedules, etc. keep working without renaming the lookup key.
    // Pass nil to leave a field unchanged; pass "" to explicitly clear
    // email/phone. Returns the updated visitor entry.
    func updateVisitorContact(
        sessionId: String,
        visitorName: String,
        visitorSpeaker: String?,
        newName: String? = nil,
        newEmail: String? = nil,
        newPhone: String? = nil
    ) async throws -> VisitorResult {
        var payload: [String: Any] = [
            "name": visitorName,
            "speaker": visitorSpeaker ?? "",
        ]
        if let n = newName { payload["new_name"] = n }
        if let e = newEmail { payload["new_email"] = e }
        if let p = newPhone { payload["new_phone"] = p }
        let req = try crmRequest(
            "sessions/\(sessionId)/visitors/contact", method: "PATCH", body: payload
        )
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(VisitorResult.self, from: data)
    }

    // Save an edited follow-up draft. Pass clear=true (with nil body) to wipe
    // the override and fall back to the AI draft.
    func updateDraft(
        sessionId: String,
        visitorName: String,
        visitorSpeaker: String?,
        body: String?,
        subject: String? = nil,
        clear: Bool = false
    ) async throws -> LeadState {
        var payload: [String: Any] = [
            "name": visitorName,
            "speaker": visitorSpeaker ?? "",
        ]
        if clear {
            payload["clear"] = true
        } else {
            payload["body"] = body ?? ""
            if let subject { payload["subject"] = subject }
        }
        let req = try crmRequest(
            "sessions/\(sessionId)/visitors/draft", method: "PATCH", body: payload
        )
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LeadStateEnvelope.self, from: data).leadState
    }

    // MARK: – Templates

    func listTemplates() async throws -> TemplatesEnvelope {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("me/templates"))
        req.httpMethod = "GET"
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(TemplatesEnvelope.self, from: data)
    }

    func createTemplate(name: String, subject: String, body: String, matchHints: String, enabled: Bool = true) async throws -> FollowupTemplate {
        let req = try crmRequest("me/templates", method: "POST", body: [
            "name": name, "subject": subject, "body": body,
            "match_hints": matchHints, "enabled": enabled,
        ])
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(FollowupTemplate.self, from: data)
    }

    func updateTemplate(id: String, name: String, subject: String, body: String, matchHints: String, enabled: Bool = true) async throws -> FollowupTemplate {
        let req = try crmRequest("me/templates/\(id)", method: "PATCH", body: [
            "name": name, "subject": subject, "body": body,
            "match_hints": matchHints, "enabled": enabled,
        ])
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(FollowupTemplate.self, from: data)
    }

    func deleteTemplate(id: String) async throws {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("me/templates/\(id)"))
        req.httpMethod = "DELETE"
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
    }

    // MARK: – Offers / campaigns

    func listOffers() async throws -> [Offer] {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("me/offers"))
        req.httpMethod = "GET"
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(OffersEnvelope.self, from: data).offers
    }

    func createOffer(name: String, body: String, enabled: Bool = true) async throws -> Offer {
        let req = try crmRequest("me/offers", method: "POST", body: [
            "name": name, "body": body, "enabled": enabled,
        ])
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Offer.self, from: data)
    }

    func updateOffer(id: String, name: String, body: String, enabled: Bool) async throws -> Offer {
        let req = try crmRequest("me/offers/\(id)", method: "PATCH", body: [
            "name": name, "body": body, "enabled": enabled,
        ])
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Offer.self, from: data)
    }

    func setOfferEnabled(id: String, enabled: Bool) async throws -> Offer {
        let req = try crmRequest("me/offers/\(id)/enabled", method: "POST", body: [
            "enabled": enabled,
        ])
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Offer.self, from: data)
    }

    func setTemplateEnabled(id: String, enabled: Bool) async throws -> FollowupTemplate {
        let req = try crmRequest("me/templates/\(id)/enabled", method: "POST", body: [
            "enabled": enabled,
        ])
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(FollowupTemplate.self, from: data)
    }

    func deleteOffer(id: String) async throws {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("me/offers/\(id)"))
        req.httpMethod = "DELETE"
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
    }

    func setForceTemplates(_ force: Bool) async throws -> Bool {
        let req = try crmRequest("me/force_templates", method: "POST", body: ["force": force])
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        struct Wrapper: Codable {
            let forceTemplates: Bool
            enum CodingKeys: String, CodingKey { case forceTemplates = "force_templates" }
        }
        return try JSONDecoder().decode(Wrapper.self, from: data).forceTemplates
    }

    func cancelScheduledEmail(sessionId: String, visitorName: String, visitorSpeaker: String?) async throws -> LeadState {
        var comps = URLComponents(url: Config.backendURL.appendingPathComponent(
            "sessions/\(sessionId)/visitors/schedule_email"
        ), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "name", value: visitorName),
            URLQueryItem(name: "speaker", value: visitorSpeaker ?? ""),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(LeadStateEnvelope.self, from: data).leadState
    }

    // Re-run the analysis pipeline on a session's saved audio with a new
    // speakers_expected hint. Used by the Summary "Re-analyze" control.
    // Returns once the backend has *queued* the work; caller should poll.
    func reprocessSession(id: String, speakersExpected: Int?) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("sessions/\(id)/reprocess"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        authorize(&req)

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

    // Fan-out diarization A/B test — backend runs the saved audio through
    // AssemblyAI, Deepgram, and Speechmatics in parallel and returns
    // speaker-labeled transcripts for each. Used by the session detail
    // "Compare providers" affordance to evaluate diarization quality on
    // real recordings without leaving the app.
    func abTestSession(id: String) async throws -> AbTestResponse {
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("sessions/\(id)/abtest"))
        req.httpMethod = "POST"
        // Real wall time: Speechmatics polls every 2s and can take 30-60s
        // on top of AAI's 5-15s. Push the timeout well past worst case so
        // we don't drop the result right before it lands.
        req.timeoutInterval = 240
        authorize(&req)
        let (data, response) = try await self.session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AbTestResponse.self, from: data)
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
        req.setValue("OpenHouseCopilot", forHTTPHeaderField: "X-System")
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
            "source": "OpenHouseCopilot",
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

// MARK: – Auth (Google Sign-In via backend-brokered OAuth)

// Single source of truth for "is the agent signed in?". Holds the backend
// JWT (Keychain-backed) and the latest /auth/me profile. RootView gates on
// `currentUser` — nil means show LoginView, set means show the main app.
@MainActor
@Observable
final class AuthStore {
    static let shared = AuthStore()

    nonisolated static let tokenKey = "auth_token"
    private static let cachedUserKey = "auth_cached_user"
    private static let welcomedUserIdsKey = "auth_welcomed_user_ids"

    var currentUser: AuthUser?
    var loading: Bool
    var lastError: String?

    var token: String? { Keychain.get(Self.tokenKey) }
    var isSignedIn: Bool { currentUser != nil }

    // True the first time this user-id is welcomed. Flip to false after the
    // welcome overlay has run once for them so we say "Welcome back" on every
    // subsequent launch.
    var isFirstWelcome: Bool {
        guard let uid = currentUser?.id else { return true }
        let welcomed = UserDefaults.standard.stringArray(forKey: Self.welcomedUserIdsKey) ?? []
        return !welcomed.contains(uid)
    }

    func markWelcomed() {
        guard let uid = currentUser?.id else { return }
        var welcomed = UserDefaults.standard.stringArray(forKey: Self.welcomedUserIdsKey) ?? []
        guard !welcomed.contains(uid) else { return }
        welcomed.append(uid)
        UserDefaults.standard.set(welcomed, forKey: Self.welcomedUserIdsKey)
    }

    private init() {
        // Seed currentUser from the cached profile so the UI can render
        // immediately on cold launch — before /auth/me round-trips. If the
        // token is missing or revoked we'll clear this in restore().
        if Keychain.get(Self.tokenKey) != nil,
           let data = UserDefaults.standard.data(forKey: Self.cachedUserKey),
           let cached = try? JSONDecoder().decode(AuthUser.self, from: data) {
            self.currentUser = cached
            // Already signed in optimistically — no splash gate needed.
            self.loading = false
        } else {
            self.loading = true
        }
    }

    private static func cacheUser(_ user: AuthUser?) {
        if let user, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: cachedUserKey)
        } else {
            UserDefaults.standard.removeObject(forKey: cachedUserKey)
        }
    }

    // Called from RootView on app launch. If we have a saved token, refresh
    // /auth/me in the background to pick up profile changes — but only treat
    // an authoritative 401/403 as "sign out". Transient errors (network,
    // 5xx, timeout) keep the cached session so the agent isn't logged out
    // by a flaky connection.
    func restore() async {
        guard token != nil else {
            await MainActor.run {
                self.currentUser = nil
                Self.cacheUser(nil)
                self.loading = false
            }
            return
        }
        do {
            let user = try await APIClient.shared.fetchMe()
            await MainActor.run {
                self.currentUser = user
                Self.cacheUser(user)
                self.loading = false
            }
        } catch {
            // Only wipe credentials on definitive auth failures. Everything
            // else (offline, slow Render, brief Cloudflare 502) keeps the
            // user signed in with the cached profile.
            let isAuthFailure: Bool = {
                if case let APIError.http(status, _) = error, status == 401 || status == 403 {
                    return true
                }
                return false
            }()
            if isAuthFailure {
                Keychain.remove(Self.tokenKey)
                await MainActor.run {
                    self.currentUser = nil
                    Self.cacheUser(nil)
                    self.loading = false
                }
            } else {
                await MainActor.run {
                    // Keep the cached user (if any) so the UI doesn't bounce
                    // back to the login screen on a transient hiccup.
                    self.loading = false
                }
            }
        }
    }

    // Re-fetch /auth/me and update currentUser in place. Used after
    // edits to the profile so other screens (avatar in IPadProfile, the
    // report's email signature when re-rendered) see the new values
    // without a full app re-launch. Silently ignores transient errors —
    // the worst case is a stale cached profile.
    func refreshMe() async {
        guard token != nil else { return }
        if let user = try? await APIClient.shared.fetchMe() {
            currentUser = user
            Self.cacheUser(user)
        }
    }

    // Drives the ASWebAuthenticationSession dance: open the backend's
    // /auth/google/start in a system-managed webview, listen for the
    // com.openhouseboss.app:// redirect, pull the token out, verify with
    // /auth/me, and stash both.
    func signInWithGoogle(presentationAnchor: ASPresentationAnchor) async {
        await MainActor.run {
            self.lastError = nil
            self.loading = true
        }
        do {
            let token = try await GoogleAuthDriver.run(presentationAnchor: presentationAnchor)
            try Keychain.set(token, for: Self.tokenKey)
            let user = try await APIClient.shared.fetchMe()
            await MainActor.run {
                self.currentUser = user
                Self.cacheUser(user)
                self.loading = false
            }
        } catch {
            Keychain.remove(Self.tokenKey)
            await MainActor.run {
                self.currentUser = nil
                Self.cacheUser(nil)
                self.loading = false
                if let asError = error as? ASWebAuthenticationSessionError, asError.code == .canceledLogin {
                    // User backed out — not an error worth surfacing.
                    self.lastError = nil
                } else {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func signOut() {
        Keychain.remove(Self.tokenKey)
        Self.cacheUser(nil)
        currentUser = nil
    }
}

struct AuthUser: Codable, Hashable {
    let id: String
    let email: String?
    let name: String?
    let picture: String?
    // Agent profile — same shape as the backend's profile_for() return.
    // Optional so legacy cached AuthUsers (decoded from UserDefaults on
    // launch before this field existed) still parse cleanly.
    var profile: AgentProfile?
}

// Branding the agent puts on outgoing emails (Open House Report
// signature today; future follow-ups will use the same block). Strings
// default to "" so SwiftUI form bindings don't have to special-case nil.
struct AgentProfile: Codable, Hashable {
    var brokerage: String = ""
    var licenseNumber: String = ""
    var phone: String = ""
    var title: String = ""
    var tagline: String = ""
    // Relative URL like "/me/profile/headshot?v=1700000000" — expand
    // against Config.backendURL. nil = no headshot uploaded.
    var headshotUrl: String?

    enum CodingKeys: String, CodingKey {
        case brokerage, phone, title, tagline
        case licenseNumber = "license_number"
        case headshotUrl = "headshot_url"
    }

    static let empty = AgentProfile()

    // True when at least one branded field is set — drives the "Set up
    // branding" callout in the Profile screen.
    var hasBranding: Bool {
        !brokerage.isEmpty || !licenseNumber.isEmpty || !phone.isEmpty
        || !title.isEmpty || !tagline.isEmpty || headshotUrl != nil
    }
}

// ASWebAuthenticationSession wrapper. Adapts the callback-based API to
// async/await and pulls the `token` query param out of the success URL.
enum GoogleAuthDriver {
    enum AuthError: Error, LocalizedError {
        case missingToken
        var errorDescription: String? { "Sign-in finished but no token came back." }
    }

    @MainActor
    static func run(presentationAnchor: ASPresentationAnchor) async throws -> String {
        let url = Config.backendURL.appendingPathComponent("auth/google/start")
            .appending(queryItems: [URLQueryItem(name: "platform", value: "ios")])
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "com.openhouseboss.app"
            ) { callbackURL, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let callbackURL,
                      let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let token = comps.queryItems?.first(where: { $0.name == "token" })?.value
                else {
                    cont.resume(throwing: AuthError.missingToken)
                    return
                }
                cont.resume(returning: token)
            }
            session.presentationContextProvider = AuthAnchorProvider.shared(anchor: presentationAnchor)
            // Pop into a webview the user is already signed in to — they
            // won't see a Google login form if they already have a session
            // in Safari/iCloud Keychain. prefersEphemeralWebBrowserSession
            // would force a fresh login each time; keep it off for UX.
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
}

// Same pattern as GoogleAuthDriver, but for the secondary Gmail-send grant.
// The backend's /auth/gmail/start needs to know which user is connecting,
// and ASWebAuthenticationSession can't attach Authorization headers, so we
// pass the current session JWT as a query param. Backend verifies it the
// same way as a header bearer.
enum GmailConnectDriver {
    enum ConnectError: Error, LocalizedError {
        case notSignedIn
        case cancelled
        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in before connecting Gmail."
            case .cancelled:   return "Gmail connection cancelled."
            }
        }
    }

    @MainActor
    static func run(presentationAnchor: ASPresentationAnchor) async throws {
        guard let userToken = AuthStore.shared.token else {
            throw ConnectError.notSignedIn
        }
        let url = Config.backendURL.appendingPathComponent("auth/gmail/start")
            .appending(queryItems: [URLQueryItem(name: "user_token", value: userToken)])

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "com.openhouseboss.app"
            ) { callbackURL, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                // The callback URL is `com.openhouseboss.app://gmail-connected`
                // — no payload needed, presence of the callback signals
                // success. The refresh token is already stored server-side.
                if callbackURL != nil {
                    cont.resume(returning: ())
                } else {
                    cont.resume(throwing: ConnectError.cancelled)
                }
            }
            session.presentationContextProvider = AuthAnchorProvider.shared(anchor: presentationAnchor)
            // Force a fresh consent every time — Google omits refresh_token
            // on subsequent grants otherwise, and the backend rejects the
            // callback when refresh_token is missing.
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
}

// ASWebAuthenticationSession wants a UIWindow-ish anchor to attach its
// presentation to. Holding a strong reference here keeps the provider
// alive for the duration of the auth flow.
final class AuthAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static var _shared: AuthAnchorProvider?
    private let anchor: ASPresentationAnchor

    static func shared(anchor: ASPresentationAnchor) -> AuthAnchorProvider {
        let provider = AuthAnchorProvider(anchor: anchor)
        _shared = provider
        return provider
    }

    private init(anchor: ASPresentationAnchor) { self.anchor = anchor }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
