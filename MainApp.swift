import SwiftUI
import AVFoundation
import Combine
import Foundation

struct Company: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct Group: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct Location: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct User: Codable, Identifiable, Hashable {
    let id: Int?
    let name: String
    let email: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(email)
    }
    
    static func == (lhs: User, rhs: User) -> Bool {
        return lhs.name == rhs.name && lhs.email == rhs.email
    }
}

enum ProcessType: String, CaseIterable, Hashable {
    case shipping = "出荷"
    case return_ = "返却"
    case disposal = "廃棄"
    
    var displayName: String {
        return self.rawValue
    }
}

struct ScanResult: Codable {
    let success: Bool
    let message: String?
    let item: ScannedItem?
}

struct ScannedItem: Codable {
    let managementNumber: String
    let company: String?
    let group: String?
    let location: String?
    let status: String
    
    enum CodingKeys: String, CodingKey {
        case managementNumber = "management_number"
        case company, group, location, status
    }
}

extension URLSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let data = data, let response = response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case networkError(String)
    case serverError(Int)
    case unauthorized
    case csrfTokenMissing
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なURL"
        case .noData:
            return "データが取得できませんでした"
        case .decodingError:
            return "データの解析に失敗しました"
        case .networkError(let message):
            return "ネットワークエラー: \(message)"
        case .serverError(let code):
            switch code {
            case 401:
                return "認証エラー: ログインが必要です"
            case 403:
                return "アクセス拒否: 権限がありません"
            case 404:
                return "リソースが見つかりません"
            case 419:
                return "CSRFトークンエラー: ページを再読み込みしてください"
            case 422:
                return "入力データエラー: 入力内容を確認してください"
            case 500:
                return "サーバーエラー: しばらく時間をおいて再試行してください"
            default:
                return "サーバーエラー: \(code)"
            }
        case .unauthorized:
            return "認証が必要です。再度ログインしてください。"
        case .csrfTokenMissing:
            return "CSRFトークンが見つかりません。ページを再読み込みしてください。"
        }
    }
}

class UserDefaultsManager: ObservableObject {
    private let userDefaults = UserDefaults.standard
    
    @Published var isLoggedIn: Bool {
        didSet {
            userDefaults.set(isLoggedIn, forKey: "isLoggedIn")
        }
    }
    
    @Published var userName: String {
        didSet {
            userDefaults.set(userName, forKey: "userName")
        }
    }
    
    @Published var authToken: String {
        didSet {
            userDefaults.set(authToken, forKey: "authToken")
        }
    }
    
    @Published var baseURL: String {
        didSet {
            userDefaults.set(baseURL, forKey: "baseURL")
        }
    }
    
    @Published var csrfToken: String {
        didSet {
            userDefaults.set(csrfToken, forKey: "csrfToken")
        }
    }
    
    init() {
        self.isLoggedIn = userDefaults.bool(forKey: "isLoggedIn")
        self.userName = userDefaults.string(forKey: "userName") ?? ""
        self.authToken = userDefaults.string(forKey: "authToken") ?? ""
        self.baseURL = userDefaults.string(forKey: "baseURL") ?? ""
        self.csrfToken = userDefaults.string(forKey: "csrfToken") ?? ""
    }
    
    func logout() {
        isLoggedIn = false
        userName = ""
        authToken = ""
        csrfToken = ""
    }
}

class EnhancedAPIService: NSObject, ObservableObject, URLSessionDelegate {
    @Published var isLoading = false
    let userDefaultsManager: UserDefaultsManager
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    init(userDefaultsManager: UserDefaultsManager) {
        self.userDefaultsManager = userDefaultsManager
        super.init()
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
    }
    
    private var baseURL: String {
        let ip = userDefaultsManager.baseURL.isEmpty ? "192.168.1.100" : userDefaultsManager.baseURL
        
        if ip.hasPrefix("http://") || ip.hasPrefix("https://") {
            return ip
        } else {
            return "https://\(ip)"
        }
    }
    
