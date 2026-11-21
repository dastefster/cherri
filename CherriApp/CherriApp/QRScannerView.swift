// ===================================
// QR Scanner
// v0.0.1 BUILD 2026-11-21 10:07
// Camera view that reads the pairing QR code shown by the Cherri Helper on the user's Mac.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import AVFoundation


// ===================================
// SWIFTUI WRAPPER
// ===================================

struct QRScannerView: UIViewControllerRepresentable {
    // Returns true when the code was a valid pairing, so a wrong QR code just lets the person try another.
    let onCode: (String) -> Bool
    let onProblem: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        controller.onProblem = onProblem
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}


// ===================================
// CAMERA CONTROLLER
// ===================================

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Bool)?
    var onProblem: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var handled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.configure() : self.cameraOff() }
            }
        default:
            cameraOff()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { if session.isRunning { session.stopRunning() } }
    }

    private func cameraOff() {
        onProblem?("Camera access is off for Cherri Shortcuts. Turn it on in the Settings app, or use Paste Pairing Link instead.")
    }

    private func configure() {
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            onProblem?("This device has no camera that can scan codes. Use Paste Pairing Link instead.")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            onProblem?("The camera could not start. Use Paste Pairing Link instead.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer

        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !handled, let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        handled = true

        if onCode?(code) == true {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.handled = false }
        }
    }
}
