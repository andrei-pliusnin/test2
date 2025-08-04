import SwiftUI
import AVFoundation
import Combine

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

class APIService: ObservableObject {
    private let baseURL = "YOUR_BASE_URL_HERE"
    private let session = URLSession.shared
    
    func fetchCompanies() async throws -> [Company] {
        return [
            Company(id: 1, name: "Company A"),
            Company(id: 2, name: "Company B")
        ]
    }
    
    func fetchGroups(for companyId: Int) async throws -> [Group] {
        guard let url = URL(string: "\(baseURL)/company-groups-limited/\(companyId)") else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode([Group].self, from: data)
    }
    
    func fetchLocations(for groupId: Int) async throws -> [Location] {
        guard let url = URL(string: "\(baseURL)/locations-limited/\(groupId)") else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode([Location].self, from: data)
    }
    
    func updateStatus(qrCode: String, process: ProcessType, company: Int?, group: Int?, location: Int?, userName: String, note: String) async throws -> ScanResult {
        guard let url = URL(string: "\(baseURL)/api/update-status") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "qr_code": qrCode,
            "process": process.rawValue,
            "company": company?.description ?? "",
            "group": group?.description ?? "",
            "location": location?.description ?? "",
            "userName": userName,
            "note": note
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(ScanResult.self, from: data)
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

protocol QRScannerDelegate: AnyObject {
    func didScanQRCode(_ code: String)
}

class QRScannerViewController: UIViewController {
    weak var delegate: QRScannerDelegate?
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var lastScannedCode: String?
    private var lastScanTime: Date = Date()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startScanning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        let overlayView = createScanningOverlay()
        view.addSubview(overlayView)
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
        
        let path = UIBezierPath(rect: overlayView.bounds)
        let scanAreaPath = UIBezierPath(roundedRect: CGRect(x: (view.bounds.width - 250) / 2, y: (view.bounds.height - 250) / 2, width: 250, height: 250), cornerRadius: 10)
        path.append(scanAreaPath.reversing())
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        overlayView.layer.mask = maskLayer
        
        return overlayView
    }
    
    private func startScanning() {
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .background).async {
                self.captureSession.startRunning()
            }
        }
    }
    
    private func stopScanning() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
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

struct ProcessSelectionView: View {
    @StateObject private var apiService = APIService()
    @State private var selectedProcess: ProcessType = .shipping
    @State private var selectedCompany: Company?
    @State private var selectedGroup: Group?
    @State private var selectedLocation: Location?
    @State private var note: String = ""
    @State private var userName: String = "User"
    
    @State private var companies: [Company] = []
    @State private var groups: [Group] = []
    @State private var locations: [Location] = []
    
    @State private var showingScanner = false
    @State private var isLoading = false
    
    var canProceed: Bool {
        selectedProcess == .return_ || selectedProcess == .disposal || selectedCompany != nil
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                HStack {
                    Text(userName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("ログアウト") {
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                
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
            .task {
                await loadCompanies()
            }
            .fullScreenCover(isPresented: $showingScanner) {
                QRScannerContainerView(
                    selectedProcess: selectedProcess,
                    selectedCompany: selectedCompany,
                    selectedGroup: selectedGroup,
                    selectedLocation: selectedLocation,
                    note: note,
                    userName: userName
                )
            }
        }
    }
    
    private func loadCompanies() async {
        do {
            companies = try await apiService.fetchCompanies()
        } catch {
            print("Error loading companies: \(error)")
        }
    }
    
    private func loadGroups() {
        guard let companyId = selectedCompany?.id else { return }
        
        Task {
            do {
                groups = try await apiService.fetchGroups(for: companyId)
            } catch {
                print("Error loading groups: \(error)")
            }
        }
    }
    
    private func loadLocations() {
        guard let groupId = selectedGroup?.id else { return }
        
        Task {
            do {
                locations = try await apiService.fetchLocations(for: groupId)
            } catch {
                print("Error loading locations: \(error)")
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
    
    @StateObject private var apiService = APIService()
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
                
                QRScannerView(scannedCode: $scannedCode)
                    .frame(height: 300)
                    .cornerRadius(10)
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
                }
                
                Spacer()
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

struct ContentView: View {
    var body: some View {
        EnhancedLoginView()
    }
}

struct QRScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