    private func createRequest(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        if !userDefaultsManager.csrfToken.isEmpty {
            request.setValue(userDefaultsManager.csrfToken, forHTTPHeaderField: "X-CSRF-TOKEN")
        }
        
        if !userDefaultsManager.authToken.isEmpty {
            request.setValue("Bearer \(userDefaultsManager.authToken)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        return request
    }
    
    func fetchUsers() async throws -> [User] {
        guard let url = URL(string: "\(baseURL)/login") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        defer {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        if let htmlString = String(data: data, encoding: .utf8) {
            if let csrfToken = extractCSRFToken(from: htmlString) {
                DispatchQueue.main.async {
                    self.userDefaultsManager.csrfToken = csrfToken
                }
            }
            
            return parseUsersFromHTML(htmlString)
        }
        
        throw APIError.decodingError
    }
    
    private func parseUsersFromHTML(_ html: String) -> [User] {
        var users: [User] = []
        
        let pattern = #"<option value="([^"]+)">([^<]+)</option>"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: html.utf16.count)
        
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            if let match = match,
               let valueRange = Range(match.range(at: 1), in: html),
               let nameRange = Range(match.range(at: 2), in: html) {
                let value = String(html[valueRange])
                let name = String(html[nameRange])
                
                if !value.isEmpty && value != "" && value != "disabled" && value != "selected" {
                    let user = User(id: users.count, name: name, email: nil)
                    if !users.contains(where: { $0.name == name }) {
                        users.append(user)
                    }
                }
            }
        }
        
        return users
    }
    
    private func extractCSRFToken(from html: String) -> String? {
        let patterns = [
            #"<meta name="csrf-token" content="([^"]+)""#,
            #"<input[^>]*name="_token"[^>]*value="([^"]+)""#,
            #"_token['"]\s*:\s*['"]([^'"]+)['"]"#,
            #"csrf_token['"]\s*:\s*['"]([^'"]+)['"]"#,
            #"<input[^>]*type="hidden"[^>]*name="_token"[^>]*value="([^"]+)""#
        ]
        
        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let range = NSRange(location: 0, length: html.utf16.count)
                
                if let match = regex.firstMatch(in: html, range: range),
                   let tokenRange = Range(match.range(at: 1), in: html) {
                    let token = String(html[tokenRange])
                    if !token.isEmpty && token.count > 10 {
                        return token
                    }
                }
            } catch {
                continue
            }
        }
        
        return nil
    }
    
    func login(username: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/login") else {
            throw APIError.invalidURL
        }
        
