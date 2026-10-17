import Foundation
import AuthenticationServices
import UIKit
import Security

/// Strava OAuth + activity upload. You register a free API application at
/// strava.com/settings/api (Authorization Callback Domain: `localhost`) and
/// paste its Client ID / Secret into Settings; tokens live in the Keychain.
@MainActor
final class StravaService: NSObject, ObservableObject {
    static let clientIDKey = "stravaClientID"
    static let clientSecretKey = "stravaClientSecret"
    static let autoUploadKey = "stravaAutoUpload"
    static let redirectURI = "ridepulse://localhost/strava"

    @Published private(set) var isConnected = false
    @Published private(set) var athleteName: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isBusy = false

    private var authSession: ASWebAuthenticationSession?

    private struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: TimeInterval
        var athleteName: String?
    }

    override init() {
        super.init()
        if let t = loadTokens() {
            isConnected = true
            athleteName = t.athleteName
        }
    }

    static var isAutoUploadEnabled: Bool {
        UserDefaults.standard.object(forKey: autoUploadKey) as? Bool ?? false
    }

    private var clientID: String { UserDefaults.standard.string(forKey: Self.clientIDKey) ?? "" }
    private var clientSecret: String { UserDefaults.standard.string(forKey: Self.clientSecretKey) ?? "" }

    // MARK: - Connect / disconnect

    func connect() {
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            statusMessage = "Enter your Strava Client ID and Secret first."
            return
        }
        var comps = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: "read,activity:write")
        ]
        statusMessage = nil
        let session = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: "ridepulse") { [weak self] url, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        self.statusMessage = "Sign-in failed: \(error.localizedDescription)"
                    }
                    return
                }
                guard let url,
                      let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.statusMessage = "Strava didn't return an authorization code."
                    return
                }
                await self.exchange(code: code)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    func disconnect() {
        deleteTokens()
        isConnected = false
        athleteName = nil
        statusMessage = "Disconnected from Strava."
    }

    private func exchange(code: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let t = try await tokenRequest(["client_id": clientID, "client_secret": clientSecret,
                                            "code": code, "grant_type": "authorization_code"])
            saveTokens(t)
            isConnected = true
            athleteName = t.athleteName
            statusMessage = "Connected to Strava" + (t.athleteName.map { " as \($0)" } ?? "") + "."
        } catch {
            statusMessage = "Token exchange failed: \(error.localizedDescription)"
        }
    }

    private func validAccessToken() async throws -> String {
        guard var t = loadTokens() else { throw StravaError.notConnected }
        if Date().timeIntervalSince1970 > t.expiresAt - 60 {
            let refreshed = try await tokenRequest(["client_id": clientID, "client_secret": clientSecret,
                                                    "refresh_token": t.refreshToken, "grant_type": "refresh_token"])
            t.accessToken = refreshed.accessToken
            t.refreshToken = refreshed.refreshToken
            t.expiresAt = refreshed.expiresAt
            saveTokens(t)
        }
        return t.accessToken
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> Tokens {
        var req = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw StravaError.http(String(data: data, encoding: .utf8) ?? "token error")
        }
        struct R: Decodable {
            let access_token: String; let refresh_token: String; let expires_at: TimeInterval
            struct Athlete: Decodable { let firstname: String?; let lastname: String? }
            let athlete: Athlete?
        }
        let r = try JSONDecoder().decode(R.self, from: data)
        let name = [r.athlete?.firstname, r.athlete?.lastname].compactMap { $0 }.joined(separator: " ")
        return Tokens(accessToken: r.access_token, refreshToken: r.refresh_token,
                      expiresAt: r.expires_at, athleteName: name.isEmpty ? nil : name)
    }

    // MARK: - Upload

    /// Upload a ride as GPX. Returns the Strava activity ID once processed.
    func upload(_ ride: Ride, name: String? = nil) async throws -> Int {
        isBusy = true
        defer { isBusy = false }
        let token = try await validAccessToken()
        let gpx = RideStore.gpxString(for: ride).data(using: .utf8)!
        let boundary = "RidePulse-\(UUID().uuidString)"
        var body = Data()
        func field(_ n: String, _ v: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(n)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
        }
        field("data_type", "gpx")
        field("sport_type", "Ride")
        field("name", name ?? "RidePulse ride")
        field("description", "Recorded with RidePulse")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ride.gpx\"\r\nContent-Type: application/gpx+xml\r\n\r\n".data(using: .utf8)!)
        body.append(gpx)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let code = (resp as? HTTPURLResponse)?.statusCode, code == 201 || code == 200 else {
            throw StravaError.http(String(data: data, encoding: .utf8) ?? "upload rejected")
        }
        struct U: Decodable { let id: Int; let activity_id: Int?; let error: String?; let status: String? }
        var u = try JSONDecoder().decode(U.self, from: data)

        // Poll until Strava finishes processing (usually a few seconds).
        for _ in 0..<15 where u.activity_id == nil && u.error == nil {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            var poll = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads/\(u.id)")!)
            poll.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (d, _) = try await URLSession.shared.data(for: poll)
            u = try JSONDecoder().decode(U.self, from: d)
        }
        if let err = u.error { throw StravaError.http(err) }
        guard let id = u.activity_id else { throw StravaError.http(u.status ?? "Still processing — check Strava in a minute.") }
        statusMessage = "Uploaded to Strava."
        return id
    }

    enum StravaError: LocalizedError {
        case notConnected, http(String)
        var errorDescription: String? {
            switch self {
            case .notConnected: return "Connect Strava in Settings first."
            case .http(let m): return m
            }
        }
    }

    // MARK: - Keychain

    private let keychainAccount = "strava-tokens"

    private func saveTokens(_ t: Tokens) {
        guard let data = try? JSONEncoder().encode(t) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: keychainAccount]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadTokens() -> Tokens? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: keychainAccount,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    private func deleteTokens() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: keychainAccount]
        SecItemDelete(q as CFDictionary)
    }
}

extension StravaService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // ASWebAuthenticationSession calls this on the main thread.
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
