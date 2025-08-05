import SwiftUI
import AVFoundation

protocol QRScannerDelegate: AnyObject {
    func didScanQRCode(_ code: String)
}

class QRScannerViewController: UIViewController {
    weak var delegate: QRScannerDelegate?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastScannedCode: String?
    private var lastScanTime: Date = Date()
    private var isSetupComplete = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupInitialView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !isSetupComplete {
            Task {
                await requestCameraPermissionAndSetup()
            }
        } else {
            startScanning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }
    
    private func setupInitialView() {
        let loadingLabel = UILabel()
        loadingLabel.text = "カメラを準備中..."
        loadingLabel.textColor = .white
        loadingLabel.textAlignment = .center
        loadingLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(loadingLabel)
        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func requestCameraPermissionAndSetup() async {
        let hasPermission = await CameraPermissionHandler.checkCameraPermission()
        
        await MainActor.run {
            if hasPermission {
                self.setupCamera()
            } else {
                self.showCameraPermissionAlert()
            }
        }
    }
    
    private func setupCamera() {
        guard !isSetupComplete else { return }
        
        do {
            captureSession = AVCaptureSession()
            guard let captureSession = captureSession else { return }
            
            guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
                showErrorAlert("カメラが利用できません")
                return
            }
            
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                showErrorAlert("カメラ入力の追加に失敗しました")
                return
            }
            
            let metadataOutput = AVCaptureMetadataOutput()
            
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            } else {
                showErrorAlert("メタデータ出力の追加に失敗しました")
                return
            }
            
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.frame = view.layer.bounds
            previewLayer?.videoGravity = .resizeAspectFill
            
            if let previewLayer = previewLayer {
                view.layer.sublayers?.removeAll()
                view.layer.addSublayer(previewLayer)
            }
            
            let overlayView = createScanningOverlay()
            view.addSubview(overlayView)
            
            isSetupComplete = true
            startScanning()
            
        } catch {
            showErrorAlert("カメラの初期化に失敗しました: \(error.localizedDescription)")
        }
    }
    
    private func showCameraPermissionAlert() {
        let alert = UIAlertController(
            title: "カメラアクセス許可が必要です",
            message: "QRコードをスキャンするにはカメラへのアクセスを許可してください。設定からカメラアクセスを有効にしてください。",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "設定を開く", style: .default) { _ in
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        })
        
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func showErrorAlert(_ message: String) {
        let alert = UIAlertController(
            title: "エラー",
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func createScanningOverlay() -> UIView {
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        
        let scanArea = UIView()
        scanArea.layer.borderColor = UIColor.white.cgColor
        scanArea.layer.borderWidth = 2
        scanArea.layer.cornerRadius = 10
        scanArea.backgroundColor = UIColor.clear
        
        overlayView.addSubview(scanArea)
        scanArea.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scanArea.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            scanArea.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            scanArea.widthAnchor.constraint(equalToConstant: 250),
            scanArea.heightAnchor.constraint(equalToConstant: 250)
        ])
        
        let instructionLabel = UILabel()
        instructionLabel.text = "QRコードをスキャンしてください"
        instructionLabel.textColor = UIColor.white
        instructionLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        overlayView.addSubview(instructionLabel)
        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            instructionLabel.topAnchor.constraint(equalTo: scanArea.bottomAnchor, constant: 20)
        ])
        
        let path = UIBezierPath(rect: overlayView.bounds)
        let scanAreaRect = CGRect(
            x: (view.bounds.width - 250) / 2,
            y: (view.bounds.height - 250) / 2,
            width: 250,
            height: 250
        )
        let scanAreaPath = UIBezierPath(roundedRect: scanAreaRect, cornerRadius: 10)
        path.append(scanAreaPath.reversing())
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        overlayView.layer.mask = maskLayer
        
        return overlayView
    }
    
    private func startScanning() {
        guard let captureSession = captureSession, isSetupComplete else {
            return
        }
        
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
        }
    }
    
    private func stopScanning() {
        guard let captureSession = captureSession else { return }
        
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.stopRunning()
            }
        }
    }
    
    deinit {
        stopScanning()
    }
}