        var loginData = "username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if !userDefaultsManager.csrfToken.isEmpty {
            loginData += "&_token=\(userDefaultsManager.csrfToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        if !userDefaultsManager.csrfToken.isEmpty {
            request.setValue(userDefaultsManager.csrfToken, forHTTPHeaderField: "X-CSRF-TOKEN")
        }
        
        request.httpBody = loginData.data(using: .utf8)
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        defer {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("Invalid response")
        }
        
        #if DEBUG
        print("🔐 Login Response Status: \(httpResponse.statusCode)")
        if let responseData = String(data: data, encoding: .utf8) {
            print("🔐 Login Response Data: \(responseData.prefix(500))")
        }
        print("🔐 Login Response Headers: \(httpResponse.allHeaderFields)")
        #endif
        
        if httpResponse.statusCode == 302 || httpResponse.statusCode == 200 {
            if let setCookieHeader = httpResponse.allHeaderFields["Set-Cookie"] as? String {
                print("🍪 Session Cookie: \(setCookieHeader)")
            }
            
            DispatchQueue.main.async {
                self.userDefaultsManager.userName = username
                self.userDefaultsManager.isLoggedIn = true
            }
            return true
        } else if httpResponse.statusCode == 419 {
            throw APIError.serverError(419)
        } else if httpResponse.statusCode == 422 {
            throw APIError.networkError("Validation failed - check username")
        }
        
        throw APIError.serverError(httpResponse.statusCode)
    }
    
    func fetchCompanies() async throws -> [Company] {
        guard let url = URL(string: "\(baseURL)/companies") else {
            throw APIError.invalidURL
        }
        
        let request = createRequest(url: url)
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        defer {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("Invalid response")
        }
        
        #if DEBUG
        print("🏢 Companies Response Status: \(httpResponse.statusCode)")
        if let responseData = String(data: data, encoding: .utf8) {
            print("🏢 Companies Response: \(responseData.prefix(200))")
        }
        #endif
        
        if httpResponse.statusCode == 401 {
            DispatchQueue.main.async {
                self.userDefaultsManager.logout()
            }
            throw APIError.serverError(401)
        } else if httpResponse.statusCode == 200 {
            do {
                return try JSONDecoder().decode([Company].self, from: data)
            } catch {
                print("🏢 Decoding error: \(error)")
                print("🏢 Response data: \(String(data: data, encoding: .utf8) ?? "No data")")
                throw APIError.decodingError
            }
        } else {
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
    
    func fetchGroups(for companyId: Int) async throws -> [Group] {
        guard let url = URL(string: "\(baseURL)/company-groups-limited/\(companyId)") else {
            throw APIError.invalidURL
        }
        
        let request = createRequest(url: url)
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        defer {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("Invalid response")
        }
        
        #if DEBUG
        print("👥 Groups Response Status: \(httpResponse.statusCode)")
        #endif
        
        if httpResponse.statusCode == 401 {
            DispatchQueue.main.async {
                self.userDefaultsManager.logout()
            }
            throw APIError.unauthorized
        } else if httpResponse.statusCode == 200 {
            do {
                return try JSONDecoder().decode([Group].self, from: data)
            } catch {
                print("👥 Decoding error: \(error)")
                throw APIError.decodingError
            }
        } else {
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
    
    func fetchLocations(for groupId: Int) async throws -> [Location] {
        guard let url = URL(string: "\(baseURL)/locations-limited/\(groupId)") else {
            throw APIError.invalidURL
        }
        
        let request = createRequest(url: url)
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        defer {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("Invalid response")
        }
        
        #if DEBUG
        print("📍 Locations Response Status: \(httpResponse.statusCode)")
        #endif
        
        if httpResponse.statusCode == 401 {
            DispatchQueue.main.async {
                self.userDefaultsManager.logout()
            }
            throw APIError.unauthorized
        } else if httpResponse.statusCode == 200 {
            do {
                return try JSONDecoder().decode([Location].self, from: data)
            } catch {
                print("📍 Decoding error: \(error)")
                throw APIError.decodingError
            }
        } else {
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
    
    func updateStatus(qrCode: String, process: ProcessType, company: Int?, group: Int?, location: Int?, userName: String, note: String) async throws -> ScanResult {
        let endpoint = "/update-status"
        let fullURL = "\(baseURL)\(endpoint)"
        
        print("🔍 Attempting API call:")
        print("📍 Full URL: \(fullURL)")
        print("📦 QR Code: \(qrCode)")
        print("⚙️ Process: \(process.rawValue)")
        print("🏢 Company: \(company?.description ?? "nil")")
        print("👤 User: \(userName)")
        
        guard let url = URL(string: fullURL) else {
            print("❌ Invalid URL: \(fullURL)")
            throw APIError.invalidURL
        }
        
        let body = [
            "qr_code": qrCode,
            "process": process.rawValue,
            "company": company?.description ?? "",
            "group": group?.description ?? "",
            "location": location?.description ?? "",
            "userName": userName,
            "note": note
        ]
        
        print("📤 Request body: \(body)")
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let request = createRequest(url: url, method: "POST", body: bodyData)
        
        print("🔐 Request headers:")
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            print("  \(key): \(value)")
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        defer {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw APIError.networkError("Invalid response")
        }
        
        print("📥 Response status: \(httpResponse.statusCode)")
        print("📥 Response headers: \(httpResponse.allHeaderFields)")
        
        if let responseData = String(data: data, encoding: .utf8) {
            print("📥 Response body: \(responseData)")
        }
        
        switch httpResponse.statusCode {
        case 200:
            do {
                let result = try JSONDecoder().decode(ScanResult.self, from: data)
                print("✅ Decoded successfully: \(result)")
                return result
            } catch {
                print("❌ Decoding error: \(error)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 Raw response: \(responseString)")
                }
                throw APIError.decodingError
            }
        case 401:
            print("🔐 Unauthorized - logging out user")
            DispatchQueue.main.async {
                self.userDefaultsManager.logout()
            }
            throw APIError.serverError(401)
        case 404:
            print("🔍 404 Error - Endpoint not found")
            print("📋 Possible issues:")
            print("  1. Server URL incorrect: \(baseURL)")
            print("  2. Endpoint path wrong: \(endpoint)")
            print("  3. Server not running")
            print("  4. Route not configured")
            throw APIError.serverError(404)
        case 422:
            print("📝 Validation error - check request data")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Error details: \(responseString)")
            }
            throw APIError.serverError(422)
        default:
            print("❌ Server error: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Error response: \(responseString)")
            }
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
    
    func updateStatusWithDiagnostics(qrCode: String, process: ProcessType, company: Int?, group: Int?, location: Int?, userName: String, note: String) async throws -> ScanResult {
        let endpoint = "/update-status"
        let fullURL = "\(baseURL)\(endpoint)"
        
        print("🔍 Attempting API call:")
        print("📍 Full URL: \(fullURL)")
        print("📦 QR Code: \(qrCode)")
        print("⚙️ Process: \(process.rawValue)")
        print("🏢 Company: \(company?.description ?? "nil")")
        print("👤 User: \(userName)")
        
        guard let url = URL(string: fullURL) else {
            print("❌ Invalid URL: \(fullURL)")
            throw APIError.invalidURL
        }
        
        let body = [
            "qr_code": qrCode,
            "process": process.rawValue,
            "company": company?.description ?? "",
            "group": group?.description ?? "",
            "location": location?.description ?? "",
            "userName": userName,
            "note": note
        ]
        
        print("📤 Request body: \(body)")
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let request = createRequest(url: url, method: "POST", body: bodyData)
        
        print("🔐 Request headers:")
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            print("  \(key): \(value)")
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        defer {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw APIError.networkError("Invalid response")
        }
        
        print("📥 Response status: \(httpResponse.statusCode)")
        print("📥 Response headers: \(httpResponse.allHeaderFields)")
        
        if let responseData = String(data: data, encoding: .utf8) {
            print("📥 Response body: \(responseData)")
        }
        
        switch httpResponse.statusCode {
        case 200:
            do {
                let result = try JSONDecoder().decode(ScanResult.self, from: data)
                print("✅ Decoded successfully: \(result)")
                return result
            } catch {
                print("❌ Decoding error: \(error)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 Raw response: \(responseString)")
                }
                throw APIError.decodingError
            }
        case 401:
            print("🔐 Unauthorized - logging out user")
            DispatchQueue.main.async {
                self.userDefaultsManager.logout()
            }
            throw APIError.serverError(401)
        case 404:
            print("🔍 404 Error - Endpoint not found")
            print("📋 Possible issues:")
            print("  1. Server URL incorrect: \(baseURL)")
            print("  2. Endpoint path wrong: \(endpoint)")
            print("  3. Server not running")
            print("  4. Route not configured")
            throw APIError.serverError(404)
        case 422:
            print("📝 Validation error - check request data")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Error details: \(responseString)")
            }
            throw APIError.serverError(422)
        default:
            print("❌ Server error: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Error response: \(responseString)")
            }
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}
