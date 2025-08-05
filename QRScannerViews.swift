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
