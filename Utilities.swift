import SwiftUI
import Foundation

// MARK: - Network Utilities
struct NetworkUtilities {
    static func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
    
    static func sanitizeURL(_ urlString: String) -> String {
        var cleanURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanURL.hasSuffix("/") {
            cleanURL = String(cleanURL.dropLast())
        }
        
        if !cleanURL.hasPrefix("http://") && !cleanURL.hasPrefix("https://") {
            cleanURL = "https://\(cleanURL)"
        }
        
        return cleanURL
    }
}

// MARK: - Camera Permission Handler
struct CameraPermissionHandler {
    static func checkCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

// MARK: - String Extensions
extension String {
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: self)
    }
    
    var isValidIP: Bool {
        let parts = self.components(separatedBy: ".")
        guard parts.count == 4 else { return false }
        
        for part in parts {
            guard let num = Int(part), num >= 0 && num <= 255 else {
                return false
            }
        }
        return true
    }
}

// MARK: - Date Utilities
extension Date {
    func formattedString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: self)
    }
}

// MARK: - View Extensions
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Error Display Helper
struct ErrorView: View {
    let error: Error
    let onRetry: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("エラーが発生しました")
                .font(.headline)
            
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let onRetry = onRetry {
                Button("再試行") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

// MARK: - Loading View
struct LoadingView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Alert Helper
struct AlertHelper {
    static func showError(_ error: Error, in viewController: UIViewController) {
        let alert = UIAlertController(
            title: "エラー",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alert, animated: true)
    }
    
    static func showSuccess(_ message: String, in viewController: UIViewController) {
        let alert = UIAlertController(
            title: "成功",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alert, animated: true)
    }
}

// MARK: - Vibration Helper
struct VibrationHelper {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
    }
    
    static func success() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
    }
    
    static func error() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.error)
    }
}

// MARK: - Debug Helper
struct DebugHelper {
    static func printAPI(_ message: String, url: String? = nil, data: Data? = nil) {
        #if DEBUG
        print("🌐 API: \(message)")
        if let url = url {
            print("📍 URL: \(url)")
        }
        if let data = data,
           let jsonString = String(data: data, encoding: .utf8) {
            print("📦 Data: \(jsonString)")
        }
        #endif
    }
    
    static func printError(_ error: Error, function: String = #function) {
        #if DEBUG
        print("❌ Error in \(function): \(error.localizedDescription)")
        #endif
    }
}

// MARK: - Constants
struct Constants {
    struct API {
        static let timeoutInterval: TimeInterval = 30
        static let maxRetries = 3
    }
    
    struct UI {
        static let cornerRadius: CGFloat = 8
        static let defaultPadding: CGFloat = 16
        static let buttonHeight: CGFloat = 44
    }
    
    struct QRScanner {
        static let scanAreaSize: CGFloat = 250
        static let duplicateScanDelay: TimeInterval = 2.0
    }
}