extension QRScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else { return }
        
        let currentTime = Date()
        if stringValue == lastScannedCode && currentTime.timeIntervalSince(lastScanTime) < 2.0 {
            return
        }
        
        lastScannedCode = stringValue
        lastScanTime = currentTime
        
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        delegate?.didScanQRCode(stringValue)
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, QRScannerDelegate {
        let parent: QRScannerView
        
        init(_ parent: QRScannerView) {
            self.parent = parent
        }
        
        func didScanQRCode(_ code: String) {
            parent.scannedCode = code
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
    @StateObject private var apiService: EnhancedAPIService
    
    @State private var users: [User] = []
    @State private var selectedUser: User?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingSettings = false
    @State private var showingAdvancedSettings = false
    
    init() {
        let sharedUserDefaults = UserDefaultsManager()
        _userDefaultsManager = StateObject(wrappedValue: sharedUserDefaults)
        _apiService = StateObject(wrappedValue: EnhancedAPIService(userDefaultsManager: sharedUserDefaults))
    }
    
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
                        if users.isEmpty && !apiService.isLoading {
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
                        
                        if apiService.isLoading {
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
                ProcessSelectionView()
                    .environmentObject(userDefaultsManager)
            }
            .onAppear {
                if !userDefaultsManager.baseURL.isEmpty && users.isEmpty {
                    Task {
                        await loadUsers()
                    }
                }
            }
        }
    }
    
    private func loadUsers() async {
        do {
            users = try await apiService.fetchUsers()
        } catch {
            DispatchQueue.main.async {
                self.alertMessage = "ユーザーの読み込みに失敗しました: \(error.localizedDescription)"
                self.showingAlert = true
            }
        }
    }
    
    private func performLogin() async {
        guard let user = selectedUser else { return }
        
        do {
            let success = try await apiService.login(username: user.name)
            if !success {
                DispatchQueue.main.async {
                    self.alertMessage = "ログインに失敗しました"
                    self.showingAlert = true
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.alertMessage = error.localizedDescription
                self.showingAlert = true
            }
        }
    }
}

struct ProcessSelectionView: View {
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
                
                if let api = apiService, api.isLoading {
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
                    Task {
                        await loadCompanies()
                    }
                }
            }
            .alert("エラー", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .fullScreenCover(isPresented: $showingScanner) {
                if let apiService = apiService {
                    QRScannerContainerView(
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
            DispatchQueue.main.async {
                if let apiError = error as? APIError,
                   case .serverError(let code) = apiError,
                   code == 401 {
                    self.alertMessage = "セッションが期限切れです。再度ログインしてください。"
                } else {
                    self.alertMessage = "会社リストの読み込みエラー: \(error.localizedDescription)"
                }
                self.showingAlert = true
            }
        }
    }
    
    private func loadGroups() {
        guard let companyId = selectedCompany?.id,
              let apiService = apiService else { return }
        
        Task {
            do {
                groups = try await apiService.fetchGroups(for: companyId)
            } catch {
                DispatchQueue.main.async {
                    if let apiError = error as? APIError,
                       case .serverError(let code) = apiError,
                       code == 401 {
                        self.alertMessage = "セッションが期限切れです。再度ログインしてください。"
                    } else {
                        self.alertMessage = "グループリストの読み込みエラー: \(error.localizedDescription)"
                    }
                    self.showingAlert = true
                }
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
                DispatchQueue.main.async {
                    if let apiError = error as? APIError,
                       case .serverError(let code) = apiError,
                       code == 401 {
                        self.alertMessage = "セッションが期限切れです。再度ログインしてください。"
                    } else {
                        self.alertMessage = "ロケーションリストの読み込みエラー: \(error.localizedDescription)"
                    }
                    self.showingAlert = true
                }
            }
        }
    }
}

struct QRScannerContainerView: View {
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
                    .frame(height: 400)
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
                        VibrationHelper.success()
                        self.showAlert(title: "成功", message: "QRコードの読み取りに成功しました")
                    } else {
                        VibrationHelper.error()
                        self.showAlert(title: "失敗", message: result.message ?? "不明なエラー")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    VibrationHelper.error()
                    
                    var errorMessage = error.localizedDescription
                    
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .unauthorized:
                            errorMessage = "セッションが期限切れです。アプリを再起動してログインし直してください。"
                        case .serverError(419):
                            errorMessage = "CSRFトークンエラー。アプリを再起動してください。"
                        default:
                            errorMessage = apiError.localizedDescription
                        }
                    }
                    
                    self.showAlert(title: "エラー", message: errorMessage)
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
