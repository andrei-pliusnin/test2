import SwiftUI
import Foundation

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
            return "サーバーエラー: \(code)"
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
    private let userDefaultsManager: UserDefaultsManager
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
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
        
        isLoading = true
        defer { isLoading = false }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        if let htmlString = String(data: data, encoding: .utf8) {
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
            #"_token['"]\s*:\s*['"]([^'"]+)['"]"#
        ]
        
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern)
            let range = NSRange(location: 0, length: html.utf16.count)
            
            if let match = regex.firstMatch(in: html, range: range),
               let tokenRange = Range(match.range(at: 1), in: html) {
                return String(html[tokenRange])
            }
        }
        
        return nil
    }
    
    func login(username: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/login") else {
            throw APIError.invalidURL
        }
        
        let loginData = "username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = loginData.data(using: .utf8)
        
        isLoading = true
        defer { isLoading = false }
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("Invalid response")
        }
        
        if httpResponse.statusCode == 302 || httpResponse.statusCode == 200 {
            DispatchQueue.main.async {
                self.userDefaultsManager.userName = username
                self.userDefaultsManager.isLoggedIn = true
            }
            return true
        }
        
        throw APIError.serverError(httpResponse.statusCode)
    }
    
    func fetchCompanies() async throws -> [Company] {
        guard let url = URL(string: "\(baseURL)/companies") else {
            throw APIError.invalidURL
        }
        
        let request = createRequest(url: url)
        
        isLoading = true
        defer { isLoading = false }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        do {
            return try JSONDecoder().decode([Company].self, from: data)
        } catch {
            print("Decoding error: \(error)")
            print("Response data: \(String(data: data, encoding: .utf8) ?? "No data")")
            throw APIError.decodingError
        }
    }
    
    func fetchGroups(for companyId: Int) async throws -> [Group] {
        guard let url = URL(string: "\(baseURL)/company-groups-limited/\(companyId)") else {
            throw APIError.invalidURL
        }
        
        let request = createRequest(url: url)
        
        isLoading = true
        defer { isLoading = false }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        do {
            return try JSONDecoder().decode([Group].self, from: data)
        } catch {
            print("Decoding error: \(error)")
            print("Response data: \(String(data: data, encoding: .utf8) ?? "No data")")
            throw APIError.decodingError
        }
    }
    
    func fetchLocations(for groupId: Int) async throws -> [Location] {
        guard let url = URL(string: "\(baseURL)/locations-limited/\(groupId)") else {
            throw APIError.invalidURL
        }
        
        let request = createRequest(url: url)
        
        isLoading = true
        defer { isLoading = false }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        do {
            return try JSONDecoder().decode([Location].self, from: data)
        } catch {
            print("Decoding error: \(error)")
            print("Response data: \(String(data: data, encoding: .utf8) ?? "No data")")
            throw APIError.decodingError
        }
    }
    
    func updateStatus(qrCode: String, process: ProcessType, company: Int?, group: Int?, location: Int?, userName: String, note: String) async throws -> ScanResult {
        guard let url = URL(string: "\(baseURL)/update-status") else {
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
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let request = createRequest(url: url, method: "POST", body: bodyData)
        
        isLoading = true
        defer { isLoading = false }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("Invalid response")
        }
        
        if httpResponse.statusCode == 200 {
            do {
                return try JSONDecoder().decode(ScanResult.self, from: data)
            } catch {
                print("Decoding error: \(error)")
                print("Response data: \(String(data: data, encoding: .utf8) ?? "No data")")
                throw APIError.decodingError
            }
        } else {
            print("Server error. Status code: \(httpResponse.statusCode)")
            if let errorData = String(data: data, encoding: .utf8) {
                print("Error response: \(errorData)")
            }
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}

struct SettingsView: View {
    @StateObject private var userDefaultsManager = UserDefaultsManager()
    @State private var serverIP = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "gear")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("設定")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                .padding(.top, 50)
                
                Spacer()
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("サーバーIP")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("例: 192.168.1.100 または https://192.168.1.100")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("サーバーIPを入力", text: $serverIP)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                    }
                    
                    Button("保存") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(serverIP.isEmpty)
                    
                    if !userDefaultsManager.baseURL.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("現在の設定:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(userDefaultsManager.baseURL)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                Button("戻る") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 50)
            }
            .navigationBarHidden(true)
            .onAppear {
                serverIP = userDefaultsManager.baseURL
            }
            .alert("設定", isPresented: $showingAlert) {
                Button("OK") { 
                    presentationMode.wrappedValue.dismiss()
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func saveSettings() {
        var cleanIP = serverIP.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanIP.hasSuffix("/") {
            cleanIP = String(cleanIP.dropLast())
        }
        
        userDefaultsManager.baseURL = cleanIP
        alertMessage = "設定が保存されました"
        showingAlert = true
    }
}

struct EnhancedLoginView: View {
    @StateObject private var userDefaultsManager = UserDefaultsManager()
    @State private var apiService: EnhancedAPIService?
    
    @State private var users: [User] = []
    @State private var selectedUser: User?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingSettings = false
    @State private var showingAdvancedSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                
                VStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("資産管理システム")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    if userDefaultsManager.baseURL.isEmpty {
                        VStack(spacing: 12) {
                            Text("最初にサーバー設定を行ってください")
                                .font(.headline)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.center)
                            
                            Button("設定") {
                                showingSettings = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    } else {
                        if users.isEmpty && apiService?.isLoading != true {
                            Button("ユーザーを読み込む") {
                                Task {
                                    await loadUsers()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else if !users.isEmpty {
                            Picker("ユーザーを選択", selection: $selectedUser) {
                                Text("名前").tag(User?.none)
                                ForEach(users) { user in
                                    Text(user.name).tag(User?.some(user))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(8)
                            
                            Button("ログイン") {
                                Task {
                                    await performLogin()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(selectedUser == nil || apiService.isLoading)
                        }
                        
                        if apiService?.isLoading == true {
                            ProgressView("読み込み中...")
                                .scaleEffect(1.2)
                                .padding()
                        }
                        
                        HStack {
                            Spacer()
                            Button("設定") {
                                showingSettings = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("高度") {
                                showingAdvancedSettings = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.horizontal, 32)
                
                Spacer()
            }
            .navigationBarHidden(true)
            .alert("エラー", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingAdvancedSettings) {
                AdvancedSettingsView()
            }
            .fullScreenCover(isPresented: $userDefaultsManager.isLoggedIn) {
                EnhancedProcessSelectionView()
                    .environmentObject(userDefaultsManager)
            }
            .onAppear {
                if apiService == nil {
                    apiService = EnhancedAPIService(userDefaultsManager: userDefaultsManager)
                }
                if !userDefaultsManager.baseURL.isEmpty && users.isEmpty {
                    Task {
                        await loadUsers()
                    }
                }
            }
        }
    }
    
    private func loadUsers() async {
        guard let apiService = apiService else { return }
        do {
            users = try await apiService.fetchUsers()
        } catch {
            alertMessage = "ユーザーの読み込みに失敗しました: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    private func performLogin() async {
        guard let user = selectedUser,
              let apiService = apiService else { return }
        
        do {
            let success = try await apiService.login(username: user.name)
            if !success {
                alertMessage = "ログインに失敗しました"
                showingAlert = true
            }
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }
}

struct EnhancedProcessSelectionView: View {
    @EnvironmentObject var userDefaultsManager: UserDefaultsManager
    @State private var apiService: EnhancedAPIService?
    
    @State private var selectedProcess: ProcessType = .shipping
    @State private var selectedCompany: Company?
    @State private var selectedGroup: Group?
    @State private var selectedLocation: Location?
    @State private var note: String = ""
    
    @State private var companies: [Company] = []
    @State private var groups: [Group] = []
    @State private var locations: [Location] = []
    
    @State private var showingScanner = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var canProceed: Bool {
        selectedProcess == .return_ || selectedProcess == .disposal || selectedCompany != nil
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                HStack {
                    Text(userDefaultsManager.userName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    
                    Button("ログアウト") {
                        userDefaultsManager.logout()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                
                if apiService.isLoading {
                    ProgressView("読み込み中...")
                        .scaleEffect(1.2)
                        .padding()
                }
                
                Form {
                    Section("処理選択") {
                        Picker("処理を選択", selection: $selectedProcess) {
                            ForEach(ProcessType.allCases, id: \.self) { process in
                                Text(process.displayName).tag(process)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    if selectedProcess == .shipping {
                        Section("得意先情報") {
                            Picker("得意先", selection: $selectedCompany) {
                                Text("得意先を選択").tag(Company?.none)
                                ForEach(companies) { company in
                                    Text(company.name).tag(Company?.some(company))
                                }
                            }
                            .onChange(of: selectedCompany) { _ in
                                selectedGroup = nil
                                selectedLocation = nil
                                loadGroups()
                            }
                            
                            if selectedCompany != nil {
                                Picker("JV名", selection: $selectedGroup) {
                                    Text("JV名を選択").tag(Group?.none)
                                    ForEach(groups) { group in
                                        Text(group.name).tag(Group?.some(group))
                                    }
                                }
                                .onChange(of: selectedGroup) { _ in
                                    selectedLocation = nil
                                    loadLocations()
                                }
                                
                                if selectedGroup != nil {
                                    Picker("現場名", selection: $selectedLocation) {
                                        Text("現場名を選択").tag(Location?.none)
                                        ForEach(locations) { location in
                                            Text(location.name).tag(Location?.some(location))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    Section("備考") {
                        TextField("備考", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                
                Button("次へ") {
                    showingScanner = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canProceed)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("処理選択")
            .navigationBarHidden(true)
            .onAppear {
                if apiService == nil {
                    apiService = EnhancedAPIService(userDefaultsManager: userDefaultsManager)
                }
            }
            .task {
                await loadCompanies()
            }
            .alert("エラー", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .fullScreenCover(isPresented: $showingScanner) {
                if let apiService = apiService {
                    EnhancedQRScannerContainerView(
                        selectedProcess: selectedProcess,
                        selectedCompany: selectedCompany,
                        selectedGroup: selectedGroup,
                        selectedLocation: selectedLocation,
                        note: note,
                        userName: userDefaultsManager.userName,
                        apiService: apiService
                    )
                }
            }
        }
    }
    
    private func loadCompanies() async {
        guard let apiService = apiService else { return }
        do {
            companies = try await apiService.fetchCompanies()
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }
    
    private func loadGroups() {
        guard let companyId = selectedCompany?.id,
              let apiService = apiService else { return }
        
        Task {
            do {
                groups = try await apiService.fetchGroups(for: companyId)
            } catch {
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }
    
    private func loadLocations() {
        guard let groupId = selectedGroup?.id,
              let apiService = apiService else { return }
        
        Task {
            do {
                locations = try await apiService.fetchLocations(for: groupId)
            } catch {
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }
}

struct EnhancedQRScannerContainerView: View {
    let selectedProcess: ProcessType
    let selectedCompany: Company?
    let selectedGroup: Group?
    let selectedLocation: Location?
    let note: String
    let userName: String
    let apiService: EnhancedAPIService
    
    @State private var scannedCode: String?
    @State private var scannedItems: [ScannedItem] = []
    @State private var scanCount = 0
    
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Text(userName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("戻る") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                
                if apiService.isLoading {
                    ProgressView("処理中...")
                        .scaleEffect(1.2)
                        .padding()
                }
                
                QRScannerView(scannedCode: $scannedCode)
                    .frame(height: 300)
                    .cornerRadius(10)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("処理: \(selectedProcess.displayName)")
                        .font(.headline)
                    
                    if selectedProcess == .shipping {
                        if let company = selectedCompany {
                            Text("得意先: \(company.name)")
                        }
                        if let group = selectedGroup {
                            Text("JV名: \(group.name)")
                        }
                        if let location = selectedLocation {
                            Text("現場名: \(location.name)")
                        }
                    }
                    
                    if !note.isEmpty {
                        Text("備考: \(note)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                if !scannedItems.isEmpty {
                    List(scannedItems.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). 管理番号: \(scannedItems[index].managementNumber)")
                                .fontWeight(.semibold)
                            
                            if let company = scannedItems[index].company,
                               let group = scannedItems[index].group,
                               let location = scannedItems[index].location {
                                Text("現場: \(company) \(group) \(location)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("状態: \(scannedItems[index].status)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .onChange(of: scannedCode) { code in
                if let code = code {
                    processScannedCode(code)
                    scannedCode = nil
                }
            }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    private func processScannedCode(_ code: String) {
        Task {
            do {
                let result = try await apiService.updateStatus(
                    qrCode: code,
                    process: selectedProcess,
                    company: selectedCompany?.id,
                    group: selectedGroup?.id,
                    location: selectedLocation?.id,
                    userName: userName,
                    note: note
                )
                
                DispatchQueue.main.async {
                    if result.success {
                        if let item = result.item {
                            self.scannedItems.append(item)
                            self.scanCount += 1
                        }
                        self.showAlert(title: "成功", message: "QRコードの読み取りに成功しました")
                    } else {
                        self.showAlert(title: "失敗", message: result.message ?? "不明なエラー")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showAlert(title: "失敗", message: error.localizedDescription)
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

@main
struct EnhancedQRScannerApp: App {
    var body: some Scene {
        WindowGroup {
            EnhancedLoginView()
        }
    }
}
