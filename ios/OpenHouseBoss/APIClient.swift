import Foundation

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

actor APIClient {
    static let shared = APIClient()

    // iOS-only path: upload audio, let the backend synthesize visitors from
    // diarized speakers. Returns the freshly-created session (status=processing).
    func createSession(audioURL: URL, address: String? = nil) async throws -> Session {
        try await createSession(audioURL: audioURL, address: address, visitorsCSV: nil)
    }

    // Kiosk path: upload audio plus a sign-in CSV so the backend can match
    // named visitors to speakers.
    func createSession(audioURL: URL, address: String?, visitors: [VisitorInput]) async throws -> Session {
        let csv = (["name,email,phone,signed_in_at"]
            + visitors.map { "\($0.name),\($0.email),\($0.phone)," }).joined(separator: "\n")
        return try await createSession(audioURL: audioURL, address: address, visitorsCSV: Data(csv.utf8))
    }

    private func createSession(audioURL: URL, address: String?, visitorsCSV: Data?) async throws -> Session {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: Config.backendURL.appendingPathComponent("sessions"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        if let a = address?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
            body.appendField(boundary: boundary, name: "address", value: a)
        }
        if let csv = visitorsCSV {
            body.appendForm(boundary: boundary, name: "visitors", filename: "visitors.csv",
                            contentType: "text/csv", data: csv)
        }
        let audioData = try Data(contentsOf: audioURL)
        body.appendForm(boundary: boundary, name: "audio", filename: "recording.m4a",
                        contentType: "audio/m4a", data: audioData)
        body.append("--\(boundary)--\r\n")

        let (data, response) = try await URLSession.shared.upload(for: req, from: body)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    // GET /sessions — compact list for the home screen.
    func listSessions() async throws -> [SessionSummary] {
        let url = Config.backendURL.appendingPathComponent("sessions")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)
        struct Wrapper: Codable { let sessions: [SessionSummary] }
        return try JSONDecoder().decode(Wrapper.self, from: data).sessions
    }

    func getSession(id: String) async throws -> Session {
        let url = Config.backendURL.appendingPathComponent("sessions/\(id)")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func pollUntilDone(id: String) async throws -> Session {
        while true {
            let s = try await getSession(id: id)
            if s.status == "ready" || s.status == "error" { return s }
            try await Task.sleep(for: .seconds(2))
        }
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
