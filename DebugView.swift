import SwiftUI
import Foundation

struct DebugView: View {
    @StateObject private var userDefaultsManager = UserDefaultsManager()
    @StateObject private var apiService: EnhancedAPIService
    @State private var testResults = ""
    @State private var isLoading = false
    
    init() {
        let userDefaults = UserDefaultsManager()
        _apiService = StateObject(wrappedValue: EnhancedAPIService(userDefaultsManager: userDefaults))
    }
    
    private func testLogin() {
        isLoading = true
        testResults += "\n=== Testing Login ===\n"
        testResults += "URL: \(userDefaultsManager.baseURL)/login\n"
        testResults += "CSRF Token: \(userDefaultsManager.csrfToken.isEmpty ? "❌ Missing" : "✅ \(userDefaultsManager.csrfToken.prefix(20))...")\n"
        
        if userDefaultsManager.csrfToken.isEmpty {
            testResults += "⚠️ No CSRF token found. Fetching users first to get token...\n"
            
            Task {
                do {
                    let users = try await apiService.fetchUsers()
                    
                    DispatchQueue.main.async {
                        self.testResults += "✅ Fetched \(users.count) users and CSRF token\n"
                        self.testResults += "CSRF Token: \(self.userDefaultsManager.csrfToken.isEmpty ? "❌ Still Missing" : "✅ \(self.userDefaultsManager.csrfToken.prefix(20))...")\n"
                        
                        if let firstUser = users.first {
                            self.testResults += "Testing login with user: \(firstUser.name)\n"
                            
                            Task {
                                do {
                                    let success = try await self.apiService.login(username: firstUser.name)
                                    DispatchQueue.main.async {
                                        self.testResults += success ? "✅ Login successful!\n" : "❌ Login failed\n"
                                        self.isLoading = false
                                    }
                                } catch {
                                    DispatchQueue.main.async {
                                        self.testResults += "❌ Login Error: \(error.localizedDescription)\n"
                                        self.isLoading = false
                                    }
                                }
                            }
                        } else {
                            self.testResults += "❌ No users found to test login\n"
                            self.isLoading = false
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.testResults += "❌ Error fetching users: \(error.localizedDescription)\n"
                        self.isLoading = false
                    }
                }
            }
        } else {
            Task {
                do {
                    let users = try await apiService.fetchUsers()
                    if let firstUser = users.first {
                        testResults += "Testing login with user: \(firstUser.name)\n"
                        
                        let success = try await apiService.login(username: firstUser.name)
                        DispatchQueue.main.async {
                            self.testResults += success ? "✅ Login successful!\n" : "❌ Login failed\n"
                            self.isLoading = false
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.testResults += "❌ No users found to test login\n"
                            self.isLoading = false
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.testResults += "❌ Login Error: \(error.localizedDescription)\n"
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("デバッグ画面")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("現在の設定:")
                            .font(.headline)
                        Text("Server IP: \(userDefaultsManager.baseURL)")
                        Text("User: \(userDefaultsManager.userName)")
                        Text("Logged in: \(userDefaultsManager.isLoggedIn ? "Yes" : "No")")
                        Text("CSRF Token: \(userDefaultsManager.csrfToken.isEmpty ? "❌ Missing" : "✅ Available")")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    VStack(spacing: 12) {
                        Button("Test Users API") {
                            testUsersAPI()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Test Login") {
                            testLogin()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Test Companies API") {
                            testCompaniesAPI()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Test QR Update") {
                            testQRUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Clear Results") {
                            testResults = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if isLoading {
                        ProgressView("テスト中...")
                            .padding()
                    }
                    
                    if !testResults.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("テスト結果:")
                                .font(.headline)
                            
                            ScrollView {
                                Text(testResults)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 300)
                        }
                        .padding()
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func testUsersAPI() {
        isLoading = true
        testResults += "\n=== Testing Users API ===\n"
        testResults += "URL: \(userDefaultsManager.baseURL)/login\n"
        
        Task {
            do {
                let users = try await apiService.fetchUsers()
                DispatchQueue.main.async {
                    self.testResults += "✅ Success! Found \(users.count) users:\n"
                    for (index, user) in users.enumerated() {
                        self.testResults += "- [\(index)] \(user.name)\n"
                    }
                    self.testResults += "CSRF Token: \(self.userDefaultsManager.csrfToken.isEmpty ? "❌ Missing" : "✅ Found (\(self.userDefaultsManager.csrfToken.prefix(20))...)")\n"
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.testResults += "❌ Error: \(error.localizedDescription)\n"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func testCompaniesAPI() {
        isLoading = true
        testResults += "\n=== Testing Companies API ===\n"
        testResults += "URL: \(userDefaultsManager.baseURL)/companies\n"
        
        Task {
            do {
                let companies = try await apiService.fetchCompanies()
                DispatchQueue.main.async {
                    self.testResults += "✅ Success! Found \(companies.count) companies:\n"
                    for company in companies {
                        self.testResults += "- ID: \(company.id), Name: \(company.name)\n"
                    }
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.testResults += "❌ Error: \(error.localizedDescription)\n"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func testQRUpdate() {
        isLoading = true
        testResults += "\n=== Testing QR Update API ===\n"
        testResults += "URL: \(userDefaultsManager.baseURL)/update-status\n"
        
        Task {
            do {
                let result = try await apiService.updateStatus(
                    qrCode: "test123",
                    process: .shipping,
                    company: 1,
                    group: 1,
                    location: 1,
                    userName: userDefaultsManager.userName,
                    note: "Test from iOS"
                )
                
                DispatchQueue.main.async {
                    self.testResults += "✅ Success: \(result.success)\n"
                    self.testResults += "Message: \(result.message ?? "No message")\n"
                    if let item = result.item {
                        self.testResults += "Item: \(item.managementNumber)\n"
                    }
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.testResults += "❌ Error: \(error.localizedDescription)\n"
                    self.isLoading = false
                }
            }
        }
    }
}

struct ConnectionTestView: View {
    @State private var serverIP = ""
    @State private var testResult = ""
    @State private var isLoading = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    
    enum ConnectionStatus {
        case unknown, connecting, success, failed
        
        var color: Color {
            switch self {
            case .unknown: return .gray
            case .connecting: return .blue
            case .success: return .green
            case .failed: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .unknown: return "questionmark.circle"
            case .connecting: return "arrow.clockwise"
            case .success: return "checkmark.circle"
            case .failed: return "xmark.circle"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("接続テスト")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(spacing: 16) {
                TextField("サーバーIP (例: 192.168.1.100)", text: $serverIP)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                Button("接続テスト") {
                    testConnection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(serverIP.isEmpty || isLoading)
                
                HStack {
                    Image(systemName: connectionStatus.icon)
                        .foregroundColor(connectionStatus.color)
                        .font(.title2)
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    
                    Text(getStatusText())
                        .foregroundColor(connectionStatus.color)
                }
            }
            
            if !testResult.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("結果:")
                        .font(.headline)
                    
                    ScrollView {
                        Text(testResult)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func getStatusText() -> String {
        switch connectionStatus {
        case .unknown: return "未確認"
        case .connecting: return "接続中..."
        case .success: return "接続成功"
        case .failed: return "接続失敗"
        }
    }
    
    private func testConnection() {
        isLoading = true
        connectionStatus = .connecting
        testResult = ""
        
        var testURLs: [String] = []
        
        if serverIP.hasPrefix("http://") || serverIP.hasPrefix("https://") {
            testURLs = [serverIP]
        } else {
            testURLs = ["https://\(serverIP)", "http://\(serverIP)"]
        }
        
        Task {
            for baseURL in testURLs {
                do {
                    guard let url = URL(string: "\(baseURL)/login") else {
                        continue
                    }
                    
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 10
                    
                    let config = URLSessionConfiguration.default
                    let session = URLSession(configuration: config)
                    
                    let (data, response) = try await session.data(for: request)
                    
                    DispatchQueue.main.async {
                        if let httpResponse = response as? HTTPURLResponse {
                            self.testResult = """
                            接続テスト結果:
                            URL: \(url.absoluteString)
                            Protocol: \(url.scheme?.uppercased() ?? "UNKNOWN")
                            Status Code: \(httpResponse.statusCode)
                            Response Size: \(data.count) bytes
                            
                            Headers:
                            \(httpResponse.allHeaderFields.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
                            """
                            
                            if httpResponse.statusCode == 200 {
                                self.connectionStatus = .success
                            } else {
                                self.connectionStatus = .failed
                            }
                        }
                        self.isLoading = false
                    }
                    return
                    
                } catch {
                    print("Failed to connect to \(baseURL): \(error)")
                    continue
                }
            }
            
            DispatchQueue.main.async {
                self.testResult = "すべてのプロトコル（HTTP/HTTPS）で接続に失敗しました\n\n試行したURL:\n" + testURLs.joined(separator: "\n")
                self.connectionStatus = .failed
                self.isLoading = false
            }
        }
    }
}

struct AdvancedSettingsView: View {
    @StateObject private var userDefaultsManager = UserDefaultsManager()
    @State private var serverIP = ""
    @State private var showDebugView = false
    @State private var showConnectionTest = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("高度な設定")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("サーバーIP設定")
                            .font(.headline)
                        
                        Text("Laravel サーバーのIPアドレスを入力してください（HTTPS対応）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("例: 192.168.1.100 または https://192.168.1.100", text: $serverIP)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button("保存") {
                            saveSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(serverIP.isEmpty)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    if !userDefaultsManager.baseURL.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("現在の設定")
                                .font(.headline)
                            
                            Text("Server: \(userDefaultsManager.baseURL)")
                            Text("User: \(userDefaultsManager.userName)")
                            Text("Status: \(userDefaultsManager.isLoggedIn ? "ログイン済み" : "未ログイン")")
                            Text("CSRF Token: \(userDefaultsManager.csrfToken.isEmpty ? "❌ Missing" : "✅ Available")")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    VStack(spacing: 12) {
                        Text("テストツール")
                            .font(.headline)
                        
                        Button("接続テスト") {
                            showConnectionTest = true
                        }
                        .buttonStyle(.bordered)
                        
                        Button("APIデバッグ") {
                            showDebugView = true
                        }
                        .buttonStyle(.bordered)
                        
                        Button("設定をリセット") {
                            resetSettings()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
                
                Spacer()
                
                Button("閉じる") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
            }
            .navigationBarHidden(true)
            .onAppear {
                serverIP = userDefaultsManager.baseURL
            }
            .alert("設定", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showDebugView) {
                DebugView()
            }
            .sheet(isPresented: $showConnectionTest) {
                ConnectionTestView()
            }
        }
    }
    
    private func saveSettings() {
        var cleanIP = serverIP.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanIP.hasSuffix("/") {
            cleanIP = String(cleanIP.dropLast())
        }
        
        userDefaultsManager.baseURL = cleanIP
        alertMessage = "設定が保存されました\nURL: \(cleanIP)"
        showingAlert = true
    }
    
    private func resetSettings() {
        userDefaultsManager.baseURL = ""
        userDefaultsManager.userName = ""
        userDefaultsManager.isLoggedIn = false
        userDefaultsManager.authToken = ""
        userDefaultsManager.csrfToken = ""
        serverIP = ""
        alertMessage = "すべての設定がリセットされました"
        showingAlert = true
    }
}
